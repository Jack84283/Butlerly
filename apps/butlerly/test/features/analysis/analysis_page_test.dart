import 'dart:async';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_custom_period_sheet.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_period_selector.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_skeleton.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_summary.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_count_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Widget app(
    Future<ApplicationResult<List<RuleExecutionResult>>> Function() load, {
    Future<ApplicationResult<List<RuleExecutionResult>>> Function(String)?
    loadForPeriod,
    Future<ApplicationResult<AnalysisCalendarResult>> Function(int, int)?
    loadCalendar,
    Future<ApplicationResult<List<TransactionDto>>> Function(String)?
    loadTransactionsForDate,
    Future<TransactionMasterData> Function()? loadMasterData,
    Future<ApplicationResult<List<RecurringPattern>>> Function()?
    loadRecurringPatterns,
    ValueChanged<String>? onNavigationRequested,
    ValueChanged<TransactionDto>? onTransactionRequested,
    ThemeData? theme,
  }) => MaterialApp(
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: AnalysisPage(
      key: UniqueKey(),
      load: load,
      loadForPeriod: loadForPeriod,
      loadCalendar: loadCalendar,
      loadTransactionsForDate: loadTransactionsForDate,
      loadMasterData: loadMasterData,
      loadRecurringPatterns: loadRecurringPatterns,
      onNavigationRequested: onNavigationRequested,
      onTransactionRequested: onTransactionRequested,
    ),
  );

  testWidgets('does not show or load paused recurring patterns', (
    tester,
  ) async {
    var recurringLoads = 0;
    await tester.pumpWidget(
      app(
        () async => const ApplicationSuccess(<RuleExecutionResult>[]),
        loadRecurringPatterns: () async {
          recurringLoads++;
          return const ApplicationSuccess(<RecurringPattern>[]);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recurring patterns'), findsNothing);
    expect(recurringLoads, 0);
  });

  testWidgets('uses one shared period selector and reloads its result', (
    tester,
  ) async {
    final periods = <String>[];
    await tester.pumpWidget(
      app(
        () async => const ApplicationSuccess(<RuleExecutionResult>[]),
        loadForPeriod: (period) async {
          periods.add(period);
          return const ApplicationSuccess(<RuleExecutionResult>[]);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analysis-period-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last month').last);
    await tester.pumpAndSettle();
    expect(periods, contains('current_month'));
    expect(periods, contains('previous_month'));
    expect(
      find.byKey(const ValueKey('analysis-period-selector')),
      findsOneWidget,
    );
  });

  testWidgets('period header fits its pinned extent at enlarged text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              const subtitle = 'Selected period';
              return ButlerlyPage(
                title: 'Analysis',
                pinnedHeaderExtent: AnalysisPeriodPinnedHeader.extent(
                  context,
                  subtitle,
                ),
                pinnedHeader: AnalysisPeriodPinnedHeader(
                  subtitle: subtitle,
                  value: 'current_month',
                  onChanged: (_) {},
                ),
                children: const [SizedBox(height: 800)],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final header = find.byKey(const ValueKey('analysis-period-pinned-header'));
    final selector = find.byKey(const ValueKey('analysis-period-selector'));
    final subtitle = find.text('Selected period');
    expect(header, findsOneWidget);
    expect(selector, findsOneWidget);
    expect(subtitle, findsOneWidget);

    final headerRect = tester.getRect(header);
    final subtitleRect = tester.getRect(subtitle);
    final selectorRect = tester.getRect(selector);
    expect(subtitleRect.top, greaterThanOrEqualTo(headerRect.top));
    expect(subtitleRect.bottom, lessThan(selectorRect.top));
    expect(selectorRect.bottom, lessThanOrEqualTo(headerRect.bottom));
  });

  testWidgets('refresh keeps analysis content and pinned controls visible', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var loads = 0;
    final refreshResult =
        Completer<ApplicationResult<List<RuleExecutionResult>>>();

    Future<ApplicationResult<List<RuleExecutionResult>>> loadForPeriod(
      String _,
    ) {
      loads++;
      if (loads == 1) {
        return Future.value(const ApplicationSuccess(<RuleExecutionResult>[]));
      }
      return refreshResult.future;
    }

    await tester.pumpWidget(
      app(
        () async => const ApplicationSuccess(<RuleExecutionResult>[]),
        loadForPeriod: loadForPeriod,
      ),
    );
    await tester.pumpAndSettle();

    final butlerlyPage = tester.widget<ButlerlyPage>(find.byType(ButlerlyPage));
    expect(
      butlerlyPage.pinnedSpacing,
      same(ButlerlyPinnedPageSpacing.tightHeader),
    );

    final selector = find.byKey(const ValueKey('analysis-period-selector'));
    expect(selector, findsOneWidget);
    expect(find.text('Financial calendar'), findsOneWidget);

    final refreshIndicator = tester.widget<RefreshIndicator>(
      find.byKey(const ValueKey('analysis-pull-to-refresh')),
    );
    final refresh = refreshIndicator.onRefresh();
    await tester.pump();

    expect(loads, 2);
    expect(selector, findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-period-pinned-header')),
      findsOneWidget,
    );
    expect(find.text('Financial calendar'), findsOneWidget);

    refreshResult.complete(const ApplicationSuccess(<RuleExecutionResult>[]));
    await refresh;
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('period change keeps analysis shell and current body visible', (
    tester,
  ) async {
    var loads = 0;
    final periodResult =
        Completer<ApplicationResult<List<RuleExecutionResult>>>();

    Future<ApplicationResult<List<RuleExecutionResult>>> loadForPeriod(
      String _,
    ) {
      loads++;
      if (loads == 1) {
        return Future.value(const ApplicationSuccess(<RuleExecutionResult>[]));
      }
      return periodResult.future;
    }

    await tester.pumpWidget(
      app(
        () async => const ApplicationSuccess(<RuleExecutionResult>[]),
        loadForPeriod: loadForPeriod,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Financial calendar'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-period-pinned-header')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('analysis-period-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last month').last);
    await tester.pump();

    expect(loads, 2);
    expect(find.byType(AnalysisSkeleton), findsNothing);
    expect(
      find.byKey(const ValueKey('analysis-period-pinned-header')),
      findsOneWidget,
    );
    expect(find.text('Financial calendar'), findsOneWidget);

    periodResult.complete(const ApplicationSuccess(<RuleExecutionResult>[]));
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisSkeleton), findsNothing);
    expect(
      find.byKey(const ValueKey('analysis-period-pinned-header')),
      findsOneWidget,
    );
  });

  testWidgets('custom period uses a staged bottom sheet range editor', (
    tester,
  ) async {
    Future<DateTimeRange?>? selectedRange;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  selectedRange = showButlerlyBottomSheet<DateTimeRange>(
                    context: context,
                    builder: (_) => AnalysisCustomPeriodSheet(
                      initialRange: DateTimeRange(
                        start: DateTime(2026, 9, 1),
                        end: DateTime(2026, 9, 20),
                      ),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Select range'), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    final save = find.byKey(const ValueKey('analysis-custom-period-save'));
    expect(save, findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-custom-period-cancel')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.textContaining('Sep 1'), findsWidgets);
    expect(find.textContaining('Sep 20'), findsWidgets);

    final titleX = tester.getTopLeft(find.text('Select range')).dx;
    final from = find.byKey(const ValueKey('analysis-custom-period-from'));
    final fromX = tester.getTopLeft(from).dx;
    final fromValueX = tester
        .getTopLeft(
          find.descendant(of: from, matching: find.textContaining('Sep 1')),
        )
        .dx;
    expect(fromX, closeTo(titleX, 0.1));
    expect(fromValueX, closeTo(fromX, 0.1));

    expect(tester.widget(save), isA<FilledButton>());
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await selectedRange, isNotNull);
    expect((await selectedRange)!.start, DateTime(2026, 9, 1));
    expect((await selectedRange)!.end, DateTime(2026, 9, 20));
  });

  testWidgets('cancelling custom period leaves the selection unapplied', (
    tester,
  ) async {
    Future<DateTimeRange?>? selectedRange;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  selectedRange = showButlerlyBottomSheet<DateTimeRange>(
                    context: context,
                    builder: (_) => AnalysisCustomPeriodSheet(
                      initialRange: DateTimeRange(
                        start: DateTime(2026, 9, 1),
                        end: DateTime(2026, 9, 20),
                      ),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('analysis-custom-period-cancel')),
    );
    await tester.pumpAndSettle();

    expect(await selectedRange, isNull);
    expect(find.text('Select range'), findsNothing);
  });

  testWidgets(
    'refresh reloads analysis, calendar, and selected-day transactions',
    (tester) async {
      var analysisLoads = 0;
      var calendarLoads = 0;
      var selectedDayLoads = 0;
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

      await tester.pumpWidget(
        app(
          () async {
            analysisLoads++;
            return const ApplicationSuccess(<RuleExecutionResult>[]);
          },
          loadCalendar: (year, month) async {
            calendarLoads++;
            return ApplicationSuccess(
              AnalysisCalendarResult(
                year: year,
                month: month,
                timeZoneId: 'America/Los_Angeles',
                days: [
                  AnalysisCalendarDay(
                    financialDate: date,
                    transactionCount: 1,
                    expenseTotal: null,
                    incomeTotal: null,
                    currencyBasis: CurrencyBasis.baseCurrency,
                  ),
                ],
              ),
            );
          },
          loadTransactionsForDate: (_) async {
            selectedDayLoads++;
            return const ApplicationSuccess(<TransactionDto>[]);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(ValueKey('analysis-calendar-$date')),
      );
      await tester.tap(find.byKey(ValueKey('analysis-calendar-$date')));
      await tester.pumpAndSettle();
      final beforeAnalysis = analysisLoads;
      final beforeCalendar = calendarLoads;
      final beforeSelectedDay = selectedDayLoads;

      notifyTransactionChanged();
      await tester.pumpAndSettle();

      expect(analysisLoads, greaterThan(beforeAnalysis));
      expect(calendarLoads, greaterThan(beforeCalendar));
      expect(selectedDayLoads, greaterThan(beforeSelectedDay));
    },
  );

  testWidgets('renders an offline all-clear state from application results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(() async => const ApplicationSuccess(<RuleExecutionResult>[])),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Not evaluated'), findsOneWidget);
    expect(
      find.text('Calculated privately on this device and available offline.'),
      findsNothing,
    );
  });

  testWidgets('distinguishes unavailable calculation from a zero result', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        () async => const ApplicationFailure(
          ApplicationFailureDetail(
            code: ApplicationFailureCode.unavailable,
            operation: 'analysis',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Analysis is unavailable'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('does not claim all-clear when insight execution failed', (
    tester,
  ) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R014'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.r014.name',
      descriptionKey: 'analysis.rule.r014.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('a' * 64),
      surface: AnalysisSurface.insights,
    );
    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(
            rule: rule,
            failure: const AnalysisFailure(
              code: 'executionFailed',
              message: 'Could not calculate insight.',
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('No findings'), findsNothing);
    expect(find.text('Insights are unavailable'), findsOneWidget);
  });

  testWidgets('renders a valid comparison without an emitted insight', (
    tester,
  ) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R020'),
      version: RuleVersion('1.2.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.r020.name',
      descriptionKey: 'analysis.rule.r020.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.previousEquivalentPeriod,
      condition: RuleCondition(
        operator: 'gte',
        value: DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0),
      ),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('b' * 64),
      surface: AnalysisSurface.insights,
    );
    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(
            rule: rule,
            comparison: AnalysisComparison(
              currentValue: DecimalValue.parse('4820'),
              baselineValue: DecimalValue.parse('5239.13'),
              absoluteChange: DecimalValue.parse('-419.13'),
              percentageChange: DecimalValue.parse('-8'),
              availability: AnalysisDataAvailability.sufficient,
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('previous period'), findsOneWidget);
    expect(find.text('Notable'), findsNothing);
  });

  testWidgets('does not render an insufficient comparison', (tester) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R020'),
      version: RuleVersion('1.2.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.r020.name',
      descriptionKey: 'analysis.rule.r020.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.previousEquivalentPeriod,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('c' * 64),
      surface: AnalysisSurface.insights,
    );
    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(
            rule: rule,
            comparison: AnalysisComparison(
              currentValue: DecimalValue.parse('4820'),
              availability: AnalysisDataAvailability.insufficient,
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('previous period'), findsNothing);
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('localizes a bundled rule name', (tester) async {
    const localizations = AppLocalizations(Locale('es'));
    expect(localizations.text('analysis.rule.r001.name'), 'Gastos');
    expect(
      localizations.text('analysis.rule.r001.name'),
      isNot('analysis.rule.r001.name'),
    );
  });

  testWidgets('category rows use localized labels and authoritative evidence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R010'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r010.name',
      descriptionKey: 'analysis.rule.r010.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.category,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('c' * 64),
    );
    final metric = AnalysisMetric(
      id: 'category-result',
      rule: rule,
      context: context,
      value: DecimalValue.parse('100'),
      dimension: 'category-id:value',
      currency: CurrencyCode('USD'),
      evidence: [
        EvidenceReference(transactionId: TransactionId('occurrence-only')),
      ],
      calculatedAt: DateTime.utc(2026, 8, 31),
    );
    String? requestedNavigation;
    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
        ]),
        loadMasterData: () async => const TransactionMasterData(
          categoryNames: {'category-id': 'Dining'},
        ),
        onNavigationRequested: (path) => requestedNavigation = path,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('category-id'), findsNothing);
    expect(find.text('View all categories'), findsNothing);
    await tester.ensureVisible(find.text('Dining'));
    await tester.tap(find.text('Dining'));
    final uri = Uri.parse(requestedNavigation!);
    expect(uri.path, '/search');
    expect(uri.queryParameters['locked'], 'true');
    expect(uri.queryParameters['category'], 'category-id');
    expect(uri.queryParameters['ids'], 'occurrence-only');
    expect(uri.queryParameters['from'], '2026-08-01');
    expect(uri.queryParameters['to'], '2026-08-31');
  });

  testWidgets(
    'merchant and subcategory rows retain subtitles and drill into exact evidence',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final period = AnalysisContext(
        period: AnalysisPeriod(
          startDate: '2026-08-01',
          endDate: '2026-08-31',
          timeZoneId: 'America/Los_Angeles',
        ),
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.baseCurrency,
      );

      AnalysisRuleDefinition rule(String id, RuleGrouping grouping) =>
          AnalysisRuleDefinition(
            identity: RuleIdentity(id),
            version: RuleVersion('1.0.0'),
            schemaVersion: '1.0.0',
            type: AnalysisRuleType.metric,
            nameKey: 'analysis.rule.r011.name',
            descriptionKey: 'analysis.rule.r011.description',
            enabled: true,
            status: AnalysisRuleStatus.active,
            period: 'selected_period',
            measure: const RuleMeasure(
              operation: RuleOperation.sum,
              field: 'amount',
            ),
            grouping: grouping,
            surface: AnalysisSurface.spending,
            baseline: RuleBaseline.none,
            condition: const RuleCondition(operator: 'none'),
            severity: RuleSeverity.info,
            definitionHash: RuleDefinitionHash('f' * 64),
          );

      final merchantRule = rule('ANL-R011', RuleGrouping.merchant);
      final subcategoryRule = rule('ANL-R012', RuleGrouping.subcategory);
      AnalysisMetric metric(
        AnalysisRuleDefinition definition,
        String id,
        String dimension,
        String transactionId,
      ) => AnalysisMetric(
        id: id,
        rule: definition,
        context: period,
        value: DecimalValue.parse('42'),
        dimension: '$dimension:value',
        currency: CurrencyCode('USD'),
        evidence: [
          EvidenceReference(transactionId: TransactionId(transactionId)),
        ],
        calculatedAt: DateTime.utc(2026, 8, 31),
      );

      String? navigation;
      await tester.pumpWidget(
        app(
          () async => ApplicationSuccess([
            RuleExecutionResult(
              rule: merchantRule,
              metric: metric(
                merchantRule,
                'merchant-row',
                'merchant-one',
                't-merchant',
              ),
            ),
            RuleExecutionResult(
              rule: subcategoryRule,
              metric: metric(
                subcategoryRule,
                'subcategory-row',
                'subcategory-one',
                't-subcategory',
              ),
            ),
          ]),
          loadMasterData: () async => const TransactionMasterData(
            merchantNames: {'merchant-one': 'Local market'},
            merchantCategoryIds: {'merchant-one': 'category.shopping'},
            categoryNames: {'subcategory-one': 'Fresh produce'},
            categoryParentIds: {'subcategory-one': 'category.food'},
          ),
          onNavigationRequested: (path) => navigation = path,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Top merchants for the selected period'),
        findsOneWidget,
      );
      expect(
        find.text('Top subcategories for the selected period'),
        findsOneWidget,
      );

      final merchant = find.byKey(
        const ValueKey('analysis-merchant-metric-merchant-row'),
      );
      final merchantIcon = find.descendant(
        of: merchant,
        matching: find.byType(ButlerlyCategoryIcon),
      );
      expect(merchantIcon, findsOneWidget);
      expect(
        tester.widget<ButlerlyCategoryIcon>(merchantIcon).categoryId,
        'category.shopping',
      );
      await tester.ensureVisible(merchant);
      await tester.tap(merchant);
      final merchantUri = Uri.parse(navigation!);
      expect(merchantUri.path, '/search');
      expect(merchantUri.queryParameters['locked'], 'true');
      expect(merchantUri.queryParameters['merchant'], 'merchant-one');
      expect(merchantUri.queryParameters['ids'], 't-merchant');
      expect(merchantUri.queryParameters['from'], '2026-08-01');

      navigation = null;
      final subcategory = find.byKey(
        const ValueKey('analysis-subcategory-metric-subcategory-row'),
      );
      final subcategoryIcon = find.descendant(
        of: subcategory,
        matching: find.byType(ButlerlyCategoryIcon),
      );
      expect(subcategoryIcon, findsOneWidget);
      expect(
        tester.widget<ButlerlyCategoryIcon>(subcategoryIcon).categoryId,
        'category.food',
      );
      await tester.ensureVisible(subcategory);
      await tester.tap(subcategory);
      final subcategoryUri = Uri.parse(navigation!);
      expect(subcategoryUri.path, '/search');
      expect(subcategoryUri.queryParameters['locked'], 'true');
      expect(subcategoryUri.queryParameters['subcategory'], 'subcategory-one');
      expect(subcategoryUri.queryParameters['ids'], 't-subcategory');
      expect(subcategoryUri.queryParameters['to'], '2026-08-31');
    },
  );

  testWidgets('breakdown taps open Search with fixed filters', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    AnalysisRuleDefinition rule(String id, RuleGrouping grouping) =>
        AnalysisRuleDefinition(
          identity: RuleIdentity(id),
          version: RuleVersion('1.0.0'),
          schemaVersion: '1.0.0',
          type: AnalysisRuleType.metric,
          nameKey: 'analysis.rule.r011.name',
          descriptionKey: 'analysis.rule.r011.description',
          enabled: true,
          status: AnalysisRuleStatus.active,
          period: 'selected_period',
          measure: const RuleMeasure(
            operation: RuleOperation.sum,
            field: 'amount',
          ),
          grouping: grouping,
          surface: AnalysisSurface.spending,
          baseline: RuleBaseline.none,
          condition: const RuleCondition(operator: 'none'),
          severity: RuleSeverity.info,
          definitionHash: RuleDefinitionHash('a' * 64),
        );

    final results = [
      for (final entry in <(String, RuleGrouping, String, String)>[
        ('ANL-R010', RuleGrouping.category, 'category.food', 't-category'),
        ('ANL-R011', RuleGrouping.merchant, 'merchant-one', 't-merchant'),
        (
          'ANL-R012',
          RuleGrouping.subcategory,
          'category.food.groceries',
          't-subcategory',
        ),
      ])
        RuleExecutionResult(
          rule: rule(entry.$1, entry.$2),
          metric: AnalysisMetric(
            id: entry.$4,
            rule: rule(entry.$1, entry.$2),
            context: context,
            value: DecimalValue.parse('42'),
            dimension: '${entry.$3}:value',
            currency: CurrencyCode('USD'),
            evidence: [
              EvidenceReference(transactionId: TransactionId(entry.$4)),
            ],
            calculatedAt: DateTime.utc(2026, 8, 31),
          ),
        ),
    ];
    final router = GoRouter(
      initialLocation: '/analysis',
      routes: [
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (_, _, navigationShell) => navigationShell,
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/',
                      builder: (_, _) => const Scaffold(body: Text('Home')),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/transactions',
                      builder: (_, state) => Scaffold(
                        body: Text(
                          'Transaction IDs: ${state.uri.queryParameters['ids']}',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/search',
              builder: (_, state) {
                final parameters = state.uri.queryParameters;
                return SearchPage(
                  readOnly: parameters['locked'] == 'true',
                  selectedMerchantId: parameters['merchant'],
                  selectedSubcategoryId: parameters['subcategory'],
                  initialQuery: ListTransactionsQuery(
                    transactionIds: parameters['ids']?.split(','),
                    from: DateTime.tryParse(parameters['from'] ?? ''),
                    to: DateTime.tryParse(parameters['to'] ?? ''),
                    categoryId: parameters['category'],
                  ),
                );
              },
            ),
            GoRoute(
              path: '/analysis',
              builder: (_, _) => AnalysisPage(
                load: () async => ApplicationSuccess(results),
                loadMasterData: () async => const TransactionMasterData(
                  categoryNames: {
                    'category.food': 'Dining',
                    'category.food.groceries': 'Groceries',
                  },
                  categoryParentIds: {
                    'category.food.groceries': 'category.food',
                  },
                  merchantNames: {'merchant-one': 'Local market'},
                  merchantCategoryIds: {'merchant-one': 'category.shopping'},
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );

    for (final drill in <(Finder, String, String, String)>[
      (find.text('Dining'), 't-category', 'category', 'category.food'),
      (
        find.byKey(const ValueKey('analysis-merchant-metric-t-merchant')),
        't-merchant',
        'merchant',
        'merchant-one',
      ),
      (
        find.byKey(const ValueKey('analysis-subcategory-metric-t-subcategory')),
        't-subcategory',
        'subcategory',
        'category.food.groceries',
      ),
    ]) {
      await tester.pumpAndSettle();
      await tester.ensureVisible(drill.$1);
      await tester.tap(drill.$1);
      await tester.pumpAndSettle();
      final search = find.byType(SearchPage);
      expect(search, findsOneWidget);
      // Imperative GoRouter.push does not necessarily replace the browser
      // route-information URI. Inspect the active secondary route instead.
      final searchContext = tester.element(search);
      final uri = GoRouterState.of(searchContext).uri;
      expect(
        uri.path,
        '/search',
        reason: 'Drill-through: ${drill.$3} / ${drill.$4}',
      );
      expect(uri.queryParameters['ids'], drill.$2);
      expect(uri.queryParameters['locked'], 'true');
      expect(uri.queryParameters[drill.$3], drill.$4);
      expect(uri.queryParameters['from'], '2026-08-01');
      expect(uri.queryParameters['to'], '2026-08-31');
      expect(
        find.byKey(const ValueKey('locked-search-criteria')),
        findsOneWidget,
      );
      expect(find.textContaining(drill.$4), findsWidgets);
      expect(router.canPop(), isTrue);
      expect(tester.takeException(), isNull);
      router.pop();
    }
  });

  testWidgets('subcategory rows use the subcategory unavailable label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R022'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r022.name',
      descriptionKey: 'analysis.rule.r022.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.subcategory,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('a' * 64),
    );
    final metric = AnalysisMetric(
      id: 'missing-subcategory-result',
      rule: rule,
      context: context,
      value: DecimalValue.parse('100'),
      dimension: 'subcategory-missing:value',
      currency: CurrencyCode('USD'),
      calculatedAt: DateTime.utc(2026, 8, 31),
    );

    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
        ]),
        loadMasterData: () async => const TransactionMasterData(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unavailable subcategory'), findsOneWidget);
    expect(find.text('Unavailable category'), findsNothing);
  });

  testWidgets('View all categories appears only when more than five exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R010'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r010.name',
      descriptionKey: 'analysis.rule.r010.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.category,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('d' * 64),
    );
    final results = [
      for (var i = 1; i <= 6; i++)
        RuleExecutionResult(
          rule: rule,
          metric: AnalysisMetric(
            id: 'category-$i',
            rule: rule,
            context: context,
            value: DecimalValue.parse('$i'),
            dimension: 'category-$i:value',
            currency: CurrencyCode('USD'),
            calculatedAt: DateTime.utc(2026, 8, 31),
          ),
        ),
    ];
    String? requestedNavigation;
    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess(results),
        loadMasterData: () async => const TransactionMasterData(
          categoryNames: {
            'category-1': 'One',
            'category-2': 'Two',
            'category-3': 'Three',
            'category-4': 'Four',
            'category-5': 'Five',
            'category-6': 'Six',
          },
        ),
        onNavigationRequested: (path) => requestedNavigation = path,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View all categories'));
    expect(find.text('Other'), findsOneWidget);
    await tester.tap(find.text('View all categories'));
    expect(
      requestedNavigation,
      '/search?locked=true&from=2026-08-01&to=2026-08-31',
    );
  });

  testWidgets('breakdowns do not render unavailable currency totals as zero', (
    tester,
  ) async {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R011'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r011.name',
      descriptionKey: 'analysis.rule.r011.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.merchant,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('e' * 64),
    );
    final metric = AnalysisMetric(
      id: 'merchant-result',
      rule: rule,
      context: context,
      value: DecimalValue.parse('0'),
      dimension: 'merchant-id:value',
      currency: CurrencyCode('USD'),
      availability: AnalysisDataAvailability.insufficient,
      calculatedAt: DateTime.utc(2026, 8, 31),
    );
    String? requestedNavigation;

    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
        ]),
        loadMasterData: () async => const TransactionMasterData(
          merchantNames: {'merchant-id': 'Foreign merchant'},
        ),
        onNavigationRequested: (path) => requestedNavigation = path,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Foreign merchant'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('0 USD'), findsNothing);
    await tester.tap(find.text('Foreign merchant'));
    expect(requestedNavigation, isNull);
  });

  testWidgets('summary does not render unavailable totals as zero', (
    tester,
  ) async {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R001'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r001.name',
      descriptionKey: 'analysis.rule.r001.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      role: AnalysisSemanticRole.expenseTotal,
      definitionHash: RuleDefinitionHash('f' * 64),
    );
    final metric = AnalysisMetric(
      id: 'spending-total',
      rule: rule,
      context: context,
      value: DecimalValue.parse('0'),
      currency: CurrencyCode('USD'),
      availability: AnalysisDataAvailability.insufficient,
      calculatedAt: DateTime.utc(2026, 8, 31),
    );

    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('0 USD'), findsNothing);
  });

  testWidgets('summary renders a valid empty total as zero', (tester) async {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R001'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r001.name',
      descriptionKey: 'analysis.rule.r001.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      role: AnalysisSemanticRole.expenseTotal,
      definitionHash: RuleDefinitionHash('1' * 64),
    );
    final metric = AnalysisMetric(
      id: 'spending-total-empty',
      rule: rule,
      context: context,
      value: DecimalValue.parse('0'),
      currency: CurrencyCode('USD'),
      availability: AnalysisDataAvailability.empty,
      calculatedAt: DateTime.utc(2026, 8, 31),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnalysisSummary(
          model: AnalysisOverview(
            spending: metric,
            insightUnavailable: false,
            trend: const [],
            categories: const [],
            qualityCount: 0,
            qualityEvaluated: false,
            qualityLimited: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('USD'), findsOneWidget);
    expect(find.text('Not available'), findsNothing);
  });

  testWidgets('category breakdown preserves unavailable categories', (
    tester,
  ) async {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R010'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r010.name',
      descriptionKey: 'analysis.rule.r010.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.category,
      surface: AnalysisSurface.spending,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('a' * 64),
    );
    final metric = AnalysisMetric(
      id: 'category-unavailable',
      rule: rule,
      context: context,
      value: DecimalValue.parse('0'),
      dimension: 'category-id:value',
      currency: CurrencyCode('USD'),
      availability: AnalysisDataAvailability.insufficient,
      calculatedAt: DateTime.utc(2026, 8, 31),
    );
    final availableMetric = AnalysisMetric(
      id: 'category-available',
      rule: rule,
      context: context,
      value: DecimalValue.parse('100'),
      dimension: 'category-available:value',
      currency: CurrencyCode('USD'),
      availability: AnalysisDataAvailability.sufficient,
      calculatedAt: DateTime.utc(2026, 8, 31),
    );
    String? requestedNavigation;

    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
          RuleExecutionResult(rule: rule, metric: availableMetric),
        ]),
        loadMasterData: () async => const TransactionMasterData(
          categoryNames: {
            'category-id': 'Foreign category',
            'category-available': 'Available category',
          },
        ),
        onNavigationRequested: (path) => requestedNavigation = path,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Foreign category'), findsOneWidget);
    expect(
      find.text(
        'Some categories are unavailable because currency normalization is missing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('0 USD'), findsNothing);
    expect(requestedNavigation, isNull);
  });

  testWidgets(
    'calendar navigates months, selects empty dates, and lists drill-down rows',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requestedMonths = <String>[];
      TransactionDto? selectedTransaction;
      ApplicationResult<AnalysisCalendarResult> calendar(int year, int month) {
        requestedMonths.add('$year-$month');
        final last = DateTime.utc(year, month + 1, 0).day;
        return ApplicationSuccess(
          AnalysisCalendarResult(
            year: year,
            month: month,
            timeZoneId: 'UTC',
            days: [
              for (var day = 1; day <= last; day++)
                AnalysisCalendarDay(
                  financialDate:
                      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
                  transactionCount: day == 2 ? 1 : 0,
                  expenseTotal: day == 2
                      ? Money(
                          amount: DecimalValue.parse('12'),
                          currency: CurrencyCode('USD'),
                        )
                      : null,
                  incomeTotal: null,
                  currencyBasis: CurrencyBasis.baseCurrency,
                  expenseAvailability: day == 2
                      ? AnalysisDataAvailability.sufficient
                      : AnalysisDataAvailability.empty,
                ),
            ],
          ),
        );
      }

      await tester.pumpWidget(
        app(
          () async => const ApplicationSuccess(<RuleExecutionResult>[]),
          loadCalendar: (year, month) async => calendar(year, month),
          loadTransactionsForDate: (date) async => ApplicationSuccess(
            date.endsWith('-02')
                ? [
                    for (var index = 1; index <= 4; index++)
                      TransactionDto(
                        id: 'transaction-$index',
                        amount: switch (index) {
                          1 => '12.00',
                          2 => '100.00',
                          3 => '7.00',
                          _ => '3.00',
                        },
                        currency: switch (index) {
                          1 || 3 => 'USD',
                          2 => 'EUR',
                          _ => 'GBP',
                        },
                        direction: switch (index) {
                          1 || 3 => 'expense',
                          _ => 'income',
                        },
                        status: 'active',
                        reviewState: 'clear',
                        transactionDate: date,
                        description: index == 1 ? 'Groceries' : 'Item $index',
                        createdAt: DateTime.utc(2026),
                        updatedAt: DateTime.utc(2026),
                      ),
                  ]
                : const [],
          ),
          onTransactionRequested: (transaction) =>
              selectedTransaction = transaction,
          theme: AppTheme.light,
        ),
      );
      await tester.pumpAndSettle();
      final initial = requestedMonths.single;
      final parts = initial.split('-').map(int.parse).toList();
      final date1 = '${parts[0]}-${parts[1].toString().padLeft(2, '0')}-01';
      final date2 = '${parts[0]}-${parts[1].toString().padLeft(2, '0')}-02';
      final firstDay = find.byKey(ValueKey('analysis-calendar-$date1'));
      await tester.ensureVisible(firstDay);
      expect(tester.getSize(firstDay).height, 40);
      final weekdayRow = find.byKey(
        const ValueKey('analysis-calendar-weekday-labels'),
      );
      final datesGrid = find.byKey(
        const ValueKey('analysis-calendar-days-grid'),
      );
      expect(
        tester.getTopLeft(datesGrid).dy - tester.getBottomLeft(weekdayRow).dy,
        closeTo(ButlerlySpacing.small, 1),
      );
      final weekdayLabel = find
          .descendant(of: weekdayRow, matching: find.byType(Text))
          .first;
      final dateLabel = find
          .descendant(of: firstDay, matching: find.byType(Text))
          .first;
      final visibleWeekdayGap =
          tester.getTopLeft(dateLabel).dy -
          tester.getBottomLeft(weekdayLabel).dy;
      expect(visibleWeekdayGap, greaterThanOrEqualTo(ButlerlySpacing.small));
      await tester.tap(find.byKey(ValueKey('analysis-calendar-$date1')));
      await tester.pumpAndSettle();
      expect(find.text('No transactions yet'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(ValueKey('analysis-calendar-$date2')),
      );
      await tester.tap(find.byKey(ValueKey('analysis-calendar-$date2')));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      final displayedDate = MaterialLocalizations.of(
        tester.element(find.text('Groceries')),
      ).formatFullDate(DateTime.parse(date2));
      final displayedDateLabel = find.byKey(
        const ValueKey('analysis-selected-day-date'),
      );
      final summaryLabel = find.byKey(
        const ValueKey('analysis-selected-day-summary'),
      );
      expect(tester.widget<Text>(displayedDateLabel).data, displayedDate);
      expect(
        tester.getTopLeft(displayedDateLabel).dy -
            tester.getBottomLeft(datesGrid).dy,
        closeTo(ButlerlySpacing.small, 1),
      );
      final countLabel = find.descendant(
        of: summaryLabel,
        matching: find.byType(TransactionCountText),
      );
      expect(countLabel, findsOneWidget);
      expect(tester.widget<TransactionCountText>(countLabel).count, 4);
      final amountLabel = find.byKey(
        const ValueKey('analysis-selected-day-amount'),
      );
      expect(tester.widget<Text>(amountLabel).data, r'$12.00');
      expect(
        tester.getTopLeft(countLabel).dx,
        lessThan(tester.getTopLeft(amountLabel).dx),
      );
      expect(
        tester.getTopLeft(amountLabel).dy,
        closeTo(tester.getTopLeft(countLabel).dy, 1),
      );
      expect(
        tester.getTopLeft(summaryLabel).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(displayedDateLabel).dy),
      );
      final innerCard = find.byType(ButlerlyTransactionInnerCard);
      expect(innerCard, findsOneWidget);
      final outerRect = tester.getRect(
        find.byKey(const ValueKey('analysis-financial-calendar-card')),
      );
      final innerRect = tester.getRect(innerCard);
      expect(innerRect.left - outerRect.left, ButlerlySpacing.small);
      expect(outerRect.right - innerRect.right, ButlerlySpacing.small);
      final recordRows = tester.widgetList<ButlerlyRecordRow>(
        find.byType(ButlerlyRecordRow),
      );
      expect(recordRows, hasLength(4));
      expect(
        recordRows.every(
          (row) => row.variant == ButlerlyTransactionRowVariant.dashboard,
        ),
        isTrue,
      );
      // The row is the primary drill-down control; the former View
      // transactions link is intentionally absent.
      await tester.tap(find.text('Item 4'));
      expect(find.text('View transactions'), findsNothing);
      expect(selectedTransaction?.id, 'transaction-4');
      expect(requestedMonths, hasLength(1));
    },
  );

  testWidgets(
    'calendar day summary preserves unavailable currency normalization',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ApplicationResult<AnalysisCalendarResult> calendar(int year, int month) {
        final last = DateTime.utc(year, month + 1, 0).day;
        return ApplicationSuccess(
          AnalysisCalendarResult(
            year: year,
            month: month,
            timeZoneId: 'UTC',
            days: [
              for (var day = 1; day <= last; day++)
                AnalysisCalendarDay(
                  financialDate:
                      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
                  transactionCount: day == 2 ? 1 : 0,
                  expenseTotal: day == 2
                      ? Money(
                          amount: DecimalValue.parse('0'),
                          currency: CurrencyCode('USD'),
                        )
                      : null,
                  incomeTotal: null,
                  currencyBasis: CurrencyBasis.baseCurrency,
                  expenseAvailability: day == 2
                      ? AnalysisDataAvailability.insufficient
                      : AnalysisDataAvailability.empty,
                ),
            ],
          ),
        );
      }

      await tester.pumpWidget(
        app(
          () async => const ApplicationSuccess(<RuleExecutionResult>[]),
          loadCalendar: (year, month) async => calendar(year, month),
          loadTransactionsForDate: (date) async => ApplicationSuccess(
            date.endsWith('-02')
                ? [
                    TransactionDto(
                      id: 'foreign-expense',
                      amount: '12.00',
                      currency: 'EUR',
                      direction: 'expense',
                      status: 'active',
                      reviewState: 'clear',
                      transactionDate: date,
                      description: 'Foreign purchase',
                      createdAt: DateTime.utc(2026),
                      updatedAt: DateTime.utc(2026),
                    ),
                  ]
                : const [],
          ),
          theme: AppTheme.light,
        ),
      );
      await tester.pumpAndSettle();

      final calendarCard = find.byKey(
        const ValueKey('analysis-financial-calendar-card'),
      );
      final day = find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.endsWith('-02'),
      );
      expect(day, findsOneWidget);
      await tester.tap(day);
      await tester.pumpAndSettle();
      expect(calendarCard, findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('0 USD'), findsNothing);
    },
  );

  testWidgets('presents catalog data-quality counts and evidence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R090'),
      version: RuleVersion('1.1.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.dataQuality,
      nameKey: 'analysis.rule.r090.name',
      descriptionKey: 'analysis.rule.r090.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(
        operation: RuleOperation.count,
        field: 'unresolvedNormalization',
      ),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.warning,
      surface: AnalysisSurface.dataQuality,
      definitionHash: RuleDefinitionHash('9' * 64),
    );
    final metric = AnalysisMetric(
      id: 'quality',
      rule: rule,
      context: AnalysisContext(
        period: AnalysisPeriod(
          startDate: '2026-08-01',
          endDate: '2026-08-31',
          timeZoneId: 'UTC',
        ),
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.baseCurrency,
      ),
      value: DecimalValue.parse('1'),
      transactionCount: 1,
      evidence: [EvidenceReference(transactionId: TransactionId('t1'))],
      calculatedAt: DateTime.utc(2026, 8, 26),
    );
    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 items need attention'), findsOneWidget);
    expect(find.text('Data quality issues'), findsNothing);
    expect(find.textContaining('1'), findsWidgets);
    expect(find.text('t1'), findsNothing);
  });

  testWidgets('data-quality visual semantics distinguish all three states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R091'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'analysis.rule.r091.name',
      descriptionKey: 'analysis.rule.r091.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(
        operation: RuleOperation.count,
        field: 'amount',
      ),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('e' * 64),
    );
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
    );
    final metric = AnalysisMetric(
      id: 'quality-good',
      rule: rule,
      context: context,
      value: DecimalValue.parse('0'),
      calculatedAt: DateTime.utc(2026, 8, 31),
    );

    await tester.pumpWidget(
      app(() async => const ApplicationSuccess(<RuleExecutionResult>[])),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);

    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(
            rule: rule,
            failure: const AnalysisFailure(
              code: 'execution',
              message: 'failed',
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Limited'));
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);

    await tester.pumpWidget(
      app(
        () async => ApplicationSuccess([
          RuleExecutionResult(rule: rule, metric: metric),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.check_circle_outline));
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
