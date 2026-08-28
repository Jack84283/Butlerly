import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'matches exact canonical identity and excludes the edited record',
    () async {
      final transaction = _transaction('existing');
      final checker = DuplicateTransactionChecker(_Transactions([transaction]));
      final result = await checker(
        const DuplicateTransactionCheckCommand(
          transactionDate: '2026-08-20',
          amount: '25',
          currency: 'usd',
          direction: TransactionDirection.expense,
        ),
      );
      expect(
        result,
        isA<ApplicationSuccess<DuplicateTransactionCheckResult>>(),
      );
      expect((result as ApplicationSuccess).value.candidates, hasLength(1));
      expect((result as ApplicationSuccess).value.requiresConfirmation, isTrue);

      final excluded = await checker(
        const DuplicateTransactionCheckCommand(
          transactionDate: '2026-08-20',
          amount: '25',
          currency: 'USD',
          direction: TransactionDirection.expense,
          excludeTransactionId: 'existing',
        ),
      );
      expect((excluded as ApplicationSuccess).value.candidates, isEmpty);
    },
  );

  test(
    'does not match a different direction, date, amount, or currency',
    () async {
      final checker = DuplicateTransactionChecker(
        _Transactions([_transaction('existing')]),
      );
      for (final command in const [
        DuplicateTransactionCheckCommand(
          transactionDate: '2026-08-21',
          amount: '25',
          currency: 'USD',
          direction: TransactionDirection.expense,
        ),
        DuplicateTransactionCheckCommand(
          transactionDate: '2026-08-20',
          amount: '26',
          currency: 'USD',
          direction: TransactionDirection.expense,
        ),
        DuplicateTransactionCheckCommand(
          transactionDate: '2026-08-20',
          amount: '25',
          currency: 'EUR',
          direction: TransactionDirection.expense,
        ),
        DuplicateTransactionCheckCommand(
          transactionDate: '2026-08-20',
          amount: '25',
          currency: 'USD',
          direction: TransactionDirection.income,
        ),
      ]) {
        final result = await checker(command);
        expect((result as ApplicationSuccess).value.candidates, isEmpty);
      }
    },
  );
}

Transaction _transaction(String id) {
  final now = DateTime.utc(2026, 8, 20);
  return Transaction(
    id: TransactionId(id),
    timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
    money: Money(
      amount: DecimalValue.parse('25.00'),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    transactionDate: '2026-08-20',
    provenance: [
      Provenance(
        id: ProvenanceId('$id-p'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: now,
        originalRepresentation: 'manual',
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

final class _Transactions implements TransactionRepository {
  _Transactions(this.values);
  final List<Transaction> values;
  Future<void> save(Transaction value) async => values.add(value);
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((v) => v.id == id).firstOrNull;
  Future<List<Transaction>> listAll() async => values;
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values
          .where(
            (v) =>
                (query.from == null ||
                    v.transactionDate! == _date(query.from!)) &&
                (query.to == null || v.transactionDate! == _date(query.to!)) &&
                (query.currency == null ||
                    v.money.currency.value == query.currency) &&
                (query.direction == null || v.direction == query.direction) &&
                (query.status == null || v.status == query.status),
          )
          .toList();
  Future<void> removePermanently(TransactionId id) async =>
      values.removeWhere((v) => v.id == id);
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
