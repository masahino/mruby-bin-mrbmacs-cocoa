assert('Cocoa frame derives its initial editor size from columns and lines') do
  view = CocoaViewForLayoutTest.new
  view.text_width_scale = 8
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  assert_equal 120, Mrbmacs::FrameCocoa::INITIAL_COLUMNS
  assert_equal 40, Mrbmacs::FrameCocoa::INITIAL_LINES
  assert_equal 1040, frame.initial_native_editor_width
  assert_equal 640, frame.initial_native_editor_height

  view.text_width_scale = 10
  view.define_singleton_method(:sci_text_height) { |_line| 20 }
  pane.update_margin_widths

  assert_equal 1300, frame.initial_native_editor_width
  assert_equal 800, frame.initial_native_editor_height
end

assert('Mrbmacs::FrameCocoa configures its echo-area caret') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)
  theme = Mrbmacs::SolarizedDarkTheme.new
  style = Scintilla::CARETSTYLE_BLOCK_AFTER |
          Scintilla::CARETSTYLE_OVERSTRIKE_BLOCK |
          Scintilla::CARETSTYLE_BLOCK

  frame.apply_theme(theme)

  assert_equal [style], echo_win.caret_styles
  assert_equal [theme.foreground_color], echo_win.caret_colors
end

assert('Mrbmacs::FrameCocoa provides the shared notification queue') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  assert_equal [], frame.sci_notifications
end

assert('Mrbmacs::FrameCocoa shows annotations in the active pane') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  frame.show_annotation(3, 1, 'Warning:message', 42)

  assert_equal [[:text, 2, 'Warning:message'], [:style, 2, 42]],
               view.annotations
end

assert('Mrbmacs::FrameCocoa applies a font to every pane and echo area') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  first = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(101), buffer)
  second = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(102), buffer)
  tab = Mrbmacs::TabCocoa.new(first)
  tab.split(first, second, :vertical)
  echo_win = CocoaViewForLayoutTest.new(103)
  frame = Mrbmacs::FrameCocoa.new(tab, echo_win)
  theme = Mrbmacs::SolarizedDarkTheme.new
  frame.apply_theme(theme)
  frame.set_font('Monaco', 16)

  [first.view, second.view, echo_win].each do |view|
    assert_true view.theme_messages.include?(
      [:style_font, Scintilla::STYLE_DEFAULT, 'Monaco']
    )
    assert_true view.theme_messages.include?(
      [:style_size, Scintilla::STYLE_DEFAULT, 16]
    )
  end
  [first.view, second.view].each do |view|
    assert_true view.theme_messages.include?(:style_clear_all)
  end
  assert_true echo_win.theme_messages.include?([:extra_ascent, 3])
  assert_true echo_win.theme_messages.include?([:extra_descent, 3])
end

assert('Mrbmacs::FrameCocoa updates the active pane mode line') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))
  app = CocoaModelineApplicationForTest.new

  frame.modeline(app)

  assert_equal app.modeline_str, pane.modeline_text
end

assert('Mrbmacs::FrameCocoa displays messages in its shared echo area') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)

  frame.echo_puts('New file')

  assert_same echo_win, frame.echo_win
  assert_false echo_win.horizontal_scrollbar
  assert_false echo_win.vertical_scrollbar
  (0..2).each do |margin|
    assert_true echo_win.margin_messages.include?([:margin_width, margin, 0])
  end
  assert_equal 'New file', echo_win.text
  assert_true echo_win.messages.include?(:document_end)
  assert_equal 'New file', frame.last_message
end

assert('Mrbmacs::FrameCocoa configures a separate echo notification bridge') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)

  assert_kind_of Mrbmacs::EchoNotificationBridge,
                 echo_win.notification_callback
end

assert('Mrbmacs::FrameCocoa reads input through its shared echo area') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:enter, '/tmp/test.rb']]

  assert_equal '/tmp/test.rb', frame.echo_gets('Find file: ', '/tmp/')
  assert_equal '', echo_win.text
  assert_true echo_win.margin_messages.include?([:margin_text, 0, 'Find file: '])
  assert_true echo_win.margin_messages.include?([:margin_text, 0, ''])
  assert_true view.messages.include?(:grab_focus)
end


assert('Mrbmacs::FrameCocoa completes echo input with Tab') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:tab, 'for'], :enter, :enter]

  result = frame.echo_gets('M-x ') do |input|
    ['forward-char forward-line', input.length]
  end

  assert_equal 'forward-char', result
  assert_true view.messages.include?(:grab_focus)
end

assert('Mrbmacs::FrameCocoa selects a buffer through its echo area') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:enter, 'notes.rb']]

  result = frame.select_buffer('*scratch*', ['*scratch*', 'notes.rb'])

  assert_equal 'notes.rb', result
  assert_true echo_win.margin_messages.include?(
    [:margin_text, 0, 'Switch to buffer: (default *scratch*) ']
  )
  assert_true view.messages.include?(:grab_focus)
end

assert('Mrbmacs::FrameCocoa completes buffer names by prefix') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:tab, 'no'], :enter, :enter]

  result = frame.select_buffer(
    '*scratch*', ['*scratch*', 'notes.rb', 'notice.txt']
  )

  assert_equal 'notes.rb', result
  assert_equal [2, 'notes.rb notice.txt'], echo_win.autocomplete_lists.first
  assert_true view.messages.include?(:grab_focus)
end

assert('Mrbmacs::FrameCocoa confirms with one modal key') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForConfirmationTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )

  frame.confirmation_event = :yes
  assert_true frame.y_or_n('Buffer modified; kill anyway? (y or n) ')
  frame.confirmation_event = :no
  assert_false frame.y_or_n('Buffer modified; kill anyway? (y or n) ')
  assert_equal '', echo_win.text
  assert_true view.messages.include?(:grab_focus)
  assert_true echo_win.margin_messages.include?([:margin_text, 0, ''])
end
