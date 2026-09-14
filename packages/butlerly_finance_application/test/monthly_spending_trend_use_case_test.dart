import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  late CalculateAnalysisOverview analysis;

  setUp(() {
    analysis = CalculateAnalysisOverview(
      _Rules([_expenseTotalRule()]),
      AnalysisDatasetBuilder(
        _Transactions([
          _transaction('july', '2026-07-10', '30'),
          _transaction('august-a', '2026-08-02', '40'),
          _transaction('august-b', '2026-08-31', '60'),
          _transaction('september-a', '2026-09-01', '100'),
          _transaction('september-b', '2026-09-05', '50'),
          _transaction('future', '2026-09-06', '999'),
          _transaction(
            'income',
            '2026-09-03',
            '500',
            direction: TransactionDirection.income,
          ),
        ]),
        _Preferences(),
        null,
      ),
      const AnalysisRuleEngine(),
    );
  });

  test(
    'uses complete historical months and month-to-date for the current month',
    () async {
      final result = await CalculateMonthlySpendingTrend(analysis)(
        endingMonth: DateTime.utc(2026, 9, 1),
        instant: DateTime.utc(2026, 9, 5, 12),
        monthCount: 3,
      );

      final points =
          (result as ApplicationSuccess<List<MonthlySpendingTrendPoint>>).value;
      expect(
        points.map((point) => point.month),
        [
          DateTime.utc(2026, 7, 1),
          DateTime.utc(2026, 8, 1),
          DateTime.utc(2026, 9, 1),
        ],
      );
      expect(
        points.map((point) => point.spending!.value),
        [
          DecimalValue.parse('30'),
          DecimalValue.parse('100'),
          DecimalValue.parse('150'),
        ],
      );
    },
  );

  test('historical ending month is resolved as a complete month', () async {
    final result = await CalculateMonthlySpendingTrend(analysis)(
      endingMonth: DateTime.utc(2026, 8, 1),
      instant: DateTime.utc(2026, 9, 5, 12),
      monthCount: 2,
    );

    final points =
        (result as ApplicationSuccess<List<MonthlySpendingTrendPoint>>).value;
    expect(
      points.map((point) => point.spending!.value),
      [DecimalValue.parse('30'), DecimalValue.parse('100')],
    );
  });

  test('rejects a future ending month', () async {
    final result = await CalculateMonthlySpendingTrend(analysis)(
      endingMonth: DateTime.utc(2026, 10, 1),
      instant: DateTime.utc(2026, 9, 5, 12),
    );

    expect(result, isA<ApplicationFailure<List<MonthlySpendingTrendPoint>>>());
    final failure =
        (result as ApplicationFailure<List<MonthlySpendingTrendPoint>>).failure;
    expect(failure.code, ApplicationFailureCode.validation);
    expect(failure.field, 'endingMonth');
  });
}

AnalysisRuleDefinition _expenseTotalRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R001'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'analysis.rule.r001.name',
  descriptionKey: 'analysis.rule.r001.description',
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
  severity: RuleSeverity.info,
  surface: AnalysisSurface.overview,
  role: 'expenseTotal',
  filters: const [
    AnalysisFilter(
      kind: AnalysisFilterKind.direction,
      values: ['expense'],
    ),
  ],
  definitionHash: RuleDefinitionHash('a' * 64),
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
