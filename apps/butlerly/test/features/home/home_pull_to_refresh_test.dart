import 'dart:async';
import 'dart:io';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _summaryTestFontFamily = 'ButlerlyTestSans';

Future<void> _loadSummaryTestFont() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
        '/artifacts/material_fonts/Roboto-Regular.ttf',
  ];
  String? fontPath;
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      fontPath = candidate;
      break;
    }
  }
  if (fontPath == null) {
    throw StateError('Flutter Roboto test font was not found');
  }
  final bytes = await File(fontPath).readAsBytes();
  final loader = FontLoader(_summaryTestFontFamily)
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  await loader.load();
}

ThemeData _summaryTestTheme() {
  final base = AppTheme.light;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _summaryTestFontFamily),
  );
}

void main() {
  late _Transactions transactions;
  late _Preferences preferences;
  late _Merchants merchants;
  late _DuplicateGroups duplicateGroups;
  late _Rules rules;
  late FinanceServices finance;

  setUpAll(_loadSummaryTestFont);

  setUp(() async {
    await services.reset();
    HomePage.debugCurrentDate = DateTime(2026, 9, 16, 15);
    transactions = _Transactions();
    preferences = _Preferences();
    merchants = _Merchants();
    duplicateGroups = _DuplicateGroups();
    rules = _Rules([_expenseRule()]);
    finance = FinanceServices(
      transactions,
      _PaymentSources(),
      merchants,
      _Categories(),
      _Tags(),
      _Evidence(),
      preferences,
      duplicateGroups: duplicateGroups,
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
      find.byKey(const ValueKey('home-attention-card')),
      find.byKey(const ValueKey('home-recent-card')),
      find.byKey(const ValueKey('home-insight-card')),
    ];
    for (final card in cards) {
      expect(card, findsOneWidget);
    }
    final summaryRect = tester.getRect(cards.first);
    expect(summaryRect.left, ButlerlySize.contentGutter);
    expect(summaryRect.right, 390 - ButlerlySize.contentGutter);
    final positions = cards.map((card) => tester.getTopLeft(card).dy).toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('Monthly summary'), findsOneWidget);
    expect(find.text('Spending'), findsOneWidget);
    expect(find.text('Spending trend'), findsOneWidget);
    expect(find.text('Top categories'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Net position'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Sep 2026'), findsOneWidget);
    expect(
      find.text("Here's your financial overview for September 2026."),
      findsOneWidget,
    );
    expect(find.text('vs previous period'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(4));
    expect(find.byTooltip('View all categories'), findsOneWidget);
    expect(find.byTooltip('View all transactions'), findsOneWidget);
    expect(find.byTooltip('View all attention items'), findsOneWidget);
    expect(find.byTooltip('View all insights'), findsOneWidget);
    final monthSelector = find.byKey(const Key('home-month-selector'));
    expect(
      tester.getSize(monthSelector).height,
      greaterThanOrEqualTo(ButlerlySize.minimumTarget),
    );
    final monthSurface = find.descendant(
      of: monthSelector,
      matching: find.byType(Ink),
    );
    expect(monthSurface, findsOneWidget);
    expect(
      tester.getSize(monthSurface).height,
      lessThan(ButlerlySize.minimumTarget),
    );
    final monthSurfaceWidget = tester.widget<Ink>(monthSurface);
    expect(monthSurfaceWidget.decoration, isA<BoxDecoration>());
    expect((monthSurfaceWidget.decoration! as BoxDecoration).border, isNotNull);
    final summaryTitle = tester.widget<Text>(find.text('Monthly summary'));
    expect(
      summaryTitle.style?.fontFamily,
      isNot(ButlerlyTypography.editorialFontFamily),
    );
    expect(summaryTitle.style?.fontSize, 18);
    final summaryAmount = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-card')),
        matching: find.text('\$10.00'),
      ),
    );
    expect(
      summaryAmount.style?.fontFamily,
      isNot(ButlerlyTypography.editorialFontFamily),
    );
    expect(summaryAmount.style?.fontFeatures, isNotEmpty);
    expect(find.byKey(const ValueKey('home-attention-card')), findsOneWidget);
    expect(find.text('1 merchant to review'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-insight-card')), findsOneWidget);
    final transactionRow = find.byKey(
      const ValueKey('home-recent-transaction-home-refresh-initial'),
    );
    expect(transactionRow, findsOneWidget);
    final rowPadding = find.descendant(
      of: transactionRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding ==
                EdgeInsets.fromLTRB(
                  ButlerlyTransactionItemTokens.horizontalInset,
                  ButlerlyTransactionItemTokens.topPadding,
                  ButlerlyTransactionItemTokens.horizontalInset,
                  ButlerlyTransactionItemTokens.bottomPadding,
                ),
      ),
    );
    expect(rowPadding, findsOneWidget);
    expect(ButlerlyTransactionItemTokens.topPadding, 12);
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
    expect(find.text('Insights are unavailable'), findsOneWidget);
    expect(find.text('Nothing needs your attention'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-empty-transactions-card')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home trend range keeps the other cards visible while loading locally',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-category-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-recent-card')), findsOneWidget);

      final trendReadGate = Completer<void>();
      transactions.readGate = trendReadGate.future;
      await tester.tap(find.byKey(const Key('home-trend-range-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 12 months'));
      await tester.pump();

      expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-category-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-recent-card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-trend-local-loading')),
        findsOneWidget,
      );
      expect(find.text('Sep 2026'), findsOneWidget);

      trendReadGate.complete();
      transactions.readGate = null;
      await tester.pumpAndSettle();

      expect(find.text('Last 12 months'), findsOneWidget);
      for (
        var month = DateTime(2025, 10);
        month.isBefore(DateTime(2026, 10));
        month = DateTime(month.year, month.month + 1)
      ) {
        expect(
          find.byKey(
            ValueKey('home-spending-trend-label-${month.year}-${month.month}'),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Sep 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home places attention and insight cards around recent activity', (
    tester,
  ) async {
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
    final insightCard = find.byKey(const ValueKey('home-insight-card'));
    expect(
      find.descendant(
        of: insightCard,
        matching: find.byKey(const ValueKey('home-insight-icon')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: insightCard,
        matching: find.textContaining('Current period:'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: insightCard,
        matching: find.textContaining('Previous period:'),
      ),
      findsNothing,
    );
    final positions = cards.map((card) => tester.getTopLeft(card).dy);
    expect(positions, orderedEquals([...positions]..sort()));

    await tester.ensureVisible(
      find.byKey(const ValueKey('home-attention-card')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-attention-card')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('review-uri'))).data,
      '/review?view=uncategorized&from=2026-09-01&to=2026-09-16&timeZoneId=UTC',
    );
  });

  testWidgets('Home exposes generic review issues in Needs Attention', (
    tester,
  ) async {
    final stored = transactions.values['home-refresh-initial']!;
    final at = stored.updatedAt.add(const Duration(seconds: 1));
    final merchantReviewIssue = stored.reviewIssues.first;
    transactions.values['home-refresh-initial'] = stored
        .resolveReviewIssue(merchantReviewIssue.id, at)
        .assignCategory(CategoryId('category.food'), at)
        .addReviewIssue(
          ReviewIssue(
            id: ReviewIssueId('home-generic-review'),
            transactionId: stored.id,
            reason: ReviewIssueReason.incomplete,
            createdAt: at,
          ),
          at,
        );

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-attention-card')), findsOneWidget);
    expect(find.text('1 item to review'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-attention-card')),
        matching: find.text('Needs review'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home attention rows open their matching Review datasets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final matching = await finance.createTransaction(
      CreateTransactionCommand(
        id: 'home-attention-matching',
        provenanceId: 'home-attention-matching-provenance',
        timing: KnownTransactionTime(DateTime.utc(2026, 9, 14, 12)),
        transactionDate: '2026-09-15',
        money: Money(
          amount: DecimalValue.parse('10.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Matching Home spending',
      ),
    );
    expect(matching, isA<ApplicationSuccess<TransactionDto>>());
    final initial = transactions.values['home-refresh-initial']!;
    final matchingTransaction = transactions.values['home-attention-matching']!;
    duplicateGroups.values.add(
      DuplicateCandidateGroup(
        id: 'home-attention-duplicate',
        transactionIds: [initial.id, matchingTransaction.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-09-15',
          amount: DecimalValue.parse('10.00'),
          currency: 'USD',
          direction: 'expense',
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
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
          builder: (_, state) {
            final parameters = state.uri.queryParameters;
            final from = parameters['from'];
            final to = parameters['to'];
            final timeZoneId = parameters['timeZoneId'];
            final scope = from == null || to == null || timeZoneId == null
                ? const ReviewPeriodScope.invalid()
                : ReviewPeriodScope.fromDateValues(
                    startDate: from,
                    endDate: to,
                    timeZoneId: timeZoneId,
                  );
            final reason = ReviewIssueReason.values
                .where((value) => value.name == parameters['reason'])
                .firstOrNull;
            return Scaffold(
              body: ReviewPage(
                showPossibleDuplicates: parameters['view'] == 'duplicates',
                showUncategorized: parameters['view'] == 'uncategorized',
                showNeedsReview: parameters['view'] == 'needsReview',
                showReviewOverview: parameters['view'] == 'overview',
                reviewScope: scope,
                reviewReason: reason,
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_RouterTestApp(router: router));
    await tester.pumpAndSettle();

    final uncategorizedRow = find.text('Uncategorised transactions');
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-attention-card')),
    );
    await tester.pumpAndSettle();
    await tester.tap(uncategorizedRow);
    await tester.pumpAndSettle();
    expect(find.text('Initial Home spending'), findsOneWidget);
    expect(find.text('Matching Home spending'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    final duplicateRow = find.textContaining('possible duplicate');
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-attention-card')),
    );
    await tester.pumpAndSettle();
    await tester.tap(duplicateRow);
    await tester.pumpAndSettle();
    expect(find.text('Possible duplicate group'), findsOneWidget);
    expect(find.text('Initial Home spending'), findsOneWidget);
    expect(find.text('Matching Home spending'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-attention-view-all')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-attention-view-all')));
    await tester.pumpAndSettle();
    expect(find.text('Not categorized'), findsWidgets);
    expect(find.textContaining('Possible duplicates'), findsWidgets);
    expect(find.text('Needs review'), findsWidgets);

    router.go('/');
    await tester.pumpAndSettle();
    final merchantRow = find
        .byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.contains('merchant') == true &&
              widget.data?.contains('review') == true,
        )
        .first;
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-attention-card')),
    );
    await tester.pumpAndSettle();
    await tester.tap(merchantRow);
    await tester.pumpAndSettle();
    expect(find.text('Initial Home spending'), findsOneWidget);
    expect(find.text('Matching Home spending'), findsOneWidget);
    expect(find.text('Possible duplicate group'), findsNothing);

    await tester.tap(find.text('Initial Home spending').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Dismiss'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resolve'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
    await tester.pumpAndSettle();
    expect(
      transactions.values['home-refresh-initial']!.reviewIssues.first.status,
      ReviewIssueStatus.dismissed,
    );
  });

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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-category-card')), findsOneWidget);
    final metricKeys = [
      const ValueKey('home-summary-metric-spending'),
      const ValueKey('home-summary-metric-income'),
      const ValueKey('home-summary-metric-savings'),
      const ValueKey('home-summary-metric-net-position'),
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
    for (final label in ['Spending', 'Income', 'Savings', 'Net position']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-card')),
        matching: find.text('\$10.00'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Summary keeps all four metrics in one row normally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final model = AnalysisOverview(
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: true,
      qualityLimited: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: _summaryTestTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySize.contentGutter,
            ),
            child: homeSummaryForTest(model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final spending = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-spending')),
    );
    final income = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-income')),
    );
    final savings = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-savings')),
    );
    final netPosition = tester.getTopLeft(
      find.byKey(const ValueKey('home-summary-metric-net-position')),
    );
    expect(spending.dy, closeTo(income.dy, 0.01));
    expect(spending.dy, closeTo(savings.dy, 0.01));
    expect(spending.dy, closeTo(netPosition.dy, 0.01));
    expect(spending.dx, lessThan(income.dx));
    expect(income.dx, lessThan(savings.dx));
    expect(savings.dx, lessThan(netPosition.dx));
    for (final entry in [
      ('home-summary-metric-spending', 'Spending'),
      ('home-summary-metric-income', 'Income'),
      ('home-summary-metric-savings', 'Savings'),
      ('home-summary-metric-net-position', 'Net position'),
    ]) {
      final cell = find.byKey(ValueKey(entry.$1));
      final label = find.descendant(of: cell, matching: find.text(entry.$2));
      expect(
        (tester.getCenter(cell).dx - tester.getCenter(label).dx).abs(),
        lessThan(0.01),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Summary uses the active text scale when deciding fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

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
    final model = AnalysisOverview(
      spending: _categoryMetric(value: '9999.99'),
      income: _categoryMetric(value: '4150.00'),
      savings: AnalysisValue(
        value: DecimalValue.parse('1809.82'),
        currency: CurrencyCode('USD'),
        context: context,
      ),
      net: _categoryMetric(value: '1809.82'),
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: true,
      qualityLimited: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: _summaryTestTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySize.contentGutter,
            ),
            child: homeSummaryForTest(model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metricKeys = [
      const ValueKey('home-summary-metric-spending'),
      const ValueKey('home-summary-metric-income'),
      const ValueKey('home-summary-metric-savings'),
      const ValueKey('home-summary-metric-net-position'),
    ];
    final metricTops = [
      for (final key in metricKeys) tester.getTopLeft(find.byKey(key)).dy,
    ];
    for (var index = 1; index < metricTops.length; index++) {
      expect(metricTops[index], greaterThan(metricTops[index - 1]));
    }
    final value = tester.widget<Text>(find.text('\$9,999.99'));
    expect(value.style?.fontSize, 15);
    expect(value.softWrap, isTrue);
    expect(value.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Summary keeps reference amounts on one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    final model = AnalysisOverview(
      spending: _categoryMetric(value: '2340.18'),
      income: _categoryMetric(value: '4150.00'),
      savings: AnalysisValue(
        value: DecimalValue.parse('1809.82'),
        currency: CurrencyCode('USD'),
        context: context,
      ),
      net: _categoryMetric(value: '1809.82'),
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: true,
      qualityLimited: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: _summaryTestTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySize.contentGutter,
            ),
            child: homeSummaryForTest(model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const referenceValues = {
      'home-summary-metric-spending': '\$2,340.18',
      'home-summary-metric-income': '\$4,150.00',
      'home-summary-metric-savings': '\$1,809.82',
      'home-summary-metric-net-position': '\$1,809.82',
    };
    for (final entry in referenceValues.entries) {
      final textFinder = find.descendant(
        of: find.byKey(ValueKey(entry.key)),
        matching: find.text(entry.value),
      );
      expect(textFinder, findsOneWidget);
      final text = tester.widget<Text>(textFinder);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.visible);
      expect(text.style?.fontSize, 15);
      final render = tester.renderObject<RenderParagraph>(textFinder);
      final context = tester.element(textFinder);
      final effectiveStyle = DefaultTextStyle.of(
        context,
      ).style.merge(text.style);
      final painter = TextPainter(
        text: TextSpan(text: entry.value, style: effectiveStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      expect(painter.width, lessThanOrEqualTo(render.size.width + 0.01));
    }
    final metricTops = [
      for (final key in referenceValues.keys)
        tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
    for (final top in metricTops.skip(1)) {
      expect(top, closeTo(metricTops.first, 0.01));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Summary stacks extreme amounts at enlarged text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

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
    final model = AnalysisOverview(
      spending: _categoryMetric(
        value: '123456789012345678901234567890',
        currency: 'USDLONG',
      ),
      income: _categoryMetric(value: '4150.00'),
      savings: AnalysisValue(
        value: DecimalValue.parse('1809.82'),
        currency: CurrencyCode('USD'),
        context: context,
      ),
      net: _categoryMetric(value: '1809.82'),
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: true,
      qualityLimited: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: _summaryTestTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySize.contentGutter,
            ),
            child: homeSummaryForTest(model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metricKeys = [
      const ValueKey('home-summary-metric-spending'),
      const ValueKey('home-summary-metric-income'),
      const ValueKey('home-summary-metric-savings'),
      const ValueKey('home-summary-metric-net-position'),
    ];
    final metricTops = [
      for (final key in metricKeys) tester.getTopLeft(find.byKey(key)).dy,
    ];
    for (var index = 1; index < metricTops.length; index++) {
      expect(metricTops[index], greaterThan(metricTops[index - 1]));
    }
    final longValue = find.textContaining('USDLONG');
    expect(longValue, findsOneWidget);
    final longValueRect = tester.getRect(longValue);
    final spendingRect = tester.getRect(find.byKey(metricKeys.first));
    expect(longValueRect.left, greaterThanOrEqualTo(spendingRect.left - 0.01));
    expect(longValueRect.right, lessThanOrEqualTo(spendingRect.right + 0.01));
    final valueText = tester.widget<Text>(longValue);
    expect(valueText.softWrap, isTrue);
    expect(valueText.maxLines, isNull);
    final renderedValue = tester.renderObject<RenderParagraph>(longValue);
    final singleLinePainter = TextPainter(
      text: TextSpan(text: valueText.data, style: valueText.style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(tester.element(longValue)),
    )..layout();
    expect(
      renderedValue.textSize.height,
      greaterThan(singleLinePainter.preferredLineHeight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Summary uses semantic colors for supporting values', (
    tester,
  ) async {
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
    final model = AnalysisOverview(
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: false,
      qualityLimited: false,
      savings: AnalysisValue(
        value: DecimalValue.parse('5'),
        currency: CurrencyCode('USD'),
        context: context,
      ),
      savingsRate: DecimalValue.parse('0.5'),
      spendingComparison: _comparison('2'),
      incomeComparison: _comparison('-3'),
      netComparison: _comparison('4'),
    );
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
        home: Scaffold(body: homeSummaryForTest(model)),
      ),
    );

    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
    expect(
      _lastTextIn(tester, 'home-summary-metric-spending').style?.color,
      colors.error,
    );
    expect(
      _lastTextIn(tester, 'home-summary-metric-income').style?.color,
      colors.success,
    );
    final savingsRate = tester.widget<Text>(find.text('50%'));
    expect(savingsRate.style?.color, colors.info);
    expect(savingsRate.style?.fontSize, 12);
    expect(
      _lastTextIn(tester, 'home-summary-metric-net-position').style?.color,
      colors.success,
    );
    final savingsSemantics = tester.getSemantics(
      find.byKey(const ValueKey('home-summary-metric-savings')),
    );
    expect(savingsSemantics.label, contains('50%'));
    expect(savingsSemantics.label, contains('of income'));
    final netSemantics = tester.getSemantics(
      find.byKey(const ValueKey('home-summary-metric-net-position')),
    );
    expect(netSemantics.label, contains('+4.00'));
  });

  testWidgets('Home Insight preview uses data-driven localized copy', (
    tester,
  ) async {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-09-01',
        endDate: '2026-09-16',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: CurrencyCode('USD'),
      periodType: 'selected_period',
    );
    final insight = InsightResult(
      outputType: InsightOutputType.pattern,
      rule: _homeInsightRule(grouping: RuleGrouping.category),
      context: context,
      baselineContext: context,
      percentageChange: DecimalValue.parse('28'),
      dimension: 'restaurants',
    );

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
          body: homeInsightForTest(
            insight,
            masterData: const TransactionMasterData(
              categoryNames: {'restaurants': 'Restaurants'},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Spending up 28%'), findsOneWidget);
    expect(
      find.textContaining(
        'Your Restaurants spending is 28% higher than the comparable previous period.',
      ),
      findsOneWidget,
    );
    expect(find.text('analysis.rule.r020.name'), findsNothing);
  });

  testWidgets('Home Insight uses same-period wording for current month', (
    tester,
  ) async {
    await _pumpHomeInsight(tester, 'current_month');

    expect(
      find.text(
        'Your Restaurants spending is 28% higher than the same period last month.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home Insight uses same-period wording for selected month', (
    tester,
  ) async {
    await _pumpHomeInsight(tester, 'selected_month');

    expect(
      find.text(
        'Your Restaurants spending is 28% higher than the same period last month.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home Summary does not show insufficient derived savings', (
    tester,
  ) async {
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
    final model = AnalysisOverview(
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: false,
      qualityLimited: false,
      savings: AnalysisValue(
        value: DecimalValue.parse('5'),
        currency: CurrencyCode('USD'),
        context: context,
        availability: AnalysisDataAvailability.insufficient,
      ),
      savingsRate: DecimalValue.parse('0.5'),
    );
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
        home: Scaffold(body: homeSummaryForTest(model)),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-metric-savings')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-metric-savings')),
        matching: find.text('50%'),
      ),
      findsNothing,
    );
  });

  testWidgets('Home Summary does not show empty derived savings', (
    tester,
  ) async {
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
    final model = AnalysisOverview(
      insightUnavailable: false,
      trend: const [],
      categories: const [],
      qualityCount: 0,
      qualityEvaluated: false,
      qualityLimited: false,
      savings: AnalysisValue(
        value: DecimalValue.parse('100'),
        currency: CurrencyCode('USD'),
        context: context,
        availability: AnalysisDataAvailability.empty,
      ),
      savingsRate: DecimalValue.parse('1'),
    );
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
        home: Scaffold(body: homeSummaryForTest(model)),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-metric-savings')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-metric-savings')),
        matching: find.text('100.0% of income'),
      ),
      findsNothing,
    );
  });

  testWidgets('Home Summary and categories hide insufficient metric values', (
    tester,
  ) async {
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
    final model = AnalysisOverview(
      spending: _categoryMetric(
        availability: AnalysisDataAvailability.insufficient,
      ),
      insightUnavailable: false,
      trend: const [],
      categories: [
        _categoryMetric(availability: AnalysisDataAvailability.insufficient),
      ],
      qualityCount: 0,
      qualityEvaluated: false,
      qualityLimited: false,
      savings: AnalysisValue(
        value: DecimalValue.parse('5'),
        currency: CurrencyCode('USD'),
        context: context,
        availability: AnalysisDataAvailability.insufficient,
      ),
    );
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
        home: Scaffold(body: homeSummaryForTest(model)),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-metric-spending')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(find.text('\$1,234,567.89'), findsNothing);

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
          body: homeCategorySummaryItemForTest(
            metric: _categoryMetric(
              availability: AnalysisDataAvailability.insufficient,
            ),
          ),
        ),
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('\$1,234,567.89'), findsNothing);
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

    expect(find.text('\$1,234,567.89'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home category summary uses compact semantic typography', (
    tester,
  ) async {
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
          body: homeCategorySummaryItemForTest(
            metric: _categoryMetric(),
            share: DecimalValue.parse('0.25'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amount = tester.widget<Text>(find.text(r'$1,234,567.89'));
    final percentage = tester.widget<Text>(find.text('25%'));
    expect(amount.style?.fontSize, 14);
    expect(amount.style?.fontWeight, FontWeight.w600);
    expect(percentage.style?.fontSize, 13);
    expect(percentage.style?.fontWeight, FontWeight.w400);
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
          matching: find.text('\$10.00'),
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
          matching: find.text('\$10.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('\$15.00'), findsNothing);

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
          matching: find.text('\$10.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('\$15.00'), findsNothing);
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
      expect(find.text('\$10.00'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-summary-card')),
          matching: find.text('\$15.00'),
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
      expect(
        find.byKey(const ValueKey('home-review-unavailable-retry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-review-unavailable-content')),
        findsOneWidget,
      );
      expect(transactions.queries, isEmpty);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('home-category-view-all')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('home-recent-view-all')))
            .onPressed,
        isNull,
      );
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

    expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-trend-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-category-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-attention-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-recent-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-insight-card')), findsOneWidget);
    expect(find.text('\$0.00'), findsNWidgets(4));
    expect(find.text('No spending recorded in this period.'), findsOneWidget);
    expect(find.text('Nothing needs attention'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('home-attention-card')))
          .label,
      contains('Nothing needs attention'),
    );
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Nothing needs your attention'), findsOneWidget);
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

      expect(find.byKey(const ValueKey('home-summary-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-recent-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-insight-card')), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('home-recent-unavailable-retry')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('home-recent-unavailable-content')),
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

    expect(find.byKey(const ValueKey('home-attention-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-review-unavailable-retry')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-summary-card')),
        matching: find.text('\$10.00'),
      ),
      findsOneWidget,
    );
    expect(find.text('No findings'), findsNothing);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('home-review-unavailable-content')),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  });

  testWidgets(
    'Home preserves loaded review items when duplicate detection fails',
    (tester) async {
      duplicateGroups.fail = true;

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-review-unavailable-card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('home-attention-card')), findsOneWidget);
      expect(find.text('1 merchant to review'), findsOneWidget);
      expect(
        find.text('Possible duplicate detection unavailable'),
        findsOneWidget,
      );
    },
  );
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

AnalysisRuleDefinition _homeInsightRule({
  RuleGrouping grouping = RuleGrouping.none,
}) => AnalysisRuleDefinition(
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
  grouping: grouping,
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

AnalysisMetric _categoryMetric({
  AnalysisDataAvailability availability = AnalysisDataAvailability.sufficient,
  String value = '1234567.89',
  String currency = 'USD',
}) {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-16',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode(currency),
  );
  return AnalysisMetric(
    id: 'category-result',
    rule: _categoryRule(),
    context: context,
    value: DecimalValue.parse(value),
    currency: CurrencyCode(currency),
    dimension: 'CAT-001:categorySpending',
    availability: availability,
    calculatedAt: DateTime.utc(2026, 9, 16),
  );
}

AnalysisContext _homeInsightContext(String periodType) => AnalysisContext(
  period: AnalysisPeriod(
    startDate: '2026-09-01',
    endDate: '2026-09-16',
    timeZoneId: 'UTC',
  ),
  datasetMode: DatasetMode.allEligible,
  currencyBasis: CurrencyBasis.baseCurrency,
  baseCurrency: CurrencyCode('USD'),
  periodType: periodType,
);

Future<void> _pumpHomeInsight(WidgetTester tester, String periodType) async {
  final context = _homeInsightContext(periodType);
  final insight = InsightResult(
    outputType: InsightOutputType.pattern,
    rule: _homeInsightRule(grouping: RuleGrouping.category),
    context: context,
    baselineContext: context,
    percentageChange: DecimalValue.parse('28'),
    dimension: 'restaurants',
  );
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
        body: homeInsightForTest(
          insight,
          masterData: const TransactionMasterData(
            categoryNames: {'restaurants': 'Restaurants'},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AnalysisComparison _comparison(String change) => AnalysisComparison(
  currentValue: DecimalValue.parse('10'),
  baselineValue: DecimalValue.parse('8'),
  absoluteChange: DecimalValue.parse(change),
  percentageChange: DecimalValue.parse('25'),
  availability: AnalysisDataAvailability.sufficient,
);

Text _lastTextIn(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .last;

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

final class _DuplicateGroups implements DuplicateCandidateGroupRepository {
  final values = <DuplicateCandidateGroup>[];
  bool fail = false;

  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async {
    if (fail) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'duplicate query failed',
      );
    }
    return values
        .where((group) => status == null || group.status == status)
        .toList(growable: false);
  }

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async => const [];

  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async => const [];

  @override
  Future<void> save(DuplicateCandidateGroup group) async {
    values.removeWhere((value) => value.id == group.id);
    values.add(group);
  }

  @override
  Future<void> remove(String id) async {
    values.removeWhere((value) => value.id == id);
  }
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
