import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'analysis keeps legacy transaction dates after trimming persisted text',
    () async {
      final at = DateTime.utc(2026, 7, 15, 12);
      final transaction = Transaction(
        id: TransactionId('legacy-date'),
        timing: KnownTransactionTime(at),
        money: Money(
          amount: DecimalValue.parse('10'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.import,
        provenance: [
          Provenance(
            id: ProvenanceId('legacy-date-provenance'),
            sourceType: ProvenanceSourceType.import,
            capturedAt: at,
            originalRepresentation: 'legacy-date',
          ),
        ],
        transactionDate: ' 2026-07-15 ',
        createdAt: at,
        updatedAt: at,
      );
      final result =
          await AnalysisDatasetBuilder(
            _Transactions([transaction]),
            _Preferences(),
            null,
          ).build(
            AnalysisContext(
              period: AnalysisPeriod(
                startDate: '2026-07-01',
                endDate: '2026-07-31',
                timeZoneId: 'UTC',
              ),
              datasetMode: DatasetMode.allEligible,
              currencyBasis: CurrencyBasis.baseCurrency,
              baseCurrency: CurrencyCode('USD'),
            ),
          );

      final dataset = (result as ApplicationDatasetSuccess).dataset;
      expect(
        dataset
            .primaryTransactionsByPeriod['selected_period']!
            .single
            .transactionDate,
        '2026-07-15',
      );
    },
  );

  test('fromResults keeps the shared multi-rule insight ranking', () {
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-07-01',
        endDate: '2026-07-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: CurrencyCode('USD'),
    );
    final patternRule = _insightRule(
      'ANL-R021',
      outputType: InsightOutputType.pattern,
      severity: RuleSeverity.warning,
    );
    final alertRule = _insightRule(
      'ANL-R024',
      outputType: InsightOutputType.alert,
      severity: RuleSeverity.attention,
    );
    final useCase = CalculateInsights(
      CalculateAnalysisOverview(
        _Rules(),
        AnalysisDatasetBuilder(_Transactions(), _Preferences(), null),
        const AnalysisRuleEngine(),
      ),
    );

    final evaluation = useCase.fromResults(context, [
      RuleExecutionResult(
        rule: patternRule,
        finding: _finding(patternRule, context, 'pattern'),
      ),
      RuleExecutionResult(
        rule: alertRule,
        finding: _finding(alertRule, context, 'alert'),
      ),
    ]);

    expect(
      evaluation.activeFindings.map((result) => result.rule.identity.value),
      ['ANL-R024', 'ANL-R021'],
    );
  });
}

AnalysisRuleDefinition _insightRule(
  String id, {
  required InsightOutputType outputType,
  required RuleSeverity severity,
}) => AnalysisRuleDefinition(
  identity: RuleIdentity(id),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: 'analysis.$id.name',
  descriptionKey: 'analysis.$id.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.previousEquivalentPeriod,
  condition: const RuleCondition(operator: 'none'),
  severity: severity,
  surface: AnalysisSurface.insights,
  outputType: outputType,
  resultPersistence: ResultPersistencePolicy.finding,
  definitionHash: RuleDefinitionHash('a' * 64),
);

AnalysisFinding _finding(
  AnalysisRuleDefinition rule,
  AnalysisContext context,
  String suffix,
) => AnalysisFinding(
  id: 'finding-$suffix',
  rule: rule,
  context: context,
  severity: rule.severity,
  lifecycle: FindingLifecycle.active,
  generatedAt: DateTime.utc(2026, 8, 1),
);

final class _Rules implements AnalysisRuleRepository {
  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => const [];

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => const [];

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

final class _Transactions implements TransactionRepository {
  const _Transactions([this.values = const []]);

  final List<Transaction> values;

  @override
  Future<Transaction?> findById(TransactionId id) async => null;

  @override
  Future<List<Transaction>> listAll() async => values;

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      const [];

  @override
  Future<void> removePermanently(TransactionId id) async {}

  @override
  Future<void> save(Transaction transaction) async {}
}

final class _Preferences implements UserPreferenceRepository {
  @override
  Future<UserPreference?> load() async => UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: 'UTC',
  );

  @override
  Future<void> save(UserPreference preference) async {}
}
