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
static BOOL mrbmacs_confirmation_input;

enum {
  MRBMACS_MODAL_RESPONSE_TAB = 1001,
  MRBMACS_MODAL_RESPONSE_YES,
  MRBMACS_MODAL_RESPONSE_NO
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
mrbmacs_frame_wait_confirmation_event(mrb_state *mrb, mrb_value self)
{
  NSModalResponse response;
  mrb_value echo_win;

  echo_win = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@echo_win"));
  mrb_funcall(mrb, echo_win, "sci_grab_focus", 0);
  mrbmacs_confirmation_input = YES;
  response = [NSApp runModalForWindow:NSApp.keyWindow];
  mrbmacs_confirmation_input = NO;
  if (response == MRBMACS_MODAL_RESPONSE_YES) {
    return mrb_symbol_value(mrb_intern_lit(mrb, "yes"));
  }
  return mrb_symbol_value(mrb_intern_lit(mrb, "no"));
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

static NSView *
mrbmacs_create_pane_native_view(mrb_state *mrb, mrb_value pane)
{
  const CGFloat modeline_height = 22.0;
  mrb_value view_value;
  mrb_value native_handle;
  NSView *view;
  NSView *container;
  NSTextField *modeline;

  view_value = mrb_funcall(mrb, pane, "view", 0);
  native_handle = mrb_funcall(mrb, view_value, "native_handle", 0);
  view = (NSView *)(intptr_t)mrb_integer(native_handle);
  container = [[[NSView alloc]
    initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
  modeline = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
  [modeline setEditable:NO];
  [modeline setSelectable:NO];
  [modeline setBezeled:NO];
  [modeline setDrawsBackground:YES];
  [modeline setFont:[NSFont
    monospacedSystemFontOfSize:12.0
    weight:NSFontWeightRegular]];
  [modeline setLineBreakMode:NSLineBreakByTruncatingTail];
  [view setFrame:NSMakeRect(
    0, modeline_height, container.bounds.size.width,
    container.bounds.size.height - modeline_height
  )];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [modeline setFrame:NSMakeRect(
    0, 0, container.bounds.size.width, modeline_height
  )];
  [modeline setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [container addSubview:view];
  [container addSubview:modeline];
  mrb_funcall(
    mrb, pane, "modeline_native_handle=", 1,
    mrb_int_value(mrb, (mrb_int)(intptr_t)modeline)
  );
  mrb_funcall(
    mrb, pane, "layout_native_handle=", 1,
    mrb_int_value(mrb, (mrb_int)(intptr_t)container)
  );
  return container;
}

static NSView *
mrbmacs_pane_native_view(mrb_state *mrb, mrb_value pane)
{
  mrb_value native_handle = mrb_iv_get(
    mrb, pane, mrb_intern_lit(mrb, "@layout_native_handle")
  );
  return (NSView *)(intptr_t)mrb_integer(native_handle);
}

static mrb_value
mrbmacs_frame_split_native_pane(mrb_state *mrb, mrb_value self)
{
  mrb_value target_pane;
  mrb_value new_pane;
  mrb_sym orientation;
  NSView *target;
  NSView *new_view;
  NSView *parent;
  NSSplitView *split;
  NSRect frame;
  BOOL side_by_side;

  (void)self;
  mrb_get_args(mrb, "oon", &target_pane, &new_pane, &orientation);
  target = mrbmacs_pane_native_view(mrb, target_pane);
  new_view = mrbmacs_create_pane_native_view(mrb, new_pane);
  parent = target.superview;
  frame = target.frame;
  side_by_side = orientation == mrb_intern_lit(mrb, "horizontal");
  split = [[[NSSplitView alloc] initWithFrame:frame] autorelease];
  [split setVertical:side_by_side];
  [split setDividerStyle:NSSplitViewDividerStyleThin];
  [split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [parent replaceSubview:target with:split];
  [target setFrame:split.bounds];
  [new_view setFrame:split.bounds];
  [split addSubview:target];
  [split addSubview:new_view];
  [split adjustSubviews];
  [split setPosition:(side_by_side ? NSWidth(split.bounds) : NSHeight(split.bounds)) / 2.0
      ofDividerAtIndex:0];
  return mrb_nil_value();
}

static mrb_value
mrbmacs_frame_pane_can_split(mrb_state *mrb, mrb_value self)
{
  mrb_value pane;
  mrb_sym orientation;
  mrb_int minimum_extent;
  NSView *pane_view;
  CGFloat available_extent;
  CGFloat divider_width;
  BOOL side_by_side;

  (void)self;
  mrb_get_args(mrb, "oni", &pane, &orientation, &minimum_extent);
  pane_view = mrbmacs_pane_native_view(mrb, pane);
  side_by_side = orientation == mrb_intern_lit(mrb, "horizontal");
  divider_width = 1.0;
  available_extent = side_by_side ? NSWidth(pane_view.bounds)
                                  : NSHeight(pane_view.bounds);
  return mrb_bool_value(
    available_extent >= (CGFloat)(minimum_extent * 2) + divider_width
  );
}

static mrb_value
mrbmacs_frame_remove_native_pane(mrb_state *mrb, mrb_value self)
{
  mrb_value target_pane;
  NSView *target;
  NSView *survivor;
  NSSplitView *split;
  NSView *parent;
  NSRect frame;

  (void)self;
  mrb_get_args(mrb, "o", &target_pane);
  target = mrbmacs_pane_native_view(mrb, target_pane);
  split = (NSSplitView *)target.superview;
  survivor = split.subviews[0] == target ? split.subviews[1] : split.subviews[0];
  parent = split.superview;
  frame = split.frame;
  [survivor retain];
  [survivor removeFromSuperview];
  [parent replaceSubview:split with:survivor];
  [survivor setFrame:frame];
  [survivor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [survivor release];
  return mrb_nil_value();
}

static mrb_value
mrbmacs_frame_keep_only_native_pane(mrb_state *mrb, mrb_value self)
{
  mrb_value pane;
  mrb_value native_handle;
  NSView *pane_view;
  NSView *layout_view;
  NSArray *subviews;

  mrb_get_args(mrb, "o", &pane);
  pane_view = mrbmacs_pane_native_view(mrb, pane);
  native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@layout_native_handle")
  );
  layout_view = (NSView *)(intptr_t)mrb_integer(native_handle);
  [pane_view retain];
  [pane_view removeFromSuperview];
  subviews = [layout_view.subviews copy];
  for (NSView *view in subviews) {
    [view removeFromSuperview];
  }
  [subviews release];
  [pane_view setFrame:layout_view.bounds];
  [pane_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [layout_view addSubview:pane_view];
  [pane_view release];
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
  BOOL echo_is_responder;

  if (key == nil) {
    return event;
  }
  responder = NSApp.keyWindow.firstResponder;
  echo_is_responder = [responder isEqual:mrbmacs_echo_native_view] ||
    ([responder isKindOfClass:[NSView class]] &&
     [(NSView *)responder isDescendantOf:mrbmacs_echo_native_view]);
  if (NSApp.modalWindow != nil && echo_is_responder) {
    if (mrbmacs_confirmation_input) {
      if ([key isEqualToString:@"y"]) {
        [NSApp stopModalWithCode:MRBMACS_MODAL_RESPONSE_YES];
        return nil;
      }
      if ([key isEqualToString:@"n"] || [key isEqualToString:@"C-g"]) {
        [NSApp stopModalWithCode:MRBMACS_MODAL_RESPONSE_NO];
        return nil;
      }
      return nil;
    }
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
  if (echo_is_responder) {
    handled = mrb_funcall(
      mrbmacs_mrb, mrbmacs_app, "echo_key_press", 1,
      mrb_str_new_cstr(mrbmacs_mrb, key.UTF8String)
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      return event;
    }
    return mrb_test(handled) ? nil : event;
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
    NSView *layout_view;
    NSView *pane_view;
    CGFloat echo_height = 24.0;

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
    mrb_define_method(
      mrbmacs_mrb, frame_class, "wait_confirmation_event",
      mrbmacs_frame_wait_confirmation_event, MRB_ARGS_NONE()
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "split_native_pane",
      mrbmacs_frame_split_native_pane, MRB_ARGS_REQ(3)
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "pane_can_split?",
      mrbmacs_frame_pane_can_split, MRB_ARGS_REQ(3)
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "remove_native_pane",
      mrbmacs_frame_remove_native_pane, MRB_ARGS_REQ(1)
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "keep_only_native_pane",
      mrbmacs_frame_keep_only_native_pane, MRB_ARGS_REQ(1)
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
    layout_view = [[[NSView alloc] initWithFrame:NSMakeRect(
      0, echo_height, window.contentView.bounds.size.width,
      window.contentView.bounds.size.height - echo_height
    )] autorelease];
    [layout_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    pane_view = mrbmacs_create_pane_native_view(mrbmacs_mrb, pane);
    [pane_view setFrame:layout_view.bounds];
    [pane_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [layout_view addSubview:pane_view];
    mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "native_handle=", 1,
      mrb_int_value(mrbmacs_mrb, (mrb_int)(intptr_t)window)
    );
    mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "layout_native_handle=", 1,
      mrb_int_value(mrbmacs_mrb, (mrb_int)(intptr_t)layout_view)
    );
    [echo_view setFrame:NSMakeRect(
      0, 0, window.contentView.bounds.size.width, echo_height
    )];
    [echo_view setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [window.contentView addSubview:layout_view];
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
