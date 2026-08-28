module Scintilla
  # Cocoa-only override.
  #
  # Scintilla's Cocoa autocompletion / user-list popup truncates long entries
  # ("Swap operands to + [comma...") because its NSTableView text column is
  # sized to the raw glyph width, an inflated intercellSpacing.width on current
  # macOS eats the little slack Scintilla adds, and Scintilla provides no
  # message to widen it. See tools/mrbmacs-cocoa/autoc-cocoa.c.
  #
  # sci_autoc_show is used by the echo-area completion (find-file, M-x, buffer
  # switch, ...) and the builtin keyword completion; sci_userlist_show is used
  # by every LSP list (completion, code action, document symbol, navigation).
  # Wrapping both here covers all of them from a single place, without touching
  # mruby-mrbmacs-base or mruby-mrbmacs-lsp.
  #
  # The actual fix lives in tools/mrbmacs-cocoa/autoc-cocoa.c
  # (Mrbmacs.fixup_autocomplete_listbox).
  class ScintillaCocoa
    def sci_autoc_show(length, item_list)
      result = send_message(Scintilla::SCI_AUTOCSHOW, length, item_list)
      mrbmacs_after_autocomplete_list
      result
    end

    def sci_userlist_show(list_type, item_list)
      result = send_message(Scintilla::SCI_USERLISTSHOW, list_type, item_list)
      mrbmacs_after_autocomplete_list
      result
    end

    # Separated out so it can be exercised in tests without a live view; the
    # native helper is only linked into the app binary, not the test binary.
    def mrbmacs_after_autocomplete_list
      return unless Mrbmacs.respond_to?(:fixup_autocomplete_listbox)

      Mrbmacs.fixup_autocomplete_listbox
    end
  end
end
