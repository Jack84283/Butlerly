import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('concentration insight does not require baseline category history', () {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-09-01',
        endDate: '2026-09-10',
        timeZoneId: 'America/Los_Angeles',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: CurrencyCode('USD'),
      periodType: 'selected_period',
    );

    AnalysisEconomicTransaction expense(
      String id,
      String amount,
      String category,
    ) => AnalysisEconomicTransaction(
      id: TransactionId(id),
      money: Money(
        amount: DecimalValue.parse(amount),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      transactionDate: '2026-09-05',
      categoryId: CategoryId(category),
    );

    final travel = expense('travel-1', '70', 'travel');
    final food = expense('food-1', '30', 'food');
    final current = [travel, food];

    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R026'),
      version: RuleVersion('1.1.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.r026.name',
      descriptionKey: 'analysis.rule.r026.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(
        operation: RuleOperation.share,
        field: 'amount',
        currencyBasis: CurrencyBasis.baseCurrency,
      ),
      grouping: RuleGrouping.category,
      baseline: RuleBaseline.none,
      condition: RuleCondition(
        operator: 'gte',
        left: 'value',
        value: DecimalValue.fromParts(
          coefficient: BigInt.from(50),
          scale: 0,
        ),
      ),
      severity: RuleSeverity.attention,
      surface: AnalysisSurface.insights,
      outputType: InsightOutputType.pattern,
      resultPersistence: ResultPersistencePolicy.finding,
      definitionHash: RuleDefinitionHash('6' * 64),
      filters: [
        AnalysisFilter(
          kind: AnalysisFilterKind.direction,
          values: ['expense'],
        ),
      ],
    );

    final results = const AnalysisRuleEngine().execute(
      dataset: AnalysisDataset(
        context: context,
        transactions: current,
        primaryTransactionsByPeriod: {'selected_period': current},
        // No travel transaction exists in baseline history. Concentration is
        // structural and must still be evaluated from the current period.
        baselineTransactions: const [],
      ),
      definitions: [rule],
    );

    final travelResult = results.singleWhere(
      (result) => result.finding?.dimension == 'travel',
    );
    expect(travelResult.finding, isNotNull);
    expect(travelResult.finding!.currentValue, DecimalValue.parse('70'));
    expect(travelResult.finding!.baselineValue, isNull);
    expect(travelResult.finding!.percentageChange, isNull);
    expect(travelResult.comparison, isNull);
    expect(
      travelResult.issues.map((issue) => issue.code),
      isNot(contains('missingBaseline')),
    );

    final foodResult = results.singleWhere(
      (result) => result.finding?.dimension != 'travel',
    );
    expect(foodResult.finding, isNull);
    expect(foodResult.comparison, isNull);
  });
}
