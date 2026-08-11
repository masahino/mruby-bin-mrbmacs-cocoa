assert('Mrbmacs::ApplicationCocoa replaces all text from point') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  view = CocoaViewForLayoutTest.new
  view.text = 'one two one'
  echo_win = CocoaViewForLayoutTest.new
  frame = Mrbmacs::FrameCocoa.new(
    Mrbmacs::TabCocoa.new(Mrbmacs::PaneCocoa.new(view, buffer)), echo_win
  )
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

  app.start_replace(false, 'a', 'あ')

  assert_equal 'あ'.bytesize, view.replacement_lengths.last
end
