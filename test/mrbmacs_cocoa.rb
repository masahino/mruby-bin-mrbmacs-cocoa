class CocoaNotificationReceiver
  attr_reader :notification

  def sci_notify(notification)
    @notification = notification
  end
end

class CocoaApplicationForTest < Mrbmacs::ApplicationCocoa
  attr_reader :notification

  def initialize
  end

  def call_sci_event(notification)
    @notification = notification
  end
end

class CocoaFrameForExitTest < Mrbmacs::FrameCocoa
  attr_reader :exited

  def exit
    @exited = true
  end
end

class CocoaViewForLayoutTest
  attr_accessor :notification_callback
  attr_accessor :current_pos
  attr_accessor :text
  attr_reader :added_documents, :copied_ranges, :set_documents
  attr_reader :messages, :save_point

  def initialize(docpointer = 100)
    @docpointer = docpointer
    @added_documents = []
    @copied_ranges = []
    @current_pos = 0
    @set_documents = []
    @messages = []
    @text = ''
    @save_point = false
  end

  def sci_get_docpointer
    @docpointer
  end

  def sci_add_refdocument(docpointer)
    @added_documents << docpointer
  end

  def sci_set_docpointer(docpointer)
    @set_documents << docpointer
    @docpointer = docpointer
  end

  def send_message(message)
    @messages << message
  end

  def sci_home
    @messages << Scintilla::SCI_HOME
  end

  def sci_get_current_pos
    @current_pos
  end

  def sci_set_anchor(position)
    @messages << [:set_anchor, position]
  end

  def sci_get_move_extends_selection
    0
  end

  def sci_set_selection_mode(mode)
    @messages << [:set_selection_mode, mode]
  end

  def sci_copy_range(start_pos, end_pos)
    @copied_ranges << [start_pos, end_pos]
  end

  def sci_set_empty_selection(position)
    @messages << [:set_empty_selection, position]
  end

  def sci_paste
    @messages << :paste
  end

  def sci_autoc_active
    false
  end

  def sci_new_line
    @messages << :new_line
  end

  def sci_get_length
    @text.bytesize
  end

  def sci_get_text(_length)
    @text
  end

  def sci_set_save_point
    @save_point = true
  end

  def sci_marker_delete_all(_marker)
  end

  def native_handle
    1234
  end
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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_same frame, app.frame
  assert_same buffer, app.current_buffer
  assert_equal [buffer], app.buffer_list
  assert_equal({}, app.sci_handler)
  assert_kind_of Mrbmacs::Config, app.config
end


assert('Mrbmacs::ApplicationCocoa handles a Scintilla key command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-f')
  assert_equal [Scintilla::SCI_CHARRIGHT], view.messages
end


assert('Mrbmacs::ApplicationCocoa handles a prefix Scintilla command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_false app.key_press('a')
  assert_equal [], view.messages
end


assert('Mrbmacs::ApplicationCocoa runs a shared Ruby editor command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-a')
  assert_equal [Scintilla::SCI_HOME], view.messages
end

assert('Mrbmacs::ApplicationCocoa handles mark, copy, and yank commands') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

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
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('C-c')
  assert_true frame.exited
end


assert('Cocoa layout starts with one frame, one tab, and one pane') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  tab = Mrbmacs::TabCocoa.new(pane)
  frame = Mrbmacs::FrameCocoa.new(tab)

  assert_same view, pane.view
  assert_kind_of Mrbmacs::ScintillaNotificationBridge,
                 view.notification_callback
  assert_equal [pane], tab.panes
  assert_same pane, tab.active_pane
  assert_equal [tab], frame.tabs
  assert_same tab, frame.active_tab
  assert_same pane, frame.active_pane
  assert_same view, frame.view
  assert_equal 1234, pane.native_handle
end

assert('Cocoa layout exposes the shared frame and edit-window interface') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  assert_kind_of Mrbmacs::FrameBase, frame
  assert_same view, pane.sci
  assert_same view, frame.view_win
  assert_same pane, frame.edit_win
  assert_equal [pane], frame.edit_win_list
end

assert('Mrbmacs::TabCocoa is a layout and not a buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)

  assert_same buffer, pane.buffer
  assert_false tab.respond_to?(:buffer)
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
