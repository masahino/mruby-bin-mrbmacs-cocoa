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

    # EditWindow-compatible access used by shared editor commands.
    def sci
      @view
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
  class FrameCocoa < FrameBase
    attr_reader :echo_win
    attr_reader :tabs
    attr_reader :last_message
    attr_accessor :active_tab, :native_handle

    def initialize(tab, echo_win = nil)
      @tabs = [tab]
      @active_tab = tab
      @echo_win = echo_win
      @native_handle = nil
      @last_message = nil
      view.sci_set_hscrollbar(false)
      unless @echo_win.nil?
        @echo_win.sci_set_hscrollbar(false)
        @echo_win.sci_set_vscrollbar(false)
        @echo_win.sci_set_margin_typen(3, 4)
      end
    end

    def active_pane
      @active_tab.active_pane
    end

    def view
      active_pane.view
    end

    # FrameBase-compatible accessors are derived from the active layout. They
    # are not separate state, so changing tabs or panes cannot leave stale
    # view/edit-window references behind.
    def view_win
      view
    end

    def edit_win
      active_pane
    end

    def edit_win_list
      @active_tab.panes
    end

    def echo_puts(text)
      @last_message = text.to_s
      if @echo_win.nil?
        $stderr.puts @last_message
      else
        @echo_win.sci_clear_all
        @echo_win.sci_add_text(@last_message.bytesize, @last_message)
        @echo_win.sci_document_end
      end
    end

    def echo_set_prompt(prompt)
      width = @echo_win.sci_text_width(Scintilla::STYLE_DEFAULT, prompt)
      @echo_win.sci_set_margin_widthn(3, width)
      @echo_win.sci_margin_set_text(0, prompt)
    end

    def echo_gets(prompt, text = '', &block)
      @echo_win.sci_clear_all
      echo_set_prompt(prompt)
      @echo_win.sci_add_text(text.bytesize, text)
      input = nil

      loop do
        case wait_echo_event
        when :cancel
          break
        when :enter
          if @echo_win.sci_autoc_active
            @echo_win.sci_autoc_complete
          else
            input = @echo_win.sci_get_line(0)
            break
          end
        when :tab
          complete_echo_input(block) unless block.nil?
        end
      end
      input
    ensure
      @echo_win.sci_autoc_cancel unless @echo_win.nil?
      @echo_win.sci_clear_all unless @echo_win.nil?
      echo_set_prompt('') unless @echo_win.nil?
      view.sci_grab_focus
    end

    def complete_echo_input(block)
      input_text = @echo_win.sci_get_line(0)
      was_active = @echo_win.sci_autoc_active
      @echo_win.sci_autoc_cancel if was_active
      completion_list, length = block.call(input_text)

      if was_active
        candidates = completion_list.split(
          @echo_win.sci_autoc_get_separator.chr
        )
        common = Mrbmacs.common_prefix(candidates)
        unless common.nil?
          suffix = common[length..]
          @echo_win.sci_add_text(suffix.bytesize, suffix) unless suffix.nil?
          length = common.length
        end
      end
      @echo_win.sci_autoc_show(length, completion_list)
    end

    def wait_echo_event
      raise NotImplementedError
    end
  end

  # Native macOS mrbmacs application.
  class ApplicationCocoa < Application
    def initialize(frame, buffer)
      init_instance_variables
      @logger = init_logfile
      @frame = frame
      @current_buffer = buffer
      @buffer_list = [buffer]
      @keymap = ViewKeyMap.new
      @prefix_key = ''
      @command_list = Mrbmacs::Command.instance_methods.map(&:to_s).sort
    end

    def sci_notify(notification)
      $stderr.puts notification['code'] if $DEBUG
      call_sci_event(notification)
    end

    # Use the shared file-loading path for command-line files as well as files
    # opened after startup. A missing path therefore starts as an empty new
    # file instead of placing an error message in the editor document.
    def load_initial_file(filename = nil)
      open_file(filename) unless filename.nil?
      @frame.view.sci_set_save_point
    end

    # Cocoa terminates its native event loop through FrameCocoa#exit. Avoid
    # raising SystemExit while handling an NSEvent callback.
    def save_buffers_kill_terminal
      before_save_buffers_kill_terminal(self)
      @frame.exit
    end

    # Returns true only when mrbmacs consumed the key. Unhandled keys continue
    # through Scintilla's Cocoa text input path, including IME composition.
    def key_press(key)
      if key == 'Escape'
        add_recent_key(key)
        @prefix_key = 'M-'
        return true
      end

      key_sequence = "#{@prefix_key}#{key}"
      command = key_scan(key_sequence)
      if command.nil?
        @prefix_key = ''
        return false
      end

      add_recent_key(key)
      if command.is_a?(Integer)
        @frame.view.send_message(command)
        @prefix_key = ''
      elsif command == 'prefix'
        @prefix_key = "#{key_sequence} "
      else
        extend(command)
        @prefix_key = ''
      end
      true
    end
  end
end
