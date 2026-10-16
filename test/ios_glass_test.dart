import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/glass_dock.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/native_effects.dart';

void main() {
  testWidgets('transparent header keeps status icons legible in each theme', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.viewPadding = const FakeViewPadding(top: 72);
    tester.view.padding = const FakeViewPadding(top: 72);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: novelSystemUiStyle(brightness),
            child: const Align(
              alignment: Alignment.topCenter,
              child: FrostedHeader(child: Text('archive')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(SystemChrome.latestStyle!.statusBarBrightness, brightness);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('dock uses only its active renderer animation lifecycle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channels = <MethodChannel>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'];
        final channel = MethodChannel('org.mewx.wenku8/glass_controls/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    Widget dock(int selected) => CupertinoApp(
      home: Center(
        child: GlassDock(selectedIndex: selected, onSelected: (_) {}),
      ),
    );
    await tester.pumpWidget(dock(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(dock(1));
    await tester.pump();
    await tester.pumpWidget(dock(2));
    await tester.pump();
    expect(
      tester.binding.transientCallbackCount,
      nativeIOSGlassEnabled ? isZero : greaterThan(0),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('system menus receive the app appearance and typed selection', (
    tester,
  ) async {
    const channel = MethodChannel('org.mewx.wenku8/glass_presentation');
    Map? arguments;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      arguments = call.arguments as Map;
      return 1;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    for (final brightness in Brightness.values) {
      final anchor = GlobalKey();
      await tester.pumpWidget(
        CupertinoApp(
          theme: CupertinoThemeData(brightness: brightness),
          home: Center(child: SizedBox(key: anchor, width: 80, height: 44)),
        ),
      );
      final selected = await showIOSMenu(anchor.currentContext!, const [
        IOSMenuOption(3, 'first', selected: true),
        IOSMenuOption(7, 'second'),
      ]);
      expect(selected, 7);
      expect(arguments!['dark'], brightness == Brightness.dark);
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'unchanged controls do not resend native state during parent animation',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var messages = 0;
      MethodChannel? channel;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          channel = MethodChannel(
            'org.mewx.wenku8/glass_controls/${(call.arguments as Map)['id']}',
          );
          messenger.setMockMethodCallHandler(channel!, (call) async {
            if (call.method == 'state') messages++;
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
      });
      Future<void> rebuild(String label) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: IOSGlassControl(
              kind: 'dock',
              configuration: {
                'selectedIndex': 0,
                'items': [
                  {'label': label, 'enabled': true},
                ],
              },
              onAction: (_) {},
            ),
          ),
        );
        await tester.pump();
      }

      await rebuild('发现');
      final initial = messages;
      for (var frame = 0; frame < 20; frame++) {
        await rebuild('发现');
      }
      expect(
        messages,
        initial,
        reason:
            'A stable native control must not allocate new native effects every animation tick.',
      );
      await rebuild('书架');
      expect(messages, initial + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('system menu selection and cancellation preserve typed results', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.mewx.wenku8/glass_presentation');
    int? response = 1;
    Map? request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = call.arguments as Map;
      return response;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    late BuildContext anchor;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            anchor = context;
            return const SizedBox(width: 46, height: 46);
          },
        ),
      ),
    );
    const options = [
      IOSMenuOption('keep', '保留'),
      IOSMenuOption('remove', '移除', destructive: true),
    ];
    expect(await showIOSMenu(anchor, options), 'remove');
    expect((request!['items'] as List)[1]['destructive'], true);
    expect((request!['anchor'] as Map)['width'], greaterThan(0));
    response = null;
    expect(await showIOSMenu(anchor, options), isNull);
    response = 99;
    expect(await showIOSMenu(anchor, options), isNull);
  });

  testWidgets('iOS scroll edge cannot filter native control foregrounds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      const MaterialApp(home: SizedBox(height: 120, child: ProgressiveBlur())),
    );
    expect(
      find.byType(NativeBackdrop),
      nativeIOSGlassEnabled ? findsNothing : findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      const MaterialApp(home: SizedBox(height: 120, child: ProgressiveBlur())),
    );
    expect(find.byType(NativeBackdrop), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

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
