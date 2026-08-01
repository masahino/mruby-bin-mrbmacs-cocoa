module Mrbmacs
  # Forwards Scintilla notifications to the active mrbmacs application.
  class ScintillaNotificationBridge
    def call(notification)
      return if $app.nil?

      $app.sci_notify(notification)
    end
  end

  # Keeps echo-area changes separate from notifications sent by editor panes.
  class EchoNotificationBridge
    def call(notification)
      return if $app.nil?

      $app.echo_sci_notify(notification)
    end
  end

  # Cocoa implementations for commands that require echo-area interaction.
  module Command
    def replace_string
      start_replace(false)
    end

    def query_replace
      start_replace(true)
    end
  end

  # A single editor area. A pane owns its Scintilla view and displays one
  # buffer.
  class PaneCocoa
    attr_reader :view
    attr_reader :buffer
    attr_reader :modeline_text
    attr_accessor :modeline_native_handle

    def initialize(view, buffer = nil)
      @view = view
      @buffer = nil
      @modeline_native_handle = nil
      @modeline_text = ''
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

    # Shared recenter logic uses pixel height for GUI edit windows.
    def height
      @view.sci_text_height(0) * @view.sci_lines_on_screen
    end

    # EditWindow-compatible access used by shared editor commands.
    def sci
      @view
    end

    def newline
      case @view.sci_get_eol_mode
      when Scintilla::SC_EOL_CRLF then 'CRLF'
      when Scintilla::SC_EOL_CR then 'CR'
      when Scintilla::SC_EOL_LF then 'LF'
      else ''
      end
    end

    def modeline_text=(text)
      @modeline_text = text.to_s
      update_native_modeline(@modeline_text) unless @modeline_native_handle.nil?
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
        @echo_win.notification_callback = EchoNotificationBridge.new
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

    def modeline(app, pane = active_pane)
      pane.modeline_text = get_mode_str(app)
    end

    def modeline_refresh(app)
      modeline(app)
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

    def select_buffer(default_buffername, buffer_list)
      prompt = "Switch to buffer: (default #{default_buffername}) "
      echo_gets(prompt, '') do |input_text|
        candidates = buffer_list.select do |name|
          name[0, input_text.length] == input_text
        end
        [
          candidates.join(@echo_win.sci_autoc_get_separator.chr),
          input_text.length
        ]
      end
    end

    def y_or_n(prompt)
      @echo_win.sci_clear_all
      echo_set_prompt(prompt)
      wait_confirmation_event == :yes
    ensure
      @echo_win.sci_clear_all unless @echo_win.nil?
      echo_set_prompt('') unless @echo_win.nil?
      view.sci_grab_focus
    end

    def start_isearch(prompt)
      @echo_win.sci_clear_all
      echo_set_prompt(prompt)
      @echo_win.sci_grab_focus
    end

    def update_isearch_prompt(prompt)
      echo_set_prompt(prompt)
    end

    def set_isearch_text(text)
      @echo_win.sci_clear_all
      @echo_win.sci_add_text(text.bytesize, text)
      @echo_win.sci_document_end
    end

    def finish_isearch
      @echo_win.sci_clear_all
      echo_set_prompt('')
      view.sci_grab_focus
    end

    def start_query_replace(prompt)
      @echo_win.sci_clear_all
      echo_set_prompt(prompt)
      @echo_win.sci_grab_focus
    end

    def finish_query_replace
      @echo_win.sci_clear_all
      echo_set_prompt('')
      view.sci_grab_focus
    end

    def wait_echo_event
      raise NotImplementedError
    end


    def wait_confirmation_event
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
      @command_list = Mrbmacs::Command.instance_methods.map(&:to_s).sort
    end

    def sci_notify(notification)
      $stderr.puts notification['code'] if $DEBUG
      call_sci_event(notification)
      @frame.modeline(self) unless @frame.nil?
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

    def isearch_prompt
      @isearch_backward ? 'I-search backward: ' : 'I-search: '
    end

    # Like the terminal frontends, Cocoa currently switches documents in the
    # active pane. Native tab creation will be added with the tab UI.
    def add_buffer_to_frame(_buffer)
    end

    # The other frontends create *Messages* during Application initialization,
    # so the shared switch_to_buffer implementation can use buffer_list[-2] as
    # its default. Cocoa does not create that buffer yet and can start with only
    # one buffer.
    def switch_to_buffer(buffername = nil)
      if buffername.nil? && @buffer_list.size == 1
        buffername = @frame.select_buffer(
          @current_buffer.name, @buffer_list.map(&:name)
        )
        return if buffername.nil?

        buffername = @current_buffer.name if buffername == ''
      end
      super(buffername)
    end

    # Theme initialization is not part of the current Cocoa startup path yet.
    def apply_theme_to_mode(mode, edit_win, theme)
      return if theme.nil?

      super
    end

    # Use the shared file-loading path for command-line files as well as files
    # opened after startup. A missing path therefore starts as an empty new
    # file instead of placing an error message in the editor document.
    def load_initial_file(filename = nil)
      open_file(filename) unless filename.nil?
      @frame.view.sci_set_save_point
      @frame.modeline(self)
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
