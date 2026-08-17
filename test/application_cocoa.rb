assert('Mrbmacs::ApplicationCocoa uses the shared initializer') do
  methods = Mrbmacs::ApplicationCocoa.instance_methods(false)

  assert_false methods.include?(:initialize)
  assert_false methods.include?(:init_buffer)
  assert_true methods.include?(:init_frame)
end


assert('Mrbmacs::ScintillaNotificationBridge forwards to $app') do
  previous_app = $app
  receiver = CocoaNotificationReceiver.new
  notification = { 'code' => Scintilla::SCN_MODIFIED }

  begin
    $app = receiver
    Mrbmacs::ScintillaNotificationBridge.new.call(notification)
    assert_same notification, receiver.notification
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::ScintillaNotificationBridge ignores a missing $app') do
  previous_app = $app

  begin
    $app = nil
    assert_nil Mrbmacs::ScintillaNotificationBridge.new.call(
      'code' => Scintilla::SCN_MODIFIED
    )
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::EchoNotificationBridge forwards echo notifications') do
  previous_app = $app
  receiver = Object.new
  notification = { 'code' => Scintilla::SCN_MODIFIED }
  receiver.define_singleton_method(:echo_sci_notify) do |event|
    @notification = event
  end
  receiver.define_singleton_method(:notification) { @notification }

  begin
    $app = receiver
    Mrbmacs::EchoNotificationBridge.new.call(notification)
    assert_same notification, receiver.notification
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::ApplicationCocoa dispatches Scintilla notifications') do
  app = CocoaApplicationForTest.new
  notification = { 'code' => Scintilla::SCN_MODIFIED }

  app.sci_notify(notification)
  assert_same notification, app.notification
end


assert('Mrbmacs::ApplicationCocoa owns its Cocoa frame and initial buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))
  app = build_cocoa_application_for_test(frame, buffer)

  assert_same frame, app.frame
  assert_same buffer, app.current_buffer
  assert_equal [buffer], app.buffer_list
  assert_equal({}, app.sci_handler)
  assert_kind_of Mrbmacs::Config, app.config
  assert_kind_of Mrbmacs::Base16DefaultDarkTheme, app.theme
  assert_true pane.view.theme_messages.include?(
    [:lexer, buffer.mode.lexer]
  )
  assert_true pane.view.theme_messages.include?(
    [:style_fore, Scintilla::STYLE_DEFAULT, app.theme.foreground_color]
  )
  assert_true pane.view.theme_messages.include?(
    [
      :element_colour,
      Scintilla::SC_ELEMENT_SELECTION_INACTIVE_TEXT,
      app.theme.background_color | 0xff000000
    ]
  )
  assert_true pane.view.theme_messages.include?(
    [
      :element_colour,
      Scintilla::SC_ELEMENT_SELECTION_INACTIVE_BACK,
      app.theme.foreground_color | 0xff000000
    ]
  )
end

assert('Mrbmacs::ApplicationCocoa applies the shared echo-area keymap') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)
  build_cocoa_application_for_test(frame, buffer)
  ctrl = Scintilla::SCMOD_META << 16

  assert_equal 1, echo_win.autocomplete_choose_single
  assert_true echo_win.command_keys.include?(
    [ctrl + 'a'.ord, Scintilla::SCI_HOME]
  )
  assert_true echo_win.command_keys.include?(
    [ctrl + 'e'.ord, Scintilla::SCI_LINEEND]
  )
  assert_true echo_win.command_keys.include?(
    [ctrl + 'k'.ord, Scintilla::SCI_DELLINERIGHT]
  )
  assert_true echo_win.command_keys.include?(
    [ctrl + 'y'.ord, Scintilla::SCI_PASTE]
  )
end

assert('Mrbmacs::ApplicationCocoa registers native IO readability') do
  app = CocoaIOApplicationForTest.allocate
  app.init_instance_variables
  io = Object.new
  io.define_singleton_method(:close) {}
  called = false

  app.add_io_read_event(io) { |_application, readable_io|
    called = readable_io.equal?(io)
  }
  app.process_io_read_event(io)

  assert_same io, app.watched_io
  assert_true called

  app.del_io_read_event(io)
  assert_same io, app.unwatched_io
end

assert('Mrbmacs::ApplicationCocoa follows native pane focus') do
  first_buffer = Mrbmacs::Buffer.new('first')
  second_buffer = Mrbmacs::Buffer.new('second')
  first = Mrbmacs::PaneCocoa.new(
    CocoaViewForLayoutTest.new(101), first_buffer
  )
  second = Mrbmacs::PaneCocoa.new(
    CocoaViewForLayoutTest.new(102), second_buffer
  )
  tab = Mrbmacs::TabCocoa.new(first)
  tab.split(first, second, :vertical)
  frame = Mrbmacs::FrameCocoa.new(tab)
  app = build_cocoa_application_for_test(frame, first_buffer)
  previous_app = $app

  begin
    $app = app
    second.view.notification_callback.call(
      'code' => Scintilla::SCN_MODIFIED
    )
    assert_same first, frame.active_pane
    assert_same first_buffer, app.current_buffer

    second.view.notification_callback.call(
      'code' => Scintilla::SCN_FOCUSIN
    )
    assert_same second, frame.active_pane
    assert_same second_buffer, app.current_buffer
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::ApplicationCocoa opens a new file with shared find_file') do
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-cocoa-find-#{$$}.rb"
  File.delete(filename) if File.exist?(filename)
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view, buffer)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))
  app = build_cocoa_application_for_test(frame, buffer)

  app.find_file(filename)

  assert_equal File.expand_path(filename), app.current_buffer.filename
  assert_equal 2, app.buffer_list.length
  assert_same app.current_buffer, pane.buffer
  assert_equal 'New file', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa switches safely with only one buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  frame.input_events = [[:enter, '']]
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('b')
  assert_same buffer, app.current_buffer
  assert_equal [buffer], app.buffer_list
end

assert('Mrbmacs::ApplicationCocoa kills a buffer through shared command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  frame = CocoaFrameForConfirmationTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = build_cocoa_application_for_test(frame, buffer)
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-kill-#{$$}.txt"
  app.find_file(filename)
  frame.input_events = [[:enter, '']]

  assert_true app.key_press('C-x')
  assert_true app.key_press('k')
  assert_equal ['*scratch*'], app.buffer_list.map(&:name)
  assert_equal '*scratch*', app.current_buffer.name
end

assert('Mrbmacs::ApplicationCocoa handles a Scintilla key command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('C-f')
  assert_equal [Scintilla::SCI_CHARRIGHT], view.messages
end


assert('Mrbmacs::ApplicationCocoa handles a prefix Scintilla command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('u')
  assert_equal [Scintilla::SCI_UNDO], view.messages
end

assert('Mrbmacs::ApplicationCocoa treats Escape as a Meta prefix') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('Escape')
  assert_true app.key_press('f')
  assert_equal [Scintilla::SCI_WORDRIGHT], view.messages
end

assert('Mrbmacs::ApplicationCocoa clears an undefined Escape prefix') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('Escape')
  assert_false app.key_press('z')
  assert_true app.key_press('C-f')
  assert_equal [Scintilla::SCI_CHARRIGHT], view.messages
end


assert('Mrbmacs::ApplicationCocoa leaves text input to Cocoa') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_false app.key_press('a')
  assert_equal [], view.messages
end


assert('Mrbmacs::ApplicationCocoa runs a shared Ruby editor command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('C-a')
  assert_equal [Scintilla::SCI_HOME], view.messages
end

assert('Mrbmacs::ApplicationCocoa handles mark, copy, and yank commands') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  view.current_pos = 2
  assert_true app.key_press('C- ')
  view.current_pos = 7
  assert_true app.key_press('M-w')
  assert_true app.key_press('C-y')

  assert_equal [[2, 7]], view.copied_ranges
  assert_equal [
    [:set_anchor, 2],
    [:set_selection_mode, 0],
    [:set_empty_selection, 7],
    :paste
  ], view.messages
end

assert('Mrbmacs::ApplicationCocoa handles newline') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('Enter')
  assert_equal [:new_line], view.messages
end


assert('Mrbmacs::ApplicationCocoa saves through a shared Ruby command') do
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-cocoa-save-#{$$}.txt"
  buffer = Mrbmacs::Buffer.new(filename)
  view = CocoaViewForLayoutTest.new
  view.text = "saved from Cocoa\n"
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  begin
    assert_true app.key_press('C-x')
    assert_true app.key_press('C-s')
    assert_equal "saved from Cocoa\n", File.read(filename)
    assert_true view.save_point
  ensure
    File.delete(filename) if File.exist?(filename)
  end
end

assert('Mrbmacs::ApplicationCocoa exits through its Cocoa frame') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = CocoaFrameForExitTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = build_cocoa_application_for_test(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('C-c')
  assert_true frame.exited
end
