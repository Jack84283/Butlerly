import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  late ButlerlyDatabase database;
  late SqliteTransactionRepository transactions;
  final now = DateTime.utc(2026, 8, 9, 18);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await database.open();
    transactions = SqliteTransactionRepository(database);
  });

  tearDown(() => database.close());

  test('round-trips a complete transaction aggregate', () async {
    final paymentSource = PaymentSource(
      id: PaymentSourceId('source-1'),
      name: 'Wallet',
      type: PaymentSourceType.wallet,
    );
    final merchant = Merchant(id: MerchantId('merchant-1'), name: 'Café 東京');
    final category = Category(
      id: CategoryId('category-1'),
      name: 'Dining',
      origin: CategoryOrigin.user,
    );
    final tag = Tag(id: TagId('tag-1'), name: '旅行');
    await SqlitePaymentSourceRepository(database).save(paymentSource);
    await SqliteMerchantRepository(database).save(merchant);
    await SqliteCategoryRepository(database).save(category);
    await SqliteTagRepository(database).save(tag);

    final original = Money(
      amount: DecimalValue.parse('1250.50'),
      currency: CurrencyCode('JPY'),
    );
    var value = Transaction(
      id: TransactionId('transaction-1'),
      timing: KnownTransactionTime(now),
      money: original,
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.import,
      description: '昼ご飯',
      rawCounterparty: 'CAFE TOKYO',
      sourceLanguage: 'ja',
      paymentSourceId: paymentSource.id,
      merchantId: merchant.id,
      categoryId: category.id,
      tagIds: [tag.id],
      provenance: [importProvenance(now)],
      createdAt: now,
      updatedAt: now,
      transactionDate: '2026-08-09',
    );
    value = value.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('review-1'),
        transactionId: value.id,
        reason: ReviewIssueReason.uncertain,
        createdAt: now,
      ),
      now,
    );
    value = value.addNormalizedMoney(
      NormalizedMoney(
        original: original,
        converted: Money(
          amount: DecimalValue.parse('8.45'),
          currency: CurrencyCode('USD'),
        ),
        exchangeRate: ExchangeRate(
          id: ExchangeRateId('rate-1'),
          fromCurrency: CurrencyCode('JPY'),
          toCurrency: CurrencyCode('USD'),
          rate: DecimalValue.parse('0.00676'),
          effectiveAt: now,
          source: 'Test rate source',
        ),
      ),
      now,
    );

    await transactions.save(value);
    final restored = await transactions.findById(value.id);

    expect(restored, isNotNull);
    expect(restored!.money, original);
    expect(restored.description, '昼ご飯');
    expect(restored.sourceLanguage, 'ja');
    expect(restored.paymentSourceId, paymentSource.id);
    expect(restored.tagIds, [tag.id]);
    expect(restored.reviewState, TransactionReviewState.needsReview);
    expect(
      restored.normalizedMoney.single.converted.currency,
      CurrencyCode('USD'),
    );
    expect(restored.provenance.single.originalRepresentation, '元の取引');
  });

  test('maps foreign-key failures without leaking SQLite details', () async {
    final value = minimalTransaction(
      now,
    ).assignMerchant(MerchantId('missing'), now);

    await expectLater(
      transactions.save(value),
      throwsA(
        isA<RepositoryException>().having(
          (error) => error.operation,
          'operation',
          isNot(contains('FOREIGN KEY')),
        ),
      ),
    );
    expect(await transactions.findById(value.id), isNull);
  });

  test(
    'creates, lists, archives, and permanently removes transactions',
    () async {
      final value = minimalTransaction(now);
      await transactions.save(value);
      await transactions.save(
        value.archive(now.add(const Duration(minutes: 1))),
      );

      expect(
        (await transactions.listAll()).single.status,
        TransactionStatus.archived,
      );

      await transactions.removePermanently(value.id);
      expect(await transactions.findById(value.id), isNull);
    },
  );

  test('searches and filters transactions locally', () async {
    final value = Transaction(
      id: TransactionId('searchable-transaction'),
      timing: KnownTransactionTime(now),
      money: Money(
        amount: DecimalValue.parse('42.25'),
        currency: CurrencyCode('EUR'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      description: 'Déjeuner à Paris',
      notes: 'Client meeting',
      provenance: [
        Provenance(
          id: ProvenanceId('search-provenance'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      transactionDate: '2026-08-09',
    );
    await transactions.save(value);

    final matching = await transactions.query(
      TransactionRepositoryQuery(
        text: 'client',
        from: now.subtract(const Duration(days: 1)),
        to: now.add(const Duration(days: 1)),
        currency: 'eur',
        direction: TransactionDirection.expense,
        status: TransactionStatus.active,
        needsReview: false,
      ),
    );
    final excluded = await transactions.query(
      const TransactionRepositoryQuery(text: 'missing'),
    );

    expect(matching.single.id, value.id);
    expect(excluded, isEmpty);
  });

  test('stores evidence links and suggestions separately', () async {
    final transaction = minimalTransaction(now);
    await transactions.save(transaction);
    final evidenceRepository = SqliteEvidenceRepository(database);
    final evidence = EvidenceItem(
      id: EvidenceId('evidence-1'),
      type: EvidenceType.receiptImage,
      originalName: '領収書.jpg',
      mediaType: 'image/jpeg',
      provenance: Provenance(
        id: ProvenanceId('evidence-provenance'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
        originalRepresentation: '領収書.jpg',
        sourceLanguage: 'ja',
      ),
      createdAt: now,
      sourceLanguage: 'ja',
      localFileName: 'evidence-1.jpg',
    );
    await evidenceRepository.save(evidence);
    await evidenceRepository.link(
      AttachmentLink(
        id: AttachmentLinkId('link-1'),
        transactionId: transaction.id,
        evidenceId: evidence.id,
        createdAt: now,
      ),
    );
    final suggestions = SqliteSuggestionRepository(database);
    final suggestion = Suggestion(
      id: SuggestionId('suggestion-1'),
      transactionId: transaction.id,
      target: SuggestionTarget.category,
      proposedValue: 'Dining',
      method: SuggestionMethod.localAi,
      provenance: Provenance(
        id: ProvenanceId('suggestion-provenance'),
        sourceType: ProvenanceSourceType.localAi,
        capturedAt: now,
        originalRepresentation: 'Dining',
      ),
      createdAt: now,
      confidence: 0.8,
    );
    await suggestions.save(suggestion);

    expect(
      (await evidenceRepository.listForTransaction(
        transaction.id,
      )).single.localFileName,
      'evidence-1.jpg',
    );
    expect(
      (await suggestions.listForTransaction(transaction.id)).single.status,
      SuggestionStatus.proposed,
    );
    await evidenceRepository.remove(evidence.id);
    expect(await evidenceRepository.findById(evidence.id), isNull);
    expect(
      await evidenceRepository.listForTransaction(transaction.id),
      isEmpty,
    );
    expect(
      await database.connection.query(
        'provenances',
        where: 'id = ?',
        whereArgs: ['evidence-provenance'],
      ),
      isEmpty,
    );
  });
}

Transaction minimalTransaction(DateTime now) => Transaction(
  id: TransactionId('transaction-minimal'),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.pending),
  money: Money(amount: DecimalValue.parse('10'), currency: CurrencyCode('EUR')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  provenance: [
    Provenance(
      id: ProvenanceId('manual-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);

Provenance importProvenance(DateTime now) => Provenance(
  id: ProvenanceId('import-provenance'),
  sourceType: ProvenanceSourceType.import,
  capturedAt: now,
  sourceId: 'file-row-1',
  originalRepresentation: '元の取引',
  sourceLanguage: 'ja',
);
