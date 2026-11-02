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

  test('projects the transaction-count prior-period comparison', () {
    final count = _result(
      'ANL-R704',
      '12',
      role: AnalysisSemanticRole.eligibleTransactionCount,
    );
    final comparison = AnalysisComparison(
      currentValue: DecimalValue.parse('12'),
      baselineValue: DecimalValue.parse('8'),
      absoluteChange: DecimalValue.parse('4'),
      percentageChange: DecimalValue.parse('50'),
      availability: AnalysisDataAvailability.sufficient,
    );
    final overview = AnalysisOverview.fromResults([
      RuleExecutionResult(
        rule: count.rule,
        metric: count.metric,
        comparison: comparison,
      ),
    ]);

    expect(overview.transactionCount?.value, DecimalValue.parse('12'));
    expect(overview.transactionCountComparison, same(comparison));
  });

  test('derives savings and category shares from authoritative metrics', () {
    final spending = _result(
      'ANL-R701',
      '60',
      role: AnalysisSemanticRole.expenseTotal,
    );
    final income = _result(
      'ANL-R702',
      '100',
      role: AnalysisSemanticRole.incomeTotal,
    );
    final groceries = _result(
      'ANL-R703',
      '25',
      surface: AnalysisSurface.spending,
      grouping: RuleGrouping.category,
      dimension: 'category.groceries',
    );

    final overview = AnalysisOverview.fromResults([
      spending,
      income,
      groceries,
    ]);

    expect(overview.savings?.value, DecimalValue.parse('40'));
    expect(overview.savings?.currency, CurrencyCode('USD'));
    expect(overview.savingsRate, DecimalValue.parse('0.4'));
    expect(
      overview.categoryShares['ANL-R703:category.groceries'],
      DecimalValue.parse('0.416666'),
    );
  });

  test('derives a percentage for every available normalized category only', () {
    final spending = _result(
      'ANL-R701',
      '100',
      role: AnalysisSemanticRole.expenseTotal,
    );
    final groceries = _result(
      'ANL-R703',
      '25',
      surface: AnalysisSurface.spending,
      grouping: RuleGrouping.category,
      dimension: 'category.groceries',
    );
    final transport = _result(
      'ANL-R704',
      '75',
      surface: AnalysisSurface.spending,
      grouping: RuleGrouping.category,
      dimension: 'category.transport',
    );
    final unavailable = _result(
      'ANL-R705',
      '50',
      surface: AnalysisSurface.spending,
      grouping: RuleGrouping.category,
      dimension: 'category.unavailable',
      availability: AnalysisDataAvailability.insufficient,
    );

    final overview = AnalysisOverview.fromResults([
      spending,
      groceries,
      transport,
      unavailable,
    ]);

    expect(
      overview.categoryShares['ANL-R703:category.groceries'],
      DecimalValue.parse('0.25'),
    );
    expect(
      overview.categoryShares['ANL-R704:category.transport'],
      DecimalValue.parse('0.75'),
    );
    expect(
      overview.categoryShares.containsKey('ANL-R705:category.unavailable'),
      isFalse,
    );
  });

  test('does not derive a share across different normalized currencies', () {
    final spending = _result(
      'ANL-R701',
      '100',
      role: AnalysisSemanticRole.expenseTotal,
    );
    final foreignCategory = _result(
      'ANL-R706',
      '25',
      surface: AnalysisSurface.spending,
      grouping: RuleGrouping.category,
      dimension: 'category.foreign',
      currency: 'EUR',
    );

    final overview = AnalysisOverview.fromResults([spending, foreignCategory]);

    expect(
      overview.categoryShares.containsKey('ANL-R706:category.foreign'),
      isFalse,
    );
  });

  test(
    'does not derive a share when normalized currency metadata is missing',
    () {
      final spending = _result(
        'ANL-R701',
        '100',
        role: AnalysisSemanticRole.expenseTotal,
        currency: null,
      );
      final category = _result(
        'ANL-R706',
        '25',
        surface: AnalysisSurface.spending,
        grouping: RuleGrouping.category,
        dimension: 'category.unknown-currency',
        currency: null,
      );

      final overview = AnalysisOverview.fromResults([spending, category]);

      expect(
        overview.categoryShares.containsKey(
          'ANL-R706:category.unknown-currency',
        ),
        isFalse,
      );
    },
  );

  test('does not derive a share from original-currency metrics', () {
    final spending = _result(
      'ANL-R701',
      '100',
      role: AnalysisSemanticRole.expenseTotal,
      currencyBasis: CurrencyBasis.original,
    );
    final category = _result(
      'ANL-R706',
      '25',
      surface: AnalysisSurface.spending,
      grouping: RuleGrouping.category,
      dimension: 'category.original-currency',
      currencyBasis: CurrencyBasis.original,
    );

    final overview = AnalysisOverview.fromResults([spending, category]);

    expect(
      overview.categoryShares.containsKey(
        'ANL-R706:category.original-currency',
      ),
      isFalse,
    );
  });

  test(
    'marks derived savings unavailable when source data is insufficient',
    () {
      final spending = _result(
        'ANL-R701',
        '60',
        role: AnalysisSemanticRole.expenseTotal,
        availability: AnalysisDataAvailability.insufficient,
      );
      final income = _result(
        'ANL-R702',
        '100',
        role: AnalysisSemanticRole.incomeTotal,
      );

      final overview = AnalysisOverview.fromResults([spending, income]);

      expect(
        overview.savings?.availability,
        AnalysisDataAvailability.insufficient,
      );
      expect(overview.savingsRate, isNull);
    },
  );

  test('treats empty spending as zero when deriving savings', () {
    final spending = _result(
      'ANL-R701',
      '0',
      role: AnalysisSemanticRole.expenseTotal,
      availability: AnalysisDataAvailability.empty,
    );
    final income = _result(
      'ANL-R702',
      '100',
      role: AnalysisSemanticRole.incomeTotal,
    );

    final overview = AnalysisOverview.fromResults([spending, income]);

    expect(overview.savings?.value, DecimalValue.parse('100'));
    expect(overview.savings?.availability, AnalysisDataAvailability.sufficient);
    expect(overview.savingsRate, DecimalValue.parse('1'));
  });

  test('treats empty income as zero when deriving savings', () {
    final spending = _result(
      'ANL-R701',
      '60',
      role: AnalysisSemanticRole.expenseTotal,
    );
    final income = _result(
      'ANL-R702',
      '0',
      role: AnalysisSemanticRole.incomeTotal,
      availability: AnalysisDataAvailability.empty,
    );

    final overview = AnalysisOverview.fromResults([spending, income]);

    expect(overview.savings?.value, DecimalValue.parse('-60'));
    expect(overview.savings?.availability, AnalysisDataAvailability.sufficient);
    expect(overview.savingsRate, isNull);
  });

  test(
    'keeps derived savings insufficient when either source is insufficient',
    () {
      final spending = _result(
        'ANL-R701',
        '60',
        role: AnalysisSemanticRole.expenseTotal,
      );
      final income = _result(
        'ANL-R702',
        '100',
        role: AnalysisSemanticRole.incomeTotal,
        availability: AnalysisDataAvailability.insufficient,
      );

      final overview = AnalysisOverview.fromResults([spending, income]);

      expect(
        overview.savings?.availability,
        AnalysisDataAvailability.insufficient,
      );
      expect(overview.savingsRate, isNull);
    },
  );

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
  AnalysisDataAvailability availability = AnalysisDataAvailability.sufficient,
  String? currency = 'USD',
  CurrencyBasis currencyBasis = CurrencyBasis.baseCurrency,
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
    measure: RuleMeasure(
      operation: RuleOperation.sum,
      field: 'amount',
      currencyBasis: currencyBasis,
    ),
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
    currencyBasis: currencyBasis,
    baseCurrency: currency == null ? null : CurrencyCode(currency),
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
      availability: availability,
    ),
  );
}
