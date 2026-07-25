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

The sibling `mruby-scintilla-cocoa` repository must exist next to this
repository.

```sh
rake
```

Run the tests:

```sh
rake test
```

Run the development executable:

```sh
./mruby/bin/mrbmacs-cocoa
./mruby/bin/mrbmacs-cocoa path/to/file
```
