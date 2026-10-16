import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/native_effects.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_catalogue.dart';
import 'package:wenku8_flutter/legacy_cover.dart';
import 'package:wenku8_flutter/reading_history.dart';

import 'offline_fixture.dart';
import 'cover_fixture.dart';

void iosTest(String name, Future<void> Function(WidgetTester) body) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;
  final channels = <MethodChannel>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'shelfFilter': 'finished'});
    state = await LibraryState.load();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final channel = MethodChannel(
          'org.mewx.wenku8/glass_controls/${(call.arguments as Map)['id']}',
        );
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return null;
    });
  });
  tearDown(() {
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
  });
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: direction,
              child: Scaffold(body: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  iosTest(
    'small, Pro Max and landscape controls fit large text in both directions',
    (tester) async {
      for (final size in [
        const Size(320, 568),
        const Size(430, 932),
        const Size(844, 390),
      ]) {
        for (final direction in TextDirection.values) {
          for (final child in [
            ReaderCatalogue(novel: offlineFixtureBook(71), currentChapter: 1),
            SettingsPage(state: state),
          ]) {
            await tester.pumpWidget(const SizedBox.shrink());
            await mount(
              tester,
              child,
              size: size,
              scale: 2,
              direction: direction,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size / $direction / ${child.runtimeType}',
            );
          }
        }
      }
    },
  );

  iosTest('book and settings pushes retain live, progressing iOS animations', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(coverFixtureBytes))!;
    final books = [
      for (var id = 970000; id < 970005; id++) coverFixtureBook(id),
    ];
    for (final book in books) {
      LegacyCover.seedLocalBytes(book.id, bytes);
    }
    final repository = OfflineFixtureRepository(books: books);
    await mount(tester, HomeShell(state: state, repository: repository));
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(bytes),
        tester.element(find.byType(HomeShell)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('archive-shelf-open')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(PaperCoverFlight), findsOneWidget);
    final animation = tester
        .widget<PaperCoverFlight>(find.byType(PaperCoverFlight))
        .animation;
    final initial = animation.value;
    await tester.pump(const Duration(milliseconds: 100));
    expect(animation.value, greaterThan(initial));
    expect(animation.value, lessThan(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, SettingsPage(state: state, repository: repository));
    await tester.tap(find.text('阅读历史'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final route = ModalRoute.of(
      tester.element(find.byType(ReadingHistoryPage)),
    )!;
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    final first = route.animation!.value;
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.animation!.value, greaterThan(first));
    await tester.pumpAndSettle();
  });

  iosTest('search input never paints an opaque rectangle over its glass', (
    tester,
  ) async {
    await mount(
      tester,
      HomeShell(state: state, repository: OfflineFixtureRepository()),
    );
    final search = tester.widget<GlassIconButton>(
      find.byWidgetPredicate((w) => w is GlassIconButton && w.label == '搜索'),
    );
    search.onPressed!();
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('expanded-search-input')),
    );
    expect(input.decoration!.filled, false);
    expect(input.decoration!.fillColor, Colors.transparent);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  iosTest('discovery sort preserves archive icon and menu contents', (
    tester,
  ) async {
    await mount(
      tester,
      HomeShell(state: state, repository: OfflineFixtureRepository()),
    );
    final sort = find.byWidgetPredicate(
      (w) => w is GlassIconButton && w.label == '分类与排序',
    );
    expect(
      find.descendant(of: sort, matching: find.byType(IOSGlassControl)),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: sort, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlassMenuItem), findsWidgets);
    expect(find.text('最近更新'), findsWidgets);
    expect(
      tester.widget<GlassMenuSurface>(find.byType(GlassMenuSurface)).source,
      isNotNull,
    );
    Navigator.of(tester.element(find.byType(GlassMenuSurface))).pop();
    await tester.pumpAndSettle();
  });

  iosTest('header controls have separate 44 point targets and safe margins', (
    tester,
  ) async {
    await mount(
      tester,
      ReaderCatalogue(novel: offlineFixtureBook(71), currentChapter: 1),
    );
    final grid = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is GlassIconButton && w.label == '定位当前章节',
      ),
    );
    final search = tester.getRect(
      find.byWidgetPredicate((w) => w is GlassIconButton && w.label == '关闭目录'),
    );
    expect(search.left - grid.right, greaterThanOrEqualTo(8));
    expect(search.width, greaterThanOrEqualTo(44));
    expect(search.height, greaterThanOrEqualTo(44));
    expect(search.right, lessThanOrEqualTo(390 - 16));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  iosTest(
    'shelf removes filtering, preserves saved books and places sort before history',
    (tester) async {
      final books = [offlineFixtureBook(71), offlineFixtureBook(72)];
      await tester.runAsync(() async {
        for (final book in books) {
          await state.setShelfMembership(book.id, true, novel: book);
        }
      });
      await mount(
        tester,
        ShelfPage(
          books: books,
          state: state,
          repository: OfflineFixtureRepository(books: books),
        ),
      );
      expect(find.byKey(const ValueKey('shelf-filter')), findsNothing);
      expect(find.byKey(const ValueKey('shelf-book-71')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-book-72')), findsOneWidget);
      final sort = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is GlassIconButton && w.label == '书架排序',
        ),
      );
      final history = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is GlassIconButton && w.icon == CupertinoIcons.clock,
        ),
      );
      expect(sort.center.dy, closeTo(history.center.dy, .01));
      expect(history.left - sort.right, greaterThanOrEqualTo(8));
      final search = tester.widget<CupertinoSearchTextField>(
        find.byKey(const ValueKey('shelf-search')),
      );
      expect(search.borderRadius!.topLeft.x, ArchiveDesign.panelRadius);
      await tester.enterText(
        find.byKey(const ValueKey('shelf-search')),
        'no matching book',
      );
      await tester.pumpAndSettle();
      expect(find.text('试试其他关键词'), findsOneWidget);
      expect(find.textContaining('切回全部'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  iosTest(
    'appearance preserves archive text, dark selected row and source morph',
    (tester) async {
      await mount(tester, SettingsPage(state: state));
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
      final glass = tester.widget<LiquidGlass>(
        find.byWidgetPredicate(
          (w) => w is LiquidGlass && w.semanticLabel == '选择外观模式',
        ),
      );
      glass.onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GlassMenuSurface), findsOneWidget);
      final material = find.descendant(
        of: find.byType(GlassMenuSurface),
        matching: find.byType(IOSGlassControl),
      );
      final surfaceElement = tester.element(material);
      final radius =
          (tester.widget<IOSGlassControl>(material).configuration['radius']
                  as num)
              .toDouble();
      expect(radius, greaterThan(20));
      expect(radius, lessThan(28));
      final selected = find.byWidgetPredicate(
        (w) => w is GlassMenuItem && w.selected,
      );
      expect(selected, findsOneWidget);
      final boxes = tester.widgetList<Container>(
        find.descendant(of: selected, matching: find.byType(Container)),
      );
      final decoration = boxes
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(decoration.color!.a, greaterThan(.85));
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        greaterThanOrEqualTo(12),
      );
      final anchor = find.byType(GlassMenuAnchor).first;
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: anchor, matching: find.byType(Opacity)).first,
            )
            .opacity,
        0,
      );
      await tester.pumpAndSettle();
      expect(tester.element(material), same(surfaceElement));
      expect(
        tester.widget<IOSGlassControl>(material).configuration['radius'],
        28,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is GlassMenuItem && w.label == '浅色',
              ),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(state.theme, ThemeMode.light);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: anchor, matching: find.byType(Opacity)).first,
            )
            .opacity,
        1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  iosTest('iOS scroll edge remains an actual backdrop blur', (tester) async {
    await mount(
      tester,
      const Align(
        alignment: Alignment.topCenter,
        child: FrostedHeader(child: Text('header')),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(ProgressiveBlur),
        matching: find.byType(NativeBackdrop),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  iosTest('catalogue input and current chapter use rounded corners', (
    tester,
  ) async {
    await mount(
      tester,
      ReaderCatalogue(novel: offlineFixtureBook(71), currentChapter: 1),
    );
    final search = tester.widget<CupertinoSearchTextField>(
      find.byKey(const ValueKey('reader-chapter-search')),
    );
    expect(search.borderRadius!.topLeft.x, greaterThanOrEqualTo(12));
    final boxes = tester.widgetList<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('reader-chapter-1')),
        matching: find.byType(Container),
      ),
    );
    final decoration = boxes
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(
      (decoration.borderRadius! as BorderRadius).topLeft.x,
      greaterThanOrEqualTo(12),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
