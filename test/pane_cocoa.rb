assert('Mrbmacs::PaneCocoa applies active native mode line colors') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  calls = []
  pane.define_singleton_method(:update_native_modeline_theme) do |fore, back|
    calls << [fore, back]
  end
  pane.modeline_native_handle = 1
  theme = Mrbmacs::SolarizedDarkTheme.new

  pane.apply_theme(theme)
  pane.apply_modeline_theme(true)

  assert_equal [theme.font_color[:color_mode_line][0, 2]], calls
end

assert('Mrbmacs::PaneCocoa configures its line number margin') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)

  assert_true view.margin_messages.include?(
    [:margin_width, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 6]
  )
  assert_true view.margin_messages.include?(
    [
      :margin_mask,
      Mrbmacs::EditWindow::MARGIN_LINE_NUMBER,
      Mrbmacs::MARKERMASK_LINE_NUMBER
    ]
  )
  assert_true view.margin_messages.include?(
    [:margin_sensitive, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 1]
  )

  margin_width_count = view.margin_messages.count do |message|
    message == [:margin_width, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 6]
  end
  pane.apply_theme(Mrbmacs::SolarizedDarkTheme.new)
  assert_equal margin_width_count + 1, view.margin_messages.count { |message|
    message == [:margin_width, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 6]
  }
end

assert('Mrbmacs::PaneCocoa configures its folding margin') do
  view = CocoaViewForLayoutTest.new
  Mrbmacs::PaneCocoa.new(view)

  assert_true view.margin_messages.include?(
    [:margin_width, Mrbmacs::EditWindow::MARGIN_FOLDING, 2]
  )
  assert_true view.margin_messages.include?(
    [
      :margin_mask,
      Mrbmacs::EditWindow::MARGIN_FOLDING,
      Scintilla::SC_MASK_FOLDERS
    ]
  )
  assert_true view.margin_messages.include?(
    [:margin_sensitive, Mrbmacs::EditWindow::MARGIN_FOLDING, 1]
  )
  assert_true view.fold_messages.include?(
    [:automatic_fold, Scintilla::SC_AUTOMATICFOLD_CLICK]
  )
  assert_true view.fold_messages.include?(
    [
      :marker,
      Scintilla::SC_MARKNUM_FOLDER,
      Scintilla::SC_MARK_BOXPLUS
    ]
  )
  assert_true view.fold_messages.include?(
    [
      :marker,
      Scintilla::SC_MARKNUM_FOLDEROPEN,
      Scintilla::SC_MARK_BOXMINUS
    ]
  )
end

assert('Mrbmacs::PaneCocoa configures the shared version control gutter') do
  view = CocoaViewForLayoutTest.new
  view.text_width_scale = 8
  Mrbmacs::PaneCocoa.new(view)
  marker_mask = (1 << Mrbmacs::MARKERN_VC_ADDED) |
                (1 << Mrbmacs::MARKERN_VC_MODIFIED) |
                (1 << Mrbmacs::MARKERN_VC_DELETED)

  assert_equal [:margin_width, Mrbmacs::EditWindow::MARGIN_VC, 8],
               view.margin_messages.select { |message|
                 message[0] == :margin_width &&
                   message[1] == Mrbmacs::EditWindow::MARGIN_VC
               }.last
  assert_true view.margin_messages.include?(
    [:margin_mask, Mrbmacs::EditWindow::MARGIN_VC, marker_mask]
  )
  assert_true view.fold_messages.include?(
    [
      :marker,
      Mrbmacs::MARKERN_VC_ADDED,
      Scintilla::SC_MARK_LEFTRECT
    ]
  )
end

assert('Mrbmacs::PaneCocoa recalculates the change history gutter width') do
  view = CocoaViewForLayoutTest.new
  view.text_width_scale = 8
  Mrbmacs::PaneCocoa.new(view)
  assert_equal(
    [:margin_width, Mrbmacs::EditWindow::MARGIN_CHANGE_HISTORY, 8],
    view.margin_messages.select { |message|
      message[0] == :margin_width &&
        message[1] == Mrbmacs::EditWindow::MARGIN_CHANGE_HISTORY
    }.last
  )
end

assert('Mrbmacs::PaneCocoa limits modification events to text changes') do
  view = CocoaViewForLayoutTest.new
  Mrbmacs::PaneCocoa.new(view)

  assert_equal [Scintilla::SC_MOD_INSERTTEXT | Scintilla::SC_MOD_DELETETEXT],
               view.mod_event_masks
end

assert('Mrbmacs::PaneCocoa applies shared Scintilla defaults') do
  view = CocoaViewForLayoutTest.new
  Mrbmacs::PaneCocoa.new(view)

  assert_equal [Scintilla::SC_CP_UTF8], view.codepages
  assert_equal [10], view.autoc_max_heights
  assert_equal ["\t".ord], view.autoc_separators
end

assert('Mrbmacs::PaneCocoa reports its native width in text columns') do
  pane = CocoaPaneWidthForTest.new(CocoaViewForLayoutTest.new)

  assert_equal 800, pane.width
end

assert('Mrbmacs::PaneCocoa configures a Scintilla block caret') do
  view = CocoaViewForLayoutTest.new
  Mrbmacs::PaneCocoa.new(view)
  style = Scintilla::CARETSTYLE_BLOCK_AFTER |
          Scintilla::CARETSTYLE_OVERSTRIKE_BLOCK |
          Scintilla::CARETSTYLE_BLOCK

  assert_true view.caret_styles.include?(style)
end

assert('Mrbmacs::PaneCocoa uses the theme foreground for its caret') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  dark_theme = Mrbmacs::SolarizedDarkTheme.new
  light_theme = Mrbmacs::SolarizedLightTheme.new

  pane.apply_theme(dark_theme)
  pane.apply_theme(light_theme)

  assert_equal [0xffffff, dark_theme.foreground_color, light_theme.foreground_color],
               view.caret_colors
end

assert('Mrbmacs::PaneCocoa uses the theme background for its fold margin') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  theme = Mrbmacs::SolarizedDarkTheme.new

  pane.apply_theme(theme)

  assert_true view.theme_messages.include?(
    [:fold_margin_color, true, theme.background_color]
  )
  assert_true view.theme_messages.include?(
    [:fold_margin_highlight, true, theme.background_color]
  )
end

assert('Mrbmacs::PaneCocoa applies the breakpoint marker colors') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  theme = Mrbmacs::Theme.new
  colors = theme.font_color[:color_marker_breakpoint]

  pane.apply_theme(theme)

  assert_true view.theme_messages.include?(
    [:marker_fore, Mrbmacs::MARKERN_BREAKPOINT, colors[0]]
  )
  assert_true view.theme_messages.include?(
    [:marker_back, Mrbmacs::MARKERN_BREAKPOINT, colors[1]]
  )
end

assert('Mrbmacs::PaneCocoa assigns its initial document to a buffer') do
  view = CocoaViewForLayoutTest.new(123)
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(view, buffer)

  assert_same buffer, pane.buffer
  assert_equal 123, buffer.docpointer
  assert_equal [], view.added_documents
  assert_equal [], view.set_documents
end


assert('Mrbmacs::PaneCocoa displays an existing buffer document') do
  view = CocoaViewForLayoutTest.new(123)
  buffer = Mrbmacs::Buffer.new('*scratch*')
  buffer.docpointer = 456
  pane = Mrbmacs::PaneCocoa.new(view, buffer)

  assert_same buffer, pane.buffer
  assert_equal [456], view.added_documents
  assert_equal [456], view.set_documents
end
