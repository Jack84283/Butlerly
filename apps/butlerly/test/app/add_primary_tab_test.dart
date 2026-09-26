import 'dart:ui' show Tristate;

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  testWidgets(
    'primary navigation is exactly Home, Transactions, Add, Tools, More',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      final navigation = find.byKey(const ValueKey('primary-phone-navigation'));
      final content = find.descendant(
        of: navigation,
        matching: find.byKey(const ValueKey('primary-navigation-content')),
      );
      expect(
        find.descendant(of: content, matching: find.byType(InkWell)),
        findsNWidgets(5),
      );

      final destinations = <String, Finder>{
        'Home': find.bySemanticsLabel('Home'),
        'Transactions': find.bySemanticsLabel('Transactions'),
        'Add': find.bySemanticsLabel('Add transaction'),
        'Tools': find.bySemanticsLabel('Tools'),
        'More': find.bySemanticsLabel('More'),
      };
      for (final entry in destinations.entries) {
        expect(entry.value, findsOneWidget, reason: entry.key);
      }

      final centers = [
        for (final finder in destinations.values) tester.getCenter(finder),
      ];
      expect(
        centers,
        orderedEquals([...centers]..sort((a, b) => a.dx.compareTo(b.dx))),
      );
      expect(
        find.descendant(of: navigation, matching: find.text('Review')),
        findsNothing,
      );
      expect(
        find.descendant(of: navigation, matching: find.text('Search')),
        findsNothing,
      );
      expect(
        find.descendant(of: navigation, matching: find.text('Settings')),
        findsNothing,
      );
    },
  );

  testWidgets('Add is a selected primary destination and keeps the footer', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Add transaction manually'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(
      tester
              .getSemantics(find.bySemanticsLabel('Add transaction'))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue,
      isTrue,
    );
  });

  testWidgets('Tools and More remain primary destinations', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Tools'));
    await tester.pumpAndSettle();
    final navigation = find.byKey(const ValueKey('primary-phone-navigation'));
    expect(
      find.text('Useful ways to explore and understand your records.'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: navigation,
              matching: find.bySemanticsLabel('Tools'),
            ),
          )
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    final moreNavigation = find.byKey(
      const ValueKey('primary-phone-navigation'),
    );
    expect(find.text('More'), findsAtLeastNWidgets(1));
    expect(find.text('Master data'), findsNothing);
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: moreNavigation,
              matching: find.bySemanticsLabel('More'),
            ),
          )
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('Tools owns Review, Master Data, and Rules', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Master data'), findsOneWidget);
    expect(find.text('Rules'), findsOneWidget);

    await tester.tap(find.text('Master data'));
    await tester.pumpAndSettle();
    expect(find.text('Master data'), findsOneWidget);
    expect(find.bySemanticsLabel('Tools'), findsNothing);
    appRouter.go('/tools');
    await tester.pumpAndSettle();

    final toolsScrollable = find.byType(Scrollable).first;
    await tester.drag(toolsScrollable, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.text('Rules'), findsOneWidget);
    expect(find.bySemanticsLabel('Tools'), findsNothing);
  });

  testWidgets('Payment Sources remain owned by Add', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Payment sources'), findsNWidgets(2));
    await tester.tap(find.text('Payment sources').last);
    await tester.pumpAndSettle();
    expect(find.text('Payment sources'), findsOneWidget);
    expect(find.bySemanticsLabel('Add transaction'), findsNothing);
  });

  testWidgets('secondary Review and Search routes hide primary navigation', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    for (final route in const ['/review', '/search']) {
      appRouter.go(route);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('primary-phone-navigation')),
        findsNothing,
        reason: '$route is a secondary workflow.',
      );
    }
  });

  testWidgets('secondary routes do not render the primary footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    // Keep this router-level assertion independent from feature service fixtures.
    // Receipt capture has dedicated coverage with FinanceServices configured.
    for (final route in const [
      '/transactions/add',
      '/statements',
      '/notifications',
      '/assistant',
    ]) {
      appRouter.go(route);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Add transaction'),
        findsNothing,
        reason: '$route must stay outside the primary app shell.',
      );
    }
  });

  test('nested secondary pages temporarily hide primary navigation', () {
    final controller = PrimaryShellVisibilityController();
    final observer = PrimaryShellNavigatorObserver(
      branchIndex: 0,
      controller: controller,
    );
    final primaryRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '${primaryShellRouteNamePrefix}home'),
      builder: (_) => const SizedBox.shrink(),
    );
    final secondaryRoute = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    observer.didPush(primaryRoute, null);
    expect(controller.secondaryRouteVisibleFor(0), isFalse);

    observer.didPush(secondaryRoute, primaryRoute);
    expect(controller.secondaryRouteVisibleFor(0), isTrue);

    observer.didPop(secondaryRoute, primaryRoute);
    expect(controller.secondaryRouteVisibleFor(0), isFalse);
  });
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
