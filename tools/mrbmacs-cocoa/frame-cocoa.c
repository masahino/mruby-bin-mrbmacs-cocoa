#include "mrbmacs-cocoa-internal.h"

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
  mrbmacs_application_schedule_pending_open_files();
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
  mrbmacs_application_schedule_pending_open_files();
  if (response == MRBMACS_MODAL_RESPONSE_YES) {
    return mrb_symbol_value(mrb_intern_lit(mrb, "yes"));
  }
  return mrb_symbol_value(mrb_intern_lit(mrb, "no"));
}

static mrb_value
mrbmacs_frame_update_native_echo_height(mrb_state *mrb, mrb_value self)
{
  mrb_int requested_height;
  mrb_value native_handle;
  mrb_value layout_handle;
  NSWindow *window;
  NSView *layout;
  CGFloat height;

  mrb_get_args(mrb, "i", &requested_height);
  native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@native_handle")
  );
  layout_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@layout_native_handle")
  );
  if (mrb_nil_p(native_handle) || mrb_nil_p(layout_handle)) {
    return mrb_nil_value();
  }
  height = (CGFloat)requested_height;
  window = (NSWindow *)(intptr_t)mrb_integer(native_handle);
  layout = (NSView *)(intptr_t)mrb_integer(layout_handle);
  [mrbmacs_echo_native_view setFrame:NSMakeRect(
    0, 0, window.contentView.bounds.size.width, height
  )];
  [layout setFrame:NSMakeRect(
    0, height, window.contentView.bounds.size.width,
    MAX(0, window.contentView.bounds.size.height - height)
  )];
  return mrb_nil_value();
}

@interface MrbmacsFontTarget : NSObject
- (void)changeFont:(id)sender;
@end

@implementation MrbmacsFontTarget
- (void)changeFont:(id)sender
{
  NSFont *font = [sender convertFont:[sender selectedFont]];
  if (font == nil) {
    return;
  }
  mrb_funcall(
    mrbmacs_mrb, mrbmacs_frame, "set_font", 2,
    mrb_str_new_cstr(mrbmacs_mrb, font.familyName.UTF8String),
    mrb_int_value(mrbmacs_mrb, (mrb_int)font.pointSize)
  );
  if (mrbmacs_mrb->exc != NULL) {
    mrbmacs_print_mruby_error(mrbmacs_mrb);
  }
}
@end

static mrb_value
mrbmacs_frame_select_font(mrb_state *mrb, mrb_value self)
{
  NSFontManager *manager = [NSFontManager sharedFontManager];
  mrb_value name = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@font_name")
  );
  mrb_value size = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@font_size")
  );
  NSFont *font = [NSFont fontWithName:
    [NSString stringWithUTF8String:mrb_str_to_cstr(mrb, name)]
    size:(CGFloat)mrb_integer(size)];

  [manager setTarget:mrbmacs_font_target];
  [manager setAction:@selector(changeFont:)];
  [manager setSelectedFont:font isMultiple:NO];
  [manager orderFrontFontPanel:nil];
  return mrb_nil_value();
}
static mrb_value
mrbmacs_application_initialize_native_frame(mrb_state *mrb, mrb_value self)
{
  const CGFloat echo_height = 24.0;
  NSRect window_frame = NSMakeRect(0, 0, 100, 100);
  NSWindowStyleMask style =
    NSWindowStyleMaskTitled |
    NSWindowStyleMaskClosable |
    NSWindowStyleMaskMiniaturizable |
    NSWindowStyleMaskResizable;
  mrb_value echo_view_value;
  mrb_value echo_native_handle;
  mrb_value pane;
  NSView *echo_view;
  NSView *layout_view;
  NSView *pane_view;

  mrbmacs_frame = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@frame")
  );
  pane = mrb_funcall(mrb, mrbmacs_frame, "active_pane", 0);
  echo_view_value = mrb_funcall(mrb, mrbmacs_frame, "echo_win", 0);
  echo_native_handle = mrb_funcall(mrb, echo_view_value, "native_handle", 0);
  echo_view = (NSView *)(intptr_t)mrb_integer(echo_native_handle);
  mrbmacs_echo_native_view = echo_view;

  mrbmacs_window = [
    [[NSWindow alloc]
      initWithContentRect:window_frame
      styleMask:style
      backing:NSBackingStoreBuffered
      defer:NO]
    autorelease
  ];
  [mrbmacs_window setTitle:@"mrbmacs Cocoa"];
  layout_view = [[[NSView alloc] initWithFrame:NSMakeRect(
    0, echo_height, mrbmacs_window.contentView.bounds.size.width,
    mrbmacs_window.contentView.bounds.size.height - echo_height
  )] autorelease];
  [layout_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  pane_view = mrbmacs_pane_create_native_view(mrb, pane);
  [pane_view setFrame:layout_view.bounds];
  [pane_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [layout_view addSubview:pane_view];
  mrb_funcall(
    mrb, mrbmacs_frame, "native_handle=", 1,
    mrb_int_value(mrb, (mrb_int)(intptr_t)mrbmacs_window)
  );
  mrb_funcall(
    mrb, mrbmacs_frame, "layout_native_handle=", 1,
    mrb_int_value(mrb, (mrb_int)(intptr_t)layout_view)
  );
  [echo_view setFrame:NSMakeRect(
    0, 0, mrbmacs_window.contentView.bounds.size.width, echo_height
  )];
  [echo_view setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [mrbmacs_window.contentView addSubview:layout_view];
  [mrbmacs_window.contentView addSubview:echo_view];
  mrb_funcall(
    mrb, mrbmacs_frame, "set_font", 2,
    mrb_iv_get(mrb, mrbmacs_frame, mrb_intern_lit(mrb, "@font_name")),
    mrb_iv_get(mrb, mrbmacs_frame, mrb_intern_lit(mrb, "@font_size"))
  );
  return mrb_nil_value();
}

void
mrbmacs_frame_apply_initial_window_size(mrb_state *mrb, mrb_value frame)
{
  mrb_value pane = mrb_funcall(mrb, frame, "active_pane", 0);
  mrb_value echo = mrb_funcall(mrb, frame, "echo_win", 0);
  mrb_int editor_width = mrb_integer(mrb_funcall(
    mrb, frame, "initial_native_editor_width", 0
  ));
  mrb_int editor_height = mrb_integer(mrb_funcall(
    mrb, frame, "initial_native_editor_height", 0
  ));
  NSView *echo_view = (NSView *)(intptr_t)mrb_integer(mrb_funcall(
    mrb, echo, "native_handle", 0
  ));
  CGFloat modeline_height = (CGFloat)mrb_integer(mrb_funcall(
    mrb, pane, "native_modeline_height", 0
  ));
  NSSize current_content_size = mrbmacs_window.contentView.bounds.size;
  NSRect current_frame = mrbmacs_window.frame;
  NSScreen *screen = mrbmacs_window.screen ?: [NSScreen mainScreen];
  NSSize content_size = NSMakeSize(
    (CGFloat)editor_width,
    (CGFloat)editor_height + modeline_height + NSHeight(echo_view.frame)
  );

  if (screen != nil) {
    NSRect visible_frame = screen.visibleFrame;
    CGFloat chrome_width = NSWidth(current_frame) - current_content_size.width;
    CGFloat chrome_height = NSHeight(current_frame) - current_content_size.height;
    content_size.width = MIN(
      content_size.width, MAX(1.0, NSWidth(visible_frame) - chrome_width)
    );
    content_size.height = MIN(
      content_size.height, MAX(1.0, NSHeight(visible_frame) - chrome_height)
    );
  }
  [mrbmacs_window setContentSize:content_size];
}

void
mrbmacs_frame_register_methods(mrb_state *mrb, struct RClass *mrbmacs)
{
  struct RClass *frame_class = mrb_class_get_under(mrb, mrbmacs, "FrameCocoa");
  struct RClass *application_class = mrb_class_get_under(
    mrb, mrbmacs, "ApplicationCocoa"
  );
  mrb_define_method(mrb, frame_class, "exit",
    mrbmacs_frame_exit, MRB_ARGS_NONE());
  mrb_define_method(mrb, frame_class, "wait_echo_event",
    mrbmacs_frame_wait_echo_event, MRB_ARGS_NONE());
  mrb_define_method(mrb, frame_class, "wait_confirmation_event",
    mrbmacs_frame_wait_confirmation_event, MRB_ARGS_NONE());
  mrb_define_method(mrb, frame_class, "select_font",
    mrbmacs_frame_select_font, MRB_ARGS_NONE());
  mrb_define_method(mrb, frame_class, "update_native_echo_height",
    mrbmacs_frame_update_native_echo_height, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, application_class, "initialize_native_frame",
    mrbmacs_application_initialize_native_frame, MRB_ARGS_NONE());
  mrbmacs_font_target = [[MrbmacsFontTarget alloc] init];
}


