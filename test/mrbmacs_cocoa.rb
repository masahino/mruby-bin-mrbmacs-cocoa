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
