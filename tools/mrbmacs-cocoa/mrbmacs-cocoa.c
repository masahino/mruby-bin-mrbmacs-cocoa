#import <Cocoa/Cocoa.h>

#include <mruby.h>
#include <mruby/class.h>
#include <mruby/string.h>
#include <mruby/variable.h>

static mrb_state *mrbmacs_mrb;
static mrb_value mrbmacs_frame;
static mrb_value mrbmacs_app;
static id key_event_monitor;

static void print_mruby_error(mrb_state *mrb);

static mrb_value
mrbmacs_frame_exit(mrb_state *mrb, mrb_value self)
{
  (void)mrb;
  (void)self;
  [NSApp terminate:nil];
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

  if (key == nil) {
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

static mrb_value
scintilla_constant(mrb_state *mrb, const char *name)
{
  struct RClass *module = mrb_module_get(mrb, "Scintilla");
  return mrb_const_get(mrb, mrb_obj_value(module), mrb_intern_cstr(mrb, name));
}

static void
set_editor_text(mrb_state *mrb, mrb_value view, NSString *text)
{
  NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
  mrb_value bytes = mrb_str_new(mrb, data.bytes, (mrb_int)data.length);
  mrb_value set_text = scintilla_constant(mrb, "SCI_SETTEXT");

  mrb_funcall(
    mrb, view, "send_message", 3,
    set_text, mrb_fixnum_value(0), bytes
  );
}

static NSString *
initial_text(int argc, char **argv)
{
  if (argc > 1) {
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    NSError *error = nil;
    NSString *contents = [
      NSString stringWithContentsOfFile:path
      encoding:NSUTF8StringEncoding
      error:&error
    ];
    if (contents != nil) {
      return contents;
    }
    return [NSString stringWithFormat:@"Unable to open %@\n%@\n", path, error];
  }

  return @"mrbmacs Cocoa\n\nScintilla Cocoa is running.\n";
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
    mrb_value buffer;
    mrb_value pane;
    mrb_value tab;
    mrb_value native_handle;
    NSView *view;

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
    mrbmacs = mrb_module_get(mrbmacs_mrb, "Mrbmacs");
    buffer_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "Buffer"
    );
    pane_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "PaneCocoa"
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
      mrbmacs_mrb, mrb_obj_value(frame_class), "new", 1, tab
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

    set_editor_text(mrbmacs_mrb, mrbmacs_view, initial_text(argc, argv));
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrb_funcall(mrbmacs_mrb, mrbmacs_view, "sci_set_save_point", 0);
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    native_handle = mrb_funcall(
      mrbmacs_mrb, mrbmacs_view, "native_handle", 0
    );
    view = (NSView *)(intptr_t)mrb_integer(native_handle);

    window = [
      [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:style
        backing:NSBackingStoreBuffered
        defer:NO]
      autorelease
    ];
    [window setTitle:@"mrbmacs Cocoa"];
    mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "native_handle=", 1,
      mrb_int_value(mrbmacs_mrb, (mrb_int)(intptr_t)window)
    );
    [view setFrame:window.contentView.bounds];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [window.contentView addSubview:view];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:view];

    [application activateIgnoringOtherApps:YES];
    [application run];

    [NSEvent removeMonitor:key_event_monitor];
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_app);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_frame);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_view);
    mrb_close(mrbmacs_mrb);
  }

  return EXIT_SUCCESS;
}
