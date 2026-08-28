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

  test(
    'receipt creation is idempotent and preserves reviewed fields',
    () async {
      final command = ReceiptTransactionCommand(
        id: 'receipt-transaction',
        provenanceId: 'receipt-provenance',
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        transactionDate: '2026-08-09',
        originalRepresentation: 'receipt.jpg',
        rawCounterparty: 'Cafe',
        description: 'Cafe',
        merchantId: 'merchant-1',
        categoryId: 'food',
        paymentSourceId: 'card-1',
        tagIds: ['tag-1', 'tag-2'],
      );
      final useCase = CreateReceiptTransaction(transactions, clock);
      await useCase.call(command);
      await useCase.call(
        ReceiptTransactionCommand(
          id: command.id,
          provenanceId: command.provenanceId,
          money: money('99.00'),
          transactionDate: command.transactionDate,
          originalRepresentation: 'different-source.jpg',
          description: 'Conflicting source',
        ),
      );
      expect(transactions.values, hasLength(1));
      final stored = transactions.values.values.single;
      expect(stored.merchantId?.value, 'merchant-1');
      expect(stored.categoryId?.value, 'food');
      expect(
        stored.tagIds.map((id) => id.value),
        containsAll(['tag-1', 'tag-2']),
      );
    },
  );

  test(
    'imports a date-only transaction without inventing an instant',
    () async {
      final result = await ImportTransaction(transactions, clock)(
        ImportTransactionCommand(
          id: 'import-1',
          provenanceId: 'import-provenance-1',
          sourceId: 'transactions.csv',
          originalRepresentation: '"2026-08-01","12.50","USD"',
          money: money('12.50'),
          direction: TransactionDirection.expense,
          transactionDate: '2026-08-01',
          rawCounterparty: 'Café Original',
          sourceLanguage: 'es',
        ),
      );

      expect(result, isA<ApplicationSuccess<TransactionDto>>());
      final stored = await transactions.findById(TransactionId('import-1'));
      expect(stored!.sourceType, TransactionSourceType.import);
      expect(stored.timing, isA<UnknownTransactionTime>());
      expect(stored.transactionDate, '2026-08-01');
      expect(stored.timeZoneId, isNull);
      expect(stored.rawCounterparty, 'Café Original');
      expect(stored.sourceLanguage, 'es');
      expect(stored.money, money('12.50'));
      expect(stored.provenance.single.sourceType, ProvenanceSourceType.import);
      expect(
        stored.provenance.single.originalRepresentation,
        '"2026-08-01","12.50","USD"',
      );
    },
  );

  test('rejects invalid imported business dates', () async {
    final result = await ImportTransaction(transactions, clock)(
      ImportTransactionCommand(
        id: 'import-1',
        provenanceId: 'import-provenance-1',
        sourceId: 'transactions.csv',
        originalRepresentation: 'invalid row',
        money: money('12.50'),
        direction: TransactionDirection.expense,
        transactionDate: '08/01/2026',
      ),
    );

    expect(
      result,
      isA<ApplicationFailure<TransactionDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.validation,
      ),
    );
    expect(transactions.values, isEmpty);
  });

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
          paymentSourceId: 'wallet-1',
          needsReview: false,
        ),
      );

      expect(result, isA<ApplicationSuccess<List<TransactionDto>>>());
      expect(transactions.lastQuery!.text, 'lunch');
      expect(transactions.lastQuery!.currency, 'usd');
      expect(
        transactions.lastQuery!.paymentSourceId,
        PaymentSourceId('wallet-1'),
      );
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

  test('manages and assigns a local payment source', () async {
    final sources = MemoryPaymentSources();
    final source = PaymentSource(
      id: PaymentSourceId('wallet-1'),
      name: 'Cash wallet',
      type: PaymentSourceType.wallet,
    );

    final saved = await SavePaymentSource(sources)(source);
    expect(saved, isA<ApplicationSuccess<PaymentSource>>());
    expect(
      await ListPaymentSources(sources)(),
      isA<ApplicationSuccess<List<PaymentSource>>>(),
    );

    transactions.values['transaction-1'] = transaction(now);
    final assigned = await AssignPaymentSource(transactions, sources, clock)(
      'transaction-1',
      'wallet-1',
    );
    expect(assigned, isA<ApplicationSuccess<TransactionDto>>());
    expect(
      transactions.values['transaction-1']!.paymentSourceId,
      PaymentSourceId('wallet-1'),
    );

    final archived = await ArchivePaymentSource(sources)('wallet-1');
    expect(archived, isA<ApplicationSuccess<PaymentSource>>());
    expect(
      (await sources.findById(PaymentSourceId('wallet-1')))!.status,
      PaymentSourceStatus.archived,
    );
  });

  test('lists and explicitly resolves active local review issues', () async {
    final issue = ReviewIssue(
      id: ReviewIssueId('issue-1'),
      transactionId: TransactionId('transaction-1'),
      reason: ReviewIssueReason.uncertain,
      detail: 'Confirm the transaction amount.',
      createdAt: now,
    );
    transactions.values['transaction-1'] = transaction(
      now,
    ).addReviewIssue(issue, now);

    final listed = await ListReviewItems(transactions)();
    expect(
      listed,
      isA<ApplicationSuccess<List<ReviewItemDto>>>().having(
        (value) => value.value.single.issueId,
        'issue id',
        'issue-1',
      ),
    );

    final resolved = await ResolveReviewIssue(transactions, clock)(
      'transaction-1',
      'issue-1',
    );
    expect(resolved, isA<ApplicationSuccess<TransactionDto>>());
    expect(
      transactions.values['transaction-1']!.reviewState,
      TransactionReviewState.clear,
    );
    expect(
      transactions.values['transaction-1']!.reviewIssues.single.status,
      ReviewIssueStatus.resolved,
    );
  });

  test(
    'maps evidence retrieval failures without exposing stored content',
    () async {
      final result = await ListEvidenceForTransaction(FailingEvidence())(
        'transaction-1',
      );

      expect(
        result,
        isA<ApplicationFailure<List<EvidenceItem>>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.unavailable,
        ),
      );
    },
  );
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

final class MemoryPaymentSources implements PaymentSourceRepository {
  final values = <String, PaymentSource>{};

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => values[id.value];

  @override
  Future<List<PaymentSource>> listAll() async => values.values.toList();

  @override
  Future<void> save(PaymentSource paymentSource) async {
    values[paymentSource.id.value] = paymentSource;
  }
}

final class FailingEvidence implements EvidenceRepository {
  @override
  Future<void> remove(EvidenceId id) async {}

  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;

  @override
  Future<void> link(AttachmentLink link) async {}

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async {
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'list transaction evidence',
    );
  }

  @override
  Future<void> save(EvidenceItem evidence) async {}

  @override
  Future<void> saveExtraction(Extraction extraction) async {}
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
