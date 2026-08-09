import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9, 20);
  late MemoryTransactions transactions;
  late FixedClock clock;

  setUp(() {
    transactions = MemoryTransactions();
    clock = FixedClock(now);
  });

  test(
    'creates a manual transaction with Butlerly identity and provenance',
    () async {
      final result = await CreateTransaction(transactions, clock)(
        CreateTransactionCommand(
          id: 'transaction-1',
          provenanceId: 'provenance-1',
          timing: KnownTransactionTime(now),
          money: money('12.50'),
          direction: TransactionDirection.expense,
          description: 'Lunch',
        ),
      );

      expect(result, isA<ApplicationSuccess<TransactionDto>>());
      final stored = await transactions.findById(
        TransactionId('transaction-1'),
      );
      expect(stored!.sourceType, TransactionSourceType.manual);
      expect(
        stored.provenance.single.sourceType,
        ProvenanceSourceType.userEntry,
      );
    },
  );

  test('updates canonical data while retaining provenance', () async {
    transactions.values['transaction-1'] = transaction(now);
    final result = await UpdateTransaction(transactions, clock)(
      UpdateTransactionCommand(
        id: 'transaction-1',
        timing: KnownTransactionTime(now),
        money: money('20'),
        direction: TransactionDirection.expense,
        description: 'Corrected lunch',
      ),
    );

    expect(result, isA<ApplicationSuccess<TransactionDto>>());
    final stored = transactions.values['transaction-1']!;
    expect(stored.description, 'Corrected lunch');
    expect(stored.provenance.single.id, ProvenanceId('provenance-1'));
  });

  test(
    'passes local search and filters through repository abstraction',
    () async {
      transactions.values['transaction-1'] = transaction(now);
      final result = await ListTransactions(transactions)(
        const ListTransactionsQuery(
          text: 'lunch',
          currency: 'usd',
          needsReview: false,
        ),
      );

      expect(result, isA<ApplicationSuccess<List<TransactionDto>>>());
      expect(transactions.lastQuery!.text, 'lunch');
      expect(transactions.lastQuery!.currency, 'usd');
      expect(transactions.lastQuery!.needsReview, isFalse);
    },
  );

  test('rejects an inverted date range before repository access', () async {
    final result = await ListTransactions(transactions)(
      ListTransactionsQuery(
        from: now,
        to: now.subtract(const Duration(days: 1)),
      ),
    );

    expect(
      result,
      isA<ApplicationFailure<List<TransactionDto>>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.validation,
      ),
    );
    expect(transactions.lastQuery, isNull);
  });

  test('maps repository exceptions to application failures', () async {
    transactions.failure = const RepositoryException(
      RepositoryFailureCode.storageFull,
      'save',
    );
    final result = await CreateTransaction(transactions, clock)(
      CreateTransactionCommand(
        id: 'transaction-1',
        provenanceId: 'provenance-1',
        timing: KnownTransactionTime(now),
        money: money('12.50'),
        direction: TransactionDirection.expense,
      ),
    );

    expect(
      result,
      isA<ApplicationFailure<TransactionDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.storage,
      ),
    );
  });

  test('does not assign a missing category', () async {
    transactions.values['transaction-1'] = transaction(now);
    final result = await AssignCategory(
      transactions,
      MemoryCategories(),
      clock,
    )('transaction-1', 'missing');

    expect(
      result,
      isA<ApplicationFailure<TransactionDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.notFound,
      ),
    );
    expect(transactions.values['transaction-1']!.categoryId, isNull);
  });

  test('archives and restores without permanently deleting', () async {
    transactions.values['transaction-1'] = transaction(now);

    await ArchiveTransaction(transactions, clock)('transaction-1');
    expect(
      transactions.values['transaction-1']!.status,
      TransactionStatus.archived,
    );
    await RestoreTransaction(transactions, clock)('transaction-1');
    expect(
      transactions.values['transaction-1']!.status,
      TransactionStatus.active,
    );
  });
}

final class FixedClock implements ApplicationClock {
  const FixedClock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}

final class MemoryTransactions implements TransactionRepository {
  final values = <String, Transaction>{};
  TransactionRepositoryQuery? lastQuery;
  RepositoryException? failure;

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    lastQuery = query;
    return values.values.toList();
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    if (failure case final error?) throw error;
    values[transaction.id.value] = transaction;
  }
}

final class MemoryCategories implements CategoryRepository {
  final values = <String, Category>{};

  @override
  Future<Category?> findById(CategoryId id) async => values[id.value];

  @override
  Future<List<Category>> listAll() async => values.values.toList();

  @override
  Future<void> save(Category category) async {
    values[category.id.value] = category;
  }
}

Money money(String amount) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD'));

Transaction transaction(DateTime now) => Transaction(
  id: TransactionId('transaction-1'),
  timing: KnownTransactionTime(now),
  money: money('12.50'),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  description: 'Lunch',
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-1'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);
