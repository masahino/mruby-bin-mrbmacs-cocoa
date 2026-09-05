require 'open3'

script_dir = File.expand_path('scripts', __dir__)

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
