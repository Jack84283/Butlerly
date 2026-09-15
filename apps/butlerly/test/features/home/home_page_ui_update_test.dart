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
        GoRoute(path: '/', builder: (_, _) => const HomePage()),
        GoRoute(
          path: '/search',
          builder: (_, state) => Text(
            state.uri.toString(),
            key: const Key('search-uri'),
          ),
        ),
        GoRoute(
          path: '/analysis',
          builder: (_, _) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const SizedBox.shrink(),
        ),
        GoRoute(path: '/add', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(path: '/review', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(path: '/insights', builder: (_, _) => const SizedBox.shrink()),
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

  testWidgets('Home View all actions stay right aligned in their header rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    final categoryAction = find.byKey(const Key('home-category-view-all'));
    final recentAction = find.byKey(const Key('home-recent-view-all'));
    expect(categoryAction, findsOneWidget);
    expect(recentAction, findsOneWidget);

    expect(tester.getCenter(categoryAction).dx, greaterThan(300));
    expect(tester.getCenter(recentAction).dx, greaterThan(300));
    expect(
      (tester.getCenter(categoryAction).dy -
              tester.getCenter(find.text('Spending by category')).dy)
          .abs(),
      lessThan(12),
    );
    expect(
      (tester.getCenter(recentAction).dy -
              tester.getCenter(find.text('Recent transactions')).dy)
          .abs(),
      lessThan(12),
    );
  });

  testWidgets('Recent View all opens Search with the selected Home period', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    final recentAction = find.byKey(const Key('home-recent-view-all'));
    await tester.ensureVisible(recentAction);
    await tester.tap(recentAction);
    await tester.pumpAndSettle();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/search');
    expect(uri.queryParameters['from'], '2026-09-01');
    expect(uri.queryParameters['to'], isNotNull);
    expect(DateTime.parse(uri.queryParameters['to']!).year, 2026);
    expect(DateTime.parse(uri.queryParameters['to']!).month, 9);
    expect(find.byKey(const Key('search-uri')), findsOneWidget);
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
