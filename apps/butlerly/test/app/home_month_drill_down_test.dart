import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    appRouter.go('/');
    HomePage.debugCurrentDate = DateTime(2026, 8, 13, 9);
  });

  tearDown(() => HomePage.debugCurrentDate = null);

  testWidgets('historical Home month keeps month semantics in Analysis', (
    tester,
  ) async {
    await _openJulyHome(tester);

    final actions = find.widgetWithText(TextButton, 'View all');
    final analysisButton = tester.widget<TextButton>(actions.first);
    analysisButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    final page = tester.widget<AnalysisPage>(find.byType(AnalysisPage));
    expect(page.initialMonth, DateTime(2026, 7, 1));
    expect(page.initialRange, isNull);
  });

  testWidgets('current Home month opens current-month Analysis semantics', (
    tester,
  ) async {
    await _openHome(tester);

    final actions = find.widgetWithText(TextButton, 'View all');
    final analysisButton = tester.widget<TextButton>(actions.first);
    analysisButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    final page = tester.widget<AnalysisPage>(find.byType(AnalysisPage));
    expect(page.initialMonth, isNull);
    expect(page.initialRange, isNull);
  });

  testWidgets('historical Home month is carried into Search', (
    tester,
  ) async {
    // A taller viewport keeps the recent-transactions action fully visible so
    // this regression exercises the production push/back stack directly.
    await _openJulyHome(tester, size: const Size(390, 1400));

    final searchAction = find.widgetWithText(TextButton, 'View all').last;
    expect(searchAction, findsOneWidget);
    await tester.tap(searchAction);
    await tester.pumpAndSettle();

    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/search');
    expect(uri.queryParameters['from'], '2026-07-01');
    expect(uri.queryParameters['to'], '2026-07-31');
    expect(appRouter.canPop(), isTrue);

    appRouter.pop();
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(HomePage), findsOneWidget);
  });
}

Future<void> _openHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}

Future<void> _openJulyHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  await _openHome(tester, size: size);
  await tester.tap(find.byKey(const Key('home-month-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('home-month-2026-7')));
  await tester.pumpAndSettle();

  expect(find.text('July 2026'), findsOneWidget);
}
