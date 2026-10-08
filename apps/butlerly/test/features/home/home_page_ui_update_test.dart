import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      expect(find.text('A CALMER WAY TO MONEY'), findsOneWidget);
      expect(find.text('Good afternoon'), findsOneWidget);
      expect(find.text('Sep 2026'), findsOneWidget);
      expect(
        find.text("Your financial data for September 2026."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-month-selector')), findsOneWidget);

      final headerContent = find.byKey(const ValueKey('home-header-content'));
      final monthSurface = find.descendant(
        of: find.byKey(const Key('home-month-selector')),
        matching: find.byType(Ink),
      );
      final monthDecoration =
          tester.widget<Ink>(monthSurface).decoration! as BoxDecoration;
      expect(monthDecoration.color, Colors.transparent);
      expect(monthDecoration.border, isNotNull);
      final monthButton = tester.widget<TextButton>(
        find.byKey(const Key('home-month-selector')),
      );
      expect(
        monthButton.style?.foregroundColor?.resolve({}),
        AppTheme.light.textButtonTheme.style?.foregroundColor?.resolve({}),
      );
      expect(
        tester.getTopRight(monthSurface).dx,
        closeTo(tester.getTopRight(headerContent).dx, 0.01),
      );
      final brand = find.text('Butlerly');
      final brandTagline = find.byKey(const ValueKey('home-brand-tagline'));
      final greeting = find.byKey(const ValueKey('home-greeting'));
      final intro = find.byKey(const ValueKey('home-intro'));
      expect(tester.widget<Text>(brand).style?.fontSize, 32);
      final taglineText = tester.widget<Text>(brandTagline);
      expect(taglineText.style?.fontSize, 14);
      expect(taglineText.maxLines, 1);
      expect(taglineText.softWrap, isFalse);
      expect(
        tester.getTopLeft(brandTagline).dy - tester.getBottomLeft(brand).dy,
        closeTo(ButlerlySpacing.micro, 0.01),
      );
      expect(
        tester.getTopLeft(monthSurface).dy,
        closeTo(tester.getTopLeft(brand).dy, 1.0),
      );
      expect(tester.widget<Text>(greeting).style?.fontSize, 24);
      expect(tester.widget<Text>(intro).style?.fontSize, 14);
      expect(
        tester.getTopLeft(intro).dy - tester.getBottomLeft(greeting).dy,
        closeTo(ButlerlySpacing.micro, 0.01),
      );

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

  testWidgets('Home header follows the readable card width on wide layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    final monthSurface = find.descendant(
      of: find.byKey(const Key('home-month-selector')),
      matching: find.byType(Ink),
    );
    final summaryCard = find.byKey(const ValueKey('home-summary-card'));
    expect(
      tester.getTopRight(monthSurface).dx,
      closeTo(tester.getTopRight(summaryCard).dx, 0.01),
    );
  });

  testWidgets(
    'Home lets an oversized narrow accessibility header scroll away',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();

      final scrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final header = scrollView.slivers
          .whereType<SliverPersistentHeader>()
          .single;
      expect(header.pinned, isFalse);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-summary-card')),
        400,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
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
      find.text('Tus datos financieros de septiembre de 2026.'),
      findsOneWidget,
    );
    expect(find.text("Your financial data for September 2026."), findsNothing);
  });

  testWidgets('Home keeps all dashboard cards when there is no activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    for (final key in const [
      'home-summary-card',
      'home-trend-card',
      'home-category-card',
      'home-attention-card',
      'home-recent-card',
      'home-insight-card',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byKey(const Key('home-category-view-all')), findsOneWidget);
    expect(find.byKey(const Key('home-recent-view-all')), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(4));
    expect(find.byKey(const Key('home-notification-action')), findsNothing);
  });

  testWidgets(
    'Monthly Summary keeps three inner cards horizontal on phone-sized layouts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-summary-card')),
        200,
      );
      await tester.pumpAndSettle();

      final metricKeys = const [
        ValueKey('home-summary-metric-spending'),
        ValueKey('home-summary-metric-income'),
        ValueKey('home-summary-metric-net-position'),
      ];
      final tops = [
        for (final key in metricKeys) tester.getTopLeft(find.byKey(key)).dy,
      ];
      for (final top in tops.skip(1)) {
        expect(top, closeTo(tops.first, 1.0));
      }
      expect(
        find.byKey(const ValueKey('home-summary-metric-savings')),
        findsNothing,
      );
      final innerCards = [
        for (final key in const [
          'home-summary-inner-spending',
          'home-summary-inner-income',
          'home-summary-inner-net-position',
        ])
          find.byKey(ValueKey(key)),
      ];
      for (final card in innerCards) {
        expect(card, findsOneWidget);
        expect(tester.getSize(card).height, closeTo(108, 0.01));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home intro stays within an Android phone header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(
      find.text('Your financial data for September 2026.'),
      findsOneWidget,
    );
    final intro = find.byKey(const ValueKey('home-intro'));
    final header = find.byKey(const ValueKey('home-header-content'));
    expect(
      tester.getBottomLeft(intro).dy,
      lessThanOrEqualTo(tester.getBottomLeft(header).dy + 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home card titles share the canonical top inset', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    for (final entry in const [
      (card: 'home-summary-card', title: 'Monthly summary'),
      (card: 'home-trend-card', title: 'Spending trend'),
      (card: 'home-category-card', title: 'Top categories'),
      (card: 'home-attention-card', title: 'Needs attention'),
      (card: 'home-recent-card', title: 'Recent transactions'),
      (card: 'home-insight-card', title: 'Insights'),
    ]) {
      final card = find.byKey(ValueKey(entry.card));
      final title = find.descendant(of: card, matching: find.text(entry.title));
      expect(card, findsOneWidget);
      expect(title, findsOneWidget);
      expect(
        tester.getTopLeft(title).dy - tester.getTopLeft(card).dy,
        closeTo(ButlerlySpacing.cardPadding, 1.0),
        reason: '${entry.title} should use the canonical card top inset',
      );
    }
  });

  testWidgets('Home card ellipsis actions keep their visible glyph aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    for (final entry in const [
      (
        card: 'home-category-card',
        title: 'Top categories',
        action: 'home-category-view-all',
      ),
      (
        card: 'home-attention-card',
        title: 'Needs attention',
        action: 'home-attention-view-all',
      ),
      (
        card: 'home-recent-card',
        title: 'Recent transactions',
        action: 'home-recent-view-all',
      ),
      (
        card: 'home-insight-card',
        title: 'Insights',
        action: 'home-insight-view-all',
      ),
    ]) {
      final card = find.byKey(ValueKey(entry.card));
      final title = find.descendant(of: card, matching: find.text(entry.title));
      final action = find.descendant(
        of: card,
        matching: find.byKey(ValueKey(entry.action)),
      );
      final glyph = find.descendant(
        of: action,
        matching: find.byIcon(Icons.more_horiz_rounded),
      );
      expect(title, findsOneWidget);
      expect(action, findsOneWidget);
      expect(glyph, findsOneWidget);
      expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      final titleParagraph = tester.renderObject<RenderParagraph>(title);
      final titleLine = titleParagraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: titleParagraph.text.toPlainText().length,
            ),
          )
          .first
          .toRect();
      expect(
        (tester.getCenter(glyph).dy -
                titleParagraph.localToGlobal(titleLine.center).dy)
            .abs(),
        lessThan(3),
      );
    }
  });

  testWidgets('Home Recent ellipsis keeps the selected month in Search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    final recentViewAll = find.byKey(const Key('home-recent-view-all'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(recentViewAll);
    await tester.pumpAndSettle();

    final uri = Uri.parse(
      tester.widget<Text>(find.byKey(const Key('search-uri'))).data!,
    );
    expect(uri.path, '/search');
    expect(uri.queryParameters['from'], '2026-09-01');
    expect(uri.queryParameters['to'], '2026-09-14');
    expect(uri.queryParameters['includeUndated'], isNull);
  });

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
    final chart = find.byKey(const ValueKey('home-spending-trend-chart'));
    final amount = find.text(r'$42.00');
    expect(chart, findsOneWidget);
    expect(tester.getSize(chart).height, closeTo(112, 0.1));
    if (amount.evaluate().isNotEmpty) {
      expect(tester.widget<Text>(amount).style?.fontSize, 24);
    }
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
    for (final month in [6, 8, 11]) {
      final barCenter = tester.getCenter(
        find.byKey(ValueKey('home-spending-trend-bar-2026-$month')),
      );
      final labelCenter = tester.getCenter(
        find.byKey(ValueKey('home-spending-trend-label-2026-$month')),
      );
      expect((barCenter.dx - labelCenter.dx).abs(), lessThan(1.0));
    }
  });

  testWidgets(
    'Home trend range selector changes only trend points and keeps Home month',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(router));
      await tester.pumpAndSettle();
      expect(find.byType(ButlerlyCompactSelector), findsNWidgets(2));
      final monthSelector = find.byKey(const Key('home-month-selector'));
      final trendSelector = find.byKey(const Key('home-trend-range-selector'));
      expect(tester.getSize(monthSelector).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(monthSelector).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(trendSelector).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(trendSelector).width, greaterThanOrEqualTo(44));
      expect(
        tester.getSize(monthSelector).height,
        closeTo(tester.getSize(trendSelector).height, 0.1),
      );
      final monthSurface = find.descendant(
        of: monthSelector,
        matching: find.byType(Ink),
      );
      final trendSurface = find.descendant(
        of: trendSelector,
        matching: find.byType(Ink),
      );
      expect(monthSurface, findsOneWidget);
      expect(trendSurface, findsOneWidget);
      expect(tester.getSize(monthSurface).height, lessThan(44));
      expect(tester.getSize(trendSurface).height, lessThan(44));
      expect(
        tester.getSize(trendSurface).height,
        lessThan(tester.getSize(monthSurface).height),
      );

      final headerTitle = find.descendant(
        of: find.byKey(const ValueKey('home-header-context')),
        matching: find.text('Butlerly'),
      );
      final trendTitle = find.descendant(
        of: find.byKey(const ValueKey('home-trend-card')),
        matching: find.text('Spending trend'),
      );
      expect(headerTitle, findsOneWidget);
      expect(trendTitle, findsOneWidget);
      await tester.ensureVisible(trendSelector);
      await tester.pumpAndSettle();
      final surfaceRect = tester.getRect(trendSurface);
      final selectorRect = tester.getRect(trendSelector);
      expect(surfaceRect.top, greaterThanOrEqualTo(selectorRect.top));
      expect(surfaceRect.bottom, lessThanOrEqualTo(selectorRect.bottom));
      await tester.tapAt(Offset(surfaceRect.center.dx, surfaceRect.top + 1));
      await tester.pumpAndSettle();

      expect(find.text('Last 3 months'), findsOneWidget);
      expect(find.text('Last 6 months'), findsWidgets);
      expect(find.text('Last 12 months'), findsOneWidget);
      await tester.tap(find.text('Last 3 months'));
      await tester.pumpAndSettle();

      expect(find.text('Sep 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-trend-range-selector')),
        findsOneWidget,
      );

      await tester.tap(trendSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 12 months'));
      await tester.pumpAndSettle();

      await tester.tap(trendSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 6 months').last);
      await tester.pumpAndSettle();
      expect(find.text('Sep 2026'), findsOneWidget);
    },
  );

  testWidgets('Home spending trend uses a readable four-step currency scale', (
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
            (month: DateTime(2026, 6), value: 3300, selected: false),
            (month: DateTime(2026, 7), value: 2400, selected: false),
            (month: DateTime(2026, 8), value: 1800, selected: true),
            (month: DateTime(2026, 9), value: 1200, selected: false),
            (month: DateTime(2026, 10), value: 600, selected: false),
            (month: DateTime(2026, 11), value: 300, selected: false),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4K'), findsOneWidget);
    expect(find.text('3K'), findsOneWidget);
    expect(find.text('2K'), findsOneWidget);
    expect(find.text('1K'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('Home spending trend uses the spending comparison', (
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
          body: homeSpendingTrendForTest(
            [
              (month: DateTime(2026, 6), value: 20, selected: false),
              (month: DateTime(2026, 7), value: 32, selected: false),
              (month: DateTime(2026, 8), value: 42, selected: true),
              (month: DateTime(2026, 9), value: 28, selected: false),
              (month: DateTime(2026, 10), value: 18, selected: false),
              (month: DateTime(2026, 11), value: 36, selected: false),
            ],
            comparison: AnalysisComparison(
              currentValue: DecimalValue.parse('12'),
              baselineValue: DecimalValue.parse('10'),
              absoluteChange: DecimalValue.parse('2'),
              percentageChange: DecimalValue.parse('20'),
              availability: AnalysisDataAvailability.sufficient,
            ),
            selectedMetric: _trendMetric(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('↑ 20% vs. last month'), findsOneWidget);
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
        find.text("Your financial data for September 2026."),
      );
      final month = tester.widget<Text>(find.text('Sep 2026'));
      for (final text in [brand, greeting, intro, month]) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }
      expect(find.byKey(const Key('home-month-selector')), findsOneWidget);
      final monthSelector = find.byKey(const Key('home-month-selector'));
      expect(tester.getSize(monthSelector).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(monthSelector).height, greaterThanOrEqualTo(44));
      final monthSurface = find.descendant(
        of: monthSelector,
        matching: find.byType(Ink),
      );
      expect(tester.getSize(monthSurface).height, greaterThanOrEqualTo(44));
      final headerContent = find.byKey(const ValueKey('home-header-content'));
      expect(
        tester.getTopRight(monthSurface).dx,
        closeTo(tester.getTopRight(headerContent).dx, 0.01),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-trend-card')),
        600,
      );
      await tester.pumpAndSettle();
      final trendSelector = find.byKey(
        const ValueKey('home-trend-range-selector'),
      );
      expect(trendSelector, findsOneWidget);
      expect(tester.getSize(trendSelector).height, greaterThanOrEqualTo(44));
      final trendSurface = find.descendant(
        of: trendSelector,
        matching: find.byType(Ink),
      );
      expect(trendSurface, findsOneWidget);
      expect(tester.getSize(trendSurface).height, greaterThanOrEqualTo(44));
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

AnalysisMetric _trendMetric() => AnalysisMetric(
  id: 'trend-result',
  rule: AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R098'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'analysis.rule.r010.name',
    descriptionKey: 'analysis.rule.r010.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(
      operation: RuleOperation.sum,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    surface: AnalysisSurface.trends,
    definitionHash: RuleDefinitionHash('c' * 64),
  ),
  context: AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-16',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  ),
  value: DecimalValue.parse('42'),
  currency: CurrencyCode('USD'),
  calculatedAt: DateTime.utc(2026, 9, 16),
);
