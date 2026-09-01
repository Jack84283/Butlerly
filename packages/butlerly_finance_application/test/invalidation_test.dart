import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final findings = _Findings();

  AnalysisRuleDefinition rule(
    String id, {
    RuleMeasure? measure,
    List<RuleMeasure> measures = const [],
    List<RuleDependency> dependencies = const [],
    AnalysisRuleType type = AnalysisRuleType.metric,
  }) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: type,
    nameKey: 'name',
    descriptionKey: 'description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: measure ?? const RuleMeasure(
      operation: RuleOperation.sum,
      field: 'amount',
    ),
    measures: measures,
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    dependencies: dependencies,
    definitionHash: RuleDefinitionHash('b' * 64),
    resultPersistence: ResultPersistencePolicy.materialized,
  );

  Future<Set<String>> invalidate(
    AnalysisInvalidationReason reason,
    List<AnalysisRuleDefinition> rules,
  ) async {
    final results = _Results();
    final repository = _Rules(rules);
    final outcome = await InvalidateAnalysis(
      findings,
      results: results,
      rules: repository,
    ).call(
      reason,
      DateTime.utc(2026, 8, 15),
      periodStart: '2026-08-01',
      periodEnd: '2026-08-31',
    );
    expect(outcome, isA<ApplicationSuccess<void>>());
    return results.ruleIds;
  }

  test('invalidates a singular amount measure', () async {
    expect(
      await invalidate(
        AnalysisInvalidationReason.transactionAmountChanged,
        [rule('ANL-R001')],
      ),
      {'ANL-R001'},
    );
  });

  test('invalidates singular base-currency measures for FX and base changes', () async {
    final base = rule(
      'ANL-R001',
      measure: const RuleMeasure(
        operation: RuleOperation.sum,
        field: 'amount',
        currencyBasis: CurrencyBasis.baseCurrency,
      ),
    );
    expect(await invalidate(AnalysisInvalidationReason.exchangeRateChanged, [base]), {'ANL-R001'});
    expect(await invalidate(AnalysisInvalidationReason.baseCurrencyChanged, [base]), {'ANL-R001'});
  });

  test('retains multi-measure support and propagates to dependents', () async {
    final root = rule(
      'ANL-R001',
      measures: const [RuleMeasure(operation: RuleOperation.sum, field: 'amount')],
    );
    final dependent = rule(
      'ANL-R002',
      type: AnalysisRuleType.insight,
      dependencies: [RuleDependency(ruleId: RuleIdentity('ANL-R001'))],
    );
    final grandchild = rule(
      'ANL-R003',
      dependencies: [RuleDependency(ruleId: RuleIdentity('ANL-R002'))],
    );
    expect(
      await invalidate(AnalysisInvalidationReason.transactionAmountChanged, [root, dependent, grandchild]),
      {'ANL-R001', 'ANL-R002', 'ANL-R003'},
    );
  });

  test('leaves unrelated rules out of a narrow invalidation scope', () async {
    final unrelated = rule(
      'ANL-R004',
      measure: const RuleMeasure(operation: RuleOperation.count, field: 'transaction'),
    );
    expect(
      await invalidate(AnalysisInvalidationReason.transactionAmountChanged, [unrelated]),
      isEmpty,
    );
  });
}

final class _Results implements AnalysisRuleResultRepository {
  Set<String> ruleIds = {};

  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async => const [];

  @override
  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  }) async => null;

  @override
  Future<void> save(AnalysisRuleResult result) async {}

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async => ruleIds == null ? ruleIds = {} : this.ruleIds = ruleIds;
}

final class _Rules implements AnalysisRuleRepository {
  _Rules(this.values);
  final List<AnalysisRuleDefinition> values;

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => values;
  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => values;
  @override
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id) async => null;
  @override
  Future<void> activate(RuleIdentity id, RuleVersion version, bool enabled, DateTime at) async {}
  @override
  Future<void> install(AnalysisRuleDefinition definition, {required String sourceType, required String canonicalDefinition}) async {}
}

final class _Findings implements AnalysisFindingRepository {
  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async => const [];
  @override
  Future<void> save(AnalysisFinding finding) async {}
  @override
  Future<void> updateLifecycle(String id, FindingLifecycle lifecycle, DateTime at) async {}
}
