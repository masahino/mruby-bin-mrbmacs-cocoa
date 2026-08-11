assert('Mrbmacs::ApplicationCocoa searches incrementally forward') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'alpha beta alpha'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

  app.isearch_forward
  echo_win.text = 'あ'
  app.echo_sci_notify('code' => Scintilla::SCN_MODIFIED)
  assert_equal 'あ'.bytesize, view.search_lengths.last
end
