import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'saved recurring decisions do not restore a forecast after evidence becomes unstable',
    () async {
      final transactions = _Transactions([
        _transaction('one', '2026-01-01', amount: '10'),
        _transaction('two', '2026-02-01', amount: '10'),
        _transaction('three', '2026-03-01', amount: '20'),
      ]);
      final decisions = _Decisions(
        RecurringPatternDecision(
          id: 'decision-variable-bill',
          patternKey: 'variable bill|expense|USD||',
          status: RecurringPatternDecisionStatus.confirmed,
          cadence: RecurringPatternDecisionCadence.monthly,
          intervalDays: 30,
          expectedAmount: DecimalValue.parse('10'),
          createdAt: DateTime.utc(2026, 3, 2),
          updatedAt: DateTime.utc(2026, 3, 2),
        ),
      );

      final result = await DetectRecurringPatterns(
        transactions,
        preferences: _Preferences(),
        decisions: decisions,
      )(timeZoneId: 'UTC');

      final pattern =
          (result as ApplicationSuccess<List<RecurringPattern>>).value.single;
      expect(pattern.status, RecurringPatternStatus.confirmed);
      expect(pattern.expectedNextDate, isNull);
    },
  );
}

Transaction _transaction(String id, String date, {required String amount}) {
  final instant = DateTime.parse('${date}T12:00:00Z');
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(instant),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.import,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-source'),
        sourceType: ProvenanceSourceType.import,
        capturedAt: instant,
        originalRepresentation: 'Variable Bill $amount',
      ),
    ],
    transactionDate: date,
    description: 'Variable Bill',
    createdAt: instant,
    updatedAt: instant,
  );
}

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

final class _Decisions implements RecurringPatternDecisionRepository {
  _Decisions(this.value);

  final RecurringPatternDecision value;

  @override
  Future<RecurringPatternDecision?> findByPatternKey(String patternKey) async =>
      value.patternKey == patternKey ? value : null;

  @override
  Future<List<RecurringPatternDecision>> list() async => [value];

  @override
  Future<void> save(RecurringPatternDecision decision) async {}
}
