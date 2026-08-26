import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-01-01',
      endDate: '2026-01-31',
      timeZoneId: 'Asia/Shanghai',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.original,
  );
  AnalysisRuleDefinition rule(
    String id,
    RuleOperation operation, {
    List<RuleDependency> dependencies = const [],
    List<AnalysisFilter> filters = const [],
    RuleGrouping grouping = RuleGrouping.none,
  }) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'name',
    descriptionKey: 'description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'currentPeriod',
    measure: RuleMeasure(operation: operation, field: 'amount'),
    grouping: grouping,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    dependencies: dependencies,
    filters: filters,
    definitionHash: RuleDefinitionHash(
      '0000000000000000000000000000000000000000000000000000000000000000',
    ),
  );
  AnalysisDataset dataset() => AnalysisDataset(
    context: context,
    transactions: [
      AnalysisEconomicTransaction(
        id: TransactionId('t1'),
        money: Money(
          amount: DecimalValue.parse('10'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        transactionDate: '2026-01-02',
      ),
      AnalysisEconomicTransaction(
        id: TransactionId('t2'),
        money: Money(
          amount: DecimalValue.parse('25'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.income,
        transactionDate: '2026-01-03',
      ),
    ],
  );

  test('applies direction filters and exact decimal sums', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(),
      definitions: [
        rule(
          'ANL-R001',
          RuleOperation.sum,
          filters: [
            AnalysisFilter(
              kind: AnalysisFilterKind.direction,
              values: ['expense'],
            ),
          ],
        ),
      ],
    );
    expect(result.single.metric!.value, DecimalValue.parse('10'));
  });

  test('executes declared dependencies before difference', () {
    final expense = rule(
      'ANL-R001',
      RuleOperation.sum,
      filters: [
        AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
      ],
    );
    final income = rule(
      'ANL-R002',
      RuleOperation.sum,
      filters: [
        AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['income']),
      ],
    );
    final net = rule(
      'ANL-R003',
      RuleOperation.difference,
      dependencies: [
        RuleDependency(ruleId: RuleIdentity('ANL-R001')),
        RuleDependency(ruleId: RuleIdentity('ANL-R002')),
      ],
    );
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(),
      definitions: [net, income, expense],
    );
    expect(result.last.metric!.value, DecimalValue.parse('15'));
  });

  test(
    'produces structured insight change and leaves zero baseline percentage undefined',
    () {
      final insight = rule(
        'ANL-R020',
        RuleOperation.sum,
      ).copyWithBaseline(RuleBaseline.previousEquivalentPeriod);
      final result = const AnalysisRuleEngine().execute(
        dataset: AnalysisDataset(
          context: context,
          transactions: dataset().transactions,
          baselineTransactions: const [],
        ),
        definitions: [insight.copyWith(type: AnalysisRuleType.insight)],
      );
      expect(result.single.finding, isNotNull);
      expect(result.single.finding!.baselineValue, isNull);
      expect(result.single.finding!.absoluteChange, isNull);
      expect(result.single.finding!.percentageChange, isNull);
      expect(
        result.single.finding!.qualityIssues.single.code,
        'missingBaseline',
      );
    },
  );

  test(
    'period selects the primary dataset while baseline remains independent',
    () {
      final selected = dataset().transactions.sublist(0, 1);
      final previous = dataset().transactions.sublist(1);
      final periodRule = rule(
        'ANL-R030',
        RuleOperation.sum,
      ).copyWithPeriod('selected_month');
      final result = const AnalysisRuleEngine().execute(
        dataset: AnalysisDataset(
          context: context,
          transactions: selected,
          baselineTransactions: previous,
          primaryTransactionsByPeriod: {
            'selected_period': selected,
            'selected_month': previous,
          },
        ),
        definitions: [periodRule],
      );
      expect(result.single.metric!.value, DecimalValue.parse('25'));

      final insight = periodRule
          .copyWithPeriod('selected_period')
          .copyWithType(AnalysisRuleType.insight)
          .copyWithBaseline(RuleBaseline.previousEquivalentPeriod);
      final finding = const AnalysisRuleEngine()
          .execute(
            dataset: AnalysisDataset(
              context: context,
              transactions: selected,
              baselineTransactions: previous,
              primaryTransactionsByPeriod: {
                'selected_period': selected,
                'selected_month': previous,
              },
            ),
            definitions: [insight],
          )
          .single
          .finding!;
      expect(finding.currentValue, DecimalValue.parse('10'));
      expect(finding.baselineValue, DecimalValue.parse('25'));
    },
  );

  test('isolates dependency cycles without suppressing valid rules', () {
    final first = rule(
      'ANL-R030',
      RuleOperation.sum,
      dependencies: [RuleDependency(ruleId: RuleIdentity('ANL-R031'))],
    );
    final second = rule(
      'ANL-R031',
      RuleOperation.sum,
      dependencies: [RuleDependency(ruleId: RuleIdentity('ANL-R030'))],
    );
    final valid = rule('ANL-R001', RuleOperation.count);
    final results = const AnalysisRuleEngine().execute(
      dataset: dataset(),
      definitions: [first, valid, second],
    );
    expect(
      results.where((result) => result.failure?.code == 'dependencyCycle'),
      hasLength(2),
    );
    expect(
      results
          .singleWhere((result) => result.rule.identity.value == 'ANL-R001')
          .metric,
      isNotNull,
    );
  });
}

extension on AnalysisRuleDefinition {
  AnalysisRuleDefinition copyWith({AnalysisRuleType? type}) =>
      AnalysisRuleDefinition(
        identity: identity,
        version: version,
        schemaVersion: schemaVersion,
        type: type ?? this.type,
        nameKey: nameKey,
        descriptionKey: descriptionKey,
        enabled: enabled,
        status: status,
        period: period,
        measure: measure,
        grouping: grouping,
        baseline: baseline,
        condition: condition,
        severity: severity,
        dependencies: dependencies,
        filters: filters,
        definitionHash: definitionHash,
      );

  AnalysisRuleDefinition copyWithBaseline(RuleBaseline baseline) =>
      AnalysisRuleDefinition(
        identity: identity,
        version: version,
        schemaVersion: schemaVersion,
        type: type,
        nameKey: nameKey,
        descriptionKey: descriptionKey,
        enabled: enabled,
        status: status,
        period: period,
        measure: measure,
        grouping: grouping,
        baseline: baseline,
        condition: condition,
        severity: severity,
        dependencies: dependencies,
        filters: filters,
        definitionHash: definitionHash,
      );

  AnalysisRuleDefinition copyWithPeriod(String period) =>
      AnalysisRuleDefinition(
        identity: identity,
        version: version,
        schemaVersion: schemaVersion,
        type: type,
        nameKey: nameKey,
        descriptionKey: descriptionKey,
        enabled: enabled,
        status: status,
        period: period,
        measure: measure,
        grouping: grouping,
        baseline: baseline,
        condition: condition,
        severity: severity,
        dependencies: dependencies,
        filters: filters,
        definitionHash: definitionHash,
      );

  AnalysisRuleDefinition copyWithType(AnalysisRuleType type) =>
      AnalysisRuleDefinition(
        identity: identity,
        version: version,
        schemaVersion: schemaVersion,
        type: type,
        nameKey: nameKey,
        descriptionKey: descriptionKey,
        enabled: enabled,
        status: status,
        period: period,
        measure: measure,
        grouping: grouping,
        baseline: baseline,
        condition: condition,
        severity: severity,
        dependencies: dependencies,
        filters: filters,
        definitionHash: definitionHash,
      );
}
