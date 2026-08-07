module Mrbmacs
  # A single editor area. A pane owns its Scintilla view and displays one
  # buffer.
  class PaneCocoa < EditWindow
    attr_reader :view
    attr_reader :buffer
    attr_reader :modeline_text
    attr_reader :modeline_native_handle
    attr_accessor :layout_native_handle, :parent

    def initialize(view, buffer = nil)
      @view = view
      @sci = view
      @buffer = nil
      @modeline_native_handle = nil
      @layout_native_handle = nil
      @parent = nil
      @modeline_text = ''
      @view.notification_callback = ScintillaNotificationBridge.new(self)
      @view.sci_set_mod_event_mask(
        Scintilla::SC_MOD_INSERTTEXT | Scintilla::SC_MOD_DELETETEXT
      )
      initialize_caret
      set_margin
      initialize_folding_markers
      update_margin_widths
      self.buffer = buffer unless buffer.nil?
    end

    def initialize_caret
      @view.sci_set_caret_style(
        Scintilla::CARETSTYLE_BLOCK_AFTER |
        Scintilla::CARETSTYLE_OVERSTRIKE_BLOCK |
        Scintilla::CARETSTYLE_BLOCK
      )
    end

    def initialize_folding_markers
      {
        Scintilla::SC_MARKNUM_FOLDEROPEN => Scintilla::SC_MARK_BOXMINUS,
        Scintilla::SC_MARKNUM_FOLDER => Scintilla::SC_MARK_BOXPLUS,
        Scintilla::SC_MARKNUM_FOLDERSUB => Scintilla::SC_MARK_VLINE,
        Scintilla::SC_MARKNUM_FOLDERTAIL => Scintilla::SC_MARK_LCORNER,
        Scintilla::SC_MARKNUM_FOLDEREND => Scintilla::SC_MARK_BOXPLUSCONNECTED,
        Scintilla::SC_MARKNUM_FOLDEROPENMID => Scintilla::SC_MARK_BOXMINUSCONNECTED,
        Scintilla::SC_MARKNUM_FOLDERMIDTAIL => Scintilla::SC_MARK_TCORNER
      }.each do |marker, symbol|
        @view.sci_marker_define(marker, symbol)
      end
    end

    def update_margin_widths
      @view.sci_set_margin_widthn(
        MARGIN_LINE_NUMBER,
        @view.sci_text_width(Scintilla::STYLE_LINENUMBER, '_99999')
      )
      @view.sci_set_margin_widthn(
        MARGIN_FOLDING,
        @view.sci_text_width(Scintilla::STYLE_LINENUMBER, '__')
      )
      @view.sci_set_margin_widthn(
        MARGIN_VC,
        @view.sci_text_width(Scintilla::STYLE_LINENUMBER, '_')
      )
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

    def width
      char_width = @view.sci_text_width(Scintilla::STYLE_DEFAULT, '0')
      return 1 if char_width <= 0

      columns = (native_client_width / char_width).to_i
      columns > 0 ? columns : 1
    end

    # EditWindow-compatible access used by shared editor commands.
    def sci
      @view
    end

    def modeline_text=(text)
      @modeline_text = text.to_s
      update_native_modeline(@modeline_text) unless @modeline_native_handle.nil?
    end

    def modeline_native_handle=(handle)
      @modeline_native_handle = handle
      return if handle.nil? || @font_name.nil?

      update_native_modeline_font(@font_name, @font_size)
    end

    def set_font(name, size)
      @font_name = name
      @font_size = size
      @view.sci_style_set_font(Scintilla::STYLE_DEFAULT, name)
      @view.sci_style_set_size(Scintilla::STYLE_DEFAULT, size)
      update_native_modeline_font(name, size) unless @modeline_native_handle.nil?
    end

    def apply_theme(theme)
      @theme = theme
      apply_theme_base(theme)
      @view.sci_set_caret_fore(theme.foreground_color)
      @view.sci_set_fold_margin_colour(true, theme.background_color)
      @view.sci_set_fold_margin_hicolour(true, theme.foreground_color)
      (25..31).each do |marker|
        @view.sci_marker_set_fore(marker, theme.foreground_color)
        @view.sci_marker_set_back(marker, theme.background_color)
      end
      update_margin_widths
    end

    def apply_modeline_theme(active)
      return if @theme.nil? || @modeline_native_handle.nil?

      color_name = active ? :color_mode_line : :color_mode_line_inactive
      colors = @theme.font_color[color_name]
      return if colors.nil?

      update_native_modeline_theme(colors[0], colors[1])
    end
  end

end
