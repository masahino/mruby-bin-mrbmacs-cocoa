#include "mrbmacs-cocoa-internal.h"

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
  new_view = mrbmacs_pane_create_native_view(mrb, new_pane);
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

void
mrbmacs_layout_register_methods(mrb_state *mrb, struct RClass *mrbmacs)
{
  struct RClass *frame_class = mrb_class_get_under(mrb, mrbmacs, "FrameCocoa");
  mrb_define_method(mrb, frame_class, "split_native_pane",
    mrbmacs_frame_split_native_pane, MRB_ARGS_REQ(3));
  mrb_define_method(mrb, frame_class, "native_divider_thickness",
    mrbmacs_frame_native_divider_thickness, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, frame_class, "move_native_divider",
    mrbmacs_frame_move_native_divider, MRB_ARGS_REQ(5));
  mrb_define_method(mrb, frame_class, "pane_can_split?",
    mrbmacs_frame_pane_can_split, MRB_ARGS_REQ(3));
  mrb_define_method(mrb, frame_class, "remove_native_pane",
    mrbmacs_frame_remove_native_pane, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, frame_class, "keep_only_native_pane",
    mrbmacs_frame_keep_only_native_pane, MRB_ARGS_REQ(1));
}


