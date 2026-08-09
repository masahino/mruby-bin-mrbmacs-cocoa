require 'fileutils'
require 'tmpdir'

MACOS_APP_NAME = 'Mrbmacs'.freeze
MACOS_APP_PATH = File.expand_path("build/#{MACOS_APP_NAME}.app", __dir__ + '/..')
MACOS_APP_CONTENTS = File.join(MACOS_APP_PATH, 'Contents').freeze
MACOS_APP_EXECUTABLE = File.join(
  MACOS_APP_CONTENTS, 'MacOS', 'mrbmacs-cocoa'
).freeze
MACOS_APP_FRAMEWORK = File.join(
  MACOS_APP_CONTENTS, 'Frameworks', 'Scintilla.framework'
).freeze
MACOS_NOTARY_PROFILE = ENV.fetch('NOTARY_PROFILE', 'mrbmacs-notary').freeze
MACOS_NOTARIZATION_ARCHIVE = File.expand_path(
  'build/Mrbmacs-notarization.zip', __dir__ + '/..'
).freeze

def scintilla_framework_path
  frameworks = Dir.glob(File.expand_path(
    '../mruby/build/*/mrbgems/mruby-scintilla-cocoa/' \
    'framework/Release/Scintilla.framework', __dir__
  ))
  framework = frameworks.find { |path| path.include?('/build/host/') }
  framework ||= frameworks.first
  raise 'Scintilla.framework was not built' if framework.nil?

  framework
end

def macos_codesign_identity
  return ENV['CODESIGN_IDENTITY'] unless ENV['CODESIGN_IDENTITY'].to_s.empty?

  identities = `security find-identity -v -p codesigning`.lines.map do |line|
    match = line.match(/"(Developer ID Application: .+)"/)
    match[1] unless match.nil?
  end.compact
  return identities.first if identities.one?
  return '-' if identities.empty?

  raise 'Multiple Developer ID Application identities found; ' \
        'set CODESIGN_IDENTITY'
end

def sign_macos_code(path, identity)
  arguments = ['codesign', '--force', '--sign', identity]
  unless identity == '-'
    arguments.insert(1, '--options', 'runtime', '--timestamp')
  end
  sh(*arguments, path)
end

def developer_team_id(identity)
  return ENV['DEVELOPER_TEAM_ID'] unless ENV['DEVELOPER_TEAM_ID'].to_s.empty?

  match = identity.match(/\(([A-Z0-9]{10})\)$/)
  raise 'Unable to determine Developer Team ID' if match.nil?

  match[1]
end

def macos_app_version
  info_plist = File.join(MACOS_APP_CONTENTS, 'Info.plist')
  IO.popen(
    ['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleShortVersionString', info_plist],
    &:read
  ).strip
end

def create_macos_app_archive(archive)
  sh(
    'ditto', '-c', '-k', '--norsrc', '--keepParent', MACOS_APP_PATH,
    archive
  )
end

def verify_macos_app_archive(archive)
  Dir.mktmpdir('mrbmacs-release-') do |directory|
    sh 'ditto', '-x', '-k', archive, directory
    app_path = File.join(directory, "#{MACOS_APP_NAME}.app")
    metadata_files = Dir.glob(
      File.join(app_path, '**', '._*'), File::FNM_DOTMATCH
    )
    unless metadata_files.empty?
      raise "Archive contains AppleDouble metadata: #{metadata_files.first}"
    end

    sh 'codesign', '--verify', '--deep', '--strict', app_path
    sh 'xcrun', 'stapler', 'validate', app_path
    sh 'spctl', '--assess', '--type', 'execute', '--verbose=4', app_path
  end
end

desc 'Build the macOS application bundle'
task app: :compile do
  identity = macos_codesign_identity
  FileUtils.rm_rf(MACOS_APP_PATH)
  FileUtils.mkdir_p(File.dirname(MACOS_APP_EXECUTABLE))
  FileUtils.mkdir_p(File.dirname(MACOS_APP_FRAMEWORK))
  FileUtils.mkdir_p(File.join(MACOS_APP_CONTENTS, 'Resources'))

  FileUtils.cp(
    File.expand_path('../mruby/bin/mrbmacs-cocoa', __dir__),
    MACOS_APP_EXECUTABLE
  )
  FileUtils.chmod(0o755, MACOS_APP_EXECUTABLE)
  FileUtils.cp(
    File.expand_path('../resources/Info.plist', __dir__),
    MACOS_APP_CONTENTS
  )
  FileUtils.cp(
    File.expand_path('../resources/mrbmacs.icns', __dir__),
    File.join(MACOS_APP_CONTENTS, 'Resources')
  )
  FileUtils.cp_r(scintilla_framework_path, File.dirname(MACOS_APP_FRAMEWORK))

  sign_macos_code(MACOS_APP_FRAMEWORK, identity)
  sign_macos_code(MACOS_APP_EXECUTABLE, identity)
  sign_macos_code(MACOS_APP_PATH, identity)
  sh 'codesign', '--verify', '--deep', '--strict', MACOS_APP_PATH

  puts "Created #{MACOS_APP_PATH} (signed with #{identity})"
end

desc 'Open the macOS application bundle'
task run_app: :app do
  sh 'open', MACOS_APP_PATH
end

desc 'Store notarization credentials in the login keychain'
task :notarization_credentials do
  apple_id = ENV['APPLE_ID']
  raise 'Set APPLE_ID to your Apple Account email address' if apple_id.to_s.empty?

  identity = macos_codesign_identity
  raise 'A Developer ID Application identity is required' if identity == '-'

  sh(
    'xcrun', 'notarytool', 'store-credentials', MACOS_NOTARY_PROFILE,
    '--apple-id', apple_id,
    '--team-id', developer_team_id(identity)
  )
end

desc 'Build, sign, notarize, staple, and archive the macOS application'
task release: :app do
  identity = macos_codesign_identity
  raise 'A Developer ID Application identity is required' if identity == '-'

  FileUtils.rm_f(MACOS_NOTARIZATION_ARCHIVE)
  create_macos_app_archive(MACOS_NOTARIZATION_ARCHIVE)
  sh(
    'xcrun', 'notarytool', 'submit', MACOS_NOTARIZATION_ARCHIVE,
    '--keychain-profile', MACOS_NOTARY_PROFILE,
    '--wait'
  )
  sh 'xcrun', 'stapler', 'staple', MACOS_APP_PATH
  sh 'xcrun', 'stapler', 'validate', MACOS_APP_PATH
  sh 'codesign', '--verify', '--deep', '--strict', MACOS_APP_PATH
  sh 'spctl', '--assess', '--type', 'execute', '--verbose=4', MACOS_APP_PATH

  archive = File.expand_path(
    "build/Mrbmacs-#{macos_app_version}-macos-arm64.zip", __dir__ + '/..'
  )
  FileUtils.rm_f(archive)
  create_macos_app_archive(archive)
  verify_macos_app_archive(archive)
  FileUtils.rm_f(MACOS_NOTARIZATION_ARCHIVE)
  puts "Created #{archive}"
end
