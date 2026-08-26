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

  test('count measures are dimensionless and retain drill-down evidence', () {
    final count = rule('ANL-R004', RuleOperation.count);
    final metric = const AnalysisRuleEngine()
        .execute(dataset: dataset(), definitions: [count])
        .single
        .metric!;
    expect(metric.value, DecimalValue.parse('2'));
    expect(metric.currency, isNull);
    expect(metric.evidence.map((value) => value.transactionId.value), [
      't1',
      't2',
    ]);
  });

  test('base-currency measures use original same-currency money', () {
    final usd = CurrencyCode('USD');
    final baseContext = AnalysisContext(
      period: context.period,
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: usd,
    );
    final definition = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R016'),
      version: RuleVersion('1.1.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'daily',
      descriptionKey: 'daily.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_month',
      measure: const RuleMeasure(
        operation: RuleOperation.sum,
        field: 'amount',
        currencyBasis: CurrencyBasis.baseCurrency,
      ),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('2' * 64),
    );
    final metric = const AnalysisRuleEngine()
        .execute(
          dataset: AnalysisDataset(
            context: baseContext,
            transactions: dataset().transactions,
          ),
          definitions: [definition],
        )
        .single
        .metric!;
    expect(metric.value, DecimalValue.parse('35'));
    expect(metric.currency, usd);
    expect(metric.transactionCount, 2);
  });

  test('measure filters apply every supported filter kind', () {
    final transaction = AnalysisEconomicTransaction(
      id: TransactionId('filtered'),
      money: Money(
        amount: DecimalValue.parse('7'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      transactionDate: '2026-01-02',
      categoryId: CategoryId('category'),
      merchantId: MerchantId('merchant'),
      paymentSourceId: PaymentSourceId('source'),
      tagIds: [TagId('tag')],
      verified: true,
    );
    for (final filter in <AnalysisFilter>[
      const AnalysisFilter(
        kind: AnalysisFilterKind.direction,
        values: ['income'],
      ),
      const AnalysisFilter(kind: AnalysisFilterKind.currency, values: ['EUR']),
      const AnalysisFilter(
        kind: AnalysisFilterKind.category,
        values: ['other'],
      ),
      const AnalysisFilter(
        kind: AnalysisFilterKind.merchant,
        values: ['other'],
      ),
      const AnalysisFilter(
        kind: AnalysisFilterKind.paymentSource,
        values: ['other'],
      ),
      const AnalysisFilter(kind: AnalysisFilterKind.tag, values: ['other']),
      const AnalysisFilter(
        kind: AnalysisFilterKind.reviewState,
        values: ['needsReview'],
      ),
      const AnalysisFilter(
        kind: AnalysisFilterKind.status,
        values: ['archived'],
      ),
    ]) {
      final definition = rule('ANL-R001', RuleOperation.count);
      final filteredDefinition = AnalysisRuleDefinition(
        identity: definition.identity,
        version: definition.version,
        schemaVersion: definition.schemaVersion,
        type: definition.type,
        nameKey: definition.nameKey,
        descriptionKey: definition.descriptionKey,
        enabled: definition.enabled,
        status: definition.status,
        period: definition.period,
        measure: RuleMeasure(
          operation: RuleOperation.count,
          field: 'transaction',
          filters: [filter],
        ),
        measures: [
          RuleMeasure(
            operation: RuleOperation.count,
            field: 'transaction',
            filters: [filter],
          ),
        ],
        grouping: definition.grouping,
        baseline: definition.baseline,
        condition: definition.condition,
        severity: definition.severity,
        definitionHash: definition.definitionHash,
      );
      final metric = const AnalysisRuleEngine()
          .execute(
            dataset: AnalysisDataset(
              context: context,
              transactions: [transaction],
            ),
            definitions: [filteredDefinition],
          )
          .single
          .metric!;
      expect(metric.value, DecimalValue.parse('0'), reason: filter.kind.name);
    }
  });

  test('each distinct-count measure uses its own declared field', () {
    final definition = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R016'),
      version: RuleVersion('1.1.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'distinct',
      descriptionKey: 'distinct.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(
        operation: RuleOperation.distinctCount,
        field: 'transaction',
        key: 'transactions',
      ),
      measures: const [
        RuleMeasure(
          operation: RuleOperation.distinctCount,
          field: 'transaction',
          key: 'transactions',
        ),
        RuleMeasure(
          operation: RuleOperation.distinctCount,
          field: 'category',
          key: 'categories',
        ),
      ],
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('3' * 64),
    );
    final results = const AnalysisRuleEngine().execute(
      dataset: AnalysisDataset(
        context: context,
        transactions: [
          for (var index = 0; index < 2; index++)
            AnalysisEconomicTransaction(
              id: TransactionId('distinct-$index'),
              money: Money(
                amount: DecimalValue.parse('1'),
                currency: CurrencyCode('USD'),
              ),
              direction: TransactionDirection.expense,
              transactionDate: '2026-01-02',
              categoryId: CategoryId('shared-category'),
            ),
        ],
      ),
      definitions: [definition],
    );
    expect(results[0].metric!.value, DecimalValue.parse('2'));
    expect(results[1].metric!.value, DecimalValue.parse('1'));
  });

  test(
    'generic grouped multi-measures apply independent direction filters',
    () {
      final daily = AnalysisRuleDefinition(
        identity: RuleIdentity('ANL-R016'),
        version: RuleVersion('1.1.0'),
        schemaVersion: '1.0.0',
        type: AnalysisRuleType.metric,
        nameKey: 'daily',
        descriptionKey: 'daily.description',
        enabled: true,
        status: AnalysisRuleStatus.active,
        period: 'selected_period',
        measure: const RuleMeasure(
          operation: RuleOperation.count,
          field: 'transaction',
        ),
        measures: const [
          RuleMeasure(
            operation: RuleOperation.count,
            field: 'transaction',
            key: 'transactionCount',
          ),
          RuleMeasure(
            operation: RuleOperation.sum,
            field: 'amount',
            key: 'expenseTotal',
            filters: [
              AnalysisFilter(
                kind: AnalysisFilterKind.direction,
                values: ['expense'],
              ),
            ],
          ),
          RuleMeasure(
            operation: RuleOperation.sum,
            field: 'amount',
            key: 'incomeTotal',
            filters: [
              AnalysisFilter(
                kind: AnalysisFilterKind.direction,
                values: ['income'],
              ),
            ],
          ),
        ],
        grouping: RuleGrouping.day,
        baseline: RuleBaseline.none,
        condition: const RuleCondition(operator: 'none'),
        severity: RuleSeverity.info,
        surface: AnalysisSurface.calendar,
        definitionHash: RuleDefinitionHash('1' * 64),
      );
      final results = const AnalysisRuleEngine().execute(
        dataset: AnalysisDataset(
          context: context,
          transactions: [
            ...dataset().transactions,
            AnalysisEconomicTransaction(
              id: TransactionId('t3'),
              money: Money(
                amount: DecimalValue.parse('5'),
                currency: CurrencyCode('USD'),
              ),
              direction: TransactionDirection.expense,
              transactionDate: '2026-01-02',
            ),
          ],
        ),
        definitions: [daily],
      );
      expect(results, hasLength(6));
      AnalysisMetric metric(String dimension) => results
          .singleWhere((value) => value.metric!.dimension == dimension)
          .metric!;
      expect(
        metric('2026-01-02:transactionCount').value,
        DecimalValue.parse('2'),
      );
      expect(metric('2026-01-02:transactionCount').currency, isNull);
      expect(metric('2026-01-02:expenseTotal').value, DecimalValue.parse('15'));
      expect(metric('2026-01-03:incomeTotal').value, DecimalValue.parse('25'));
      expect(metric('2026-01-02:incomeTotal').value, DecimalValue.parse('0'));
    },
  );
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
