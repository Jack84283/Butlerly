import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('summary selection follows semantic roles, not bundled IDs', () {
    final expense = _result(
      'ANL-R701',
      '12.34',
      role: AnalysisSemanticRole.expenseTotal,
    );
    final income = _result(
      'ANL-R702',
      '20',
      role: AnalysisSemanticRole.incomeTotal,
    );
    final net = _result(
      'ANL-R703',
      '7.66',
      role: AnalysisSemanticRole.netCashFlow,
    );
    final count = _result(
      'ANL-R704',
      '3',
      role: AnalysisSemanticRole.eligibleTransactionCount,
    );
    final wrongRole = _result('ANL-R001', '999', role: 'unrelated');
    final overview = AnalysisOverview.fromResults([
      wrongRole,
      count,
      income,
      net,
      expense,
    ]);
    expect(overview.spending, same(expense.metric));
    expect(overview.income, same(income.metric));
    expect(overview.net, same(net.metric));
    expect(overview.transactionCount, same(count.metric));
  });

  test(
    'category sorting remains exact beyond binary floating-point precision',
    () {
      final low = _result(
        'ANL-R705',
        '9007199254740993.01',
        surface: AnalysisSurface.spending,
        grouping: RuleGrouping.category,
        dimension: 'low',
      );
      final high = _result(
        'ANL-R705',
        '9007199254740993.02',
        surface: AnalysisSurface.spending,
        grouping: RuleGrouping.category,
        dimension: 'high',
      );
      expect(AnalysisOverview.fromResults([low, high]).categories, [
        high.metric,
        low.metric,
      ]);
    },
  );

  test('trends follow declared surface and preserve period order', () {
    final later = _result(
      'ANL-R706',
      '2',
      surface: AnalysisSurface.trends,
      dimension: '2026-02',
    );
    final earlier = _result(
      'ANL-R706',
      '1',
      surface: AnalysisSurface.trends,
      dimension: '2026-01',
    );
    expect(AnalysisOverview.fromResults([later, earlier]).trend, [
      earlier.metric,
      later.metric,
    ]);
  });

  test('empty and failed evaluations cannot claim an evaluated all-clear', () {
    expect(AnalysisOverview.fromResults([]).qualityEvaluated, isFalse);
    final rule = _result('ANL-R707', '0').rule;
    final overview = AnalysisOverview.fromResults([
      RuleExecutionResult(
        rule: rule,
        failure: const AnalysisFailure(
          code: 'unavailable',
          message: 'unavailable',
        ),
      ),
    ]);
    expect(overview.qualityLimited, isTrue);
    expect(overview.qualityCount, 1);
    expect(overview.spending, isNull);
  });
}

RuleExecutionResult _result(
  String id,
  String value, {
  String? role,
  AnalysisSurface surface = AnalysisSurface.overview,
  RuleGrouping grouping = RuleGrouping.none,
  String? dimension,
}) {
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'metric',
    descriptionKey: 'metric',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
    grouping: grouping,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('a' * 64),
    role: role,
    surface: surface,
  );
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-01-01',
      endDate: '2026-02-28',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  );
  return RuleExecutionResult(
    rule: rule,
    metric: AnalysisMetric(
      id: '$id:$dimension',
      rule: rule,
      context: context,
      value: DecimalValue.parse(value),
      dimension: dimension,
      calculatedAt: DateTime.utc(2026),
    ),
  );
}
