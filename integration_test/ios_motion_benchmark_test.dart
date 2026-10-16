import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/legacy_cover.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/native_effects.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/reading_history.dart';
import '../test/support/cover_fixture.dart';
import '../test/support/offline_fixture.dart';
import 'support/native_host.dart';

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let animation tickers request every vsync between test actions. The live
  // binding's default policy otherwise suppresses frames between explicit pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  await awaitNativeTestHost(binding);
  testWidgets('record the same real book search and settings transitions', (
    tester,
  ) async {
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
    });
    SharedPreferences.setMockInitialValues({});
    final state = await LibraryState.load();
    await NativeEffects.prepare();
    final bytes = await tester.runAsync(coverFixtureBytes);
    final books = [
      for (var id = 970000; id < 970005; id++)
        Novel(
          id: id,
          title: '固定档案 $id',
          author: '性能样本',
          genre: '固定样本',
          summary: '相同内容与封面用于比较实际页面转场。',
          coverUrl: 'fixture://cover/$id',
          colors: const [Colors.black, Colors.white],
          chapters: offlineFixtureBook(id).chapters,
        ),
    ];
    for (final book in books) {
      LegacyCover.seedLocalBytes(book.id, bytes!);
    }
    final repository = OfflineFixtureRepository(books: books);
    await tester.pumpWidget(NovelApp(state: state, repository: repository));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(bytes!),
        tester.element(find.byType(HomeShell)),
      ),
    );
    await tester.pumpAndSettle();
    final hz = tester.view.display.refreshRate;
    final budget = 1000000 / hz;
    final reports = <String, Object?>{};
    Map<String, Object?> reportSnapshot() => {
      'label': const String.fromEnvironment('BENCHMARK_LABEL'),
      'mode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'os': Platform.operatingSystem,
      'physical_size': [
        tester.view.physicalSize.width,
        tester.view.physicalSize.height,
      ],
      'scope':
          'controlled fixture through actual app widgets; engine build/raster timing, not presented FPS; iOS simulator is debug-only',
      'scenes': reports,
    };
    final file = File(
      '${Directory.systemTemp.path}/wenku-motion-benchmark.json',
    );
    Future<void> record(String name, Future<void> Function() action) async {
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> values) => frames.addAll(values);
      final start = DateTime.now().microsecondsSinceEpoch;
      const diagnostics = MethodChannel('org.mewx.wenku8/glass_presentation');
      var nativeAvailable = true;
      try {
        await diagnostics.invokeMethod<void>('probeStart');
      } on MissingPluginException {
        nativeAvailable = false;
      }
      binding.addTimingsCallback(collect);
      await action();
      final end = DateTime.now().microsecondsSinceEpoch;
      final nativeCounts = nativeAvailable
          ? await diagnostics.invokeMapMethod<String, dynamic>('probeEnd')
          : null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)),
      );
      binding.removeTimingsCallback(collect);
      final included = frames.where((frame) {
        final wall = frame.timestampInMicroseconds(
          ui.FramePhase.rasterFinishWallTime,
        );
        return wall >= start && wall <= end;
      }).toList();
      expect(
        included.length,
        greaterThan(30),
        reason: 'Missing actual engine FrameTiming records for $name',
      );
      int percentile(Iterable<int> values, double quantile) {
        final sorted = values.toList()..sort();
        return sorted[((sorted.length - 1) * quantile).round()];
      }

      final late = included
          .where(
            (frame) =>
                frame.buildDuration.inMicroseconds > budget ||
                frame.rasterDuration.inMicroseconds > budget,
          )
          .length;
      reports[name] = {
        'native_counts_available': nativeAvailable,
        'native_work_counts': nativeCounts,
        'samples': included.length,
        'refresh_hz': hz,
        'budget_us': budget,
        'build_p95_us': percentile(
          included.map((frame) => frame.buildDuration.inMicroseconds),
          .95,
        ),
        'raster_p95_us': percentile(
          included.map((frame) => frame.rasterDuration.inMicroseconds),
          .95,
        ),
        'over_budget_ratio': late / included.length,
        'frames': [
          for (final frame in included)
            {
              'build_us': frame.buildDuration.inMicroseconds,
              'raster_us': frame.rasterDuration.inMicroseconds,
              'total_span_us': frame.totalSpan.inMicroseconds,
            },
        ],
      };
      // Preserve completed scenes even when a later assertion fails. The
      // native result channel and exact three-scene gate still fail the run.
      await file.writeAsString(jsonEncode(reportSnapshot()), flush: true);
    }

    await record('book_open_and_return_warm', () async {
      for (var repeat = 0; repeat < 5; repeat++) {
        expect(find.byType(DetailPage), findsNothing);
        final open = find.byKey(const ValueKey('archive-shelf-open'));
        await tester.ensureVisible(open);
        // The wrapper's RenderTransform does not appear in its child's hit-test
        // path. Target the actual InkWell, retaining real pointer dispatch.
        await tester.tap(
          find.descendant(of: open, matching: find.byType(InkWell)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DetailPage), findsOneWidget);
        expect(
          tester.widget<DetailPage>(find.byType(DetailPage)).novel.id,
          books.first.id,
        );
        Navigator.of(tester.element(find.byType(DetailPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(DetailPage), findsNothing);
      }
    });
    await record('search_open_and_close', () async {
      for (var repeat = 0; repeat < 5; repeat++) {
        final search = tester.widget<GlassIconButton>(
          find
              .byWidgetPredicate(
                (widget) => widget is GlassIconButton && widget.label == '搜索',
              )
              .first,
        );
        search.onPressed!();
        await tester.pumpAndSettle();
        expect(find.byType(InlineSearchResults), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('inline-search-close')));
        await tester.pumpAndSettle();
        expect(find.byType(InlineSearchResults), findsNothing);
      }
    });
    if (nativeIOSGlassEnabled) {
      tester
          .widget<IOSGlassControl>(
            find.byWidgetPredicate(
              (widget) => widget is IOSGlassControl && widget.kind == 'tabbar',
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
      );
      await tester.tapAt(point);
    }
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('阅读历史')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await record('settings_history_open_and_return_warm', () async {
      for (var repeat = 0; repeat < 5; repeat++) {
        expect(find.byType(ReadingHistoryPage), findsNothing);
        await tester.tap(find.text('阅读历史'));
        await tester.pump();
        final page = find.byType(ReadingHistoryPage);
        expect(page, findsOneWidget);
        final route = ModalRoute.of(tester.element(page))!;
        expect(route.transitionDuration, const Duration(milliseconds: 420));
        expect(
          route.reverseTransitionDuration,
          const Duration(milliseconds: 320),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(page).dx, closeTo(0, .001));
        Navigator.of(tester.element(page)).pop();
        await tester.pumpAndSettle();
        await route.completed;
        expect(page, findsNothing);
        expect(find.byType(SettingsPage), findsOneWidget);
      }
    });
    final report = reportSnapshot();
    await file.writeAsString(jsonEncode(report), flush: true);
    // flutter test uninstalls the integration app on exit. Export through the
    // VM-service stdout stream before its sandbox is removed.
    // ignore: avoid_print
    print('WENKU_MOTION_JSON=${jsonEncode(report)}');
    // ignore: avoid_print
    print('WENKU_MOTION_REPORT=${file.path}');
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
