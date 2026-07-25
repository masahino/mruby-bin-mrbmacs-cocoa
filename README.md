# mruby-bin-mrbmacs-cocoa

Native macOS frontend for mrbmacs, built with AppKit and Scintilla Cocoa.

## Current milestone

The initial implementation:

- starts mruby 4.0.0;
- creates a native AppKit application and window;
- embeds `Scintilla::ScintillaCocoa`;
- forwards Scintilla notifications to the active mrbmacs application;
- opens a file passed on the command line;
- provides a standard application menu and Quit command.

Editor commands, modelines, multiple buffers, and the complete
`mruby-mrbmacs-base` integration will be added incrementally.

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
