#include "mrbmacs-cocoa-internal.h"

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

NSView *
mrbmacs_pane_create_native_view(mrb_state *mrb, mrb_value pane)
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

void
mrbmacs_pane_register_methods(mrb_state *mrb, struct RClass *mrbmacs)
{
  struct RClass *pane_class = mrb_class_get_under(mrb, mrbmacs, "PaneCocoa");
  mrb_define_method(mrb, pane_class, "update_native_modeline",
    mrbmacs_pane_update_native_modeline, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, pane_class, "native_client_width",
    mrbmacs_pane_native_client_width, MRB_ARGS_NONE());
  mrb_define_method(mrb, pane_class, "native_modeline_height",
    mrbmacs_pane_native_modeline_height, MRB_ARGS_NONE());
  mrb_define_method(mrb, pane_class, "update_native_modeline_theme",
    mrbmacs_pane_update_native_modeline_theme, MRB_ARGS_REQ(2));
  mrb_define_method(mrb, pane_class, "update_native_modeline_font",
    mrbmacs_pane_update_native_modeline_font, MRB_ARGS_REQ(2));
}

