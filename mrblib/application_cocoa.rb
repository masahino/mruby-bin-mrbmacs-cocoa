module Mrbmacs
  # Native macOS mrbmacs application.
  class ApplicationCocoa < Application
    def set_keybind(win, key, command)
      keydef = 0
      key_parts = key.split('-')
      if key_parts.length == 2
        modifier, key_char = key_parts
        keydef += Scintilla::SCMOD_META << 16 if modifier == 'C'
        keydef += Scintilla::SCMOD_ALT << 16 if modifier == 'M'
        keydef += key_char == 'DEL' ? Scintilla::SCK_DELETE : key_char.ord
      else
        keydef = key.ord
      end
      win.sci_assign_cmdkey(keydef, command)
    end

    def init_instance_variables
      super
      @prefix_key = ''
      @isearch_active = false
      @isearch_backward = false
      @isearch_origin = nil
      @isearch_setting_text = false
      @isearch_text = ''
      @query_replace_active = false
      @replace_count = 0
      @replace_search_text = nil
      @replacement_text = nil
      @replace_next_pos = nil
    end

    def init_frame
      view = Scintilla::ScintillaCocoa.new
      echo_view = Scintilla::ScintillaCocoa.new
      pane = PaneCocoa.new(view, @current_buffer)
      @frame = FrameCocoa.new(TabCocoa.new(pane), echo_view)
      initialize_native_frame
    end

    def add_io_read_event(io, &block)
      super
      watch_io_read_event(io)
    end

    def del_io_read_event(io)
      unwatch_io_read_event(io)
      super
    end

    def process_io_read_event(io)
      handler = @io_handler[io]
      handler.call(self, io) unless handler.nil?
    rescue StandardError => e
      @logger.error e.to_s
      @logger.error e.backtrace
      @frame.echo_puts(e.to_s)
    end

    def sci_notify(notification)
      if notification['code'] == Scintilla::SCN_URIDROPPED
        queue_native_file_uri(notification['text'])
        return
      end

      $stderr.puts notification['code'] if $DEBUG
      call_sci_event(notification)
      @frame.modeline(self) unless @frame.nil?
    end

    def open_native_files(paths)
      paths.each { |path| find_file(path) }
      @frame.view_win.sci_grab_focus
    end

    def sci_notify_from_pane(pane, notification)
      if notification['code'] == Scintilla::SCN_FOCUSIN
        @frame.active_tab.active_pane = pane
        @current_buffer = pane.buffer
      end
      sci_notify(notification)
    end

    def echo_key_press(key)
      return query_replace_key_press(key) if @query_replace_active
      return false unless @isearch_active

      case key
      when 'C-s'
        isearch_forward
      when 'C-r'
        isearch_backward
      when 'Enter'
        finish_isearch(false)
      when 'C-g'
        finish_isearch(true)
      else
        if key.start_with?('C-', 'M-') || key == 'Escape'
          finish_isearch(false)
        else
          return false
        end
      end
      true
    end

    # Cocoa uses a layout tree and NSSplitView instead of terminal coordinates.
    def split_window(horizontal)
      active_pane = @frame.active_pane
      orientation = horizontal ? :horizontal : :vertical
      unless @frame.native_handle.nil?
        minimum_extent = if horizontal
                           active_pane.view.sci_text_width(
                             Scintilla::STYLE_DEFAULT, '0' * 10
                           )
                         else
                           active_pane.view.sci_text_height(0) * 3 + 22
                         end
        unless @frame.pane_can_split?(
          active_pane, orientation, minimum_extent
        )
          @frame.echo_puts('too small for splitting')
          return
        end
      end

      new_view = Scintilla::ScintillaCocoa.new
      new_pane = PaneCocoa.new(new_view, active_pane.buffer)
      new_view.sci_set_hscrollbar(false)
      apply_keymap(new_view, @keymap)
      new_pane.set_font(@frame.font_name, @frame.font_size)
      unless @theme.nil?
        new_pane.apply_theme(@theme)
        apply_theme_to_mode(active_pane.buffer.mode, new_pane, @theme)
      end

      split = @frame.active_tab.split(active_pane, new_pane, orientation)
      unless @frame.native_handle.nil?
        split.native_handle = @frame.split_native_pane(
          active_pane, new_pane, orientation
        )
      end
      @frame.modeline(self, active_pane)
      @frame.modeline(self, new_pane)
      @frame.switch_window(active_pane)
    end

    def add_buffer_to_frame(_buffer)
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
