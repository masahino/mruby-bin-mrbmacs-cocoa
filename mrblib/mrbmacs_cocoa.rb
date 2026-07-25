module Mrbmacs
  # Forwards Scintilla notifications to the active mrbmacs application.
  class ScintillaNotificationBridge
    def call(notification)
      return if $app.nil?

      $app.sci_notify(notification)
    end
  end

  # Native macOS mrbmacs application.
  class ApplicationCocoa < Application
    def sci_notify(notification)
      $stderr.puts notification['code'] if $DEBUG
      call_sci_event(notification)
    end
  end
end
