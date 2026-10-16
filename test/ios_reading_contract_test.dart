import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/legacy_wenku_repository.dart';
import 'package:wenku8_flutter/local_platform.dart';
import 'package:wenku8_flutter/wenku_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chapter = NovelChapter('章节', '', id: 2);

  test(
    'a literal error tag inside prose is not mistaken for an API error',
    () async {
      final repository = LegacyWenkuRepository(
        request: (_) async => '正文引用 <error> 标签作为例子。',
      );
      expect(
        await repository.chapterContent(1, chapter),
        '正文引用 <error> 标签作为例子。',
      );
    },
  );

  for (final response in [
    '4',
    '20',
    '',
    '<html>challenge</html>',
    '<!DOCTYPE html><html>error</html>',
    '<?xml version="1.0"?><error>failed</error>',
  ]) {
    test('chapter rejects non-content payload: $response', () async {
      final repository = LegacyWenkuRepository(request: (_) async => response);
      await expectLater(
        repository.chapterContent(1, chapter),
        throwsA(anyOf(isA<FormatException>(), isA<WenkuApiError>())),
      );
    });
  }

  test(
    'valid chapter preserves paragraph normalization and illustration markers',
    () async {
      final repository = LegacyWenkuRepository(
        request: (_) async => '  正文第一段\r\n\r\n第二段  ',
      );
      expect(await repository.chapterContent(1, chapter), '正文第一段\n\n第二段');
    },
  );

  test(
    'iOS reader screen ownership keeps awake until the last owner leaves',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final requested = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(LocalPlatform.channel, (call) async {
        if (call.method == 'keepScreenOn') {
          requested.add(call.arguments as bool);
        }
        return null;
      });
      final first = Object(), second = Object();
      try {
        LocalPlatform.keepScreen(first, true);
        LocalPlatform.keepScreen(second, true);
        LocalPlatform.keepScreen(first, false);
        LocalPlatform.keepScreen(second, false);
        await Future<void>.delayed(Duration.zero);
        expect(requested, [true, false]);
      } finally {
        LocalPlatform.keepScreen(first, false);
        LocalPlatform.keepScreen(second, false);
        messenger.setMockMethodCallHandler(LocalPlatform.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
