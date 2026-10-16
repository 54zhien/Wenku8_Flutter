import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/legacy_cover.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reading_history.dart';
import 'package:wenku8_flutter/reader_tools.dart';

import 'support/cover_fixture.dart';
import 'support/offline_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channels = <MethodChannel>[];
  final created = <Map>[];
  setUp(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        created.add(
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(args['params'] as Uint8List),
              )
              as Map,
        );
        final channel = MethodChannel(
          'org.mewx.wenku8/glass_controls/${args['id']}',
        );
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
    created.clear();
  });

  Future<void> ios(WidgetTester tester, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    final hitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      WidgetController.hitTestWarningShouldBeFatal = hitTestPolicy;
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('page slides before destination UIKit controls are created', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    softRoute<void>(
                      Scaffold(
                        body: Center(
                          child: GlassIconButton(
                            key: const ValueKey('destination-control'),
                            icon: CupertinoIcons.back,
                            label: 'destination',
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final control = find.byKey(const ValueKey('destination-control'));
      final route = ModalRoute.of(tester.element(control))!;
      expect(route.transitionDuration, NovelMotion.enter);
      expect(route.animation!.value, inExclusiveRange(0, 1));
      final early = tester.getCenter(control).dx;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getCenter(control).dx, lessThan(early));
      expect(
        created,
        isEmpty,
        reason: 'Platform-view creation must not consume the entrance frames.',
      );
      expect(
        find.byIcon(CupertinoIcons.back),
        findsOneWidget,
        reason: 'The original Flutter control stays visible during the slide.',
      );
      await tester.pumpAndSettle();
      if (nativeIOSGlassEnabled) {
        expect(created, hasLength(1));
        final native = tester.element(find.byType(UiKitView));
        Navigator.of(tester.element(control)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          identical(tester.element(find.byType(UiKitView)), native),
          isTrue,
        );
        expect(created, hasLength(1));
        await tester.pumpAndSettle();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('full iOS app paints the original cover flight and return', (
    tester,
  ) async {
    await ios(tester, () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      final book = coverFixtureBook(975001);
      final bytes = (await tester.runAsync(coverFixtureBytes))!;
      LegacyCover.seedLocalBytes(book.id, bytes);
      final repository = OfflineFixtureRepository(books: [book]);
      await tester.pumpWidget(NovelApp(state: state, repository: repository));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(HomeShell)),
        ),
      );
      await tester.pumpAndSettle();
      expect(state.effectiveReduceMotion, isFalse);
      final nativeBefore = created.length;
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('archive-shelf-open')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      await tester.pump();
      final route = ModalRoute.of(tester.element(find.byType(DetailPage)))!;
      expect(route.transitionDuration, NovelMotion.coverFlight);
      expect(route.reverseTransitionDuration, NovelMotion.coverReturn);
      final flight = find.byType(PaperCoverFlight);
      expect(flight, findsOneWidget);
      final firstRect = tester.getRect(flight);
      await tester.pump(const Duration(milliseconds: 220));
      final bend = tester.renderObject<PaperCoverRender>(
        find.byType(PaperCoverBend),
      );
      expect(bend.progress, closeTo(.22, .005));
      expect(bend.config.image, isNotNull);
      expect(bend.debugMeshDraws, greaterThan(0));
      expect(bend.debugPlane.horizontal.dy, isNot(0));
      expect(tester.getRect(flight), isNot(firstRect));
      expect(
        created.length,
        nativeBefore,
        reason:
            'The real paper flight must not create destination UIKit controls.',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(bend.progress, closeTo(.62, .005));
      expect(tester.getRect(flight), isNot(firstRect));
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      final cover = find.descendant(
        of: find.byType(DetailPage),
        matching: find.byType(NovelCover),
      );
      expect(tester.getSize(cover), const Size(118, 166));
      expect(tester.binding.transientCallbackCount, 0);
      final admitted = created.length;
      if (nativeIOSGlassEnabled) expect(admitted, greaterThan(nativeBefore));
      Navigator.of(tester.element(cover)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(flight, findsOneWidget);
      final returning = tester.renderObject<PaperCoverRender>(
        find.byType(PaperCoverBend),
      );
      expect(returning.progress, inExclusiveRange(0, 1));
      expect(returning.debugMeshDraws, greaterThan(0));
      expect(created.length, admitted);
      await tester.pumpAndSettle();
      expect(find.byType(DetailPage), findsNothing);
      expect(flight, findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  });

  testWidgets(
    'full iOS settings detail moves on push and pop at original timing',
    (tester) async {
      await ios(tester, () async {
        SharedPreferences.setMockInitialValues({});
        final state = await LibraryState.load();
        final repository = OfflineFixtureRepository();
        await tester.pumpWidget(NovelApp(state: state, repository: repository));
        await tester.pumpAndSettle();
        if (nativeIOSGlassEnabled) {
          tester
              .widget<IOSGlassControl>(
                find.byWidgetPredicate(
                  (w) => w is IOSGlassControl && w.kind == 'tabbar',
                ),
              )
              .onAction({'index': 2});
        } else {
          final tab = find.byKey(const ValueKey('dock-tab-2'));
          final detector = find
              .ancestor(of: tab, matching: find.byType(GestureDetector))
              .first;
          final point = tester.getRect(tab).center;
          expect(
            tester.hitTestOnBinding(point).path.map((hit) => hit.target),
            contains(tester.renderObject(detector)),
            reason:
                'The dock owns one gesture detector, not per-tab listeners.',
          );
          await tester.tapAt(point);
        }
        await tester.pumpAndSettle();
        final count = created.length;
        await Scrollable.ensureVisible(
          tester.element(find.text('阅读历史')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('阅读历史'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final page = find.byType(ReadingHistoryPage);
        final route = ModalRoute.of(tester.element(page))!;
        expect(route.transitionDuration, const Duration(milliseconds: 420));
        expect(
          route.reverseTransitionDuration,
          const Duration(milliseconds: 320),
        );
        final early = tester.getTopLeft(page).dx;
        expect(early, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getTopLeft(page).dx, inExclusiveRange(0, early));
        expect(created.length, count);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(page).dx, closeTo(0, .001));
        final admitted = created.length;
        Navigator.of(tester.element(page)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getTopLeft(page).dx, greaterThan(0));
        expect(created.length, admitted);
        await tester.pumpAndSettle();
        expect(page, findsNothing);
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      });
    },
  );

  testWidgets(
    'an early pop never mounts abandoned destination native controls',
    (tester) async {
      await ios(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  softRoute<void>(
                    GlassIconButton(
                      key: const ValueKey('abort-control'),
                      icon: CupertinoIcons.back,
                      label: 'abort',
                      onPressed: () {},
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        Navigator.of(
          tester.element(find.byKey(const ValueKey('abort-control'))),
        ).pop();
        await tester.pumpAndSettle();
        expect(created, isEmpty);
        expect(find.byKey(const ValueKey('abort-control')), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('admission preserves text button and switch layout slots', (
    tester,
  ) async {
    await ios(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                softRoute<void>(
                  Scaffold(
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlassTextButton(
                          key: const ValueKey('slot-text'),
                          onPressed: () {},
                          child: const Text('排序方式'),
                        ),
                        adaptiveSwitch(
                          key: const ValueKey('slot-switch'),
                          value: false,
                          onChanged: (_) {},
                        ),
                        AdaptiveSegmentedControl<int>(
                          key: const ValueKey('slot-segment'),
                          children: const {0: Text('一'), 1: Text('二')},
                          groupValue: 0,
                          onValueChanged: (_) {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final text = tester.getSize(find.byKey(const ValueKey('slot-text')));
      final toggle = tester.getSize(find.byKey(const ValueKey('slot-switch')));
      final segment = tester.getSize(
        find.byKey(const ValueKey('slot-segment')),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('slot-text'))), text);
      expect(tester.getSize(find.byKey(const ValueKey('slot-switch'))), toggle);
      expect(
        tester.getSize(find.byKey(const ValueKey('slot-segment'))),
        segment,
      );
    });
  });

  testWidgets('native admission waits for an active page pointer to finish', (
    tester,
  ) async {
    await ios(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                softRoute<void>(
                  Scaffold(
                    body: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) {},
                      child: SizedBox.expand(
                        child: Center(
                          child: GlassIconButton(
                            icon: CupertinoIcons.back,
                            label: 'pointer',
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final pointer = await tester.startGesture(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        created,
        isEmpty,
        reason: 'Do not replace a Flutter control during an active gesture.',
      );
      await pointer.cancel();
      await tester.pumpAndSettle();
      expect(created.length, nativeIOSGlassEnabled ? 1 : 0);
    });
  });

  testWidgets('a slider drag across entrance commits before native admission', (
    tester,
  ) async {
    await ios(tester, () async {
      final interactions = <bool>[];
      final commits = <double>[];
      final previews = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                softRoute<void>(
                  Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 300,
                        child: ReaderValueSlider(
                          sliderKey: const ValueKey('drag-slider'),
                          label: '字号',
                          value: 50,
                          min: 0,
                          max: 100,
                          format: (value) => value.toStringAsFixed(0),
                          onCommitted: commits.add,
                          onPreview: previews.add,
                          onInteractionChanged: interactions.add,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final slider = find.byKey(const ValueKey('drag-slider'));
      final rect = tester.getRect(slider);
      final pointer = await tester.startGesture(rect.center);
      await pointer.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(interactions, [true]);
      expect(previews, isNotEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(created, isEmpty);
      expect(find.byType(CupertinoSlider), findsOneWidget);
      expect(commits, isEmpty);
      await pointer.up();
      await tester.pumpAndSettle();
      expect(interactions, [true, false]);
      expect(commits, hasLength(1));
      expect(commits.single, greaterThan(50));
      if (nativeIOSGlassEnabled) {
        final native = tester.widget<IOSGlassControl>(
          find.byWidgetPredicate(
            (w) => w is IOSGlassControl && w.kind == 'slider',
          ),
        );
        expect(native.configuration['value'], commits.single);
      }
    });
  });

  testWidgets(
    'reduced motion admits controls without adding an entrance delay',
    (tester) async {
      await ios(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  softRoute<void>(
                    GlassIconButton(
                      key: const ValueKey('reduced-control'),
                      icon: CupertinoIcons.back,
                      label: 'reduced',
                      onPressed: () {},
                    ),
                    reduceMotion: true,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final control = find.byKey(const ValueKey('reduced-control'));
        final route = ModalRoute.of(tester.element(control))!;
        expect(route.transitionDuration, Duration.zero);
        expect(route.animation!.value, 1);
        expect(created.length, nativeIOSGlassEnabled ? 1 : 0);
        expect(tester.binding.transientCallbackCount, 0);
      });
    },
  );

  testWidgets('cancelling an iOS back swipe retains admitted native controls', (
    tester,
  ) async {
    await ios(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                softRoute<void>(
                  Scaffold(
                    body: GlassIconButton(
                      key: const ValueKey('gesture-control'),
                      icon: CupertinoIcons.back,
                      label: 'gesture',
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final count = created.length;
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('gesture-control'))),
      )!;
      final native = nativeIOSGlassEnabled
          ? tester.element(find.byType(UiKitView))
          : null;
      final gesture = await tester.startGesture(const Offset(1, 400));
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 40));
      expect(route.popGestureInProgress, isTrue);
      expect(route.animation!.value, inExclusiveRange(0, 1));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
      expect(route.isCurrent, isTrue);
      expect(created.length, count);
      if (native != null) {
        expect(
          identical(tester.element(find.byType(UiKitView)), native),
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    });
  });
}
