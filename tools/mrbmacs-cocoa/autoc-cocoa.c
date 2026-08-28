#include "mrbmacs-cocoa-internal.h"

/*
 * Autocompletion / user-list popup fix-up.
 *
 * Scintilla's Cocoa ListBoxImpl (scintilla/cocoa/PlatCocoa.mm) sizes the popup
 * text column to the raw glyph width of the widest item and relies on the
 * small fixed slack GetDesiredRect adds to the window (maxItemWidth +
 * aveCharWidth + 4) being handed to the column by last-column autoresizing.
 *
 * On current macOS the popup's NSTableView ends up with an inflated
 * intercellSpacing.width (~17pt, a side effect of the macOS 11+ table styles).
 * That eats almost exactly Scintilla's slack, so after sizeLastColumnToFit the
 * text column is back to ~maxItemWidth and the NSTextFieldCell's own ~2pt
 * margin truncates the widest rows with an ellipsis. Scintilla exposes no
 * message to influence any of this (measured: rectOfColumn - column.width ==
 * intercellSpacing.width; cellSize.width == column.width + 2).
 *
 * After every SCI_AUTOCSHOW / SCI_USERLISTSHOW we find the popup (a borderless
 * NSWindow whose scroll-view documentView is an NSTableView) and:
 *
 *   1. shrink the horizontal intercell spacing so that room goes to the text
 *      column (row height is left alone),
 *   2. defensively force a Regular selection highlight (no source-list inset),
 *   3. as a last resort, if the widest data cell still would not fit, widen the
 *      popup window and re-fit.
 *
 * If the popup cannot be found the function is a no-op, so this keeps working
 * (or safely does nothing) across Scintilla upgrades without patching it.
 */

static NSScrollView *
mrbmacs_autoc_scroll_view(NSView *view)
{
  if (view == nil) {
    return nil;
  }
  if ([view isKindOfClass:[NSScrollView class]]) {
    NSView *document = ((NSScrollView *)view).documentView;
    if ([document isKindOfClass:[NSTableView class]]) {
      return (NSScrollView *)view;
    }
  }
  for (NSView *sub in view.subviews) {
    NSScrollView *found = mrbmacs_autoc_scroll_view(sub);
    if (found != nil) {
      return found;
    }
  }
  return nil;
}

static NSTableView *
mrbmacs_autoc_table_view(void)
{
  for (NSWindow *win in [NSApp windows]) {
    if (!win.isVisible) {
      continue;
    }
    if (win == mrbmacs_window) {
      continue;
    }
    /* The Scintilla popup is a borderless panel; skip anything with chrome. */
    if ((win.styleMask & NSWindowStyleMaskTitled) != 0) {
      continue;
    }
    NSScrollView *scroll = mrbmacs_autoc_scroll_view(win.contentView);
    if (scroll != nil) {
      return (NSTableView *)scroll.documentView;
    }
  }
  return nil;
}

static CGFloat
mrbmacs_autoc_widest_cell(NSTableView *table, NSTableColumn *column)
{
  id<NSTableViewDataSource> source = table.dataSource;
  SEL sel = @selector(tableView:objectValueForTableColumn:row:);
  if (source == nil || ![source respondsToSelector:sel]) {
    return 0.0;
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSCell *probe = [[column dataCell] copy];
#pragma clang diagnostic pop
  if (probe == nil) {
    return 0.0;
  }

  NSInteger rows = [table numberOfRows];
  if (rows > 2000) {
    rows = 2000;
  }

  CGFloat widest = 0.0;
  for (NSInteger row = 0; row < rows; row++) {
    id value = [source tableView:table
        objectValueForTableColumn:column
                              row:row];
    if (value == nil) {
      continue;
    }
    [probe setObjectValue:value];
    CGFloat width = [probe cellSize].width;
    if (width > widest) {
      widest = width;
    }
  }
  [probe release];
  return widest;
}

static void
mrbmacs_autoc_debug_log(NSTableView *table, NSTableColumn *column,
                        const char *phase)
{
  if (getenv("MRBMACS_AUTOC_DEBUG") == NULL) {
    return;
  }
  NSScrollView *scroll = table.enclosingScrollView;
  NSInteger col = [table.tableColumns indexOfObject:column];
  NSRect cellFrame = (col == NSNotFound || [table numberOfRows] == 0)
    ? NSZeroRect
    : [table frameOfCellAtColumn:col row:0];
  NSLog(@"[autoc %s] win=%.1f clip=%.1f table=%.1f col=%.1f "
        @"rectOfCol=%.1f frameOfCell=%.1f intercell=%.1f "
        @"selStyle=%ld rows=%ld scale=%.1f cellNeeds=%.1f",
        phase,
        NSWidth(table.window.frame),
        scroll ? NSWidth(scroll.contentView.bounds) : -1.0,
        NSWidth(table.frame), column.width,
        (col == NSNotFound) ? -1.0 : [table rectOfColumn:col].size.width,
        cellFrame.size.width,
        table.intercellSpacing.width,
        (long)table.selectionHighlightStyle,
        (long)[table numberOfRows],
        table.window.backingScaleFactor,
        mrbmacs_autoc_widest_cell(table, column));
}

static void
mrbmacs_autoc_fixup(void)
{
  NSTableView *table = mrbmacs_autoc_table_view();
  if (table == nil) {
    return;
  }

  NSTableColumn *nameColumn = [table tableColumnWithIdentifier:@"name"];
  if (nameColumn == nil) {
    nameColumn = table.tableColumns.lastObject;
  }
  mrbmacs_autoc_debug_log(table, nameColumn, "before");

  /* (1) Reclaim the inflated horizontal intercell spacing for the column.
   *     Leave the vertical component (row spacing) untouched. */
  if (table.intercellSpacing.width > 4.0) {
    table.intercellSpacing = NSMakeSize(4.0, table.intercellSpacing.height);
  }

  /* (2) Defensive: some macOS versions keep a source-list selection inset. */
  if (table.selectionHighlightStyle
        != NSTableViewSelectionHighlightStyleRegular) {
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
  }

  NSTableColumn *column = nameColumn;
  if (column == nil) {
    [table setNeedsDisplay:YES];
    return;
  }

  [table sizeLastColumnToFit];

  /* (3) Last resort: if the column still cannot hold its widest row, widen the
   *     popup window and re-fit. */
  CGFloat cellWidth = mrbmacs_autoc_widest_cell(table, column);
  if (cellWidth > 0.0) {
    cellWidth = ceil(cellWidth) + 4.0;

    if (column.width + 0.5 < cellWidth) {
      NSScrollView *scroll = table.enclosingScrollView;
      if (scroll != nil) {
        NSWindow *win = table.window;
        NSRect frame = win.frame;
        frame.size.width += (cellWidth - column.width);

        NSScreen *screen = win.screen ?: [NSScreen mainScreen];
        if (screen != nil && NSMaxX(frame) > NSMaxX(screen.visibleFrame)) {
          frame.origin.x = MAX(NSMinX(screen.visibleFrame),
                               NSMaxX(screen.visibleFrame) - NSWidth(frame));
        }
        [win setFrame:frame display:YES];
        [table sizeLastColumnToFit];
      }

      /* Still short (e.g. clamped at a screen edge): prefer a wider column and
       * a slight clip over a mid-text ellipsis. */
      if (column.width + 0.5 < cellWidth) {
        column.width = cellWidth;
      }
    }
  }

  mrbmacs_autoc_debug_log(table, column, "after");
  [table setNeedsDisplay:YES];
}

static mrb_value
mrbmacs_autoc_fixup_listbox(mrb_state *mrb, mrb_value self)
{
  (void)mrb;
  (void)self;
  mrbmacs_autoc_fixup();
  return mrb_nil_value();
}

void
mrbmacs_autoc_register_methods(mrb_state *mrb, struct RClass *mrbmacs)
{
  mrb_define_module_function(mrb, mrbmacs, "fixup_autocomplete_listbox",
    mrbmacs_autoc_fixup_listbox, MRB_ARGS_NONE());
}
