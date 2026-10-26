import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('Insights does not publish partial FX amounts as complete totals', () {
    final fxIssue = DataQualityIssue(
      code: 'missingFx',
      detail: 'Missing conversion',
      transactionId: TransactionId('foreign'),
    );
    final results = [
      _result(
        'ANL-R701',
        AnalysisSemanticRole.expenseTotal,
        '10',
        availability: AnalysisDataAvailability.insufficient,
        comparison: _comparison('10', '5'),
        issue: fxIssue,
      ),
      _result('ANL-R702', AnalysisSemanticRole.incomeTotal, '20'),
      _result(
        'ANL-R703',
        AnalysisSemanticRole.netCashFlow,
        '10',
        availability: AnalysisDataAvailability.insufficient,
      ),
      _result(
        'ANL-R704',
        AnalysisSemanticRole.eligibleTransactionCount,
        '2',
        transactionCount: 2,
      ),
    ];

    final summary = _insights().fromResults(_context, results).summary;
    expect(summary.expenseSpending, isNull);
    expect(summary.income, DecimalValue.parse('20'));
    expect(summary.netCashFlow, isNull);
    expect(summary.eligibleTransactionCount, 2);
    expect(summary.expenseChange, isNull);
    expect(summary.netCashFlowChange?.baselineValue, isNull);
    expect(summary.comparisonAvailable, isFalse);
    expect(summary.comparisonUnavailableReason, contains('normalized'));
    expect(
      summary.limitations.any((value) => value.code == 'missingFx'),
      isTrue,
    );
  });

  test('empty valid spending remains zero and baseline is comparable', () {
    final summary = _insights().fromResults(_context, [
      _result(
        'ANL-R701',
        AnalysisSemanticRole.expenseTotal,
        '0',
        availability: AnalysisDataAvailability.empty,
        comparison: _comparison('0', '0'),
      ),
      _result(
        'ANL-R702',
        AnalysisSemanticRole.incomeTotal,
        '20',
        comparison: _comparison('20', '10'),
      ),
      _result('ANL-R703', AnalysisSemanticRole.netCashFlow, '20'),
    ]).summary;

    expect(summary.expenseSpending, DecimalValue.parse('0'));
    expect(summary.netCashFlow, DecimalValue.parse('20'));
    expect(summary.expenseChange?.baselineValue, DecimalValue.parse('0'));
    expect(summary.comparisonAvailable, isTrue);
    expect(summary.comparisonUnavailableReason, isNull);
    expect(summary.netCashFlowChange?.baselineValue, DecimalValue.parse('10'));
  });

  test('net comparison does not assume a missing baseline means zero', () {
    final summary = _insights().fromResults(_context, [
      _result(
        'ANL-R701',
        AnalysisSemanticRole.expenseTotal,
        '5',
        comparison: _comparison('5', '7'),
      ),
      _result('ANL-R702', AnalysisSemanticRole.incomeTotal, '15'),
      _result('ANL-R703', AnalysisSemanticRole.netCashFlow, '10'),
    ]).summary;

    expect(summary.comparisonAvailable, isTrue);
    expect(summary.netCashFlowChange?.baselineValue, isNull);
    expect(
      summary.netCashFlowChange?.availability,
      AnalysisDataAvailability.insufficient,
    );
  });
}

final _context = AnalysisContext(
  period: AnalysisPeriod(
    startDate: '2026-10-01',
    endDate: '2026-10-31',
    timeZoneId: 'UTC',
  ),
  datasetMode: DatasetMode.allEligible,
  currencyBasis: CurrencyBasis.baseCurrency,
  baseCurrency: CurrencyCode('USD'),
);

CalculateInsights _insights() => CalculateInsights(
  CalculateAnalysisOverview(
    _UnusedAnalysisRules(),
    AnalysisDatasetBuilder(
      _UnusedTransactions(),
      _UnusedPreferences(),
      null,
    ),
    const AnalysisRuleEngine(),
  ),
);

AnalysisComparison _comparison(String current, String baseline) =>
    AnalysisComparison(
      currentValue: DecimalValue.parse(current),
      baselineValue: DecimalValue.parse(baseline),
      availability: AnalysisDataAvailability.sufficient,
    );

RuleExecutionResult _result(
  String ruleId,
  String role,
  String value, {
  AnalysisDataAvailability availability = AnalysisDataAvailability.sufficient,
  AnalysisComparison? comparison,
  DataQualityIssue? issue,
  int transactionCount = 0,
}) {
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity(ruleId),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'test',
    descriptionKey: 'test',
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
    definitionHash: RuleDefinitionHash('a' * 64),
    role: role,
  );
  return RuleExecutionResult(
    rule: rule,
    metric: AnalysisMetric(
      id: ruleId,
      rule: rule,
      context: _context,
      value: DecimalValue.parse(value),
      currency: CurrencyCode('USD'),
      availability: availability,
      transactionCount: transactionCount,
      qualityIssues: issue == null ? const [] : [issue],
      calculatedAt: DateTime.utc(2026, 10, 26),
    ),
    comparison: comparison,
  );
}

// The projection is tested without calling any repositories. Keep these
// separate because transaction and preference repositories have different
// save method signatures.
final class _UnusedAnalysisRules implements AnalysisRuleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _UnusedTransactions implements TransactionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _UnusedPreferences implements UserPreferenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
