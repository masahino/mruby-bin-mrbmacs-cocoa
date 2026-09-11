require 'open3'
require 'fileutils'
require 'timeout'

script_dir = File.expand_path('scripts', __dir__)
$edit_script_dir = "#{File.dirname(__FILE__)}/scripts/"
$edit_capture_file = "#{File.dirname(__FILE__)}/.capture"

# Editing scenarios shared with the curses, termbox and GTK frontends. Each
# Scintilla binding is a separate implementation and each frontend builds its
# own windows, so these have to be checked per frontend. The scripts are byte
# for byte the same everywhere; only this driver is Cocoa specific.
def cocoa_run(args, timeout: 30)
  status = nil
  Timeout.timeout(timeout) do
    _stdout, _stderr, status = Open3.capture3("#{cmd('mrbmacs-cocoa')} #{args}")
  end
  status
end

# Run a -l script that reports lines through ENV['MRBMACS_BINTEST_OUT'].
# Scripts are shared with termbox, whose PTY merges every stream, so the same
# file channel is used here.
def cocoa_capture(script)
  File.delete($edit_capture_file) if File.exist?($edit_capture_file)
  ENV['MRBMACS_BINTEST_OUT'] = $edit_capture_file
  status = cocoa_run("-q -l #{$edit_script_dir}#{script}")
  assert_equal 0, status.to_i
  File.exist?($edit_capture_file) ? File.read($edit_capture_file).split("\n") : []
end

# Copy +input_file+ aside, let +test_name+ edit and save it, then compare the
# saved bytes with the recorded expectation.
def run_edit_test(test_name, input_file = 'test.input')
  edit_file = "#{File.dirname(__FILE__)}/#{test_name}.input"
  output_file = "#{$edit_script_dir}#{test_name}.output"
  FileUtils.cp "#{File.dirname(__FILE__)}/#{input_file}", edit_file
  status = cocoa_run("-q -l #{$edit_script_dir}#{test_name} #{edit_file}")
  assert_equal 0, status.to_i
  assert_equal File.read(output_file), File.read(edit_file)
  File.delete edit_file
end

assert('report the generated frontend version') do
  version_file = File.join(
    ENV.fetch('BUILD_DIR'), 'mrbgems', GEMNAME, 'version.txt'
  )
  expected_version = File.read(version_file).strip
  stdout, stderr, status = Open3.capture3(
    "#{cmd('mrbmacs-cocoa')} --version"
  )

  assert_equal 0, status.to_i
  assert_equal '', stderr
  assert_equal expected_version, stdout.strip
end

assert('initialize Cocoa frontend') do
  stdout, _stderr, status = Open3.capture3(
    "#{cmd('mrbmacs-cocoa')} -q -l #{script_dir}/init_buffer"
  )
  assert_equal 0, status.to_i
  assert_equal ['*scratch*', 'true', 'true', 'true'], stdout.lines.map(&:chomp)
end

assert('open a file argument') do
  fixture = File.expand_path('fixtures/sample.txt', __dir__)
  stdout, _stderr, status = Open3.capture3(
    "#{cmd('mrbmacs-cocoa')} -q #{fixture} -l #{script_dir}/open_file"
  )
  assert_equal 0, status.to_i
  assert_equal ['sample.txt', 'Cocoa bintest fixture.'], stdout.lines.map(&:chomp)
end

assert('every non-interactive command runs against the real Scintilla') do
  lines = cocoa_capture('all-commands')

  failures = lines.select { |line| line.start_with?('NG ') }
  assert_equal [], failures
  # A base command in neither the allow nor the skip list needs a decision.
  undecided = lines.select { |line| line.start_with?('UNLISTED ') }
  assert_equal [], undecided
  # Without the trailing marker the script stopped early; the last line names
  # the command it was running.
  assert_true lines.include?('done'),
              "all-commands stopped at: #{lines.last.inspect}"
end

assert('edit-japanese') do
  run_edit_test('edit-japanese')
end

assert('rectangle') do
  run_edit_test('rectangle')
end

assert('comment') do
  run_edit_test('comment', 'test2.input')
end

assert('eol-crlf') do
  run_edit_test('eol-crlf', 'test-utf8-dos.input')
end

assert('encoding-cp932') do
  run_edit_test('encoding-cp932')
end

assert('window') do
  # The script reports any ERROR line logged while splitting and closing.
  assert_equal [], cocoa_capture('window')
end
