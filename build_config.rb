MRuby::Build.new do |conf|
  toolchain :clang
  conf.gembox 'default'

  conf.gem github: 'iij/mruby-regexp-pcre' do |gem|
    gem.skip_test = true
  end
  conf.gem github: 'mattn/mruby-iconv' do |gem|
    gem.skip_test = true
  end
  conf.gem github: 'masahino/mruby-mrbmacs-lsp'
  conf.gem github: 'masahino/mruby-lsp-client' do |gem|
    gem.skip_test = true
  end

  local_scintilla_cocoa =
    File.expand_path('../mruby-scintilla-cocoa', __dir__)
  conf.gem local_scintilla_cocoa if File.directory?(local_scintilla_cocoa)
  conf.gem File.expand_path(__dir__)

  conf.linker.libraries << 'c++'
  conf.enable_test
  conf.enable_bintest
end
