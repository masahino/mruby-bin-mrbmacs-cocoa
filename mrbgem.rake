MRuby::Gem::Specification.new('mruby-bin-mrbmacs-cocoa') do |spec|
  spec.license = 'MIT'
  spec.author = 'masahino'
  spec.version = '1.0.0'

  version_text = File.join(spec.build_dir, 'version.txt')
  generated_version = File.join(spec.build_dir, 'generated_version.rb')

  file version_text => __FILE__ do
    FileUtils.mkdir_p(spec.build_dir)
    File.open(version_text, 'w') { |file| file.puts spec.version }
  end

  file generated_version => version_text do
    version = File.read(version_text).strip
    File.open(generated_version, 'w') do |file|
      file.puts 'module Mrbmacs'
      file.puts '  class Application'
      file.puts "    Version = #{version.inspect}"
      file.puts '  end'
      file.puts 'end'
    end
  end

  spec.rbfiles << generated_version

  raise 'mruby-bin-mrbmacs-cocoa supports macOS only' unless RUBY_PLATFORM.include?('darwin')

  spec.add_dependency 'mruby-mrbmacs-base',
                      github: 'masahino/mruby-mrbmacs-base'
  spec.add_dependency 'mruby-scintilla-cocoa',
                      github: 'masahino/mruby-scintilla-cocoa'

  spec.bins = %w[mrbmacs-cocoa]

  # mruby's binary source discovery only includes C/C++ extensions. Compile
  # the launcher's .c file as Objective-C so it can use AppKit.
  spec.cc.flags << '-x objective-c'
  spec.linker.flags_before_libraries << '-framework Cocoa'
end
