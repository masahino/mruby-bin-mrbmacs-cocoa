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
  assert_nil vertical.native_handle
end

assert('Cocoa frame resizes the nearest matching native split') do
  first = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(101))
  second = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(102))
  third = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(103))
  tab = Mrbmacs::TabCocoa.new(first)
  horizontal = tab.split(first, second, :horizontal)
  vertical = tab.split(first, third, :vertical)
  horizontal.native_handle = 201
  vertical.native_handle = 202
  frame = Mrbmacs::FrameCocoa.new(tab)
  moves = []
  frame.define_singleton_method(:native_divider_thickness) do |split|
    split.equal?(vertical) ? 2 : 1
  end
  frame.define_singleton_method(:move_native_divider) do |*arguments|
    moves << arguments
    true
  end

  frame.enlarge_window(first, 2)
  frame.enlarge_window_horizontally(first, 3)
  frame.enlarge_window_horizontally(second, 2)

  assert_equal [vertical, true, 32, 48, 48], moves[0]
  assert_equal [horizontal, true, 3, 10, 10], moves[1]
  assert_equal [horizontal, false, 2, 10, 10], moves[2]
  assert_equal 21, frame.minimum_native_extent(horizontal, :horizontal)
  assert_equal 98, frame.minimum_native_extent(horizontal, :vertical)
end

assert('Cocoa frame ignores resize without a split in that direction') do
  first = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(101))
  second = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new(102))
  tab = Mrbmacs::TabCocoa.new(first)
  split = tab.split(first, second, :horizontal)
  split.native_handle = 201
  frame = Mrbmacs::FrameCocoa.new(tab)

  assert_false frame.enlarge_window(first, 1)
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
  app = build_cocoa_application_for_test(frame, buffer)

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
  app = build_cocoa_application_for_test(frame, buffer)

  app.split_window(false)

  assert_equal [pane], tab.panes
  assert_equal 'too small for splitting', frame.last_message
end

assert('Cocoa application associates a native split with its layout node') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(Scintilla::ScintillaCocoa.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)
  frame = CocoaFrameForNativeSplitTest.new(tab)
  frame.native_handle = 1
  app = build_cocoa_application_for_test(frame, buffer)

  app.split_window(false)

  assert_equal 4321, tab.layout_root.native_handle
end

assert('Cocoa frame refuses to delete its sole pane') do
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new)
  frame = Mrbmacs::FrameCocoa.new(Mrbmacs::TabCocoa.new(pane))

  frame.delete_window(pane)

  assert_equal [pane], frame.edit_win_list
  assert_equal 'Atempt to delete sole ordinary window', frame.last_message
end

assert('Mrbmacs::TabCocoa is a layout and not a buffer') do
  buffer = Mrbmacs::Buffer.new('*scratch*')
  pane = Mrbmacs::PaneCocoa.new(CocoaViewForLayoutTest.new, buffer)
  tab = Mrbmacs::TabCocoa.new(pane)

  assert_same buffer, pane.buffer
  assert_false tab.respond_to?(:buffer)
end
