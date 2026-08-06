module Mrbmacs
  # Forwards Scintilla notifications to the active mrbmacs application.
  class ScintillaNotificationBridge
    def initialize(pane = nil)
      @pane = pane
    end

    def call(notification)
      return if $app.nil?

      if @pane.nil?
        $app.sci_notify(notification)
      else
        $app.sci_notify_from_pane(@pane, notification)
      end
    end
  end

  # Keeps echo-area changes separate from notifications sent by editor panes.
  class EchoNotificationBridge
    def call(notification)
      return if $app.nil?

      $app.echo_sci_notify(notification)
    end
  end

end
