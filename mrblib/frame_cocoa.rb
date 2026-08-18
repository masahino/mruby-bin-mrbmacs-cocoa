module Mrbmacs
  # One native macOS window containing one or more tabs.
  class FrameCocoa < FrameBase
    INITIAL_COLUMNS = 120
    INITIAL_LINES = 40

    attr_reader :echo_win
    attr_reader :font_name, :font_size
    attr_reader :tabs
    attr_reader :last_message
    attr_accessor :active_tab, :native_handle, :layout_native_handle

    def initialize(tab, echo_win = nil)
      @tabs = [tab]
      @active_tab = tab
      @echo_win = echo_win
      @native_handle = nil
      @layout_native_handle = nil
      @last_message = nil
      @sci_notifications = []
      view.sci_set_hscrollbar(false)
      unless @echo_win.nil?
        @echo_win.notification_callback = EchoNotificationBridge.new
        @echo_win.sci_set_hscrollbar(false)
        @echo_win.sci_set_vscrollbar(false)
        @echo_win.sci_autoc_set_choose_single(1)
        @echo_win.sci_set_caret_style(
          Scintilla::CARETSTYLE_BLOCK_AFTER |
          Scintilla::CARETSTYLE_OVERSTRIKE_BLOCK |
          Scintilla::CARETSTYLE_BLOCK
        )
        (0..2).each { |margin| @echo_win.sci_set_margin_widthn(margin, 0) }
        @echo_win.sci_set_margin_typen(3, 4)
      end
      set_font('Menlo', 14)
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

    def initial_native_editor_width(columns = INITIAL_COLUMNS)
      width = view.sci_text_width(
        Scintilla::STYLE_DEFAULT, '0' * columns
      )
      view.sci_get_margins.times do |margin|
        width += view.sci_get_margin_widthn(margin)
      end
      width
    end

    def initial_native_editor_height(lines = INITIAL_LINES)
      view.sci_text_height(0) * lines
    end

    def switch_window(new_pane)
      old_pane = active_pane
      @active_tab.active_pane = new_pane
      old_pane.apply_modeline_theme(false) unless old_pane.equal?(new_pane)
      new_pane.apply_modeline_theme(true)
      new_pane.view.sci_grab_focus
    end

    def apply_theme(theme)
      @theme = theme
      @tabs.each do |tab|
        tab.panes.each do |pane|
          pane.apply_theme(theme)
          pane.apply_modeline_theme(pane.equal?(active_pane))
        end
      end
      apply_echo_theme(theme) unless @echo_win.nil?
    end

    def apply_echo_theme(theme)
      @echo_win.sci_style_set_fore(
        Scintilla::STYLE_DEFAULT, theme.foreground_color
      )
      @echo_win.sci_style_set_back(
        Scintilla::STYLE_DEFAULT, theme.background_color
      )
      @echo_win.sci_style_clear_all
      @echo_win.sci_set_caret_fore(theme.foreground_color)
    end

    def set_font(name, size)
      @font_name = name
      @font_size = size
      @tabs.each do |tab|
        tab.panes.each do |pane|
          pane.set_font(name, size)
          next if @theme.nil?

          pane.apply_theme(@theme)
          pane.buffer.mode.apply_theme(pane.sci, @theme) unless pane.buffer.nil?
          pane.apply_mode_settings(pane.buffer.mode) unless pane.buffer.nil?
        end
      end
      unless @echo_win.nil?
        @echo_win.sci_style_set_font(Scintilla::STYLE_DEFAULT, name)
        @echo_win.sci_style_set_size(Scintilla::STYLE_DEFAULT, size)
        if @theme.nil?
          @echo_win.sci_style_clear_all
        else
          apply_echo_theme(@theme)
        end
        @echo_win.sci_set_extra_ascent(3)
        @echo_win.sci_set_extra_descent(3)
      end
      unless @native_handle.nil? || @echo_win.nil?
        update_native_echo_height(@echo_win.sci_text_height(0))
      end
    end

    def delete_window(target_pane)
      if edit_win_list.size == 1
        echo_puts('Atempt to delete sole ordinary window')
        return
      end

      target_pane.view.sci_add_refdocument(target_pane.buffer.docpointer)
      survivor = @active_tab.delete(target_pane)
      remove_native_pane(target_pane) unless @native_handle.nil?
      switch_window(survivor)
    end

    def delete_other_window
      removed = edit_win_list.reject { |pane| pane.equal?(active_pane) }
      removed.each do |pane|
        pane.view.sci_add_refdocument(pane.buffer.docpointer)
      end
      @active_tab.keep_only(active_pane)
      keep_only_native_pane(active_pane) unless @native_handle.nil?
      removed.each { |pane| pane.parent = nil }
      switch_window(active_pane)
    end

    def enlarge_window(pane, lines)
      resize_native_pane(
        pane,
        :vertical,
        pane.view.sci_text_height(0) * lines
      )
    end

    def enlarge_window_horizontally(pane, columns)
      resize_native_pane(
        pane,
        :horizontal,
        pane.view.sci_text_width(Scintilla::STYLE_DEFAULT, '0') * columns
      )
    end

    def modeline(app, pane = active_pane)
      pane.modeline_text = get_mode_str(app)
      pane.apply_modeline_theme(pane.equal?(active_pane))
    end

    def modeline_refresh(app)
      modeline(app)
    end

    def resize_native_pane(pane, orientation, delta)
      branch = pane
      split = branch.parent
      until split.nil? || split.orientation == orientation
        branch = split
        split = split.parent
      end
      return false if split.nil? || split.native_handle.nil?

      move_native_divider(
        split,
        split.first.equal?(branch),
        delta,
        minimum_native_extent(split.first, orientation),
        minimum_native_extent(split.second, orientation)
      )
    end

    def minimum_native_extent(node, orientation)
      if node.is_a?(PaneCocoa)
        return orientation == :horizontal ? node.minimum_native_width :
                                            node.minimum_native_height
      end

      first_extent = minimum_native_extent(node.first, orientation)
      second_extent = minimum_native_extent(node.second, orientation)
      if node.orientation == orientation
        first_extent + native_divider_thickness(node) + second_extent
      else
        [first_extent, second_extent].max
      end
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
      echo_set_prompt('') unless @echo_win.nil?
      @echo_win.sci_add_text(1, ' ') unless @echo_win.nil?
      @echo_win.sci_clear_all unless @echo_win.nil?
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
      @echo_win.sci_add_text(1, ' ')
      @echo_win.sci_clear_all
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
      @echo_win.sci_add_text(1, ' ')
      @echo_win.sci_clear_all
      view.sci_grab_focus
    end

    def wait_echo_event
      raise NotImplementedError
    end

    def wait_confirmation_event
      raise NotImplementedError
    end
  end
end
