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
            body: Text(
              state.uri.toString(),
              key: const Key('search-uri'),
            ),
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

  testWidgets('Home header stays pinned with requested left and right content', (
    tester,
  ) async {
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
        (tester.getCenter(categoryAction).dy - tester.getCenter(categoryTitle).dy)
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

  testWidgets('Recent View all opens Search with the selected Home period', (
    tester,
  ) async {
    // Keep the action fully inside the viewport so this test isolates route
    // behavior instead of coupling it to scroll/pinned-header hit testing.
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    final recentAction = find.byKey(const Key('home-recent-view-all'));
    expect(recentAction, findsOneWidget);
    await tester.tap(recentAction);
    await tester.pumpAndSettle();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/search');
    expect(uri.queryParameters['from'], '2026-09-01');
    expect(uri.queryParameters['to'], isNotNull);
    expect(DateTime.parse(uri.queryParameters['to']!).year, 2026);
    expect(DateTime.parse(uri.queryParameters['to']!).month, 9);
    expect(find.byKey(const Key('search-uri')), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('Home remains overflow-free at 3x accessibility text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.view.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(find.text('Butlerly'), findsOneWidget);
    expect(find.byKey(const Key('home-month-selector')), findsOneWidget);
    expect(find.byKey(const Key('home-category-view-all')), findsOneWidget);
    expect(find.byKey(const Key('home-recent-view-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(GoRouter router) => MaterialApp.router(
  theme: AppTheme.light,
  routerConfig: router,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
);
