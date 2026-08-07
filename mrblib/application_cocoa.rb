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
      $stderr.puts notification['code'] if $DEBUG
      call_sci_event(notification)
      @frame.modeline(self) unless @frame.nil?
    end

    def sci_notify_from_pane(pane, notification)
      if notification['code'] == Scintilla::SCN_FOCUSIN
        @frame.active_tab.active_pane = pane
        @current_buffer = pane.buffer
      end
      sci_notify(notification)
    end

    def echo_sci_notify(_notification)
      return unless @isearch_active
      return if @isearch_setting_text

      text = @frame.echo_win.sci_get_line(0)
      return if text == @isearch_text

      @isearch_text = text
      if text.empty?
        @frame.view.sci_goto_pos(@isearch_origin)
        @frame.modeline(self)
        return
      end
      @last_search_text = text unless text.empty?
      perform_isearch(@isearch_origin)
    end

    def isearch_active?
      @isearch_active
    end

    def isearch_forward
      start_or_repeat_isearch(false)
    end

    def isearch_backward
      start_or_repeat_isearch(true)
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

    def start_replace(query, search_text = nil, replacement_text = nil)
      if @frame.view.sci_get_readonly
        @frame.echo_puts('Buffer is read-only')
        return
      end

      search_text = @frame.echo_gets('Replace string: ', '') if search_text.nil?
      return if search_text.nil?

      if search_text.empty?
        @frame.echo_puts('Empty search string')
        return
      end
      if replacement_text.nil?
        prompt = "Replace string #{search_text} with: "
        replacement_text = @frame.echo_gets(prompt, '')
      end
      return if replacement_text.nil?

      if query
        begin_query_replace(search_text, replacement_text)
      else
        count = replace_all_from(
          @frame.view.sci_get_current_pos, search_text, replacement_text
        )
        @frame.echo_puts(replace_summary(count))
        @frame.modeline(self)
      end
    end

    def begin_query_replace(search_text, replacement_text)
      @query_replace_active = true
      @replace_search_text = search_text
      @replacement_text = replacement_text
      @replace_count = 0
      @replace_next_pos = @frame.view.sci_get_current_pos
      find_next_replace_match
    end

    def query_replace_active?
      @query_replace_active
    end

    def query_replace_key_press(key)
      case key
      when 'y', ' '
        replace_query_match
        find_next_replace_match if @query_replace_active
      when 'n', 'DEL'
        @replace_next_pos = @frame.view.sci_get_target_end
        find_next_replace_match
      when '!'
        replace_query_match
        if @query_replace_active
          @replace_count += replace_all_from(
            @replace_next_pos, @replace_search_text, @replacement_text
          )
          finish_query_replace_with_summary
        end
      when 'q', 'Enter'
        finish_query_replace_with_summary
      when 'C-g'
        finish_query_replace('Quit')
      end
      true
    end

    def find_next_replace_match
      view = @frame.view
      view.sci_set_target_start(@replace_next_pos)
      view.sci_set_target_end(view.sci_get_length)
      found = view.sci_search_in_target(
        @replace_search_text.bytesize, @replace_search_text
      )
      if found == -1
        finish_query_replace_with_summary
        return
      end

      view.sci_set_sel(view.sci_get_target_start, view.sci_get_target_end)
      prompt = "Query replacing #{@replace_search_text} with " \
               "#{@replacement_text}: (y, n, !, q) "
      @frame.start_query_replace(prompt)
      @frame.modeline(self)
    end

    def replace_query_match
      view = @frame.view
      with_undo_action do
        view.sci_replace_target(@replacement_text.bytesize, @replacement_text)
      end
      @replace_count += 1
      @replace_next_pos = view.sci_get_target_end
    end

    def replace_all_from(start_pos, search_text, replacement_text)
      view = @frame.view
      count = 0
      with_undo_action do
        next_pos = start_pos
        loop do
          view.sci_set_target_start(next_pos)
          view.sci_set_target_end(view.sci_get_length)
          found = view.sci_search_in_target(search_text.bytesize, search_text)
          break if found == -1

          view.sci_replace_target(replacement_text.bytesize, replacement_text)
          count += 1
          next_pos = view.sci_get_target_end
        end
      end
      count
    end

    def with_undo_action
      @frame.view.sci_begin_undo_action
      yield
    ensure
      @frame.view.sci_end_undo_action
    end

    def finish_query_replace_with_summary
      finish_query_replace(replace_summary(@replace_count))
    end

    def finish_query_replace(message)
      @query_replace_active = false
      @frame.finish_query_replace
      @frame.echo_puts(message)
      @frame.modeline(self)
    end

    def replace_summary(count)
      "Replaced #{count} occurrence#{count == 1 ? '' : 's'}"
    end

    def start_or_repeat_isearch(backward)
      if @isearch_active
        @isearch_backward = backward
        @frame.update_isearch_prompt(isearch_prompt)
        repeat_isearch
        return
      end

      @isearch_active = true
      @isearch_backward = backward
      @isearch_origin = @frame.view.sci_get_current_pos
      @isearch_text = ''
      @frame.start_isearch(isearch_prompt)
    end

    def repeat_isearch
      if @isearch_text.empty?
        return if @last_search_text.empty?

        @isearch_text = @last_search_text
        begin
          @isearch_setting_text = true
          @frame.set_isearch_text(@isearch_text)
        ensure
          @isearch_setting_text = false
        end
      end
      view = @frame.view
      start_pos = if @isearch_backward
                    view.sci_get_selection_start
                  else
                    view.sci_get_selection_end
                  end
      perform_isearch(start_pos, true)
    end

    def perform_isearch(start_pos, wrap = false)
      return if @isearch_text.empty?

      view = @frame.view
      end_pos = @isearch_backward ? 0 : view.sci_get_length
      view.sci_set_target_start(start_pos)
      view.sci_set_target_end(end_pos)
      found = view.sci_search_in_target(
        @isearch_text.bytesize, @isearch_text
      )
      if found == -1 && wrap
        view.sci_set_target_start(
          @isearch_backward ? view.sci_get_length : 0
        )
        view.sci_set_target_end(@isearch_origin)
        found = view.sci_search_in_target(
          @isearch_text.bytesize, @isearch_text
        )
      end
      return if found == -1

      view.sci_set_sel(view.sci_get_target_start, view.sci_get_target_end)
      @frame.modeline(self)
    end

    def finish_isearch(cancel)
      @frame.view.sci_goto_pos(@isearch_origin) if cancel
      @isearch_active = false
      @frame.finish_isearch
      @frame.modeline(self)
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

      @frame.active_tab.split(active_pane, new_pane, orientation)
      unless @frame.native_handle.nil?
        @frame.split_native_pane(active_pane, new_pane, orientation)
      end
      @frame.modeline(self, active_pane)
      @frame.modeline(self, new_pane)
      @frame.switch_window(active_pane)
    end

    def isearch_prompt
      @isearch_backward ? 'I-search backward: ' : 'I-search: '
    end

    # Like the terminal frontends, Cocoa currently switches documents in the
    # active pane. Native tab creation will be added with the tab UI.
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
