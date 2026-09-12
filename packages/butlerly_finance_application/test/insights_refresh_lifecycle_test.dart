import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generic transaction invalidation keeps every still-qualifying card active',
    () async {
      final now = DateTime.utc(2026, 9, 5, 12);
      final transactions = _Transactions([
        _transaction('current', '2026-09-01', '120'),
        _transaction('baseline', '2026-08-01', '90'),
      ]);
      final rules = _Rules([
        _insightRule('ANL-R020', '1.10'),
        _insightRule('ANL-R021', '1.20'),
        _insightRule('ANL-R022', '1.30'),
      ]);
      final findings = _Findings();
      final calculate = CalculateAnalysisOverview(
        rules,
        AnalysisDatasetBuilder(transactions, _Preferences(), null),
        const AnalysisRuleEngine(),
        findings: findings,
      );

      final first = await calculate.currentMonth(now);
      final firstResults =
          (first as ApplicationSuccess<List<RuleExecutionResult>>).value;
      expect(firstResults.where((result) => result.finding != null), hasLength(3));
      expect(
        findings.values.where(
          (finding) => finding.lifecycle == FindingLifecycle.active,
        ),
        hasLength(3),
      );

      final invalidated = await InvalidateAnalysis(
        findings,
        rules: rules,
      ).call(AnalysisInvalidationReason.transactionChanged, now);
      expect(invalidated, isA<ApplicationSuccess<void>>());
      expect(
        findings.values.where(
          (finding) => finding.lifecycle == FindingLifecycle.superseded,
        ),
        hasLength(3),
      );

      final recalculated = await calculate.currentMonth(now);
      final recalculatedResults =
          (recalculated as ApplicationSuccess<List<RuleExecutionResult>>).value;
      expect(
        recalculatedResults
            .where((result) => result.finding != null)
            .map((result) => result.finding!.lifecycle),
        everyElement(FindingLifecycle.active),
      );
      expect(
        findings.values.where(
          (finding) => finding.lifecycle == FindingLifecycle.active,
        ),
        hasLength(3),
      );

      transactions.values[0] = _transaction('current', '2026-09-01', '100');
      await InvalidateAnalysis(
        findings,
        rules: rules,
      ).call(AnalysisInvalidationReason.transactionChanged, now);

      final changed = await calculate.currentMonth(now);
      final changedResults =
          (changed as ApplicationSuccess<List<RuleExecutionResult>>).value;
      final activeResults = changedResults
          .where((result) => result.finding != null)
          .toList(growable: false);
      expect(activeResults, hasLength(1));
      expect(activeResults.single.rule.identity.value, 'ANL-R020');
      expect(activeResults.single.finding!.lifecycle, FindingLifecycle.active);
      expect(
        findings.values.where(
          (finding) => finding.lifecycle == FindingLifecycle.active,
        ),
        hasLength(1),
      );
      expect(
        findings.values.where(
          (finding) => finding.lifecycle == FindingLifecycle.superseded,
        ),
        hasLength(2),
      );
    },
  );

  test('dismissed finding remains dismissed across recalculation', () async {
    final now = DateTime.utc(2026, 9, 5, 12);
    final findings = _Findings();
    final calculate = CalculateAnalysisOverview(
      _Rules([_insightRule('ANL-R020', '1.20')]),
      AnalysisDatasetBuilder(
        _Transactions([
          _transaction('current', '2026-09-01', '120'),
          _transaction('baseline', '2026-08-01', '90'),
        ]),
        _Preferences(),
        null,
      ),
      const AnalysisRuleEngine(),
      findings: findings,
    );

    final first = await calculate.currentMonth(now);
    final finding =
        (first as ApplicationSuccess<List<RuleExecutionResult>>)
            .value
            .single
            .finding!;
    await findings.updateLifecycle(
      finding.id,
      FindingLifecycle.dismissed,
      now,
    );

    final recalculated = await calculate.currentMonth(now);
    final recalculatedFinding =
        (recalculated as ApplicationSuccess<List<RuleExecutionResult>>)
            .value
            .single
            .finding!;

    expect(recalculatedFinding.lifecycle, FindingLifecycle.dismissed);
    expect(findings.values.single.lifecycle, FindingLifecycle.dismissed);
  });
}

AnalysisRuleDefinition _insightRule(String id, String multiplier) =>
    AnalysisRuleDefinition(
      identity: RuleIdentity(id),
      version: RuleVersion('1.3.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.${id.toLowerCase()}.name',
      descriptionKey: 'analysis.rule.${id.toLowerCase()}.description',
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
      condition: RuleCondition(
        operator: 'all',
        children: [
          RuleCondition(
            operator: 'gt',
            left: 'currentTotal',
            value: DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0),
          ),
          RuleCondition(
            operator: 'gteMultiplier',
            left: 'currentTotal',
            right: 'baselineTotal',
            value: DecimalValue.parse(multiplier),
          ),
        ],
      ),
      severity: RuleSeverity.attention,
      surface: AnalysisSurface.insights,
      filters: const [
        AnalysisFilter(
          kind: AnalysisFilterKind.direction,
          values: ['expense'],
        ),
      ],
      definitionHash: RuleDefinitionHash(
        switch (id) {
          'ANL-R020' => 'a' * 64,
          'ANL-R021' => 'b' * 64,
          _ => 'c' * 64,
        },
      ),
      resultPersistence: ResultPersistencePolicy.finding,
      refreshPolicy: RefreshPolicy.onInvalidation,
    );

Transaction _transaction(String id, String date, String amount) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(DateTime.utc(2026, 1, 1, 12)),
  money: Money(
    amount: DecimalValue.parse(amount),
    currency: CurrencyCode('USD'),
  ),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: date,
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-$id'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 1, 1, 12),
    ),
  ],
  createdAt: DateTime.utc(2026, 1, 1, 12),
  updatedAt: DateTime.utc(2026, 1, 1, 12),
);

final class _Transactions implements TransactionRepository {
  _Transactions(this.values);
  final List<Transaction> values;

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<Transaction>> listAll() async => values;

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async => values;

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values.removeWhere((value) => value.id == transaction.id);
    values.add(transaction);
  }
}

final class _Preferences implements UserPreferenceRepository {
  @override
  Future<UserPreference?> load() async => UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: 'Asia/Shanghai',
  );

  @override
  Future<void> save(UserPreference preference) async {}
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

final class _Findings implements AnalysisFindingRepository {
  final values = <AnalysisFinding>[];

  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async =>
      values
          .where((value) => lifecycle == null || value.lifecycle == lifecycle)
          .toList(growable: false);

  @override
  Future<void> save(AnalysisFinding finding) async {
    final index = values.indexWhere((value) => value.id == finding.id);
    if (index == -1) {
      values.add(finding);
      return;
    }
    final existing = values[index];
    final lifecycle = switch (existing.lifecycle) {
      FindingLifecycle.acknowledged || FindingLifecycle.dismissed =>
        existing.lifecycle,
      _ => finding.lifecycle,
    };
    values[index] = _withLifecycle(finding, lifecycle);
  }

  @override
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) async {
    final index = values.indexWhere((value) => value.id == id);
    if (index == -1) return;
    values[index] = _withLifecycle(values[index], lifecycle);
  }
}

AnalysisFinding _withLifecycle(
  AnalysisFinding finding,
  FindingLifecycle lifecycle,
) => AnalysisFinding(
  id: finding.id,
  rule: finding.rule,
  context: finding.context,
  severity: finding.severity,
  lifecycle: lifecycle,
  currentValue: finding.currentValue,
  baselineValue: finding.baselineValue,
  absoluteChange: finding.absoluteChange,
  percentageChange: finding.percentageChange,
  dimension: finding.dimension,
  impactValue: finding.impactValue,
  supportingMetrics: finding.supportingMetrics,
  evidence: finding.evidence,
  qualityIssues: finding.qualityIssues,
  generatedAt: finding.generatedAt,
);

extension on Iterable<Transaction> {
  Transaction? get firstOrNull => this.isEmpty ? null : first;
}
