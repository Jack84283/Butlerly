import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  Future<DuplicateTransactionCheckResult> check(
    List<Transaction> values, {
    String amount = '25',
    String date = '2026-08-20',
    String currency = 'USD',
    TransactionDirection direction = TransactionDirection.expense,
    String? exclude,
  }) async {
    final result = await DuplicateTransactionChecker(_Transactions(values))(
      DuplicateTransactionCheckCommand(
        transactionDate: date,
        amount: amount,
        currency: currency,
        direction: direction,
        excludeTransactionId: exclude,
      ),
    );
    return (result as ApplicationSuccess<DuplicateTransactionCheckResult>)
        .value;
  }

  test('canonical decimal spellings compare equally', () async {
    for (final amount in ['25', '25.0', '25.00']) {
      expect(
        (await check([_transaction('one')], amount: amount)).candidates,
        hasLength(1),
      );
    }
  });

  test('optional context does not affect strict duplicate identity', () async {
    final paymentSource = _transaction('source', paymentSourceId: 'card-a');
    final differentSource = _transaction(
      'different-source',
      paymentSourceId: 'card-b',
    );
    final merchant = _transaction('merchant', merchantId: 'merchant-a');
    expect((await check([paymentSource])).candidates, hasLength(1));
    expect((await check([differentSource])).candidates, hasLength(1));
    expect((await check([merchant])).candidates, hasLength(1));
  });

  test(
    'returns every active matching candidate and excludes only self',
    () async {
      final result = await check([
        _transaction('one'),
        _transaction('two'),
        _transaction('archived', status: TransactionStatus.archived),
      ], exclude: 'one');
      expect(result.candidates.map((value) => value.transaction.id), ['two']);
    },
  );

  test('duplicate checking never mutates the repository', () async {
    final repository = _Transactions([_transaction('one')]);
    await DuplicateTransactionChecker(repository)(
      const DuplicateTransactionCheckCommand(
        transactionDate: '2026-08-20',
        amount: '25',
        currency: 'USD',
        direction: TransactionDirection.expense,
      ),
    );
    expect(repository.saveCalls, 0);
    expect(repository.removeCalls, 0);
  });

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

Transaction _transaction(
  String id, {
  TransactionStatus status = TransactionStatus.active,
  String? paymentSourceId,
  String? merchantId,
}) {
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
    status: status,
    paymentSourceId: paymentSourceId == null
        ? null
        : PaymentSourceId(paymentSourceId),
    merchantId: merchantId == null ? null : MerchantId(merchantId),
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
  int saveCalls = 0;
  int removeCalls = 0;

  @override
  Future<void> save(Transaction value) async {
    saveCalls++;
    values.add(value);
  }

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((v) => v.id == id).firstOrNull;

  @override
  Future<List<Transaction>> listAll() async => values;

  @override
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
  @override
  Future<void> removePermanently(TransactionId id) async => _remove(id);

  void _remove(TransactionId id) {
    removeCalls++;
    values.removeWhere((v) => v.id == id);
  }
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
