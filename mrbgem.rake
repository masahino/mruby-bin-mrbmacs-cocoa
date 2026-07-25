MRuby::Gem::Specification.new('mruby-bin-mrbmacs-cocoa') do |spec|
  spec.license = 'MIT'
  spec.author = 'masahino'
  spec.version = '0.1.0'

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
