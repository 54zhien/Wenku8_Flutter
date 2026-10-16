# Deterministically add the UI-test runner for CI without changing app sources.
require 'xcodeproj'
require 'rexml/document'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |item| item.name == 'RunnerUITests' }
unless target
  target = project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '26.0')
  target.add_dependency(project.targets.find { |item| item.name == 'Runner' })
  group = project.main_group.new_group('RunnerUITests', 'RunnerUITests')
  target.source_build_phase.add_file_reference(group.new_file('RunnerUITests.swift'))
end
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'org.mewx.wenku8Flutter.RunnerUITests',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'TEST_TARGET_NAME' => 'Runner',
    'CODE_SIGNING_ALLOWED' => 'NO'
  )
end
project.save
path = 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
scheme = REXML::Document.new(File.read(path))
testables = scheme.elements['Scheme/TestAction/Testables']
unless testables.elements.to_a.any? { |entry| entry.elements['BuildableReference']&.attributes&.[]('BlueprintIdentifier') == target.uuid }
  testable = testables.add_element('TestableReference', 'skipped' => 'NO', 'parallelizable' => 'NO')
  testable.add_element('BuildableReference',
    'BuildableIdentifier' => 'primary', 'BlueprintIdentifier' => target.uuid,
    'BuildableName' => 'RunnerUITests.xctest', 'BlueprintName' => 'RunnerUITests',
    'ReferencedContainer' => 'container:Runner.xcodeproj')
  File.open(path, 'w') { |file| scheme.write(file) }
end
puts "UI-test target configured: #{target.uuid}"
