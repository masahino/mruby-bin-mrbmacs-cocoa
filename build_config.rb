MRuby::Build.new do |conf|
  toolchain :clang
  conf.gembox 'default'

  conf.gem File.expand_path('../mruby-scintilla-cocoa', __dir__)
  conf.gem File.expand_path(__dir__)

  conf.linker.libraries << 'c++'
end

