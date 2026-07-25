MRuby::Build.new do |conf|
  toolchain :clang
  conf.gembox 'default'

  conf.gem github: 'iij/mruby-regexp-pcre' do |gem|
    gem.skip_test = true
  end
  conf.gem github: 'mattn/mruby-iconv' do |gem|
    gem.skip_test = true
  end

  conf.gem File.expand_path('../mruby-scintilla-cocoa', __dir__)
  conf.gem File.expand_path(__dir__)

  conf.linker.libraries << 'c++'
  conf.enable_test
end
