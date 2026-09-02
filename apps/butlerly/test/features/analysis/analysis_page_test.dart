import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_custom_period_sheet.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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
    ValueChanged<String>? onNavigationRequested,
    ValueChanged<TransactionDto>? onTransactionRequested,
  }) => MaterialApp(
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
      onNavigationRequested: onNavigationRequested,
      onTransactionRequested: onTransactionRequested,
    ),
  );

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
    await tester.tap(find.text('Last Month').last);
    await tester.pumpAndSettle();
    expect(periods, contains('current_month'));
    expect(periods, contains('previous_month'));
    expect(
      find.byKey(const ValueKey('analysis-period-selector')),
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
    expect(
      find.text('See how spending changes across the selected period.'),
      findsOneWidget,
    );
    expect(
      find.text('More activity is needed to show a trend.'),
      findsOneWidget,
    );
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

  testWidgets('category rows use localized labels and stable filter IDs', (
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
    expect(find.text('Dining'), findsNWidgets(2));
    expect(find.text('category-id'), findsNothing);
    expect(find.text('View all categories'), findsNothing);
    await tester.ensureVisible(find.text('Dining').last);
    await tester.tap(find.text('Dining').last);
    expect(requestedNavigation, contains('from=2026-08-01'));
    expect(requestedNavigation, contains('to=2026-08-31'));
    expect(requestedNavigation, contains('category=category-id'));
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
    expect(requestedNavigation, '/search?from=2026-08-01&to=2026-08-31');
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
                  expenseTotal: null,
                  incomeTotal: null,
                  currencyBasis: CurrencyBasis.baseCurrency,
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
                        amount: '12.00',
                        currency: 'USD',
                        direction: 'expense',
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
        ),
      );
      await tester.pumpAndSettle();
      final initial = requestedMonths.single;
      final parts = initial.split('-').map(int.parse).toList();
      final date1 = '${parts[0]}-${parts[1].toString().padLeft(2, '0')}-01';
      final date2 = '${parts[0]}-${parts[1].toString().padLeft(2, '0')}-02';
      await tester.ensureVisible(
        find.byKey(ValueKey('analysis-calendar-$date1')),
      );
      await tester.tap(find.byKey(ValueKey('analysis-calendar-$date1')));
      await tester.pumpAndSettle();
      expect(find.text('No transactions yet'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(ValueKey('analysis-calendar-$date2')),
      );
      await tester.tap(find.byKey(ValueKey('analysis-calendar-$date2')));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.byType(ButlerlyRecordRow), findsNWidgets(4));
      // The row is the primary drill-down control; the former View
      // transactions link is intentionally absent.
      await tester.tap(find.text('Item 4'));
      expect(find.text('View transactions'), findsNothing);
      expect(selectedTransaction?.id, 'transaction-4');
      expect(requestedMonths, hasLength(1));
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
