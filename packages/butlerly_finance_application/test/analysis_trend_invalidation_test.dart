import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('current month summary uses month-to-date transactions', () async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
    final transactions = _Transactions([
      _transaction('expense', date, '120'),
      _transaction(
        'income',
        date,
        '500',
        direction: TransactionDirection.income,
      ),
    ]);
    final calculate = CalculateAnalysisOverview(
      _Rules([
        _summaryRule('ANL-R001', TransactionDirection.expense),
        _summaryRule('ANL-R002', TransactionDirection.income),
        _netRule(),
      ]),
      AnalysisDatasetBuilder(transactions, _Preferences(), null),
      const AnalysisRuleEngine(),
    );

    final result = await calculate.currentMonth(now);
    final values =
        (result as ApplicationSuccess<List<RuleExecutionResult>>).value;
    DecimalValue metric(String id) => values
        .singleWhere((value) => value.rule.identity.value == id)
        .metric!
        .value;
    expect(metric('ANL-R001'), DecimalValue.parse('120'));
    expect(metric('ANL-R002'), DecimalValue.parse('500'));
    expect(metric('ANL-R003'), DecimalValue.parse('380'));
  });

  test(
    'current-month materialized summaries recompute after invalidation',
    () async {
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
      final transactions = _Transactions([
        _transaction('expense', date, '120'),
        _transaction(
          'income',
          date,
          '500',
          direction: TransactionDirection.income,
        ),
      ]);
      final results = _Results();
      final rules = _Rules([
        _summaryRule('ANL-R001', TransactionDirection.expense),
        _summaryRule('ANL-R002', TransactionDirection.income),
        _netRule(),
      ]);
      final calculate = CalculateAnalysisOverview(
        rules,
        AnalysisDatasetBuilder(transactions, _Preferences(), null),
        const AnalysisRuleEngine(),
        results: results,
      );
      final first = await calculate.currentMonth(now);
      final context =
          ((first as ApplicationSuccess<List<RuleExecutionResult>>)
                  .value
                  .first
                  .metric!)
              .context;

      Future<void> invalidate(AnalysisInvalidationReason reason) async {
        await InvalidateAnalysis(
          _Findings(),
          results: results,
          rules: rules,
        ).call(
          reason,
          now,
          periodStart: context.period.startDate,
          periodEnd: context.period.endDate,
        );
      }

      transactions.values[0] = _transaction('expense', date, '200');
      await invalidate(AnalysisInvalidationReason.transactionAmountChanged);
      final second = await calculate.call(context);
      final values =
          (second as ApplicationSuccess<List<RuleExecutionResult>>).value;
      DecimalValue metric(String id) => values
          .singleWhere((value) => value.rule.identity.value == id)
          .metric!
          .value;
      expect(metric('ANL-R001'), DecimalValue.parse('200'));
      expect(metric('ANL-R002'), DecimalValue.parse('500'));
      expect(metric('ANL-R003'), DecimalValue.parse('300'));

      transactions.values[0] = _transaction(
        'expense',
        date,
        '200',
        direction: TransactionDirection.income,
      );
      await invalidate(AnalysisInvalidationReason.transactionDirectionChanged);
      final directionChanged = await calculate.call(context);
      expect(
        (directionChanged as ApplicationSuccess<List<RuleExecutionResult>>)
            .value
            .singleWhere((value) => value.rule.identity.value == 'ANL-R001')
            .metric!
            .value,
        DecimalValue.parse('0'),
      );

      transactions.values[1] = transactions.values[1].archive(now);
      await invalidate(AnalysisInvalidationReason.transactionUpdated);
      final archived = await calculate.call(context);
      expect(
        (archived as ApplicationSuccess<List<RuleExecutionResult>>).value
            .singleWhere((value) => value.rule.identity.value == 'ANL-R002')
            .metric!
            .value,
        DecimalValue.parse('200'),
      );

      transactions.values[1] = transactions.values[1].restore(now);
      await invalidate(AnalysisInvalidationReason.transactionUpdated);
      final restored = await calculate.call(context);
      expect(
        (restored as ApplicationSuccess<List<RuleExecutionResult>>).value
            .singleWhere((value) => value.rule.identity.value == 'ANL-R002')
            .metric!
            .value,
        DecimalValue.parse('700'),
      );

      await transactions.removePermanently(TransactionId('expense'));
      await invalidate(AnalysisInvalidationReason.transactionDeleted);
      final deleted = await calculate.call(context);
      expect(
        (deleted as ApplicationSuccess<List<RuleExecutionResult>>).value
            .singleWhere((value) => value.rule.identity.value == 'ANL-R002')
            .metric!
            .value,
        DecimalValue.parse('500'),
      );
    },
  );

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

AnalysisRuleDefinition _summaryRule(
  String id,
  TransactionDirection direction,
) => AnalysisRuleDefinition(
  identity: RuleIdentity(id),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: id,
  descriptionKey: id,
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.overview,
  filters: [
    AnalysisFilter(
      kind: AnalysisFilterKind.direction,
      values: [direction.name],
    ),
  ],
  definitionHash: RuleDefinitionHash('b' * 64),
);

AnalysisRuleDefinition _netRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R003'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'ANL-R003',
  descriptionKey: 'ANL-R003',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.difference,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.overview,
  dependencies: [
    RuleDependency(ruleId: RuleIdentity('ANL-R001')),
    RuleDependency(ruleId: RuleIdentity('ANL-R002')),
  ],
  definitionHash: RuleDefinitionHash('c' * 64),
);

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

Transaction _transaction(
  String id,
  String date,
  String amount, {
  TransactionDirection direction = TransactionDirection.expense,
}) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(DateTime.utc(2026, 1, 1, 12)),
  money: Money(
    amount: DecimalValue.parse(amount),
    currency: CurrencyCode('USD'),
  ),
  direction: direction,
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
  final _values = <AnalysisRuleResult>[];

  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async => _values
      .where(
        (value) =>
            value.ruleId == rule.identity &&
            value.ruleVersion == rule.version &&
            value.definitionHash == rule.definitionHash &&
            value.context.period.startDate == context.period.startDate &&
            value.context.period.endDate == context.period.endDate &&
            value.context.period.timeZoneId == context.period.timeZoneId &&
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
    _values.removeWhere((value) => value.id == result.id);
    _values.add(result);
  }

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async {
    staleRuleIds = ruleIds ?? {};
    for (var index = 0; index < _values.length; index++) {
      final value = _values[index];
      if (ruleIds != null && !ruleIds.contains(value.ruleId.value)) continue;
      if (periodStart != null &&
          value.context.period.endDate.compareTo(periodStart) < 0) {
        continue;
      }
      if (periodEnd != null &&
          value.context.period.startDate.compareTo(periodEnd) > 0) {
        continue;
      }
      _values[index] = AnalysisRuleResult(
        id: value.id,
        ruleId: value.ruleId,
        ruleVersion: value.ruleVersion,
        definitionHash: value.definitionHash,
        resultType: value.resultType,
        surface: value.surface,
        context: value.context,
        dimension: value.dimension,
        payload: value.payload,
        calculatedAt: value.calculatedAt,
        sourceRevision: value.sourceRevision,
        freshness: AnalysisResultFreshness.stale,
        createdAt: value.createdAt,
        updatedAt: value.updatedAt,
        resultSetKey: value.resultSetKey,
        resultSetSize: value.resultSetSize,
      );
    }
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
