# Autocomplete / user-list popup fix-up

## Symptom

In the Cocoa frontend the autocompletion, user-list and LSP code-action popups
truncated their widest rows with a trailing ellipsis, e.g.

```
Swap operands to + [comma…
```

It affected every popup path — `C-x C-f` file completion, `M-x` command
selection, buffer switching, in-buffer keyword completion and every LSP list
(completion, code action, document symbol, navigation). The terminal frontends
were not affected.

## What it is *not*

- **Not a Scintilla bug that needs patching.** The Scintilla source under
  `mruby-scintilla-cocoa` is downloaded unmodified from scintilla.org and built
  as `Scintilla.framework`. Its `ListBoxImpl` (`scintilla/cocoa/PlatCocoa.mm`)
  has carried the same list-sizing logic for years, and upstream's known
  mitigations (`+4` window slack since 3.7.5, `NSTableViewStylePlain` since
  5.0.2) are present.
- **Not the `String#ljust` padding** in `mruby-mrbmacs-lsp`'s
  `lsp_completion.rb`. A single, unpadded code-action title truncates too.
- **Not the source-list selection inset.** The popup table's
  `selectionHighlightStyle` is already `Regular` at runtime.

## Root cause

Scintilla sizes the popup's text column to the raw glyph width of the widest
item (`maxItemWidth`) and expects the small slack it adds to the popup window in
`ListBoxImpl::GetDesiredRect` (`maxItemWidth + aveCharWidth + 4`) to reach the
column through `NSTableView` last-column autoresizing.

On current macOS the popup's `NSTableView` ends up with an **inflated
`intercellSpacing.width` of ~17 pt** (a side effect of the macOS 11+ table
styles; the default is 3). After `sizeLastColumnToFit` that ~17 pt is subtracted
from the column, which cancels almost exactly Scintilla's slack, so the text
column is back to ~`maxItemWidth`. The `NSTextFieldCell`'s own ~2 pt internal
margin then truncates the widest rows.

Measured with `MRBMACS_AUTOC_DEBUG=1` (see below):

```
[autoc before] win=154 clip=154 col=137 rectOfCol=154 frameOfCell=137 intercell=17 cellNeeds=139
                                  └──────────────── rectOfCol - col == intercell (17)
                                                                       cellNeeds  == col + 2
```

`cellNeeds` is `[cell cellSize].width` for the widest row; `col` is the column
width; the row is drawn into `frameOfCell` which equals `col`. The column is
2 pt short of what the cell needs, hence the ellipsis.

## The fix

Because the Scintilla source must stay unmodified (a patch would have to be
re-ported on every Scintilla upgrade), the fix lives entirely in this gem and
touches only the objects Scintilla has already created:

| File | Role |
| --- | --- |
| `mrblib/autocomplete_cocoa.rb` | Reopens `Scintilla::ScintillaCocoa` and wraps `sci_autoc_show` / `sci_userlist_show`; after forwarding the message it calls `Mrbmacs.fixup_autocomplete_listbox`. One seam covers echo-area completion, in-buffer keyword completion and every LSP list, without changing `mruby-mrbmacs-base` or `mruby-mrbmacs-lsp`. |
| `tools/mrbmacs-cocoa/autoc-cocoa.c` | `Mrbmacs.fixup_autocomplete_listbox`: finds the popup and adjusts it. |

`mrbmacs_autoc_fixup()` in `autoc-cocoa.c`:

1. Locates the popup — a borderless `NSWindow` whose scroll-view
   `documentView` is an `NSTableView`. Calltip windows, the font panel and the
   main window are skipped. If nothing matches the function is a no-op.
2. **Shrinks `intercellSpacing.width` to 4 pt** (the row-height component is left
   untouched). This is the actual fix: the reclaimed ~13 pt goes to the text
   column via `sizeLastColumnToFit`.
3. Forces `selectionHighlightStyle = Regular` — currently a no-op, kept as a
   guard against future macOS changes.
4. **Last resort:** if `[cell cellSize].width` for the widest row still does not
   fit the column, widens the popup window (clamped to the screen) and re-fits.
   With step 2 in place this path is not expected to run.

After the fix the same popup measures:

```
[autoc after] win=154 clip=154 col=150 rectOfCol=154 frameOfCell=150 intercell=4 cellNeeds=139
                                 └── col now 11 pt wider than cellNeeds; window unchanged
```

The visible left indent of the row text also drops from ~17 pt to ~4 pt, which
looks tighter.

## Debugging

Set `MRBMACS_AUTOC_DEBUG` to any value before launching:

```sh
MRBMACS_AUTOC_DEBUG=1 ./mruby/bin/mrbmacs-cocoa
```

Every popup then logs one `before` and one `after` line via `NSLog` (visible in
Console.app or on stderr) with the window / clip / column / `rectOfColumn` /
`frameOfCellAtColumn:row:` widths, `intercellSpacing.width`,
`selectionHighlightStyle`, row count, backing scale and the widest
`[cell cellSize].width`. The check is a `getenv` guard, so it costs nothing when
the variable is unset.

## Upstream

Worth reporting to scintilla-interest: on macOS 15 the autocompletion
`NSTableView` gets an `intercellSpacing.width` far larger than the slack
`GetDesiredRect` adds, so long rows are truncated. Reproduce with a user list
containing one long entry.
