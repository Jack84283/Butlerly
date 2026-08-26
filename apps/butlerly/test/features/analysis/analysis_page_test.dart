import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(
    Future<ApplicationResult<List<RuleExecutionResult>>> Function() load, {
    Future<ApplicationResult<AnalysisCalendarResult>> Function(int, int)?
    loadCalendar,
    Future<ApplicationResult<List<TransactionDto>>> Function(String)?
    loadTransactionsForDate,
  }) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: AnalysisPage(
      load: load,
      loadCalendar: loadCalendar,
      loadTransactionsForDate: loadTransactionsForDate,
    ),
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
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('No findings'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Calculated privately on this device and available offline.',
      ),
      findsAtLeastNWidgets(1),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/analysis_empty_390x844.png'),
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
    expect(find.text('No findings'), findsNothing);
    expect(find.text('Insights are unavailable'), findsOneWidget);
  });

  testWidgets('localizes a bundled rule name', (tester) async {
    const localizations = AppLocalizations(Locale('es'));
    expect(localizations.text('analysis.rule.r001.name'), 'Gastos');
    expect(
      localizations.text('analysis.rule.r001.name'),
      isNot('analysis.rule.r001.name'),
    );
  });

  testWidgets(
    'calendar navigates months, selects empty dates, and lists drill-down rows',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requestedMonths = <String>[];
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
                    TransactionDto(
                      id: 'transaction-1',
                      amount: '12.00',
                      currency: 'USD',
                      direction: 'expense',
                      status: 'active',
                      reviewState: 'clear',
                      transactionDate: date,
                      description: 'Groceries',
                      createdAt: DateTime.utc(2026),
                      updatedAt: DateTime.utc(2026),
                    ),
                  ]
                : const [],
          ),
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
      expect(
        find.byKey(
          const ValueKey('analysis-calendar-transaction-transaction-1'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('analysis-calendar-previous')),
      );
      await tester.tap(
        find.byKey(const ValueKey('analysis-calendar-previous')),
      );
      await tester.pumpAndSettle();
      expect(requestedMonths, hasLength(2));
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
    expect(find.text('Data quality issues'), findsOneWidget);
    expect(find.text('1 supporting transactions'), findsOneWidget);
    expect(find.textContaining('1'), findsWidgets);
    await tester.tap(find.text('Data quality issues'));
    await tester.pumpAndSettle();
    expect(find.text('t1'), findsOneWidget);
  });
}
