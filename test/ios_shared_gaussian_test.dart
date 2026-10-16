import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/ios_scroll_edge.dart';

void main() {
  if (!const bool.fromEnvironment('WENKU8_NATIVE_GLASS')) return;
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  final updates = <MethodCall>[];
  final channels = <MethodChannel>[];
  Completer<void>? pendingCreate;
  setUp(() {
    updates.clear();
    pendingCreate = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('org.mewx.wenku8/glass_presentation'),
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'];
        final channel = MethodChannel('org.mewx.wenku8/glass_controls/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          updates.add(call);
          if (call.method == 'snapshot') {
            return {'textureId': 101, 'width': 46.0, 'height': 46.0};
          }
          return true;
        });
        await pendingCreate?.future;
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('org.mewx.wenku8/glass_presentation'),
      null,
    );
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
  });
  Widget scene({
    double x = 0,
    double blur = 8,
    bool bottom = false,
    Widget child = const Text('foreground'),
  }) => MaterialApp(
    home: Center(
      child: Transform.translate(
        offset: Offset(x, 0),
        child: SizedBox(
          width: 300,
          height: 180,
          child: IOSScrollEdge(
            blur: blur,
            plateau: 60,
            fromBottom: bottom,
            child: child,
          ),
        ),
      ),
    ),
  );
  void nativeTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  nativeTest(
    'one native Gaussian spans the entire edge with no Flutter backdrop filter',
    (tester) async {
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.creationParams, {
        'kind': 'gaussianEdge',
        'sigma': 8.0,
        'plateau': 60.0,
        'fromBottom': false,
      });
      expect(tester.getSize(find.byType(UiKitView)), const Size(300, 180));
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
      expect(find.text('foreground'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  nativeTest(
    'configuration changed during native creation reaches the attached plane',
    (tester) async {
      final pending = Completer<void>();
      pendingCreate = pending;
      await tester.pumpWidget(scene());
      await tester.pumpWidget(scene(bottom: true));
      pending.complete();
      await tester.pumpAndSettle();
      expect(updates.map((call) => call.method), ['state']);
      expect(updates.single.arguments, {
        'sigma': 8.01,
        'plateau': 60.0,
        'fromBottom': true,
      });
    },
  );
  nativeTest(
    'a native handler disappearing after detach does not leak an async error',
    (tester) async {
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      final pendingUpdate = Completer<void>();
      messenger.setMockMethodCallHandler(channels.single, (call) async {
        await pendingUpdate.future;
        throw MissingPluginException('native plane detached');
      });
      await tester.pumpWidget(scene(bottom: true));
      await tester.pumpWidget(const SizedBox.shrink());
      pendingUpdate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  nativeTest(
    'horizontal route motion does not recreate or reconfigure the Gaussian',
    (tester) async {
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      final viewState = tester.state(find.byType(UiKitView));
      await tester.pumpWidget(scene(x: 20));
      await tester.pumpAndSettle();
      await tester.pumpWidget(scene(x: -20));
      await tester.pumpAndSettle();
      expect(updates, isEmpty);
      expect(tester.state(find.byType(UiKitView)), same(viewState));
      await tester.pumpWidget(scene(x: -20, bottom: true));
      await tester.pumpAndSettle();
      expect(updates.map((call) => call.method), ['state']);
      expect(updates.single.arguments, {
        'sigma': 8.01,
        'plateau': 60.0,
        'fromBottom': true,
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  nativeTest('the passive Gaussian never blocks its live Flutter foreground', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      scene(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => tapped++,
          child: const Text('foreground'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('foreground'));
    expect(tapped, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  nativeTest(
    'shared composition keeps real native control layers during motion without readback',
    (tester) async {
      const key = ValueKey('native-body-control');
      await tester.pumpWidget(
        MaterialApp(
          home: Atmosphere(
            child: SizedBox.expand(
              child: IOSScrollEdge(
                blur: 8,
                plateau: 60,
                fromBottom: false,
                child: Center(
                  child: GlassIconButton(
                    key: key,
                    icon: CupertinoIcons.book,
                    label: 'book',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byKey(key));
      final navigator = Navigator.of(context);
      final route = softRoute<void>(const SizedBox.expand());
      navigator.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      expect(updates.where((call) => call.method == 'snapshot'), isEmpty);
      expect(tester.layers.whereType<TextureLayer>(), isEmpty);
      expect(
        tester.layers.whereType<PlatformViewLayer>().length,
        greaterThanOrEqualTo(2),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      expect(updates.where((call) => call.method == 'snapshot'), isEmpty);
      expect(tester.layers.whereType<TextureLayer>(), isEmpty);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
