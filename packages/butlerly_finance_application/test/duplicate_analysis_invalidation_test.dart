import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reopening Analysis after Keep Both uses updated canonical totals',
    () async {
      final now = DateTime.utc(2026, 9, 1);
      final first = _transaction('first');
      final second = _transaction('second');
      final groups = _Groups(
        DuplicateCandidateGroup(
          id: 'duplicate:2026-09-01|25|USD|expense',
          transactionIds: [first.id, second.id],
          duplicateKey: _key(),
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: first.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final findings = _Findings();
      final results = _Results();
      final calculate = CalculateAnalysisOverview(
        _Rules(),
        AnalysisDatasetBuilder(
          _Transactions([first, second]),
          _Preferences(),
          null,
          duplicateGroups: groups,
        ),
        const AnalysisRuleEngine(),
        findings: findings,
        results: results,
      );
      final context = AnalysisContext(
        period: AnalysisPeriod(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
          timeZoneId: 'UTC',
        ),
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.original,
        baseCurrency: CurrencyCode('USD'),
      );

      final before = await calculate(context);
      if (before is ApplicationFailure<List<RuleExecutionResult>>) {
        fail('${before.failure.code}: ${before.failure.detail}');
      }
      expect(
        (before as ApplicationSuccess<List<RuleExecutionResult>>)
            .value
            .single
            .metric
            ?.value,
        DecimalValue.parse('25'),
      );

      final resolved = await ResolveDuplicateCandidateGroup(
        groups,
        _Clock(now.add(const Duration(minutes: 1))),
        invalidateAnalysis: InvalidateAnalysis(
          findings,
          results: results,
          rules: _Rules(),
        ),
      )(groups.value.id, DuplicateCandidateGroupStatus.keepBoth);
      expect(resolved, isA<ApplicationSuccess<void>>());
      expect(results.stale, isTrue);

      final after = await calculate(context);
      expect(
        (after as ApplicationSuccess<List<RuleExecutionResult>>)
            .value
            .single
            .metric
            ?.value,
        DecimalValue.parse('50'),
      );
    },
  );
}

DuplicateTransactionKey _key() => DuplicateTransactionKey(
  transactionDate: '2026-09-01',
  amount: DecimalValue.parse('25'),
  currency: 'USD',
  direction: TransactionDirection.expense.name,
);

Transaction _transaction(String id) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(amount: DecimalValue.parse('25'), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: '2026-09-01',
  provenance: [
    Provenance(
      id: ProvenanceId('$id-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 9, 1),
    ),
  ],
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

final class _Clock implements ApplicationClock {
  const _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

final class _Transactions implements TransactionRepository {
  _Transactions(this.values);
  final List<Transaction> values;
  @override
  Future<void> save(Transaction value) async {}
  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((value) => value.id == id).firstOrNull;
  @override
  Future<List<Transaction>> listAll() async => values;
  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values;
  @override
  Future<void> removePermanently(TransactionId id) async {}
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

final class _Groups implements DuplicateCandidateGroupRepository {
  _Groups(this.value);
  DuplicateCandidateGroup value;
  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async => [value];
  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async => [];
  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async => value.transactionIds;
  @override
  Future<void> save(DuplicateCandidateGroup group) async => value = group;
  @override
  Future<void> remove(String id) async {}
}

final class _Rules implements AnalysisRuleRepository {
  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => [_rule()];
  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => [_rule()];
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

AnalysisRuleDefinition _rule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R001'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'expense',
  descriptionKey: 'expense',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.none,
  condition: RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.overview,
  definitionHash: RuleDefinitionHash('e' * 64),
  role: 'expenseTotal',
  resultPersistence: ResultPersistencePolicy.materialized,
);

final class _Results implements AnalysisRuleResultRepository {
  final values = <AnalysisRuleResult>[];
  bool stale = false;
  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async => values
      .where(
        (value) =>
            !stale &&
            value.ruleId == rule.identity &&
            value.context.period.startDate == context.period.startDate &&
            value.freshness == AnalysisResultFreshness.fresh,
      )
      .toList(growable: false);
  @override
  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  }) async => null;
  @override
  Future<void> save(AnalysisRuleResult result) async {
    values
      ..clear()
      ..add(result);
    stale = false;
  }

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async {
    stale = true;
  }
}

final class _Findings implements AnalysisFindingRepository {
  @override
  Future<void> save(AnalysisFinding finding) async {}
  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async =>
      const [];
  @override
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) async {}
}

extension on Iterable<Transaction> {
  Transaction? get firstOrNull => this.isEmpty ? null : first;
}
