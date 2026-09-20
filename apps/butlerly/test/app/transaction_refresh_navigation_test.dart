import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('transactions route has no refresh wrapper above the page', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    appRouter.go('/transactions');
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets(
    'search iOS refresh control is a body sliver below its pinned header',
    (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
      appRouter.go('/search?from=2026-09-01&to=2026-09-30');
      await tester.pumpAndSettle();

      final refreshFinder = find.byKey(
        const ValueKey('search-pull-to-refresh'),
      );
      expect(refreshFinder, findsOneWidget);
      expect(
        tester.widget(refreshFinder),
        isA<CupertinoSliverRefreshControl>(),
      );

      final scrollView = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(ButlerlyPage),
          matching: find.byType(CustomScrollView),
        ),
      );
      final headerIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is SliverAppBar,
      );
      final refreshIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is CupertinoSliverRefreshControl,
      );
      expect(headerIndex, isNonNegative);
      expect(refreshIndex, greaterThan(headerIndex));
      expect(find.byType(RefreshIndicator), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('primary shell observer invokes its pop callback', (
    tester,
  ) async {
    final controller = PrimaryShellVisibilityController();
    var popCount = 0;
    final observer = PrimaryShellNavigatorObserver(
      branchIndex: 2,
      controller: controller,
      onPop: () => popCount++,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (detailContext) => Scaffold(
                    body: FilledButton(
                      onPressed: () => Navigator.of(detailContext).pop(),
                      child: const Text('Back'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(popCount, 1);
  });
}
