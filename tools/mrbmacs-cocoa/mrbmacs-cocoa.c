#import <Cocoa/Cocoa.h>

#include <mruby.h>
#include <mruby/class.h>
#include <mruby/string.h>
#include <mruby/variable.h>

static mrb_state *mrbmacs_mrb;
static mrb_value mrbmacs_frame;
static mrb_value mrbmacs_app;
static id key_event_monitor;
static NSView *mrbmacs_echo_native_view;

enum {
  MRBMACS_MODAL_RESPONSE_TAB = 1001
};

static void print_mruby_error(mrb_state *mrb);

static mrb_value
mrbmacs_frame_exit(mrb_state *mrb, mrb_value self)
{
  (void)mrb;
  (void)self;
  [NSApp terminate:nil];
  return mrb_nil_value();
}

static mrb_value
mrbmacs_frame_wait_echo_event(mrb_state *mrb, mrb_value self)
{
  NSModalResponse response;
  mrb_value echo_win;

  echo_win = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@echo_win"));
  mrb_funcall(mrb, echo_win, "sci_grab_focus", 0);
  response = [NSApp runModalForWindow:NSApp.keyWindow];
  if (response == NSModalResponseOK) {
    return mrb_symbol_value(mrb_intern_lit(mrb, "enter"));
  }
  if (response == MRBMACS_MODAL_RESPONSE_TAB) {
    return mrb_symbol_value(mrb_intern_lit(mrb, "tab"));
  }
  return mrb_symbol_value(mrb_intern_lit(mrb, "cancel"));
}

static mrb_value
mrbmacs_pane_update_native_modeline(mrb_state *mrb, mrb_value self)
{
  char *text;
  mrb_value native_handle;
  NSTextField *modeline;

  mrb_get_args(mrb, "z", &text);
  native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@modeline_native_handle")
  );
  if (mrb_nil_p(native_handle)) {
    return mrb_nil_value();
  }
  modeline = (NSTextField *)(intptr_t)mrb_integer(native_handle);
  [modeline setStringValue:[NSString stringWithUTF8String:text]];
  return mrb_nil_value();
}

static NSString *
mrbmacs_key_name(NSEvent *event)
{
  NSEventModifierFlags modifiers =
    event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  NSString *characters;
  NSString *prefix = @"";

  if ((modifiers & NSEventModifierFlagCommand) != 0) {
    return nil;
  }
  characters = event.charactersIgnoringModifiers;
  if (characters.length == 0) {
    return nil;
  }
  if ((modifiers & NSEventModifierFlagControl) != 0) {
    prefix = @"C-";
  } else if ((modifiers & NSEventModifierFlagOption) != 0) {
    prefix = @"M-";
  }

  switch ([characters characterAtIndex:0]) {
  case 0x00:
    characters = @" ";
    break;
  case 0x1b:
    return @"Escape";
  case '\r':
    characters = @"Enter";
    break;
  case '\t':
    characters = @"Tab";
    break;
  case 0x7f:
    characters = @"DEL";
    break;
  default:
    characters = [characters lowercaseString];
    break;
  }
  return [prefix stringByAppendingString:characters];
}

static NSEvent *
mrbmacs_handle_key_event(NSEvent *event)
{
  NSString *key = mrbmacs_key_name(event);
  mrb_value handled;
  NSResponder *responder;

  if (key == nil) {
    return event;
  }
  responder = NSApp.keyWindow.firstResponder;
  if (NSApp.modalWindow != nil &&
      ([responder isEqual:mrbmacs_echo_native_view] ||
       ([responder isKindOfClass:[NSView class]] &&
        [(NSView *)responder isDescendantOf:mrbmacs_echo_native_view]))) {
    if ([key isEqualToString:@"Enter"]) {
      [NSApp stopModalWithCode:NSModalResponseOK];
      return nil;
    }
    if ([key isEqualToString:@"C-g"]) {
      [NSApp stopModalWithCode:NSModalResponseCancel];
      return nil;
    }
    if ([key isEqualToString:@"Tab"]) {
      [NSApp stopModalWithCode:MRBMACS_MODAL_RESPONSE_TAB];
      return nil;
    }
    return event;
  }
  handled = mrb_funcall(
    mrbmacs_mrb, mrbmacs_app, "key_press", 1,
    mrb_str_new_cstr(mrbmacs_mrb, key.UTF8String)
  );
  if (mrbmacs_mrb->exc != NULL) {
    print_mruby_error(mrbmacs_mrb);
    return event;
  }
  return mrb_test(handled) ? nil : event;
}

static void
print_mruby_error(mrb_state *mrb)
{
  if (mrb->exc != NULL) {
    mrb_print_error(mrb);
  }
}

static void
create_application_menu(void)
{
  NSMenu *menu_bar = [[[NSMenu alloc] init] autorelease];
  NSMenuItem *application_item = [[[NSMenuItem alloc] init] autorelease];
  NSMenu *application_menu = [[[NSMenu alloc] init] autorelease];
  NSString *quit_title = [
    NSString stringWithFormat:@"Quit %@", NSProcessInfo.processInfo.processName
  ];
  NSMenuItem *quit_item = [
    [[NSMenuItem alloc]
      initWithTitle:quit_title
      action:@selector(terminate:)
      keyEquivalent:@"q"]
    autorelease
  ];

  [application_menu addItem:quit_item];
  [application_item setSubmenu:application_menu];
  [menu_bar addItem:application_item];
  [NSApp setMainMenu:menu_bar];
}

int
main(int argc, char **argv)
{
  @autoreleasepool {
    NSApplication *application = [NSApplication sharedApplication];
    NSRect frame = NSMakeRect(0, 0, 900, 650);
    NSWindowStyleMask style =
      NSWindowStyleMaskTitled |
      NSWindowStyleMaskClosable |
      NSWindowStyleMaskMiniaturizable |
      NSWindowStyleMaskResizable;
    NSWindow *window;
    struct RClass *scintilla;
    struct RClass *view_class;
    struct RClass *mrbmacs;
    struct RClass *buffer_class;
    struct RClass *pane_class;
    struct RClass *tab_class;
    struct RClass *frame_class;
    struct RClass *application_class;
    mrb_value mrbmacs_view;
    mrb_value mrbmacs_echo_view;
    mrb_value buffer;
    mrb_value pane;
    mrb_value tab;
    mrb_value native_handle;
    mrb_value echo_native_handle;
    NSView *view;
    NSView *echo_view;
    NSTextField *modeline_view;
    CGFloat echo_height = 24.0;
    CGFloat modeline_height = 22.0;

    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    create_application_menu();

    mrbmacs_mrb = mrb_open();
    if (mrbmacs_mrb == NULL) {
      fputs("Unable to initialize mruby\n", stderr);
      return EXIT_FAILURE;
    }

    scintilla = mrb_module_get(mrbmacs_mrb, "Scintilla");
    view_class = mrb_class_get_under(
      mrbmacs_mrb, scintilla, "ScintillaCocoa"
    );
    mrbmacs_view = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(view_class), "new", 0
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    /* C retains and uses the native handle for the lifetime of the app, so
       keep its mruby wrapper registered for the same lifetime. */
    mrb_gc_register(mrbmacs_mrb, mrbmacs_view);
    mrbmacs_echo_view = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(view_class), "new", 0
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrb_gc_register(mrbmacs_mrb, mrbmacs_echo_view);
    mrbmacs = mrb_module_get(mrbmacs_mrb, "Mrbmacs");
    buffer_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "Buffer"
    );
    pane_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "PaneCocoa"
    );
    mrb_define_method(
      mrbmacs_mrb, pane_class, "update_native_modeline",
      mrbmacs_pane_update_native_modeline, MRB_ARGS_REQ(1)
    );
    tab_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "TabCocoa"
    );
    frame_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "FrameCocoa"
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "exit", mrbmacs_frame_exit, MRB_ARGS_NONE()
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "wait_echo_event",
      mrbmacs_frame_wait_echo_event, MRB_ARGS_NONE()
    );
    application_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "ApplicationCocoa"
    );

    buffer = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(buffer_class), "new", 1,
      argc > 1 ? mrb_str_new_cstr(mrbmacs_mrb, argv[1])
               : mrb_str_new_lit(mrbmacs_mrb, "*scratch*")
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    pane = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(pane_class), "new", 2,
      mrbmacs_view, buffer
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    tab = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(tab_class), "new", 1, pane
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrbmacs_frame = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(frame_class), "new", 2,
      tab, mrbmacs_echo_view
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrb_gc_register(mrbmacs_mrb, mrbmacs_frame);

    mrbmacs_app = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(application_class), "new", 2,
      mrbmacs_frame, buffer
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrb_gc_register(mrbmacs_mrb, mrbmacs_app);
    mrb_gv_set(
      mrbmacs_mrb, mrb_intern_lit(mrbmacs_mrb, "$app"), mrbmacs_app
    );
    key_event_monitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
      handler:^NSEvent *(NSEvent *event) {
        return mrbmacs_handle_key_event(event);
      }
    ];

    mrbmacs_view = mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "view", 0
    );

    native_handle = mrb_funcall(
      mrbmacs_mrb, mrbmacs_view, "native_handle", 0
    );
    view = (NSView *)(intptr_t)mrb_integer(native_handle);
    echo_native_handle = mrb_funcall(
      mrbmacs_mrb, mrbmacs_echo_view, "native_handle", 0
    );
    echo_view = (NSView *)(intptr_t)mrb_integer(echo_native_handle);
    mrbmacs_echo_native_view = echo_view;

    window = [
      [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:style
        backing:NSBackingStoreBuffered
        defer:NO]
      autorelease
    ];
    [window setTitle:@"mrbmacs Cocoa"];
    modeline_view = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [modeline_view setEditable:NO];
    [modeline_view setSelectable:NO];
    [modeline_view setBezeled:NO];
    [modeline_view setDrawsBackground:YES];
    [modeline_view setFont:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular]];
    [modeline_view setLineBreakMode:NSLineBreakByTruncatingTail];
    mrb_funcall(
      mrbmacs_mrb, pane, "modeline_native_handle=", 1,
      mrb_int_value(mrbmacs_mrb, (mrb_int)(intptr_t)modeline_view)
    );
    mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "native_handle=", 1,
      mrb_int_value(mrbmacs_mrb, (mrb_int)(intptr_t)window)
    );
    [view setFrame:NSMakeRect(
      0,
      echo_height + modeline_height,
      window.contentView.bounds.size.width,
      window.contentView.bounds.size.height - echo_height - modeline_height
    )];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [modeline_view setFrame:NSMakeRect(
      0, echo_height, window.contentView.bounds.size.width, modeline_height
    )];
    [modeline_view setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [echo_view setFrame:NSMakeRect(
      0, 0, window.contentView.bounds.size.width, echo_height
    )];
    [echo_view setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [window.contentView addSubview:view];
    [window.contentView addSubview:modeline_view];
    [window.contentView addSubview:echo_view];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:view];

    mrb_funcall(
      mrbmacs_mrb, mrbmacs_app, "load_initial_file", 1,
      argc > 1 ? mrb_str_new_cstr(mrbmacs_mrb, argv[1]) : mrb_nil_value()
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }

    [application activateIgnoringOtherApps:YES];
    [application run];

    [NSEvent removeMonitor:key_event_monitor];
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_app);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_frame);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_echo_view);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_view);
    mrb_close(mrbmacs_mrb);
  }

  return EXIT_SUCCESS;
}
