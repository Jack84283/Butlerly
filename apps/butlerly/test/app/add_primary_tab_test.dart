import 'dart:ui' show Tristate;

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  testWidgets('Add is a selected primary tab and keeps the footer visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add Transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Add transaction manually'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Add'), findsAtLeastNWidgets(1));
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
    expect(
      tester
              .getSemantics(find.bySemanticsLabel('Add Transaction'))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue,
      isTrue,
    );

    await tester.tap(find.text('Tools').last);
    await tester.pumpAndSettle();
    expect(find.text('Add transaction manually'), findsNothing);
    expect(
      tester
              .getSemantics(find.text('Tools').last)
              .flagsCollection
              .isSelected ==
          Tristate.isTrue,
      isTrue,
    );
  });

  testWidgets('direct /add route opens inside the primary shell', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    appRouter.go('/add');
    await tester.pumpAndSettle();

    expect(find.text('Add transaction manually'), findsOneWidget);
    expect(find.bySemanticsLabel('Add Transaction'), findsOneWidget);
    expect(
      tester
              .getSemantics(find.bySemanticsLabel('Add Transaction'))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue,
      isTrue,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('all Tools destinations stay inside the primary shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    for (final route in const ['/review', '/search', '/analysis', '/insights']) {
      appRouter.go(route);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.bySemanticsLabel('Add Transaction'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Tools'), findsAtLeastNWidgets(1));
      expect(find.text('More'), findsOneWidget);
      expect(
        tester
                .getSemantics(find.text('Tools').last)
                .flagsCollection
                .isSelected ==
            Tristate.isTrue,
        isTrue,
      );
    }
  });
}
