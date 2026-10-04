import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late GoRouter router;

  setUp(() {
    HomePage.debugCurrentDate = DateTime(2026, 9, 14, 13);
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HomePage()),
        ),
        GoRoute(
          path: '/search',
          builder: (_, state) => Scaffold(
            body: Text(state.uri.toString(), key: const Key('search-uri')),
          ),
        ),
        GoRoute(
          path: '/analysis',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Scaffold(
            body: SizedBox.shrink(key: ValueKey('notifications-route')),
          ),
        ),
        GoRoute(
          path: '/add',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/review',
          builder: (_, state) => Scaffold(
            body: Text(state.uri.toString(), key: const Key('review-uri')),
          ),
        ),
        GoRoute(
          path: '/insights',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
      ],
    );
  });

  tearDown(() {
    HomePage.debugCurrentDate = null;
    router.dispose();
  });

  testWidgets(
    'Home header stays pinned with requested left and right content',
    (tester) async {
      tester.view.physicalSize = const Size(390, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      expect(find.text('Butlerly'), findsOneWidget);
      expect(find.text('Good afternoon'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        find.text("Here's your financial overview for September 2026."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-notification-action')), findsOneWidget);

      final initialHeaderTop = tester.getTopLeft(find.text('Butlerly')).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Butlerly')).dy,
        closeTo(initialHeaderTop, 0.1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home period introduction is localized outside English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router, locale: const Locale('es')));
    await tester.pumpAndSettle();

    expect(
      find.text('Aquí tienes tu resumen financiero de septiembre de 2026.'),
      findsOneWidget,
    );
    expect(
      find.text("Here's your financial overview for September 2026."),
      findsNothing,
    );
  });

  testWidgets('Home uses Cupertino symbols for native iOS controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.bell), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Home avoids empty dashboard cards when there is no activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-empty-transactions-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-category-view-all')), findsOneWidget);
    expect(find.byKey(const Key('home-recent-view-all')), findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets(
    'Home keeps notification navigation available from its empty state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-notification-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notifications-route')), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notifications-route')), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    },
  );

  testWidgets(
    'Home empty-state Recent View All keeps the selected month in Search',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-recent-view-all')));
      await tester.pumpAndSettle();

      final uri = Uri.parse(
        tester.widget<Text>(find.byKey(const Key('search-uri'))).data!,
      );
      expect(uri.path, '/search');
      expect(uri.queryParameters['from'], '2026-09-01');
      expect(uri.queryParameters['to'], '2026-09-14');
      expect(uri.queryParameters['includeUndated'], isNull);
    },
  );

  testWidgets('Home spending trend grid uses the bar baseline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: homeSpendingTrendForTest([
            (month: DateTime(2026, 6), value: 20, selected: false),
            (month: DateTime(2026, 7), value: 32, selected: false),
            (month: DateTime(2026, 8), value: 42, selected: true),
            (month: DateTime(2026, 9), value: 28, selected: false),
            (month: DateTime(2026, 10), value: 18, selected: false),
            (month: DateTime(2026, 11), value: 36, selected: false),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final plot = find.byKey(const ValueKey('home-spending-trend-plot'));
    final baseline = find.byKey(
      const ValueKey('home-spending-trend-grid-line-4'),
    );
    final selectedBar = find.byKey(
      const ValueKey('home-spending-trend-bar-2026-8'),
    );
    expect(plot, findsOneWidget);
    expect(baseline, findsOneWidget);
    expect(selectedBar, findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-spending-trend-axis-label-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-spending-trend-axis-label-4')),
      findsOneWidget,
    );
    for (final month in [6, 7, 8, 9, 10, 11]) {
      expect(
        find.byKey(ValueKey('home-spending-trend-bar-2026-$month')),
        findsOneWidget,
      );
    }
    expect(
      tester.getBottomLeft(baseline).dy,
      closeTo(tester.getBottomLeft(plot).dy, 0.01),
    );
    expect(
      tester.getBottomLeft(selectedBar).dy,
      closeTo(tester.getBottomLeft(plot).dy, 0.01),
    );
  });

  testWidgets('Home distinguishes an unavailable trend from empty history', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: homeSpendingTrendForTest(const [], unavailable: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Local calculations could not be completed. No records were changed.',
      ),
      findsOneWidget,
    );
    expect(find.text('More activity is needed to show a trend.'), findsNothing);
  });

  testWidgets(
    'Home keeps essential header text readable at 3x accessibility scale',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      final brand = tester.widget<Text>(find.text('Butlerly'));
      final greeting = tester.widget<Text>(find.text('Good afternoon'));
      final intro = tester.widget<Text>(
        find.text("Here's your financial overview for September 2026."),
      );
      final month = tester.widget<Text>(find.text('September 2026'));
      for (final text in [brand, greeting, intro, month]) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }
      expect(find.byKey(const Key('home-month-selector')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _testApp(GoRouter router, {Locale? locale}) => MaterialApp.router(
  theme: AppTheme.light,
  locale: locale,
  routerConfig: router,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
);
