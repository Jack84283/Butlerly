import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
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
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/add',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/review',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
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
      expect(find.text('A CALMER WAY TO MONEY'), findsOneWidget);
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

  testWidgets('Home tagline is localized outside English', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router, locale: const Locale('es')));
    await tester.pumpAndSettle();

    expect(
      find.text('UNA FORMA MÁS TRANQUILA DE VIVIR EL DINERO'),
      findsOneWidget,
    );
    expect(find.text('A CALMER WAY TO MONEY'), findsNothing);
  });

  testWidgets(
    'Home section actions stay right aligned and category dividers stay removed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      final categoryAction = find.byKey(const Key('home-category-view-all'));
      final recentAction = find.byKey(const Key('home-recent-view-all'));
      final categoryTitle = find.text('Spending by category');
      final recentTitle = find.text('Recent transactions');
      expect(categoryAction, findsOneWidget);
      expect(recentAction, findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);

      final categoryRight = tester.getTopRight(categoryAction).dx;
      final recentRight = tester.getTopRight(recentAction).dx;
      expect(categoryRight, closeTo(recentRight, 0.1));
      expect(categoryRight, greaterThan(tester.getTopRight(categoryTitle).dx));
      expect(recentRight, greaterThan(tester.getTopRight(recentTitle).dx));
      expect(
        (tester.getCenter(categoryAction).dy -
                tester.getCenter(categoryTitle).dy)
            .abs(),
        lessThan(12),
      );
      expect(
        (tester.getCenter(recentAction).dy - tester.getCenter(recentTitle).dy)
            .abs(),
        lessThan(12),
      );
    },
  );

  testWidgets(
    'Recent View all scrolls into view and opens period-aware Search on phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      final recentAction = find.byKey(const Key('home-recent-view-all'));
      expect(recentAction, findsOneWidget);
      await tester.scrollUntilVisible(
        recentAction,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final headerBottom = tester
          .getBottomLeft(find.byKey(const Key('home-month-selector')))
          .dy;
      expect(tester.getTopLeft(recentAction).dy, greaterThan(headerBottom));
      await tester.tap(recentAction);
      await tester.pumpAndSettle();

      final searchUriText = tester.widget<Text>(
        find.byKey(const Key('search-uri')),
      );
      final uri = Uri.parse(searchUriText.data!);
      expect(uri.path, '/search');
      expect(uri.queryParameters['from'], '2026-09-01');
      expect(uri.queryParameters['to'], isNotNull);
      expect(DateTime.parse(uri.queryParameters['to']!).year, 2026);
      expect(DateTime.parse(uri.queryParameters['to']!).month, 9);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-uri')), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    },
  );

  testWidgets('Home spending trend grid uses the bar baseline', (
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
          body: homeSpendingTrendForTest([
            (
              month: DateTime(2026, 7),
              value: 20,
              selected: false,
            ),
            (
              month: DateTime(2026, 8),
              value: 42,
              selected: true,
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final plot = find.byKey(const ValueKey('home-spending-trend-plot'));
    final baseline = find.byKey(
      const ValueKey('home-spending-trend-grid-line-3'),
    );
    final selectedBar = find.byKey(
      const ValueKey('home-spending-trend-bar-2026-8'),
    );
    expect(plot, findsOneWidget);
    expect(baseline, findsOneWidget);
    expect(selectedBar, findsOneWidget);
    expect(
      tester.getBottomLeft(baseline).dy,
      closeTo(tester.getBottomLeft(plot).dy, 0.01),
    );
    expect(
      tester.getBottomLeft(selectedBar).dy,
      closeTo(tester.getBottomLeft(plot).dy, 0.01),
    );
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
      final tagline = tester.widget<Text>(find.text('A CALMER WAY TO MONEY'));
      final month = tester.widget<Text>(find.text('September 2026'));
      for (final text in [brand, greeting, tagline, month]) {
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
