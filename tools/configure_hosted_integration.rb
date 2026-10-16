# Use Flutter integration_test's native result channel, without VM-service
# discovery. Test-only project/source injection; application sources are intact.
require 'xcodeproj'

mode = ARGV.fetch(0)
counts = { 'capture' => 3, 'motion' => 1 }
abort 'Expected capture or motion' unless counts.key?(mode)
names = {
  'capture' => ['native glass texture tracks changing Flutter Metal content',
                'real platform controls retain Gaussian feather and native hit targets',
                'shared Gaussian plane preserves Metal native and foreground order'],
  'motion' => ['record the same real book search and settings transitions']
}
expected_names = names.fetch(mode).map { |name| '@' + name.dump }.join(', ')
report = mode == 'motion' ? 'wenku-motion-benchmark.json' : 'wenku-native-capture-probe.json'
source = <<~OBJC
  #import <XCTest/XCTest.h>
  @import integration_test;

  @interface WenkuHostedIntegrationTests : XCTestCase
  @end
  @implementation WenkuHostedIntegrationTests
  - (void)testDartIntegration {
    IntegrationTestPlugin *plugin = [IntegrationTestPlugin instance];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
      return plugin.testResults != nil;
    }];
    XCTNSPredicateExpectation *finished = [[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:nil];
    [self waitForExpectations:@[finished] timeout:240];
    NSDictionary *results = plugin.testResults;
    XCTAssertNotNil(results, @"Dart integration never reported results within its execution budget");
    if (!results) return;
    NSData *outcomes = [NSJSONSerialization dataWithJSONObject:results options:0 error:nil];
    XCTAttachment *resultAttachment = [XCTAttachment attachmentWithData:outcomes uniformTypeIdentifier:@"public.json"];
    resultAttachment.name = @"dart-test-results.json";
    resultAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:resultAttachment];
    XCTAssertEqual(results.count, #{counts.fetch(mode)}u, @"Every expected Dart test must report a result");
    NSSet *expected = [NSSet setWithArray:@[#{expected_names}]];
    XCTAssertEqualObjects([NSSet setWithArray:results.allKeys], expected, @"The exact expected Dart tests must execute");
    for (NSString *name in results) {
      XCTAssertEqualObjects(results[name], @"success", @"%@: %@", name, results[name]);
    }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"#{report}"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"Missing actual pixel/timing evidence: %@", path);
    if (data) {
      XCTAttachment *attachment = [XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
      attachment.name = @"#{report}";
      attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
      [self addAttachment:attachment];
    }
  }
  @end
OBJC
path = 'ios/RunnerTests/WenkuHostedIntegrationTests.m'
File.write(path, source)
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |item| item.name == 'RunnerTests' }
abort 'Existing RunnerTests target required' unless target
group = project.main_group.find_subpath('RunnerTests', false)
abort 'Existing RunnerTests group required' unless group
reference = group.files.find { |item| item.path == 'WenkuHostedIntegrationTests.m' } || group.new_file('WenkuHostedIntegrationTests.m')
unless target.source_build_phase.files_references.include?(reference)
  target.source_build_phase.add_file_reference(reference)
end
project.save
puts "Hosted #{mode}: #{counts.fetch(mode)} Dart tests; 240-second execution cap; no app-source changes"
