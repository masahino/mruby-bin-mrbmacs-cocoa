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

class CocoaIOApplicationForTest < Mrbmacs::ApplicationCocoa
  attr_reader :watched_io, :unwatched_io

  def watch_io_read_event(io)
    @watched_io = io
  end

  def unwatch_io_read_event(io)
    @unwatched_io = io
  end
end

class CocoaPaneWidthForTest < Mrbmacs::PaneCocoa
  def native_client_width
    800
  end
end

class CocoaModelineApplicationForTest
  def modeline_str
    '(utf-8-LF):-- *scratch* (1,1)    ()    [Fundamental]    []'
  end
end

def build_cocoa_application_for_test(frame, buffer)
  app = Mrbmacs::ApplicationCocoa.allocate
  app.init_instance_variables
  app.instance_variable_set(:@logger, app.init_logfile)
  app.frame = frame
  app.current_buffer = buffer
  app.buffer_list = [buffer]
  keymap = Mrbmacs::ViewKeyMap.new
  echo_keymap = Mrbmacs::EchoWinKeyMap.new
  app.instance_variable_set(:@keymap, keymap)
  app.instance_variable_set(:@echo_keymap, echo_keymap)
  app.apply_keymap(frame.echo_win, echo_keymap) unless frame.echo_win.nil?
  app.init_theme
  command_list = Mrbmacs::Command.instance_methods.map(&:to_s).sort
  app.instance_variable_set(:@command_list, command_list)
  app
end

class CocoaFrameForExitTest < Mrbmacs::FrameCocoa
  attr_reader :exited

  def exit
    @exited = true
  end
end

class CocoaFrameForNativeSplitTest < Mrbmacs::FrameCocoa
  def pane_can_split?(_pane, _direction, _size)
    true
  end

  def split_native_pane(_pane, _new_pane, _direction)
    4321
  end
end


class CocoaFrameForEchoInputTest < Mrbmacs::FrameCocoa
  attr_accessor :input_events

  def wait_echo_event
    event = @input_events.shift
    if event.is_a?(Array)
      @echo_win.text = event[1]
      event[0]
    else
      event
    end
  end
end

class CocoaFrameForConfirmationTest < CocoaFrameForEchoInputTest
  attr_accessor :confirmation_event

  def wait_confirmation_event
    @confirmation_event
  end
end

class CocoaViewForLayoutTest
  attr_accessor :notification_callback
  attr_accessor :current_pos
  attr_accessor :text
  attr_accessor :text_width_scale
  attr_reader :added_documents, :autocomplete_choose_single,
              :autocomplete_lists, :copied_ranges
  attr_reader :set_documents
  attr_reader :horizontal_scrollbar, :messages, :save_point
  attr_reader :search_lengths, :selections
  attr_reader :replacement_lengths, :undo_actions
  attr_reader :caret_colors, :caret_styles
  attr_reader :command_keys
  attr_reader :margin_messages
  attr_reader :fold_messages
  attr_reader :mod_event_masks
  attr_reader :theme_messages
  attr_reader :vertical_scrollbar
  attr_reader :annotations

  def initialize(docpointer = 100)
    @docpointer = docpointer
    @added_documents = []
    @copied_ranges = []
    @current_pos = 0
    @set_documents = []
    @messages = []
    @caret_colors = []
    @caret_styles = []
    @command_keys = []
    @margin_messages = []
    @margin_widths = {}
    @fold_messages = []
    @mod_event_masks = []
    @horizontal_scrollbar = true
    @vertical_scrollbar = true
    @autocomplete_active = false
    @autocomplete_choose_single = nil
    @autocomplete_lists = []
    @text = ''
    @text_width_scale = 1
    @save_point = false
    @search_lengths = []
    @replacement_lengths = []
    @selection_start = 0
    @selection_end = 0
    @selections = []
    @target_start = 0
    @target_end = 0
    @theme_messages = []
    @undo_actions = []
    @annotations = []
  end

  def sci_get_docpointer
    @docpointer
  end

  def sci_add_refdocument(docpointer)
    @added_documents << docpointer
  end

  def sci_set_docpointer(docpointer)
    @set_documents << docpointer
    @docpointer = docpointer.nil? ? @docpointer.to_i + 1 : docpointer
  end

  def send_message(message)
    @messages << message
  end

  def sci_home
    @messages << Scintilla::SCI_HOME
  end

  def sci_get_current_pos
    @current_pos
  end

  def sci_get_column(_position)
    0
  end

  def sci_line_from_position(_position)
    0
  end

  def sci_get_eol_mode
    Scintilla::SC_EOL_LF
  end

  def sci_get_modify
    0
  end

  def sci_get_readonly
    false
  end

  def sci_goto_pos(position)
    @current_pos = position
    @selection_start = position
    @selection_end = position
  end

  def sci_get_selection_start
    @selection_start
  end

  def sci_get_selection_end
    @selection_end
  end

  def sci_set_sel(start_pos, end_pos)
    @selection_start = start_pos
    @selection_end = end_pos
    @current_pos = end_pos
    @selections << [start_pos, end_pos]
  end

  def sci_set_caret_style(style)
    @caret_styles << style
  end

  def sci_set_caret_fore(color)
    @caret_colors << color
  end

  def sci_assign_cmdkey(key, command)
    @command_keys << [key, command]
  end

  def sci_set_target_start(position)
    @target_start = position
  end

  def sci_set_target_end(position)
    @target_end = position
  end

  def sci_get_target_start
    @target_start
  end

  def sci_get_target_end
    @target_end
  end

  def sci_search_in_target(length, search_text)
    @search_lengths << length
    if @target_start <= @target_end
      target = @text.byteslice(@target_start, @target_end - @target_start)
      char_offset = target.index(search_text)
      return -1 if char_offset.nil?

      found = @target_start + target[0...char_offset].bytesize
    else
      target = @text.byteslice(@target_end, @target_start - @target_end)
      char_offset = target.rindex(search_text)
      return -1 if char_offset.nil?

      found = @target_end + target[0...char_offset].bytesize
    end
    @target_start = found
    @target_end = found + search_text.bytesize
    found
  end

  def sci_replace_target(length, replacement_text)
    @replacement_lengths << length
    prefix = @text.byteslice(0, @target_start)
    suffix = @text.byteslice(@target_end, @text.bytesize - @target_end)
    @text = prefix + replacement_text + suffix
    @target_end = @target_start + replacement_text.bytesize
    @selection_start = @target_start
    @selection_end = @target_end
    @current_pos = @target_end
    replacement_text.bytesize
  end

  def sci_begin_undo_action
    @undo_actions << :begin
  end

  def sci_end_undo_action
    @undo_actions << :end
  end

  def sci_pointy_from_position(_point, _position)
    0
  end

  def sci_linescroll(columns, lines)
    @messages << [:line_scroll, columns, lines]
  end

  def sci_text_height(_line)
    16
  end

  def sci_lines_on_screen
    20
  end

  def sci_set_lexer_language(language)
    @theme_messages << [:lexer, language]
  end

  def sci_style_set_fore(style, color)
    @theme_messages << [:style_fore, style, color]
  end

  def sci_style_set_back(style, color)
    @theme_messages << [:style_back, style, color]
  end

  def sci_style_clear_all
    @theme_messages << :style_clear_all
  end

  def sci_style_set_italic(style, value)
    @theme_messages << [:style_italic, style, value]
  end

  def sci_style_set_bold(style, value)
    @theme_messages << [:style_bold, style, value]
  end

  def sci_style_set_font(style, name)
    @theme_messages << [:style_font, style, name]
  end

  def sci_style_set_size(style, size)
    @theme_messages << [:style_size, style, size]
  end

  def sci_set_extra_ascent(value)
    @theme_messages << [:extra_ascent, value]
  end

  def sci_set_extra_descent(value)
    @theme_messages << [:extra_descent, value]
  end

  def sci_annotation_set_visible(value)
    @theme_messages << [:annotation_visible, value]
  end

  def sci_marker_set_fore(marker, color)
    @theme_messages << [:marker_fore, marker, color]
  end

  def sci_marker_set_back(marker, color)
    @theme_messages << [:marker_back, marker, color]
  end

  def sci_set_caret_line_visible(value)
    @theme_messages << [:caret_line_visible, value]
  end

  def sci_set_caret_line_back(color)
    @theme_messages << [:caret_line_back, color]
  end

  def sci_set_sel_fore(use_setting, color)
    @theme_messages << [:selection_fore, use_setting, color]
  end

  def sci_set_sel_back(use_setting, color)
    @theme_messages << [:selection_back, use_setting, color]
  end

  def sci_set_element_colour(element, color)
    @theme_messages << [:element_colour, element, color]
  end

  def sci_set_fold_margin_colour(use_setting, color)
    @theme_messages << [:fold_margin_color, use_setting, color]
  end

  def sci_set_fold_margin_hicolour(use_setting, color)
    @theme_messages << [:fold_margin_highlight, use_setting, color]
  end

  def sci_set_keywords(index, keywords)
    @theme_messages << [:keywords, index, keywords]
  end

  def sci_set_property(name, value)
    @theme_messages << [:property, name, value]
  end

  def sci_set_tab_width(width)
    @theme_messages << [:tab_width, width]
  end

  def sci_set_use_tabs(value)
    @theme_messages << [:use_tabs, value]
  end

  def sci_set_tab_indents(value)
    @theme_messages << [:tab_indents, value]
  end

  def sci_set_back_space_un_indents(value)
    @theme_messages << [:backspace_unindents, value]
  end

  def sci_set_indent(width)
    @theme_messages << [:indent, width]
  end

  def sci_set_wrap_mode(mode)
    @theme_messages << [:wrap_mode, mode]
  end

  def sci_set_anchor(position)
    @messages << [:set_anchor, position]
  end

  def sci_get_move_extends_selection
    0
  end

  def sci_set_selection_mode(mode)
    @messages << [:set_selection_mode, mode]
  end

  def sci_copy_range(start_pos, end_pos)
    @copied_ranges << [start_pos, end_pos]
  end

  def sci_set_empty_selection(position)
    @messages << [:set_empty_selection, position]
  end

  def sci_paste
    @messages << :paste
  end

  def sci_autoc_active
    false
  end

  def sci_new_line
    @messages << :new_line
  end

  def sci_clear_all
    @text = ''
  end

  def sci_add_text(_length, text)
    @text += text
  end

  def sci_document_end
    @messages << :document_end
  end

  def sci_set_hscrollbar(visible)
    @horizontal_scrollbar = visible
  end

  def sci_set_vscrollbar(visible)
    @vertical_scrollbar = visible
  end

  def sci_set_margin_typen(margin, type)
    @margin_messages << [:margin_type, margin, type]
  end

  def sci_text_width(_style, text)
    text.bytesize * @text_width_scale
  end

  def sci_annotation_set_text(line, text)
    @annotations << [:text, line, text]
  end

  def sci_annotation_set_style(line, style)
    @annotations << [:style, line, style]
  end

  def sci_set_margin_widthn(margin, width)
    @margin_messages << [:margin_width, margin, width]
    @margin_widths[margin] = width
  end

  def sci_get_margins
    5
  end

  def sci_get_margin_widthn(margin)
    @margin_widths[margin] || 0
  end

  def sci_set_margin_maskn(margin, mask)
    @margin_messages << [:margin_mask, margin, mask]
  end

  def sci_set_marginsensitiven(margin, sensitive)
    @margin_messages << [:margin_sensitive, margin, sensitive]
  end

  def sci_set_automatic_fold(value)
    @fold_messages << [:automatic_fold, value]
  end

  def sci_marker_define(marker, symbol)
    @fold_messages << [:marker, marker, symbol]
  end

  def sci_set_mod_event_mask(mask)
    @mod_event_masks << mask
  end

  def sci_margin_set_text(line, text)
    @margin_messages << [:margin_text, line, text]
  end

  def sci_grab_focus
    @messages << :grab_focus
  end

  def sci_autoc_active
    @autocomplete_active
  end

  def sci_autoc_set_choose_single(value)
    @autocomplete_choose_single = value
  end

  def sci_autoc_cancel
    @autocomplete_active = false
  end

  def sci_autoc_complete
    unless @autocomplete_lists.empty?
      @text = @autocomplete_lists[-1][1].split.first
    end
    @autocomplete_active = false
  end

  def sci_autoc_get_separator
    32
  end

  def sci_autoc_show(length, list)
    @autocomplete_active = true
    @autocomplete_lists << [length, list]
  end

  def sci_get_line(_line)
    @text
  end

  def sci_get_length
    @text.bytesize
  end

  def sci_get_text(_length)
    @text
  end

  def sci_set_save_point
    @save_point = true
  end

  def sci_set_savepoint
    @save_point = true
  end

  def sci_marker_delete_all(_marker)
  end

  def native_handle
    1234
  end
end
