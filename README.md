# mruby-bin-mrbmacs-cocoa

Native macOS frontend for mrbmacs, built with AppKit and Scintilla Cocoa.

## Current milestone

The initial implementation:

- starts mruby 4.0.0;
- creates a native AppKit application and window;
- embeds `Scintilla::ScintillaCocoa`;
- forwards Scintilla notifications to the active mrbmacs application;
- represents the initial editor as one frame, one layout tab, and one pane;
- connects the pane's Scintilla document to an `Mrbmacs::Buffer`;
- creates an `ApplicationCocoa` that owns the initial frame and buffer;
- routes handled Emacs-style keys to the mrbmacs keymap while leaving other
  text input to Cocoa and its IME path;
- exposes the active Cocoa pane through the shared Frame/EditWindow interface;
- executes shared Ruby editor commands, including basic movement and saving;
- opens a file passed on the command line;
- opens existing and new files with `C-x C-f`;
- provides an echo area with minibuffer input, Emacs-style editing keys, and
  completion;
- executes commands by name with `M-x`;
- switches buffers with `C-x b` and kills buffers with `C-x k`;
- searches incrementally through the echo area with `C-s` and `C-r`;
- replaces text with `M-x replace-string` and `M-%` query replace;
- splits panes with `C-x 2` and `C-x 3`, selects them by click or `C-x o`,
  and removes them with `C-x 0` or `C-x 1`;
- displays the shared mrbmacs mode line in each Cocoa pane;
- applies the configured mrbmacs theme to editor panes and native mode lines,
  with runtime selection through `M-x select-theme`;
- uses Menlo 14 by default and opens the native font panel with
  `M-x select-font`;
- displays line numbers in each editor pane;
- displays theme-aware block carets in editor panes and the echo area;
- provides a standard application menu and Quit command.

Native tabs and the remaining
`mruby-mrbmacs-base` integration will be added incrementally.

Tabs represent complete pane layouts rather than individual buffers. This
keeps tabs compatible with Emacs-style window splitting and allows a buffer to
be displayed in more than one pane or tab.

## Download

Signed and notarized preview builds for Apple Silicon are available from
[GitHub Releases](https://github.com/masahino/mruby-bin-mrbmacs-cocoa/releases).

## Build

The build downloads mruby 4.0.0 and all required mrbgems, including
`mruby-scintilla-cocoa`.

```sh
git clone https://github.com/masahino/mruby-bin-mrbmacs-cocoa.git
cd mruby-bin-mrbmacs-cocoa
rake
```

For development, a sibling `mruby-scintilla-cocoa` checkout is used
automatically when present.

Run the tests:

```sh
rake test
```

Run the development executable:

```sh
./mruby/bin/mrbmacs-cocoa
./mruby/bin/mrbmacs-cocoa path/to/file
```

The Cocoa frontend uses the shared mrbmacs command-line options and loads
`~/.mrbmacsrc` during startup. Use `-q` to skip the init file or `-l FILE` to
load an additional Ruby file.

Release maintainers should see [docs/release.md](docs/release.md).
