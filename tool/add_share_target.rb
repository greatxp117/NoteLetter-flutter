# Adds the iOS share extension (F-122) to ios/Runner.xcodeproj. Once: see
# "Once only" below.
#
#   (cd ios && ruby ../tool/add_share_target.rb && pod install)
#
# The extension (`ios/Share`, bundle xp.NoteLetter.Flutter.Share) is a port of
# the retired Swift app's NoteLetterShare. It shares an App Group and a
# keychain group with Runner — this app's OWN (group.xp.NoteLetter.Flutter,
# 3SA8A2JP3T.xp.NoteLetter.Flutter.shared; ruled 2026-10-18: start fresh) — so
# it signs in as whoever signed in to the app.
#
# Pattern from NoteLetter/add_safari_targets.rb. The embed phase goes BEFORE
# Flutter's "Thin Binary" script, or Xcode reports a build-phase cycle in
# Runner.
require 'xcodeproj'

PROJECT = 'Runner.xcodeproj'
TEAM    = '3SA8A2JP3T'
NAME    = 'Share'
BUNDLE  = 'xp.NoteLetter.Flutter.Share'
DEPLOY  = '15.0'
# The extension's own floor: its SwiftUI (NavigationStack) is iOS 16. An
# extension may require more than its app — on iOS 15 the app runs and the
# share sheet simply does not offer it.
EXT_DEPLOY = '16.0'

project = Xcodeproj::Project.open(PROJECT)
runner  = project.targets.find { |t| t.name == 'Runner' }
raise 'no Runner target' unless runner

UI_TESTS = 'RunnerUITests'

# ── Once only ─────────────────────────────────────────────────────────────────
# Removing a target with xcodeproj leaves its groups, configuration lists and
# build files behind (a re-run measured 71 orphan objects), so this does not
# pretend to be re-runnable: to change what it adds, restore the project file
# from git and run it again.
if project.targets.any? { |t| [NAME, UI_TESTS].include?(t.name) }
  abort "#{NAME} is already in #{PROJECT}. To re-add it: git checkout ios/#{PROJECT}/project.pbxproj ios/#{PROJECT}/xcshareddata/xcschemes/Runner.xcscheme, then run this and `pod install` again."
end
unit_tests = project.targets.find { |t| t.name == 'RunnerTests' }

# ── Runner: its entitlements (the App Group + the shared keychain group) ──────
runner_group = project.main_group['Runner']
runner_group.new_reference('Runner.entitlements')
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  # Flutter's template defines no DEBUG for Swift, so AppDelegate's `#if DEBUG`
  # (the share extension's emulator handoff) compiled out of every build and
  # the debug extension refused. Debug only: a release build never writes it.
  if c.name == 'Debug'
    c.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG'
  end
end

# ── The extension target ─────────────────────────────────────────────────────
ext = project.new_target(:app_extension, NAME, :ios, EXT_DEPLOY)
group = project.main_group.new_group(NAME, NAME)
Dir.children(NAME).sort.each do |f|
  ref = group.new_reference(f)
  ext.add_file_references([ref]) if f.end_with?('.swift')
end

# Resources: the Flutter app's own fonts, and its Firebase config (the iOS API
# key carries no bundle restriction — checked read-only 2026-10-18).
fonts_group = group.new_group('Fonts', '../../assets/fonts')
%w[SourceSerif4-Variable.ttf SourceSerif4-Italic-Variable.ttf
   Geist-Light.ttf Geist-Regular.ttf Geist-Medium.ttf Geist-SemiBold.ttf Geist-Bold.ttf
   GeistMono-Regular.ttf GeistMono-Medium.ttf].each do |f|
  raise "missing font #{f}" unless File.exist?(File.join('..', 'assets', 'fonts', f))
  ext.add_resources([fonts_group.new_reference(f)])
end
plist = project.files.find { |r| File.basename(r.path.to_s) == 'GoogleService-Info.plist' }
raise 'no Runner/GoogleService-Info.plist' unless plist
ext.add_resources([plist])

# Base configurations: Pods + Flutter's Generated.xcconfig (for the version).
# The Flutter group has a NAME and no path (its files carry `Flutter/…`), so a
# reference made in it must carry the folder too, or it resolves to ios/ and
# CocoaPods cannot find the include in it.
flutter_group = project.main_group['Flutter']
xc = %w[Debug Release Profile].to_h do |n|
  ref = flutter_group.new_reference("Flutter/Share#{n}.xcconfig")
  ref.name = "Share#{n}.xcconfig"
  raise "missing ios/Flutter/Share#{n}.xcconfig" unless ref.real_path.file?
  [n, ref]
end
unless ext.build_configurations.any? { |c| c.name == 'Profile' }
  release = ext.build_configurations.find { |c| c.name == 'Release' }
  profile = ext.add_build_configuration('Profile', :release)
  profile.build_settings.merge!(release.build_settings)
end

ext.build_configurations.each do |c|
  c.base_configuration_reference = xc[c.name]
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'      => BUNDLE,
    'PRODUCT_NAME'                   => '$(TARGET_NAME)',
    'INFOPLIST_FILE'                 => "#{NAME}/Info.plist",
    'GENERATE_INFOPLIST_FILE'        => 'NO',
    'CODE_SIGN_ENTITLEMENTS'         => "#{NAME}/Share.entitlements",
    'CODE_SIGN_STYLE'                => 'Automatic',
    'DEVELOPMENT_TEAM'               => TEAM,
    'SWIFT_VERSION'                  => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET'     => EXT_DEPLOY,
    'TARGETED_DEVICE_FAMILY'         => '1,2',
    'SKIP_INSTALL'                   => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS'        => ['$(inherited)', '@executable_path/Frameworks',
                                         '@executable_path/../../Frameworks'],
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => c.name == 'Debug' ? 'DEBUG' : '',
  )
end

# ── Embed it in Runner, before Thin Binary ───────────────────────────────────
runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
phases = runner.build_phases
phases.delete(embed)
thin = phases.index { |p| p.display_name == 'Thin Binary' } || phases.length
phases.insert(thin, embed)

# ── Tests ────────────────────────────────────────────────────────────────────
# The activation rule, evaluated the way the share sheet evaluates it, in the
# unit bundle: UploadTypes.swift compiled in from ios/Share, so the accepted
# set the tests read is the extension's own.
unit_tests.add_file_references([project.main_group['RunnerTests'].new_reference('ShareActivationRuleTests.swift')])
upload_types = group.files.find { |r| r.path == 'UploadTypes.swift' }
unit_tests.add_file_references([upload_types])

# The extension driven from Files, Safari and Photos: a UI test bundle.
ui = project.new_target(:ui_test_bundle, UI_TESTS, :ios, DEPLOY)
ui_group = project.main_group.new_group(UI_TESTS, UI_TESTS)
Dir.children(UI_TESTS).sort.select { |f| f.end_with?('.swift') }.each do |f|
  ui.add_file_references([ui_group.new_reference(f)])
end
ui.add_dependency(runner)
ui.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'  => 'xp.NoteLetter.Flutter.RunnerUITests',
    'PRODUCT_NAME'               => '$(TARGET_NAME)',
    'GENERATE_INFOPLIST_FILE'    => 'YES',
    'CODE_SIGN_STYLE'            => 'Automatic',
    'DEVELOPMENT_TEAM'           => TEAM,
    'SWIFT_VERSION'              => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOY,
    'TARGETED_DEVICE_FAMILY'     => '1,2',
    'TEST_TARGET_NAME'           => 'Runner',
  )
end
unless ui.build_configurations.any? { |c| c.name == 'Profile' }
  rel = ui.build_configurations.find { |c| c.name == 'Release' }
  ui.add_build_configuration('Profile', :release).build_settings.merge!(rel.build_settings)
end

project.save

# The Runner scheme tests both bundles.
scheme_path = Xcodeproj::XCScheme.shared_data_dir(PROJECT) + 'Runner.xcscheme'
scheme = Xcodeproj::XCScheme.new(scheme_path)
scheme.test_action.testables.reject! { |t| t.buildable_references.any? { |r| r.target_name == UI_TESTS } }
scheme.test_action.add_testable(Xcodeproj::XCScheme::TestAction::TestableReference.new(ui))
scheme.save_as(PROJECT, 'Runner', true)

puts "targets: #{project.targets.map(&:name).join(', ')}"
puts "Runner phases: #{runner.build_phases.map(&:display_name).join(' | ')}"
