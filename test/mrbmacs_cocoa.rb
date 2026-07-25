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
  buffer = Object.new
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)

  assert_same buffer, pane.buffer
  assert_false tab.respond_to?(:buffer)
end
