#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/string.h>
#include <mruby/variable.h>

static mrb_state *mrbmacs_mrb;
static mrb_value mrbmacs_frame;
static mrb_value mrbmacs_app;
static id key_event_monitor;
static NSWindow *mrbmacs_window;
static NSView *mrbmacs_echo_native_view;
static BOOL mrbmacs_confirmation_input;
static id mrbmacs_font_target;
static NSMutableDictionary *mrbmacs_io_sources;

enum {
  MRBMACS_MODAL_RESPONSE_TAB = 1001,
  MRBMACS_MODAL_RESPONSE_YES,
  MRBMACS_MODAL_RESPONSE_NO
};

@interface MrbmacsModelineView : NSView
@property(nonatomic, readonly) NSTextField *label;
@end

@implementation MrbmacsModelineView {
  NSTextField *_label;
}

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self != nil) {
    _label = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [_label setEditable:NO];
    [_label setSelectable:NO];
    [_label setBezeled:NO];
    [_label setDrawsBackground:NO];
    [_label setLineBreakMode:NSLineBreakByTruncatingTail];
    [_label setAutoresizingMask:NSViewWidthSizable];
    [self setWantsLayer:YES];
    [self addSubview:_label];
  }
  return self;
}

- (NSTextField *)label
{
  return _label;
}

- (void)layout
{
  [_label sizeToFit];
  CGFloat height = NSHeight(_label.frame);
  [_label setFrame:NSMakeRect(
    0,
    floor((NSHeight(self.bounds) - height) / 2.0),
    NSWidth(self.bounds),
    height
  )];
}
@end

static void print_mruby_error(mrb_state *mrb);

static mrb_value
mrbmacs_application_watch_io_read_event(mrb_state *mrb, mrb_value self)
{
  mrb_value io;
  mrb_value fileno;
  NSNumber *key;
  dispatch_source_t source;

  (void)self;
  mrb_get_args(mrb, "o", &io);
  fileno = mrb_funcall(mrb, io, "fileno", 0);
  key = [NSNumber numberWithLongLong:mrb_integer(fileno)];
  if ([mrbmacs_io_sources objectForKey:key] != nil) {
    return mrb_nil_value();
  }

  source = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_READ,
    (uintptr_t)mrb_integer(fileno),
    0,
    dispatch_get_main_queue()
  );
  if (source == nil) {
    return mrb_nil_value();
  }
  dispatch_source_set_event_handler(source, ^{
    mrb_funcall(
      mrbmacs_mrb, mrbmacs_app, "process_io_read_event", 1, io
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
    }
  });
  [mrbmacs_io_sources setObject:source forKey:key];
  dispatch_resume(source);
  return mrb_nil_value();
}

static mrb_value
mrbmacs_application_unwatch_io_read_event(mrb_state *mrb, mrb_value self)
{
  mrb_value io;
  mrb_value fileno;
  NSNumber *key;
  dispatch_source_t source;

  (void)self;
  mrb_get_args(mrb, "o", &io);
  fileno = mrb_funcall(mrb, io, "fileno", 0);
  key = [NSNumber numberWithLongLong:mrb_integer(fileno)];
  source = [mrbmacs_io_sources objectForKey:key];
  if (source != nil) {
    dispatch_source_cancel(source);
    [mrbmacs_io_sources removeObjectForKey:key];
  }
  return mrb_nil_value();
}

static void
mrbmacs_cancel_io_sources(void)
{
  for (NSNumber *key in [mrbmacs_io_sources allKeys]) {
    dispatch_source_t source = [mrbmacs_io_sources objectForKey:key];
    dispatch_source_cancel(source);
  }
  [mrbmacs_io_sources removeAllObjects];
}

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
  MrbmacsModelineView *modeline;

  mrb_get_args(mrb, "z", &text);
  native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@modeline_native_handle")
  );
  if (mrb_nil_p(native_handle)) {
    return mrb_nil_value();
  }
  modeline = (MrbmacsModelineView *)(intptr_t)mrb_integer(native_handle);
  [modeline.label setStringValue:[NSString stringWithUTF8String:text]];
  [modeline setNeedsLayout:YES];
  return mrb_nil_value();
}

static mrb_value
mrbmacs_pane_native_client_width(mrb_state *mrb, mrb_value self)
{
  mrb_value native_handle = mrb_funcall(mrb, self, "native_handle", 0);
  NSView *view = (NSView *)(intptr_t)mrb_integer(native_handle);

  return mrb_float_value(mrb, NSWidth(view.bounds));
}

static mrb_value
mrbmacs_pane_native_modeline_height(mrb_state *mrb, mrb_value self)
{
  mrb_value native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@modeline_native_handle")
  );
  MrbmacsModelineView *modeline;

  if (mrb_nil_p(native_handle)) {
    return mrb_fixnum_value(0);
  }
  modeline = (MrbmacsModelineView *)(intptr_t)mrb_integer(native_handle);
  return mrb_fixnum_value((mrb_int)ceil(NSHeight(modeline.frame)));
}

static NSColor *
mrbmacs_color_from_scintilla(mrb_int color)
{
  return [NSColor colorWithCalibratedRed:(color & 0xff) / 255.0
    green:((color >> 8) & 0xff) / 255.0
    blue:((color >> 16) & 0xff) / 255.0
    alpha:1.0];
}

static mrb_value
mrbmacs_pane_update_native_modeline_theme(mrb_state *mrb, mrb_value self)
{
  mrb_int foreground;
  mrb_int background;
  mrb_value native_handle;
  MrbmacsModelineView *modeline;

  mrb_get_args(mrb, "ii", &foreground, &background);
  native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@modeline_native_handle")
  );
  if (mrb_nil_p(native_handle)) {
    return mrb_nil_value();
  }
  modeline = (MrbmacsModelineView *)(intptr_t)mrb_integer(native_handle);
  [modeline.label setTextColor:mrbmacs_color_from_scintilla(foreground)];
  modeline.layer.backgroundColor =
    mrbmacs_color_from_scintilla(background).CGColor;
  return mrb_nil_value();
}

static mrb_value
mrbmacs_pane_update_native_modeline_font(mrb_state *mrb, mrb_value self)
{
  char *name;
  mrb_int size;
  mrb_value native_handle;
  MrbmacsModelineView *modeline;
  NSFont *font;

  mrb_get_args(mrb, "zi", &name, &size);
  native_handle = mrb_iv_get(
    mrb, self, mrb_intern_lit(mrb, "@modeline_native_handle")
  );
  if (mrb_nil_p(native_handle)) {
    return mrb_nil_value();
  }
  modeline = (MrbmacsModelineView *)(intptr_t)mrb_integer(native_handle);
  font = [NSFont fontWithName:[NSString stringWithUTF8String:name]
    size:(CGFloat)size];
  if (font != nil) {
    [modeline.label setFont:font];
    CGFloat height = ceil(
      font.ascender - font.descender + font.leading
    ) + 6.0;
    NSView *container = modeline.superview;
    if (container != nil) {
      [modeline setFrame:NSMakeRect(
        0, 0, container.bounds.size.width, height
      )];
      for (NSView *view in container.subviews) {
        if (view != modeline) {
          [view setFrame:NSMakeRect(
            0, height, container.bounds.size.width,
            MAX(0, container.bounds.size.height - height)
          )];
        }
      }
      [modeline setNeedsLayout:YES];
      [modeline layoutSubtreeIfNeeded];
    }
  }
  return mrb_nil_value();
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
    print_mruby_error(mrbmacs_mrb);
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

static NSView *
mrbmacs_create_pane_native_view(mrb_state *mrb, mrb_value pane)
{
  const CGFloat modeline_height = 22.0;
  mrb_value view_value;
  mrb_value native_handle;
  NSView *view;
  NSView *container;
  MrbmacsModelineView *modeline;

  view_value = mrb_funcall(mrb, pane, "view", 0);
  native_handle = mrb_funcall(mrb, view_value, "native_handle", 0);
  view = (NSView *)(intptr_t)mrb_integer(native_handle);
  container = [[[NSView alloc]
    initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
  modeline = [[[MrbmacsModelineView alloc]
    initWithFrame:NSZeroRect] autorelease];
  [modeline.label setFont:[NSFont
    monospacedSystemFontOfSize:12.0
    weight:NSFontWeightRegular]];
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
  pane_view = mrbmacs_create_pane_native_view(mrb, pane);
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

static void
mrbmacs_apply_initial_window_size(mrb_state *mrb, mrb_value frame)
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
  return mrb_int_value(mrb, (mrb_int)(intptr_t)split);
}

static NSSplitView *
mrbmacs_split_native_view(mrb_state *mrb, mrb_value split_value)
{
  mrb_value native_handle = mrb_iv_get(
    mrb, split_value, mrb_intern_lit(mrb, "@native_handle")
  );

  if (mrb_nil_p(native_handle)) {
    return nil;
  }
  return (NSSplitView *)(intptr_t)mrb_integer(native_handle);
}

static mrb_value
mrbmacs_frame_native_divider_thickness(mrb_state *mrb, mrb_value self)
{
  mrb_value split_value;
  NSSplitView *split;

  (void)self;
  mrb_get_args(mrb, "o", &split_value);
  split = mrbmacs_split_native_view(mrb, split_value);
  if (split == nil) {
    return mrb_fixnum_value(0);
  }
  return mrb_fixnum_value((mrb_int)ceil(split.dividerThickness));
}

static mrb_value
mrbmacs_frame_move_native_divider(mrb_state *mrb, mrb_value self)
{
  mrb_value split_value;
  mrb_bool active_in_first;
  mrb_int delta;
  mrb_int first_minimum;
  mrb_int second_minimum;
  NSSplitView *split;
  NSView *first;
  CGFloat extent;
  CGFloat current_position;
  CGFloat minimum_position;
  CGFloat maximum_position;
  CGFloat requested_position;

  (void)self;
  mrb_get_args(
    mrb, "obiii", &split_value, &active_in_first, &delta,
    &first_minimum, &second_minimum
  );
  split = mrbmacs_split_native_view(mrb, split_value);
  if (split == nil || split.subviews.count != 2) {
    return mrb_false_value();
  }

  first = split.subviews[0];
  extent = split.isVertical ? NSWidth(split.bounds) : NSHeight(split.bounds);
  current_position = split.isVertical ? NSWidth(first.frame) : NSHeight(first.frame);
  minimum_position = (CGFloat)first_minimum;
  maximum_position = extent - split.dividerThickness - (CGFloat)second_minimum;
  if (maximum_position < minimum_position) {
    return mrb_false_value();
  }

  requested_position = current_position + (active_in_first ? delta : -delta);
  requested_position = MAX(minimum_position, requested_position);
  requested_position = MIN(maximum_position, requested_position);
  [split setPosition:requested_position ofDividerAtIndex:0];
  return mrb_true_value();
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
    struct RClass *mrbmacs;
    struct RClass *pane_class;
    struct RClass *frame_class;
    struct RClass *application_class;
    mrb_value mrbmacs_view;
    mrb_value mrbmacs_echo_view;
    mrb_value arg_array;
    int i;

    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    create_application_menu();

    mrbmacs_mrb = mrb_open();
    if (mrbmacs_mrb == NULL) {
      fputs("Unable to initialize mruby\n", stderr);
      return EXIT_FAILURE;
    }

    mrbmacs = mrb_module_get(mrbmacs_mrb, "Mrbmacs");
    pane_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "PaneCocoa"
    );
    mrb_define_method(
      mrbmacs_mrb, pane_class, "update_native_modeline",
      mrbmacs_pane_update_native_modeline, MRB_ARGS_REQ(1)
    );
    mrb_define_method(
      mrbmacs_mrb, pane_class, "native_client_width",
      mrbmacs_pane_native_client_width, MRB_ARGS_NONE()
    );
    mrb_define_method(
      mrbmacs_mrb, pane_class, "native_modeline_height",
      mrbmacs_pane_native_modeline_height, MRB_ARGS_NONE()
    );
    mrb_define_method(
      mrbmacs_mrb, pane_class, "update_native_modeline_theme",
      mrbmacs_pane_update_native_modeline_theme, MRB_ARGS_REQ(2)
    );
    mrb_define_method(
      mrbmacs_mrb, pane_class, "update_native_modeline_font",
      mrbmacs_pane_update_native_modeline_font, MRB_ARGS_REQ(2)
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
      mrbmacs_mrb, frame_class, "select_font",
      mrbmacs_frame_select_font, MRB_ARGS_NONE()
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "update_native_echo_height",
      mrbmacs_frame_update_native_echo_height, MRB_ARGS_REQ(1)
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "split_native_pane",
      mrbmacs_frame_split_native_pane, MRB_ARGS_REQ(3)
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "native_divider_thickness",
      mrbmacs_frame_native_divider_thickness, MRB_ARGS_REQ(1)
    );
    mrb_define_method(
      mrbmacs_mrb, frame_class, "move_native_divider",
      mrbmacs_frame_move_native_divider, MRB_ARGS_REQ(5)
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
    mrb_define_method(
      mrbmacs_mrb, application_class, "initialize_native_frame",
      mrbmacs_application_initialize_native_frame, MRB_ARGS_NONE()
    );
    mrb_define_method(
      mrbmacs_mrb, application_class, "watch_io_read_event",
      mrbmacs_application_watch_io_read_event, MRB_ARGS_REQ(1)
    );
    mrb_define_method(
      mrbmacs_mrb, application_class, "unwatch_io_read_event",
      mrbmacs_application_unwatch_io_read_event, MRB_ARGS_REQ(1)
    );
    mrbmacs_io_sources = [[NSMutableDictionary alloc] init];
    mrbmacs_font_target = [[MrbmacsFontTarget alloc] init];
    arg_array = mrb_ary_new_capa(mrbmacs_mrb, argc - 1);
    for (i = 1; i < argc; i++) {
      mrb_ary_push(
        mrbmacs_mrb, arg_array, mrb_str_new_cstr(mrbmacs_mrb, argv[i])
      );
    }
    mrbmacs_app = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(application_class), "new", 1, arg_array
    );
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrb_gc_register(mrbmacs_mrb, mrbmacs_app);
    mrbmacs_frame = mrb_iv_get(
      mrbmacs_mrb, mrbmacs_app, mrb_intern_lit(mrbmacs_mrb, "@frame")
    );
    mrb_gc_register(mrbmacs_mrb, mrbmacs_frame);
    mrbmacs_view = mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "view", 0
    );
    mrb_gc_register(mrbmacs_mrb, mrbmacs_view);
    mrbmacs_echo_view = mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "echo_win", 0
    );
    mrb_gc_register(mrbmacs_mrb, mrbmacs_echo_view);
    mrbmacs_apply_initial_window_size(mrbmacs_mrb, mrbmacs_frame);
    mrb_gv_set(
      mrbmacs_mrb, mrb_intern_lit(mrbmacs_mrb, "$app"), mrbmacs_app
    );
    key_event_monitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
      handler:^NSEvent *(NSEvent *event) {
        return mrbmacs_handle_key_event(event);
      }
    ];

    [mrbmacs_window center];
    [mrbmacs_window makeKeyAndOrderFront:nil];

    [application activateIgnoringOtherApps:YES];
    mrb_funcall(mrbmacs_mrb, mrbmacs_view, "sci_grab_focus", 0);
    if (mrbmacs_mrb->exc != NULL) {
      print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    [application run];

    [NSEvent removeMonitor:key_event_monitor];
    mrbmacs_cancel_io_sources();
    [mrbmacs_io_sources release];
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_app);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_frame);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_echo_view);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_view);
    mrb_close(mrbmacs_mrb);
  }

  return EXIT_SUCCESS;
}
