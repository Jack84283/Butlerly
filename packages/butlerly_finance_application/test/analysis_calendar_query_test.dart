import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('calendar drill-through uses the configured financial date', () async {
    final occurredAt = DateTime.utc(2026, 8, 1, 7);
    final result = await QueryTransactionsForFinancialDate(
      _Transactions([
        _transaction(id: 'occurred-only', occurredAt: occurredAt),
      ]),
      preferences: _Preferences(),
    )('2026-08-01');

    final transactions =
        (result as ApplicationSuccess<List<TransactionDto>>).value;
    expect(transactions, hasLength(1));
    expect(transactions.single.financialDate, DateTime.utc(2026, 8, 1));
    expect(transactions.single.transactionDate, isNull);
  });
}

Transaction _transaction({required String id, required DateTime occurredAt}) =>
    Transaction(
      id: TransactionId(id),
      timing: KnownTransactionTime(occurredAt),
      money: Money(
        amount: DecimalValue.parse('12'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      provenance: [
        Provenance(
          id: ProvenanceId('$id-provenance'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: occurredAt,
        ),
      ],
      createdAt: occurredAt,
      updatedAt: occurredAt,
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
  Future<void> removePermanently(TransactionId id) async {}

  @override
  Future<void> save(Transaction transaction) async {}
}

final class _Preferences implements UserPreferenceRepository {
  @override
  Future<UserPreference?> load() async => UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: 'America/Los_Angeles',
  );

  @override
  Future<void> save(UserPreference preference) async {}
}
