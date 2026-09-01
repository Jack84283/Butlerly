import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'transaction invalidation rebuilds the complete trend axis through the application use case',
    () async {
      final transactions = _Transactions([
        _transaction('t1', '2026-01-01', '20'),
      ]);
      final preferences = _Preferences();
      final rule = _trendRule();
      final rules = _Rules([rule]);
      final results = _Results();
      final calculate = CalculateAnalysisOverview(
        rules,
        AnalysisDatasetBuilder(transactions, preferences, null),
        const AnalysisRuleEngine(),
        results: results,
      );
      final contextResult = await calculate.contextForDates(
        startDate: '2026-01-01',
        endDate: '2026-01-03',
      );
      final context =
          (contextResult as ApplicationSuccess<AnalysisContext>).value;

      final before = await calculate.call(context);
      expect(before, isA<ApplicationSuccess<List<RuleExecutionResult>>>());
      expect(_trendValues(before), [
        DecimalValue.parse('20'),
        DecimalValue.parse('0'),
        DecimalValue.parse('0'),
      ]);

      final invalidated =
          await InvalidateAnalysis(
            _Findings(),
            results: results,
            rules: rules,
          ).call(
            AnalysisInvalidationReason.transactionAmountChanged,
            DateTime.utc(2026, 1, 2),
            periodStart: '2026-01-01',
            periodEnd: '2026-01-03',
          );
      expect(invalidated, isA<ApplicationSuccess<void>>());
      expect(results.staleRuleIds, contains('ANL-R014'));

      transactions.values.add(_transaction('t2', '2026-01-02', '15'));
      final after = await calculate.call(context);
      expect(after, isA<ApplicationSuccess<List<RuleExecutionResult>>>());
      expect(_trendDimensions(after), [
        '2026-01-01:value',
        '2026-01-02:value',
        '2026-01-03:value',
      ]);
      expect(_trendValues(after), [
        DecimalValue.parse('20'),
        DecimalValue.parse('15'),
        DecimalValue.parse('0'),
      ]);
    },
  );
}

AnalysisRuleDefinition _trendRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R014'),
  version: RuleVersion('1.3.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'analysis.rule.r014.name',
  descriptionKey: 'analysis.rule.r014.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.day,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.trends,
  definitionHash: RuleDefinitionHash('a' * 64),
  resultPersistence: ResultPersistencePolicy.transient,
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

List<String> _trendDimensions(Object result) =>
    ((result as ApplicationSuccess<List<RuleExecutionResult>>).value)
        .map((value) => value.metric!.dimension!)
        .toList();

List<DecimalValue> _trendValues(Object result) =>
    ((result as ApplicationSuccess<List<RuleExecutionResult>>).value)
        .map((value) => value.metric!.value)
        .toList();

final class _Transactions implements TransactionRepository {
  _Transactions(this.values);
  final List<Transaction> values;

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<Transaction>> listAll() async => values;

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values;

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

final class _Results implements AnalysisRuleResultRepository {
  Set<String> staleRuleIds = {};

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
  }) async {
    staleRuleIds = ruleIds ?? {};
  }
}

final class _Findings implements AnalysisFindingRepository {
  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async =>
      const [];

  @override
  Future<void> save(AnalysisFinding finding) async {}

  @override
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) async {}
}

extension on Iterable<Transaction> {
  Transaction? get firstOrNull => length == 0 ? null : first;
}
