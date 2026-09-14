import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
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

    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/analysis');
    expect(uri.queryParameters['month'], '2026-07');
    expect(uri.queryParameters.containsKey('from'), isFalse);
    expect(uri.queryParameters.containsKey('to'), isFalse);
  });

  testWidgets('current Home month opens current-month Analysis semantics', (
    tester,
  ) async {
    await _openHome(tester);

    final actions = find.widgetWithText(TextButton, 'View all');
    final analysisButton = tester.widget<TextButton>(actions.first);
    analysisButton.onPressed!();
    await tester.pumpAndSettle();

    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/analysis');
    expect(uri.queryParameters, isEmpty);
  });

  testWidgets('historical Home month is carried into Transactions', (
    tester,
  ) async {
    await _openJulyHome(tester);

    final actions = find.widgetWithText(TextButton, 'View all');
    final transactionsButton = tester.widget<TextButton>(actions.last);
    transactionsButton.onPressed!();
    await tester.pumpAndSettle();

    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/transactions');
    expect(uri.queryParameters['from'], '2026-07-01');
    expect(uri.queryParameters['to'], '2026-07-31');
  });
}

Future<void> _openHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}

Future<void> _openJulyHome(WidgetTester tester) async {
  await _openHome(tester);
  await tester.tap(find.byKey(const Key('home-month-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('home-month-2026-7')));
  await tester.pumpAndSettle();

  expect(find.text('July 2026'), findsOneWidget);
}
