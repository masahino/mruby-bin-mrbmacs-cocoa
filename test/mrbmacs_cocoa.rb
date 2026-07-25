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

class CocoaViewForLayoutTest
  attr_accessor :notification_callback
  attr_reader :added_documents, :set_documents

  def initialize(docpointer = 100)
    @docpointer = docpointer
    @added_documents = []
    @set_documents = []
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
