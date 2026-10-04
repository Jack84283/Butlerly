import 'dart:async';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late _Transactions transactions;
  late _Preferences preferences;
  late _Merchants merchants;
  late _Rules rules;
  late FinanceServices finance;

  setUp(() async {
    await services.reset();
    HomePage.debugCurrentDate = DateTime(2026, 9, 16, 15);
    transactions = _Transactions();
    preferences = _Preferences();
    merchants = _Merchants();
    rules = _Rules([_expenseRule()]);
    finance = FinanceServices(
      transactions,
      _PaymentSources(),
      merchants,
      _Categories(),
      _Tags(),
      _Evidence(),
      preferences,
      analysisRules: rules,
    );
    services.registerSingleton<FinanceServices>(finance);
    final seeded = await finance.createTransaction(
      CreateTransactionCommand(
        id: 'home-refresh-initial',
        provenanceId: 'home-refresh-initial-provenance',
        timing: KnownTransactionTime(DateTime.utc(2026, 9, 15, 12)),
        transactionDate: '2026-09-15',
        money: Money(
          amount: DecimalValue.parse('10.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Initial Home spending',
      ),
    );
    expect(seeded, isA<ApplicationSuccess<TransactionDto>>());
  });

  testWidgets('Home starts master-data loading alongside its overview', (
    tester,
  ) async {
    final readGate = Completer<void>();
    final masterDataStarted = Completer<void>();
    transactions.readGate = readGate.future;
    merchants.onListAll = () {
      if (!masterDataStarted.isCompleted) masterDataStarted.complete();
    };

    await tester.pumpWidget(const _TestApp());
    await tester.pump();

    expect(masterDataStarted.isCompleted, isTrue);
    expect(transactions.queries, isNotEmpty);

    readGate.complete();
    transactions.readGate = null;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home uses the approved card order for useful activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    final cards = [
      find.byKey(const ValueKey('home-summary-card')),
      find.byKey(const ValueKey('home-trend-card')),
      find.byKey(const ValueKey('home-category-card')),
      find.byKey(const ValueKey('home-recent-card')),
    ];
    for (final card in cards) {
      expect(card, findsOneWidget);
    }
    final positions = cards.map((card) => tester.getTopLeft(card).dy).toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('Financial summary'), findsOneWidget);
    expect(find.text('Total spending'), findsOneWidget);
    expect(find.text('Spending trend'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Transaction count'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
    final summaryTitle = tester.widget<Text>(find.text('Financial summary'));
    expect(
      summaryTitle.style?.fontFamily,
      isNot(ButlerlyTypography.editorialFontFamily),
    );
    final summaryAmount = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-card')),
        matching: find.text('10.00 USD'),
      ),
    );
    expect(
      summaryAmount.style?.fontFamily,
      isNot(ButlerlyTypography.editorialFontFamily),
    );
    expect(summaryAmount.style?.fontFeatures, isNotEmpty);
    expect(find.byKey(const ValueKey('home-attention-card')), findsNothing);
    expect(find.byKey(const ValueKey('home-insight-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home keeps analysis-unavailable distinct from an empty period', (
    tester,
  ) async {
    await services.reset();
    HomePage.debugCurrentDate = DateTime(2026, 10, 16, 15);
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        transactions,
        _PaymentSources(),
        merchants,
        _Categories(),
        _Tags(),
        _Evidence(),
        preferences,
      ),
    );

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    expect(find.text('Analysis is unavailable'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-empty-transactions-card')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home places attention and insight cards around recent activity',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      rules.values.add(_homeInsightRule());
      final stored = transactions.values['home-refresh-initial']!;
      transactions.values['home-refresh-initial'] = stored.addReviewIssue(
        ReviewIssue(
          id: ReviewIssueId('home-review-issue'),
          transactionId: stored.id,
          reason: ReviewIssueReason.incomplete,
          createdAt: stored.updatedAt,
        ),
        stored.updatedAt.add(const Duration(seconds: 1)),
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: HomePage()),
          ),
          GoRoute(
            path: '/review',
            builder: (_, state) => Scaffold(
              body: Text(state.uri.toString(), key: const Key('review-uri')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_RouterTestApp(router: router));
      await tester.pumpAndSettle();

      final cards = [
        find.byKey(const ValueKey('home-summary-card')),
        find.byKey(const ValueKey('home-trend-card')),
        find.byKey(const ValueKey('home-category-card')),
        find.byKey(const ValueKey('home-attention-card')),
        find.byKey(const ValueKey('home-recent-card')),
        find.byKey(const ValueKey('home-insight-card')),
      ];
      for (final card in cards) {
        expect(card, findsOneWidget);
      }
      final positions = cards.map((card) => tester.getTopLeft(card).dy);
      expect(positions, orderedEquals([...positions]..sort()));
      expect(find.textContaining('Sep 1, 2026 – Sep 16, 2026'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('home-attention-card')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-attention-card')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('review-uri'))).data,
        '/review?view=needsReview&from=2026-09-01&to=2026-09-16&timeZoneId=UTC',
      );
    },
  );

  testWidgets('Home cards remain readable at large text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    // At 3x text scale the pinned header legitimately consumes more vertical
    // space. Scroll the sliver so its lazily-built cards enter the viewport.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-category-card')), findsOneWidget);
    final metricKeys = [
      const ValueKey('home-summary-metric-spending'),
      const ValueKey('home-summary-metric-income'),
      const ValueKey('home-summary-metric-net'),
      const ValueKey('home-summary-metric-count'),
    ];
    final metricPositions = [
      for (final key in metricKeys) tester.getTopLeft(find.byKey(key)),
    ];
    for (var index = 1; index < metricPositions.length; index++) {
      expect(
        metricPositions[index].dy,
        greaterThan(metricPositions[index - 1].dy),
      );
    }
    for (final label in [
      'Total spending',
      'Income',
      'Net cash flow',
      'Transaction count',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-card')),
        matching: find.text('10.00 USD'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Summary keeps its compact two-column layout normally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    final spending = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-spending')),
    );
    final income = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-income')),
    );
    final net = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-net')),
    );
    final count = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-count')),
    );

    expect(spending.dy, closeTo(income.dy, 0.01));
    expect(net.dy, closeTo(count.dy, 0.01));
    expect(spending.dy, lessThan(net.dy));
    expect(spending.dx, lessThan(income.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home category amounts reflow at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: homeCategorySummaryItemForTest(metric: _categoryMetric()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1,234,567.89 USD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  tearDown(() async {
    HomePage.debugCurrentDate = null;
    await services.reset();
  });

  testWidgets(
    'Home keeps the pinned header and refreshes visible spending on a real iOS pull',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-summary-card')),
          matching: find.text('10.00 USD'),
        ),
        findsOneWidget,
      );
      expect(
        transactions.queries,
        contains(
          isA<TransactionRepositoryQuery>()
              .having(
                (query) => query.status,
                'status',
                TransactionStatus.active,
              )
              .having((query) => query.from, 'from', isNotNull)
              .having((query) => query.to, 'to', isNotNull)
              .having(
                (query) => query.includeUndated,
                'includeUndated',
                isFalse,
              ),
        ),
      );

      final scrollFinder = find.byType(CustomScrollView);
      final scrollView = tester.widget<CustomScrollView>(scrollFinder);
      final headerIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is SliverPersistentHeader,
      );
      final refreshIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is CupertinoSliverRefreshControl,
      );
      expect(headerIndex, isNonNegative);
      expect(refreshIndex, isNonNegative);
      expect(headerIndex, lessThan(refreshIndex));
      expect(
        (scrollView.slivers[headerIndex] as SliverPersistentHeader).pinned,
        isTrue,
      );

      final refreshControl =
          scrollView.slivers[refreshIndex] as CupertinoSliverRefreshControl;
      expect(
        refreshControl.key,
        const ValueKey('home-cupertino-refresh-control'),
      );
      expect(refreshControl.onRefresh, isNotNull);
      expect(
        find.byKey(const ValueKey('home-refresh-indicator')),
        findsNothing,
      );

      final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
      final canvas = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-canvas')),
      );
      final bodySurface = tester.widget<DecoratedSliver>(
        find.byKey(const ValueKey('home-page-content-surface')),
      );
      final bodyColor = (bodySurface.decoration as BoxDecoration).color;
      expect(canvas.color, colors.subtleSurface);
      expect(bodyColor, colors.background);
      expect(canvas.color, isNot(bodyColor));

      final bodyPadding = tester.widget<Padding>(
        find.byKey(const ValueKey('home-page-content-padding')),
      );
      expect(
        bodyPadding.padding,
        const EdgeInsets.fromLTRB(
          ButlerlySize.contentGutter,
          ButlerlySpacing.small,
          ButlerlySize.contentGutter,
          ButlerlySpacing.large,
        ),
      );

      final added = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'home-refresh-added',
          provenanceId: 'home-refresh-added-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 9, 16, 12)),
          transactionDate: '2026-09-16',
          money: Money(
            amount: DecimalValue.parse('5.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Added Home spending',
        ),
      );
      expect(added, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-summary-card')),
          matching: find.text('10.00 USD'),
        ),
        findsOneWidget,
      );
      expect(find.text('15.00 USD'), findsNothing);

      final readGate = Completer<void>();
      transactions.readGate = readGate.future;
      final bodyFinder = find.byKey(const ValueKey('home-body-data'));
      final headerFinder = find.byKey(const ValueKey('home-header-surface'));
      final beforeRefresh = (tester.widget(bodyFinder) as FutureBuilder).future;
      final headerTopBefore = tester.getTopLeft(headerFinder).dy;

      await tester.drag(scrollFinder, const Offset(0, 320));
      await tester.pump();

      // While the refresh read is deliberately held open, keep the existing
      // spending snapshot visible and keep the pinned header stationary.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-summary-card')),
          matching: find.text('10.00 USD'),
        ),
        findsOneWidget,
      );
      expect(find.text('15.00 USD'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getTopLeft(headerFinder).dy,
        closeTo(headerTopBefore, 0.01),
      );

      readGate.complete();
      transactions.readGate = null;
      await tester.pumpAndSettle();

      final afterRefresh = (tester.widget(bodyFinder) as FutureBuilder).future;
      expect(identical(beforeRefresh, afterRefresh), isFalse);
      expect(find.text('10.00 USD'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-summary-card')),
          matching: find.text('15.00 USD'),
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getTopLeft(headerFinder).dy,
        closeTo(headerTopBefore, 0.01),
      );

      expect(scrollView.physics, isA<BouncingScrollPhysics>());
      expect(
        (scrollView.physics! as BouncingScrollPhysics).parent,
        isA<AlwaysScrollableScrollPhysics>(),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Home bounds current and historical queries in the persisted timezone',
    (tester) async {
      HomePage.debugCurrentDate = DateTime.utc(2026, 9, 16, 22);
      preferences.value = UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'America/Los_Angeles',
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();

      final current = transactions.queries.last;
      expect(current.from, DateTime(2026, 9, 1));
      expect(current.to, DateTime(2026, 9, 16));
      expect(current.occurredAtFrom, DateTime.utc(2026, 9, 1, 7));
      expect(current.occurredAtToExclusive, DateTime.utc(2026, 9, 17, 7));

      await tester.tap(find.byKey(const Key('home-month-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-month-2026-8')));
      await tester.pumpAndSettle();

      final historical = transactions.queries.last;
      expect(historical.from, DateTime(2026, 8, 1));
      expect(historical.to, DateTime(2026, 8, 31));
      expect(historical.occurredAtFrom, DateTime.utc(2026, 8, 1, 7));
      expect(historical.occurredAtToExclusive, DateTime.utc(2026, 9, 1, 7));
    },
  );

  testWidgets(
    'Home disables period actions when persisted timezone resolution fails',
    (tester) async {
      preferences.value = UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'Invalid/Timezone',
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-period-unavailable-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-empty-transactions-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('home-period-unavailable-retry')),
        findsOneWidget,
      );
      expect(transactions.queries, isEmpty);
      expect(find.byKey(const Key('home-category-view-all')), findsNothing);
      expect(find.byKey(const Key('home-recent-view-all')), findsNothing);
    },
  );

  testWidgets('Home keeps a valid zero-transaction period distinct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-month-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-month-2026-8')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-empty-transactions-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-period-unavailable-card')),
      findsNothing,
    );
  });

  testWidgets(
    'Home shows the selected empty period despite earlier historical spending',
    (tester) async {
      final historical = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'home-historical-spending',
          provenanceId: 'home-historical-spending-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 6, 15, 12)),
          transactionDate: '2026-06-15',
          money: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Earlier Home spending',
        ),
      );
      expect(historical, isA<ApplicationSuccess<TransactionDto>>());

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-month-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-month-2026-7')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-empty-transactions-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-summary-card')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home distinguishes transaction load failure from empty data', (
    tester,
  ) async {
    transactions.failQueries = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-transactions-unavailable-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-empty-transactions-card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-period-unavailable-card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-transactions-unavailable-retry')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('home-transactions-unavailable-card')),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  });

  testWidgets('Home distinguishes review load failure from no findings', (
    tester,
  ) async {
    transactions.failReviewQueries = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-review-unavailable-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-review-unavailable-retry')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-card')),
        matching: find.text('10.00 USD'),
      ),
      findsOneWidget,
    );
    expect(find.text('No findings'), findsNothing);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('home-review-unavailable-card')),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(body: HomePage()),
  );
}

class _RouterTestApp extends StatelessWidget {
  const _RouterTestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.light,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
}

AnalysisRuleDefinition _expenseRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R001'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'ANL-R001',
  descriptionKey: 'ANL-R001',
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
  surface: AnalysisSurface.overview,
  role: 'expenseTotal',
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('b' * 64),
);

final class _Transactions implements TransactionRepository {
  final values = <String, Transaction>{};
  final queries = <TransactionRepositoryQuery>[];
  Future<void>? readGate;
  bool failQueries = false;
  bool failReviewQueries = false;

  Future<void> _waitForRead() async {
    if (readGate case final pending?) await pending;
  }

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async {
    await _waitForRead();
    return values.values.toList(growable: false);
  }

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    queries.add(query);
    if (failQueries || (failReviewQueries && query.needsReview == true)) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list transactions',
      );
    }
    await _waitForRead();
    return values.values
        .where((transaction) {
          if (query.status != null && transaction.status != query.status) {
            return false;
          }
          if (query.from == null && query.to == null) return true;

          final businessDate = transaction.transactionDate?.trim();
          if (businessDate != null && businessDate.isNotEmpty) {
            final date = DateTime.tryParse(businessDate);
            if (date == null) return false;
            final calendarDate = DateTime.utc(date.year, date.month, date.day);
            final from = query.from == null
                ? null
                : DateTime.utc(
                    query.from!.year,
                    query.from!.month,
                    query.from!.day,
                  );
            final to = query.to == null
                ? null
                : DateTime.utc(query.to!.year, query.to!.month, query.to!.day);
            return (from == null || !calendarDate.isBefore(from)) &&
                (to == null || !calendarDate.isAfter(to));
          }

          final timing = transaction.timing;
          if (timing is KnownTransactionTime) {
            return (query.occurredAtFrom == null ||
                    !timing.occurredAt.isBefore(query.occurredAtFrom!)) &&
                (query.occurredAtToExclusive == null ||
                    timing.occurredAt.isBefore(query.occurredAtToExclusive!));
          }
          return query.includeUndated;
        })
        .toList(growable: false);
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}

final class _Preferences implements UserPreferenceRepository {
  UserPreference value = UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: 'UTC',
  );

  @override
  Future<UserPreference?> load() async => value;

  @override
  Future<void> save(UserPreference preference) async {
    value = preference;
  }
}

final class _Rules implements AnalysisRuleRepository {
  _Rules(this.values);

  final List<AnalysisRuleDefinition> values;

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => values;

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => values;

  @override
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id) async =>
      null;

  @override
  Future<void> activate(
    RuleIdentity id,
    RuleVersion version,
    bool enabled,
    DateTime at,
  ) async {}

  @override
  Future<void> install(
    AnalysisRuleDefinition definition, {
    required String sourceType,
    required String canonicalDefinition,
  }) async {}
}

AnalysisRuleDefinition _homeInsightRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R099'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: 'analysis.rule.r020.name',
  descriptionKey: 'analysis.rule.r020.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.previousEquivalentPeriod,
  condition: RuleCondition(
    operator: 'gt',
    left: 'currentTotal',
    value: DecimalValue.parse('0'),
  ),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.insights,
  outputType: InsightOutputType.pattern,
  resultPersistence: ResultPersistencePolicy.finding,
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('c' * 64),
);

AnalysisRuleDefinition _categoryRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R098'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'analysis.rule.r010.name',
  descriptionKey: 'analysis.rule.r010.name',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.category,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.spending,
  role: 'categorySpending',
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('d' * 64),
);

AnalysisMetric _categoryMetric() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-16',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  );
  return AnalysisMetric(
    id: 'category-result',
    rule: _categoryRule(),
    context: context,
    value: DecimalValue.parse('1234567.89'),
    currency: CurrencyCode('USD'),
    dimension: 'CAT-001:categorySpending',
    calculatedAt: DateTime.utc(2026, 9, 16),
  );
}

final class _PaymentSources implements PaymentSourceRepository {
  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => null;

  @override
  Future<List<PaymentSource>> listAll() async => const [];

  @override
  Future<void> save(PaymentSource paymentSource) async {}
}

final class _Merchants implements MerchantRepository {
  VoidCallback? onListAll;

  @override
  Future<Merchant?> findById(MerchantId id) async => null;

  @override
  Future<List<Merchant>> listAll() async {
    onListAll?.call();
    return const [];
  }

  @override
  Future<void> save(Merchant merchant) async {}
}

final class _Categories implements CategoryRepository {
  @override
  Future<Category?> findById(CategoryId id) async => null;

  @override
  Future<List<Category>> listAll() async => const [];

  @override
  Future<void> save(Category category) async {}
}

final class _Tags implements TagRepository {
  @override
  Future<Tag?> findById(TagId id) async => null;

  @override
  Future<List<Tag>> listAll() async => const [];

  @override
  Future<void> save(Tag tag) async {}
}

final class _Evidence implements EvidenceRepository {
  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;

  @override
  Future<void> link(AttachmentLink link) async {}

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async =>
      const [];

  @override
  Future<void> remove(EvidenceId id) async {}

  @override
  Future<void> save(EvidenceItem evidence) async {}

  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}
