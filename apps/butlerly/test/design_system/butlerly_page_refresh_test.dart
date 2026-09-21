import 'dart:async';

import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('iOS pull to refresh stays below pinned ButlerlyPage headers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final refreshGate = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ButlerlyPage(
            title: 'Transactions',
            pinnedHeader: const Text('Filters'),
            onRefresh: () => refreshGate.future,
            refreshKey: const ValueKey('page-refresh'),
            children: const [SizedBox(height: 1200, child: Text('Body'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(CustomScrollView);
    final scrollView = tester.widget<CustomScrollView>(scrollFinder);
    final appBarIndex = scrollView.slivers.indexWhere(
      (sliver) => sliver is SliverAppBar,
    );
    final pinnedHeaderIndex = scrollView.slivers.indexWhere(
      (sliver) => sliver is SliverPersistentHeader,
    );
    final refreshIndex = scrollView.slivers.indexWhere(
      (sliver) => sliver is CupertinoSliverRefreshControl,
    );

    expect(appBarIndex, isNonNegative);
    final appBar = scrollView.slivers[appBarIndex] as SliverAppBar;
    expect(appBar.shape, isA<Border>());
    expect((appBar.shape! as Border).bottom.width, ButlerlySize.dividerWidth);
    expect(pinnedHeaderIndex, greaterThan(appBarIndex));
    expect(refreshIndex, greaterThan(pinnedHeaderIndex));
    expect(
      (scrollView.slivers[pinnedHeaderIndex] as SliverPersistentHeader).pinned,
      isTrue,
    );
    expect(scrollView.physics, isA<BouncingScrollPhysics>());
    expect(
      (scrollView.physics! as BouncingScrollPhysics).parent,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    expect(find.byType(RefreshIndicator), findsNothing);

    final titleTopBefore = tester.getTopLeft(find.text('Transactions')).dy;
    final headerTopBefore = tester.getTopLeft(find.text('Filters')).dy;

    await tester.drag(scrollFinder, const Offset(0, 320));
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Transactions')).dy,
      closeTo(titleTopBefore, 0.01),
    );
    expect(
      tester.getTopLeft(find.text('Filters')).dy,
      closeTo(headerTopBefore, 0.01),
    );

    final activity = find.byType(CupertinoActivityIndicator);
    expect(activity, findsOneWidget);
    expect(
      tester.getTopLeft(activity).dy,
      greaterThanOrEqualTo(kToolbarHeight + ButlerlySize.minimumTarget),
    );

    refreshGate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('custom pinned header extent offsets Material refresh', (
    tester,
  ) async {
    const pinnedExtent = 92.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ButlerlyPage(
            title: 'Analysis',
            pinnedHeader: const Text('Period controls'),
            pinnedHeaderExtent: pinnedExtent,
            onRefresh: () async {},
            refreshKey: const ValueKey('analysis-refresh'),
            children: const [SizedBox(height: 800)],
          ),
        ),
      ),
    );

    final indicator = tester.widget<RefreshIndicator>(
      find.byKey(const ValueKey('analysis-refresh')),
    );
    final headerExtent = kToolbarHeight + pinnedExtent;
    expect(indicator.edgeOffset, headerExtent);
    expect(indicator.displacement, headerExtent + 40);
  });

  testWidgets('Material refresh indicator is offset below page headers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ButlerlyPage(
            title: 'Search',
            pinnedHeader: const Text('Filters'),
            onRefresh: () async {},
            refreshKey: const ValueKey('page-refresh'),
            children: const [SizedBox(height: 800)],
          ),
        ),
      ),
    );

    final indicator = tester.widget<RefreshIndicator>(
      find.byKey(const ValueKey('page-refresh')),
    );
    final headerExtent = kToolbarHeight + ButlerlySize.minimumTarget;
    expect(indicator.edgeOffset, headerExtent);
    expect(indicator.displacement, headerExtent + 40);
  });
}
