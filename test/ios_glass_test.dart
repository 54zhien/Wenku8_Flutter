import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/ios_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native audio symbols preserve the meaning of icon-only actions', () {
    expect(iosSystemSymbol(CupertinoIcons.play_fill), 'play.fill');
    expect(iosSystemSymbol(CupertinoIcons.pause_fill), 'pause.fill');
    expect(iosSystemSymbol(CupertinoIcons.backward_end), 'backward.end');
    expect(iosSystemSymbol(CupertinoIcons.forward_end), 'forward.end');
    expect(iosSystemSymbol(CupertinoIcons.minus_circle), 'minus.circle');
    expect(iosSystemSymbol(const IconData(0xFFFF)), isNull);
  });

  testWidgets(
    'latest state reaches a native view that finishes creation after a rebuild',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final creation = Completer<void>();
      final states = <Map>[];
      MethodChannel? channel;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'];
          channel = MethodChannel('org.mewx.wenku8/glass_controls/$id');
          messenger.setMockMethodCallHandler(channel!, (message) async {
            if (message.method == 'state') states.add(message.arguments as Map);
            return null;
          });
          await creation.future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
      });
      Widget control(bool enabled) => CupertinoApp(
        home: IOSGlassControl(
          kind: 'button',
          configuration: {'label': '搜索', 'enabled': enabled},
          onAction: (_) {},
        ),
      );
      await tester.pumpWidget(control(true));
      await tester.pumpWidget(control(false));
      creation.complete();
      await tester.pump();
      await tester.pump();
      expect(states, isNotEmpty);
      expect(states.last['enabled'], false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native control dispatches an enabled action and ignores it after disabling',
    (tester) async {
      int? viewId;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          viewId = (call.arguments as Map)['id'] as int;
          messenger.setMockMethodCallHandler(
            MethodChannel('org.mewx.wenku8/glass_controls/$viewId'),
            (_) async => null,
          );
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (viewId != null) {
          messenger.setMockMethodCallHandler(
            MethodChannel('org.mewx.wenku8/glass_controls/$viewId'),
            null,
          );
        }
      });
      var calls = 0;
      Future<void> show(bool enabled) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: IOSGlassControl(
              kind: 'button',
              configuration: {'label': '搜索', 'enabled': enabled},
              onAction: (_) => calls++,
            ),
          ),
        );
        await tester.pump();
      }

      await show(true);
      expect(viewId, isNotNull);
      Future<void> action() async {
        await messenger.handlePlatformMessage(
          'org.mewx.wenku8/glass_controls/$viewId',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('action', {'index': 0}),
          ),
          (_) {},
        );
      }

      await action();
      expect(calls, 1);
      await show(false);
      await action();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
