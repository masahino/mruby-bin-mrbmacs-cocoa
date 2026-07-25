module Mrbmacs
  # Forwards Scintilla notifications to the active mrbmacs application.
  class ScintillaNotificationBridge
    def call(notification)
      return if $app.nil?

      $app.sci_notify(notification)
    end
  end

  # A single editor area. A pane owns its Scintilla view and displays one
  # buffer.
  class PaneCocoa
    attr_reader :view
    attr_reader :buffer

    def initialize(view, buffer = nil)
      @view = view
      @buffer = nil
      @view.notification_callback = ScintillaNotificationBridge.new
      self.buffer = buffer unless buffer.nil?
    end

    def buffer=(buffer)
      if buffer.docpointer.nil?
        buffer.docpointer = @view.sci_get_docpointer
      elsif @view.sci_get_docpointer != buffer.docpointer
        @view.sci_add_refdocument(buffer.docpointer)
        @view.sci_set_docpointer(buffer.docpointer)
      end
      @buffer = buffer
    end

    def native_handle
      @view.native_handle
    end
  end

  # One tab represents a complete editor layout, not a buffer.
  class TabCocoa
    attr_reader :panes
    attr_accessor :active_pane

    def initialize(pane)
      @panes = [pane]
      @active_pane = pane
    end
  end

  # One native macOS window containing one or more tabs.
  class FrameCocoa
    attr_reader :tabs
    attr_accessor :active_tab, :native_handle

    def initialize(tab)
      @tabs = [tab]
      @active_tab = tab
      @native_handle = nil
    end

    def active_pane
      @active_tab.active_pane
    end

    def view
      active_pane.view
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
