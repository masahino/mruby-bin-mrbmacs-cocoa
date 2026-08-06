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

class CocoaModelineApplicationForTest
  def modeline_str
    '(utf-8-LF):-- *scratch* (1,1)    ()    [Fundamental]    []'
  end
end

class CocoaFrameForExitTest < Mrbmacs::FrameCocoa
  attr_reader :exited

  def exit
    @exited = true
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
  attr_reader :added_documents, :autocomplete_lists, :copied_ranges
  attr_reader :set_documents
  attr_reader :horizontal_scrollbar, :messages, :save_point
  attr_reader :search_lengths, :selections
  attr_reader :replacement_lengths, :undo_actions
  attr_reader :caret_colors, :caret_styles
  attr_reader :margin_messages
  attr_reader :theme_messages
  attr_reader :vertical_scrollbar

  def initialize(docpointer = 100)
    @docpointer = docpointer
    @added_documents = []
    @copied_ranges = []
    @current_pos = 0
    @set_documents = []
    @messages = []
    @caret_colors = []
    @caret_styles = []
    @margin_messages = []
    @horizontal_scrollbar = true
    @vertical_scrollbar = true
    @autocomplete_active = false
    @autocomplete_lists = []
    @text = ''
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
      offset = @text[@target_start...@target_end].index(search_text)
      return -1 if offset.nil?

      found = @target_start + offset
    else
      offset = @text[@target_end...@target_start].rindex(search_text)
      return -1 if offset.nil?

      found = @target_end + offset
    end
    @target_start = found
    @target_end = found + search_text.bytesize
    found
  end

  def sci_replace_target(length, replacement_text)
    @replacement_lengths << length
    prefix = @text[0...@target_start]
    suffix = @text[@target_end..]
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
    @messages << [:lexer, language]
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
    text.bytesize
  end

  def sci_set_margin_widthn(margin, width)
    @margin_messages << [:margin_width, margin, width]
  end

  def sci_set_margin_maskn(margin, mask)
    @margin_messages << [:margin_mask, margin, mask]
  end

  def sci_set_marginsensitiven(margin, sensitive)
    @margin_messages << [:margin_sensitive, margin, sensitive]
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

assert('Mrbmacs::ScintillaNotificationBridge forwards to $app') do
  previous_app = $app
  receiver = CocoaNotificationReceiver.new
  notification = { 'code' => Scintilla::SCN_MODIFIED }

  begin
    $app = receiver
    Mrbmacs::ScintillaNotificationBridge.new.call(notification)
    assert_same notification, receiver.notification
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::ScintillaNotificationBridge ignores a missing $app') do
  previous_app = $app

  begin
    $app = nil
    assert_nil Mrbmacs::ScintillaNotificationBridge.new.call(
      'code' => Scintilla::SCN_MODIFIED
    )
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::EchoNotificationBridge forwards echo notifications') do
  previous_app = $app
  receiver = Object.new
  notification = { 'code' => Scintilla::SCN_MODIFIED }
  receiver.define_singleton_method(:echo_sci_notify) do |event|
    @notification = event
  end
  receiver.define_singleton_method(:notification) { @notification }

  begin
    $app = receiver
    Mrbmacs::EchoNotificationBridge.new.call(notification)
    assert_same notification, receiver.notification
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::ApplicationCocoa dispatches Scintilla notifications') do
  app = CocoaApplicationForTest.new
  notification = { 'code' => Scintilla::SCN_MODIFIED }

  app.sci_notify(notification)
  assert_same notification, app.notification
end


assert('Mrbmacs::ApplicationCocoa owns its Cocoa frame and initial buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_same frame, app.frame
  assert_same buffer, app.current_buffer
  assert_equal [buffer], app.buffer_list
  assert_equal({}, app.sci_handler)
  assert_kind_of Mrbmacs::Config, app.config
  assert_kind_of Mrbmacs::SolarizedDarkTheme, app.theme
  assert_true pane.view.theme_messages.include?(
    [:style_fore, Scintilla::STYLE_DEFAULT, app.theme.foreground_color]
  )
end

assert('Mrbmacs::PaneCocoa applies active native mode line colors') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  calls = []
  pane.define_singleton_method(:update_native_modeline_theme) do |fore, back|
    calls << [fore, back]
  end
  pane.modeline_native_handle = 1
  theme = Mrbmacs::SolarizedDarkTheme.new

  pane.apply_theme(theme)
  pane.apply_modeline_theme(true)

  assert_equal [theme.font_color[:color_mode_line][0, 2]], calls
end

assert('Mrbmacs::PaneCocoa configures its line number margin') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)

  assert_true view.margin_messages.include?(
    [:margin_width, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 6]
  )
  assert_true view.margin_messages.include?(
    [
      :margin_mask,
      Mrbmacs::EditWindow::MARGIN_LINE_NUMBER,
      Mrbmacs::MARKERMASK_LINE_NUMBER
    ]
  )
  assert_true view.margin_messages.include?(
    [:margin_sensitive, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 1]
  )

  margin_width_count = view.margin_messages.count do |message|
    message == [:margin_width, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 6]
  end
  pane.apply_theme(Mrbmacs::SolarizedDarkTheme.new)
  assert_equal margin_width_count + 1, view.margin_messages.count { |message|
    message == [:margin_width, Mrbmacs::EditWindow::MARGIN_LINE_NUMBER, 6]
  }
end

assert('Mrbmacs::PaneCocoa configures a Scintilla block caret') do
  view = CocoaViewForLayoutTest.new
  Mrbmacs::PaneCocoa.new(view)
  style = Scintilla::CARETSTYLE_BLOCK_AFTER |
          Scintilla::CARETSTYLE_OVERSTRIKE_BLOCK |
          Scintilla::CARETSTYLE_BLOCK

  assert_true view.caret_styles.include?(style)
end

assert('Mrbmacs::PaneCocoa uses the theme foreground for its caret') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  dark_theme = Mrbmacs::SolarizedDarkTheme.new
  light_theme = Mrbmacs::SolarizedLightTheme.new

  pane.apply_theme(dark_theme)
  pane.apply_theme(light_theme)

  assert_equal [dark_theme.foreground_color, light_theme.foreground_color],
               view.caret_colors
end

assert('Mrbmacs::FrameCocoa configures its echo-area caret') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)
  theme = Mrbmacs::SolarizedDarkTheme.new
  style = Scintilla::CARETSTYLE_BLOCK_AFTER |
          Scintilla::CARETSTYLE_OVERSTRIKE_BLOCK |
          Scintilla::CARETSTYLE_BLOCK

  frame.apply_theme(theme)

  assert_equal [style], echo_win.caret_styles
  assert_equal [theme.foreground_color], echo_win.caret_colors
end

assert('Mrbmacs::FrameCocoa applies a font to every pane and echo area') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  first = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(101), buffer)
  second = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(102), buffer)
  tab = Mrbmacs::TabCocoa.new(first)
  tab.split(first, second, :vertical)
  echo_win = CocoaViewForLayoutTest.new(103)
  frame = Mrbmacs::FrameCocoa.new(tab, echo_win)
  theme = Mrbmacs::SolarizedDarkTheme.new
  frame.apply_theme(theme)
  frame.set_font('Monaco', 16)

  [first.view, second.view, echo_win].each do |view|
    assert_true view.theme_messages.include?(
      [:style_font, Scintilla::STYLE_DEFAULT, 'Monaco']
    )
    assert_true view.theme_messages.include?(
      [:style_size, Scintilla::STYLE_DEFAULT, 16]
    )
  end
  [first.view, second.view].each do |view|
    assert_true view.theme_messages.include?(:style_clear_all)
  end
  assert_true echo_win.theme_messages.include?([:extra_ascent, 3])
  assert_true echo_win.theme_messages.include?([:extra_descent, 3])
end

assert('Mrbmacs::ApplicationCocoa follows native pane focus') do
  first_buffer = Mrbmacs::Buffer.new('first')
  second_buffer = Mrbmacs::Buffer.new('second')
  first = Mrbmacs::PaneCocoa.new(
    CocoaViewForLayoutTest.new(101), first_buffer
  )
  second = Mrbmacs::PaneCocoa.new(
    CocoaViewForLayoutTest.new(102), second_buffer
  )
  tab = Mrbmacs::TabCocoa.new(first)
  tab.split(first, second, :vertical)
  frame = Mrbmacs::FrameCocoa.new(tab)
  app = Mrbmacs::ApplicationCocoa.new(frame, first_buffer)
  previous_app = $app

  begin
    $app = app
    second.view.notification_callback.call(
      'code' => Scintilla::SCN_MODIFIED
    )
    assert_same first, frame.active_pane
    assert_same first_buffer, app.current_buffer

    second.view.notification_callback.call(
      'code' => Scintilla::SCN_FOCUSIN
    )
    assert_same second, frame.active_pane
    assert_same second_buffer, app.current_buffer
  ensure
    $app = previous_app
  end
end

assert('Mrbmacs::ApplicationCocoa starts a missing path as a new file') do
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-cocoa-new-#{$$}.txt"
  File.delete(filename) if File.exist?(filename)
  buffer = Mrbmacs::Buffer.new(filename)
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.load_initial_file(filename)

  assert_equal '', view.text
  assert_true view.save_point
  assert_equal 'New file', frame.last_message
  assert_equal File.expand_path(filename), app.current_buffer.filename
end

assert('Mrbmacs::ApplicationCocoa starts scratch as an empty saved document') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.load_initial_file

  assert_equal '', view.text
  assert_true view.save_point
  assert_nil frame.last_message
end

assert('Mrbmacs::ApplicationCocoa opens a new file with shared find_file') do
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-cocoa-find-#{$$}.rb"
  File.delete(filename) if File.exist?(filename)
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view, buffer)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.find_file(filename)

  assert_equal File.expand_path(filename), app.current_buffer.filename
  assert_equal 2, app.buffer_list.length
  assert_same app.current_buffer, pane.buffer
  assert_equal 'New file', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa switches safely with only one buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  frame.input_events = [[:enter, '']]
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('b')
  assert_same buffer, app.current_buffer
  assert_equal [buffer], app.buffer_list
end

assert('Mrbmacs::ApplicationCocoa kills a buffer through shared command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  frame = CocoaFrameForConfirmationTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-kill-#{$$}.txt"
  app.find_file(filename)
  frame.input_events = [[:enter, '']]

  assert_true app.key_press('C-x')
  assert_true app.key_press('k')
  assert_equal ['*scratch*'], app.buffer_list.map(&:name)
  assert_equal '*scratch*', app.current_buffer.name
end

assert('Mrbmacs::ApplicationCocoa searches incrementally forward') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'alpha beta alpha'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-s')
  assert_true app.isearch_active?
  echo_win.text = 'alpha'
  app.echo_sci_notify('code' => Scintilla::SCN_MODIFIED)
  assert_equal [0, 5], view.selections.last
  assert_true app.echo_key_press('C-s')
  assert_equal [11, 16], view.selections.last
  echo_win.text = ''
  app.echo_sci_notify('code' => Scintilla::SCN_MODIFIED)
  assert_equal 0, view.current_pos
  assert_true app.echo_key_press('Enter')
  assert_false app.isearch_active?
  assert_equal '', echo_win.text
end

assert('Mrbmacs::ApplicationCocoa searches backward and cancels') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'alpha beta alpha'
  view.current_pos = view.text.bytesize
  view.sci_goto_pos(view.current_pos)
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-r')
  echo_win.text = 'alpha'
  app.echo_sci_notify('code' => Scintilla::SCN_MODIFIED)
  assert_equal [11, 16], view.selections.last
  assert_true app.echo_key_press('C-g')
  assert_equal view.text.bytesize, view.current_pos
  assert_false app.isearch_active?
end

assert('Mrbmacs::ApplicationCocoa uses byte length for search text') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'aあb'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.isearch_forward
  echo_win.text = 'あ'
  app.echo_sci_notify('code' => Scintilla::SCN_MODIFIED)
  assert_equal 'あ'.bytesize, view.search_lengths.last
end

assert('Mrbmacs::ApplicationCocoa replaces all text from point') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one two one'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.start_replace(false, 'one', '1')

  assert_equal '1 two 1', view.text
  assert_equal [:begin, :end], view.undo_actions
  assert_equal 'Replaced 2 occurrences', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa starts query replace with M-%') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one two one'
  echo_win = CocoaViewForLayoutTest.new
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  frame.input_events = [[:enter, 'one'], [:enter, '1']]
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('M-%')

  assert_true app.query_replace_active?
  assert_equal [0, 3], view.selections.last
  assert_true app.echo_key_press('q')
end

assert('Mrbmacs::ApplicationCocoa skips and replaces query matches') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one two one'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.start_replace(true, 'one', '1')
  assert_true app.query_replace_active?
  assert_equal [0, 3], view.selections.last
  assert_true app.echo_key_press('n')
  assert_equal [8, 11], view.selections.last
  assert_true app.echo_key_press('y')

  assert_equal 'one two 1', view.text
  assert_false app.query_replace_active?
  assert_equal 'Replaced 1 occurrence', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa replaces remaining query matches') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one one one'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.start_replace(true, 'one', '1')
  assert_true app.echo_key_press('!')

  assert_equal '1 1 1', view.text
  assert_false app.query_replace_active?
  assert_equal 'Replaced 3 occurrences', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa cancels query replace') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one two one'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.start_replace(true, 'one', '1')
  assert_true app.echo_key_press('C-g')

  assert_equal 'one two one', view.text
  assert_false app.query_replace_active?
  assert_equal 'Quit', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa rejects an empty replacement search') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.start_replace(false, '', 'x')

  assert_equal 'one', view.text
  assert_equal 'Empty search string', frame.last_message
end

assert('Mrbmacs::ApplicationCocoa uses byte lengths for replacement') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'a'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.start_replace(false, 'a', 'あ')

  assert_equal 'あ'.bytesize, view.replacement_lengths.last
end


assert('Mrbmacs::ApplicationCocoa handles a Scintilla key command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-f')
  assert_equal [Scintilla::SCI_CHARRIGHT], view.messages
end


assert('Mrbmacs::ApplicationCocoa handles a prefix Scintilla command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('u')
  assert_equal [Scintilla::SCI_UNDO], view.messages
end

assert('Mrbmacs::ApplicationCocoa treats Escape as a Meta prefix') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('Escape')
  assert_true app.key_press('f')
  assert_equal [Scintilla::SCI_WORDRIGHT], view.messages
end

assert('Mrbmacs::ApplicationCocoa clears an undefined Escape prefix') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('Escape')
  assert_false app.key_press('z')
  assert_true app.key_press('C-f')
  assert_equal [Scintilla::SCI_CHARRIGHT], view.messages
end


assert('Mrbmacs::ApplicationCocoa leaves text input to Cocoa') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_false app.key_press('a')
  assert_equal [], view.messages
end


assert('Mrbmacs::ApplicationCocoa runs a shared Ruby editor command') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-a')
  assert_equal [Scintilla::SCI_HOME], view.messages
end

assert('Mrbmacs::ApplicationCocoa handles mark, copy, and yank commands') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  view.current_pos = 2
  assert_true app.key_press('C- ')
  view.current_pos = 7
  assert_true app.key_press('M-w')
  assert_true app.key_press('C-y')

  assert_equal [[2, 7]], view.copied_ranges
  assert_equal [
    [:set_anchor, 2],
    [:set_selection_mode, 0],
    [:set_empty_selection, 7],
    :paste
  ], view.messages
end

assert('Mrbmacs::ApplicationCocoa handles newline') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('Enter')
  assert_equal [:new_line], view.messages
end


assert('Mrbmacs::ApplicationCocoa saves through a shared Ruby command') do
  filename = "#{ENV['TMPDIR'] || '/tmp'}/mrbmacs-cocoa-save-#{$$}.txt"
  buffer = Mrbmacs::Buffer.new(filename)
  view = CocoaViewForLayoutTest.new
  view.text = "saved from Cocoa\n"
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  begin
    assert_true app.key_press('C-x')
    assert_true app.key_press('C-s')
    assert_equal "saved from Cocoa\n", File.read(filename)
    assert_true view.save_point
  ensure
    File.delete(filename) if File.exist?(filename)
  end
end

assert('Mrbmacs::ApplicationCocoa exits through its Cocoa frame') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  frame = CocoaFrameForExitTest.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer))
  )
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('C-c')
  assert_true frame.exited
end


assert('Cocoa layout starts with one frame, one tab, and one pane') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  tab = Mrbmacs::TabCocoa.new(pane)
  frame = Mrbmacs::FrameCocoa.new(tab)

  assert_same view, pane.view
  assert_kind_of Mrbmacs::ScintillaNotificationBridge,
                 view.notification_callback
  assert_equal [pane], tab.panes
  assert_same pane, tab.active_pane
  assert_equal [tab], frame.tabs
  assert_same tab, frame.active_tab
  assert_same pane, frame.active_pane
  assert_same view, frame.view
  assert_false view.horizontal_scrollbar
  assert_equal 1234, pane.native_handle
end

assert('Cocoa layout exposes the shared frame and edit-window interface') do
  view = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  assert_kind_of Mrbmacs::FrameBase, frame
  assert_same view, pane.sci
  assert_same view, frame.view_win
  assert_same pane, frame.edit_win
  assert_equal [pane], frame.edit_win_list
end

assert('Cocoa tab maintains a nested pane layout tree') do
  first = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(101))
  second = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(102))
  third = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(103))
  tab = Mrbmacs::TabCocoa.new(first)

  vertical = tab.split(first, second, :vertical)
  horizontal = tab.split(second, third, :horizontal)

  assert_same vertical, tab.layout_root
  assert_same horizontal, vertical.second
  assert_equal [first, second, third], tab.panes
  assert_equal :vertical, vertical.orientation
  assert_equal :horizontal, horizontal.orientation
end

assert('Cocoa frame cycles and deletes panes through the layout tree') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  first = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(101), buffer)
  second = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(102), buffer)
  third = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(103), buffer)
  tab = Mrbmacs::TabCocoa.new(first)
  tab.split(first, second, :vertical)
  tab.split(second, third, :horizontal)
  frame = Mrbmacs::FrameCocoa.new(tab)

  frame.switch_window(second)
  assert_same second, frame.active_pane
  assert_true second.view.messages.include?(:grab_focus)
  frame.delete_window(second)

  assert_equal [first, third], tab.panes
  assert_same third, frame.active_pane
  assert_equal 2, second.view.added_documents.size
  assert_equal second.buffer.docpointer, second.view.added_documents.last
  frame.delete_other_window
  assert_equal [third], tab.panes
  assert_same third, tab.layout_root
  assert_equal [first.buffer.docpointer], first.view.added_documents
end

assert('Cocoa application splits the active pane with the same buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(Scintilla::ScintillaCocoa.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)
  frame = Mrbmacs::FrameCocoa.new(tab)
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  assert_true app.key_press('C-x')
  assert_true app.key_press('2')

  assert_equal 2, tab.panes.size
  assert_same pane, tab.active_pane
  assert_same buffer, tab.panes[1].buffer
  pane.view.sci_set_text('shared')
  assert_equal 'shared', tab.panes[1].view.sci_get_text(7)
end

assert('Cocoa application rejects a pane that is too small to split') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)
  frame = Mrbmacs::FrameCocoa.new(tab)
  frame.native_handle = 1
  frame.define_singleton_method(:pane_can_split?) do |_pane, _direction, _size|
    false
  end
  app = Mrbmacs::ApplicationCocoa.new(frame, buffer)

  app.split_window(false)

  assert_equal [pane], tab.panes
  assert_equal 'too small for splitting', frame.last_message
end

assert('Cocoa frame refuses to delete its sole pane') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  frame.delete_window(pane)

  assert_equal [pane], frame.edit_win_list
  assert_equal 'Atempt to delete sole ordinary window', frame.last_message
end

assert('Mrbmacs::FrameCocoa updates the active pane mode line') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))
  app = CocoaModelineApplicationForTest.new

  frame.modeline(app)

  assert_equal app.modeline_str, pane.modeline_text
end

assert('Mrbmacs::FrameCocoa displays messages in its shared echo area') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)

  frame.echo_puts('New file')

  assert_same echo_win, frame.echo_win
  assert_false echo_win.horizontal_scrollbar
  assert_false echo_win.vertical_scrollbar
  (0..2).each do |margin|
    assert_true echo_win.margin_messages.include?([:margin_width, margin, 0])
  end
  assert_equal 'New file', echo_win.text
  assert_true echo_win.messages.include?(:document_end)
  assert_equal 'New file', frame.last_message
end

assert('Mrbmacs::FrameCocoa configures a separate echo notification bridge') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane), echo_win)

  assert_kind_of Mrbmacs::EchoNotificationBridge,
                 echo_win.notification_callback
end

assert('Mrbmacs::FrameCocoa reads input through its shared echo area') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:enter, '/tmp/test.rb']]

  assert_equal '/tmp/test.rb', frame.echo_gets('Find file: ', '/tmp/')
  assert_equal '', echo_win.text
  assert_true echo_win.margin_messages.include?([:margin_text, 0, 'Find file: '])
  assert_true echo_win.margin_messages.include?([:margin_text, 0, ''])
  assert_true view.messages.include?(:grab_focus)
end


assert('Mrbmacs::FrameCocoa completes echo input with Tab') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:tab, 'for'], :enter, :enter]

  result = frame.echo_gets('M-x ') do |input|
    ['forward-char forward-line', input.length]
  end

  assert_equal 'forward-char', result
  assert_true view.messages.include?(:grab_focus)
end

assert('Mrbmacs::FrameCocoa selects a buffer through its echo area') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:enter, 'notes.rb']]

  result = frame.select_buffer('*scratch*', ['*scratch*', 'notes.rb'])

  assert_equal 'notes.rb', result
  assert_true echo_win.margin_messages.include?(
    [:margin_text, 0, 'Switch to buffer: (default *scratch*) ']
  )
  assert_true view.messages.include?(:grab_focus)
end

assert('Mrbmacs::FrameCocoa completes buffer names by prefix') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForEchoInputTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )
  frame.input_events = [[:tab, 'no'], :enter, :enter]

  result = frame.select_buffer(
    '*scratch*', ['*scratch*', 'notes.rb', 'notice.txt']
  )

  assert_equal 'notes.rb', result
  assert_equal [2, 'notes.rb notice.txt'], echo_win.autocomplete_lists.first
  assert_true view.messages.include?(:grab_focus)
end

assert('Mrbmacs::FrameCocoa confirms with one modal key') do
  view = CocoaViewForLayoutTest.new
  echo_win = CocoaViewForLayoutTest.new
  pane = Mrbmacs::PaneCocoa.new(view)
  frame = CocoaFrameForConfirmationTest.new(
    Mrbmacs::TabCocoa.new(pane), echo_win
  )

  frame.confirmation_event = :yes
  assert_true frame.y_or_n('Buffer modified; kill anyway? (y or n) ')
  frame.confirmation_event = :no
  assert_false frame.y_or_n('Buffer modified; kill anyway? (y or n) ')
  assert_equal '', echo_win.text
  assert_true view.messages.include?(:grab_focus)
  assert_true echo_win.margin_messages.include?([:margin_text, 0, ''])
end

assert('Mrbmacs::TabCocoa is a layout and not a buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)

  assert_same buffer, pane.buffer
  assert_false tab.respond_to?(:buffer)
end


assert('Mrbmacs::PaneCocoa assigns its initial document to a buffer') do
  view = CocoaViewForLayoutTest.new(123)
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(view, buffer)

  assert_same buffer, pane.buffer
  assert_equal 123, buffer.docpointer
  assert_equal [], view.added_documents
  assert_equal [], view.set_documents
end


assert('Mrbmacs::PaneCocoa displays an existing buffer document') do
  view = CocoaViewForLayoutTest.new(123)
  buffer = Mrbmacs::Buffer.new('*scratch*')
  buffer.docpointer = 456
  pane = Mrbmacs::PaneCocoa.new(view, buffer)

  assert_same buffer, pane.buffer
  assert_equal [456], view.added_documents
  assert_equal [456], view.set_documents
end
