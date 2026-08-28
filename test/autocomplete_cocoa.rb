# Overriding send_message keeps these away from the real (C) Scintilla view,
# which needs a live native handle.
class AutocFixupProbeView < Scintilla::ScintillaCocoa
  attr_reader :sent, :fixup_count

  def initialize
    @sent = []
    @fixup_count = 0
  end

  def send_message(*args)
    @sent << args
    0
  end

  def mrbmacs_after_autocomplete_list
    @fixup_count += 1
  end
end

assert('ScintillaCocoa#sci_autoc_show forwards to SCI_AUTOCSHOW and fixes the listbox') do
  view = AutocFixupProbeView.new
  view.sci_autoc_show(3, "aaa\tbbb")

  assert_equal [[Scintilla::SCI_AUTOCSHOW, 3, "aaa\tbbb"]], view.sent
  assert_equal 1, view.fixup_count
end

assert('ScintillaCocoa#sci_userlist_show forwards to SCI_USERLISTSHOW and fixes the listbox') do
  view = AutocFixupProbeView.new
  view.sci_userlist_show(7, "one\ttwo")

  assert_equal [[Scintilla::SCI_USERLISTSHOW, 7, "one\ttwo"]], view.sent
  assert_equal 1, view.fixup_count
end

assert('ScintillaCocoa#mrbmacs_after_autocomplete_list is a no-op without the native helper') do
  # Mrbmacs.fixup_autocomplete_listbox is only linked into the app binary, not
  # the test binary, so calling the real body must not raise.
  probe = AutocFixupProbeView.new
  real = Scintilla::ScintillaCocoa.instance_method(:mrbmacs_after_autocomplete_list)

  assert_false Mrbmacs.respond_to?(:fixup_autocomplete_listbox)
  assert_nil real.bind(probe).call
end
