import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  late ButlerlyDatabase database;
  late SqliteStatementRepository statements;
  setUp(() async {
    sqfliteFfiInit();
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await database.open();
    statements = SqliteStatementRepository(database);
    final evidence = SqliteEvidenceRepository(database);
    await evidence.save(
      EvidenceItem(
        id: EvidenceId('evidence'),
        type: EvidenceType.document,
        originalName: 'statement.pdf',
        mediaType: 'application/pdf',
        provenance: Provenance(
          id: ProvenanceId('evidence-p'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: DateTime.utc(2026),
          originalRepresentation: 'statement.pdf',
        ),
        createdAt: DateTime.utc(2026),
      ),
    );
    await SqlitePaymentSourceRepository(database).save(
      PaymentSource(
        id: PaymentSourceId('source'),
        name: 'Card',
        type: PaymentSourceType.card,
        lastFour: '1234',
      ),
    );
  });
  tearDown(() => database.close());

  test(
    'persists statement progress and atomically completes one row once',
    () async {
      final now = DateTime.utc(2026, 8, 26);
      await statements.saveStatement(
        FinancialStatement(
          id: 'statement',
          evidenceId: 'evidence',
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final pending = StatementRow(
        id: 'row',
        statementId: 'statement',
        position: 0,
        originalText: '08/20 SHOP 12.00',
        transactionDate: DateTime.utc(2026, 8, 20),
        amount: '12.00',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        status: StatementRowStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      await statements.saveRows([pending]);
      await statements.assignPaymentSource('statement', 'source', now);
      final transaction = Transaction(
        id: TransactionId('transaction'),
        timing: const UnknownTransactionTime(
          UnknownTransactionTimeReason.unknown,
        ),
        money: Money(
          amount: DecimalValue.parse('12'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.import,
        transactionDate: '2026-08-20',
        paymentSourceId: PaymentSourceId('source'),
        provenance: [
          Provenance(
            id: ProvenanceId('transaction-p'),
            sourceType: ProvenanceSourceType.import,
            capturedAt: now,
            sourceId: 'statement',
            originalRepresentation: pending.originalText,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final completed = StatementRow(
        id: pending.id,
        statementId: pending.statementId,
        position: pending.position,
        originalText: pending.originalText,
        transactionDate: pending.transactionDate,
        amount: pending.amount,
        currency: pending.currency,
        direction: pending.direction,
        status: StatementRowStatus.saved,
        transactionId: transaction.id.value,
        createdAt: now,
        updatedAt: now,
      );
      await statements.saveRowTransaction(completed, transaction);
      expect(
        (await statements.listRows('statement')).single.status,
        StatementRowStatus.saved,
      );
      expect(
        await SqliteTransactionRepository(database).findById(transaction.id),
        isNotNull,
      );
      await expectLater(
        statements.saveRowTransaction(completed, transaction),
        throwsA(isA<RepositoryException>()),
      );
      expect((await SqliteTransactionRepository(database).listAll()).length, 1);
    },
  );

  test('round-trips statement metadata and reviewed row fields', () async {
    final now = DateTime.utc(2026, 8, 26);
    await statements.saveStatement(
      FinancialStatement(
        id: 'metadata-statement',
        evidenceId: 'evidence',
        paymentSourceId: 'source',
        status: StatementStatus.partial,
        institution: 'Issuer',
        maskedAccountIdentifier: '••••1234',
        periodStart: DateTime.utc(2026, 8, 1),
        periodEnd: DateTime.utc(2026, 8, 31),
        statementDate: DateTime.utc(2026, 9, 1),
        currency: 'USD',
        openingBalance: '100.00',
        closingBalance: '88.00',
        originalFilename: 'statement.pdf',
        rawTextReference: 'evidence/raw-text',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await statements.saveRows([
      StatementRow(
        id: 'metadata-row',
        statementId: 'metadata-statement',
        position: 0,
        originalText: '08/20 SHOP -12.00 USD',
        transactionDate: DateTime.utc(2026, 8, 20),
        postingDate: DateTime.utc(2026, 8, 21),
        description: 'SHOP',
        amount: '12.00',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        status: StatementRowStatus.skipped,
        tagIds: const ['tag-1', 'tag-2'],
        paymentSourceId: 'source',
        sourceReferenceId: 'row-ref',
        reviewReason: 'low confidence',
        dispositionReason: 'user skipped',
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    final savedStatement = await statements.findStatement('metadata-statement');
    final savedRow = (await statements.listRows('metadata-statement')).single;
    expect(savedStatement?.currency, 'USD');
    expect(savedStatement?.openingBalance, '100.00');
    expect(savedStatement?.originalFilename, 'statement.pdf');
    expect(savedStatement?.rawTextReference, 'evidence/raw-text');
    expect(
      savedRow.postingDate?.toIso8601String().substring(0, 10),
      '2026-08-21',
    );
    expect(savedRow.tagIds, ['tag-1', 'tag-2']);
    expect(savedRow.dispositionReason, 'user skipped');
  });

  test(
    'deleting statement removes candidates but preserves canonical transaction',
    () async {
      final now = DateTime.utc(2026);
      await statements.saveStatement(
        FinancialStatement(
          id: 'statement',
          evidenceId: 'evidence',
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await statements.removeStatement('statement');
      expect(await statements.findStatement('statement'), isNull);
    },
  );

  test('permanent transaction deletion reopens its statement row', () async {
    final now = DateTime.utc(2026, 8, 26);
    await statements.saveStatement(
      FinancialStatement(
        id: 'statement',
        evidenceId: 'evidence',
        paymentSourceId: 'source',
        status: StatementStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final transaction = Transaction(
      id: TransactionId('linked-transaction'),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.unknown,
      ),
      money: Money(
        amount: DecimalValue.parse('12'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.import,
      transactionDate: '2026-08-20',
      paymentSourceId: PaymentSourceId('source'),
      provenance: [
        Provenance(
          id: ProvenanceId('linked-transaction-p'),
          sourceType: ProvenanceSourceType.import,
          capturedAt: now,
          originalRepresentation: '2026-08-20 SHOP -12.00 USD',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final linked = StatementRow(
      id: 'linked-row',
      statementId: 'statement',
      position: 0,
      originalText: '2026-08-20 SHOP -12.00 USD',
      transactionDate: DateTime.utc(2026, 8, 20),
      amount: '12',
      currency: 'USD',
      direction: TransactionDirection.expense.name,
      status: StatementRowStatus.saved,
      transactionId: transaction.id.value,
      createdAt: now,
      updatedAt: now,
    );
    await SqliteTransactionRepository(database).save(transaction);
    await statements.saveRows([linked]);

    await SqliteTransactionRepository(
      database,
    ).removePermanently(transaction.id);

    final reopened = (await statements.listRows('statement')).single;
    expect(reopened.status, StatementRowStatus.pending);
    expect(reopened.transactionId, isNull);
    expect(
      await SqliteTransactionRepository(database).findById(transaction.id),
      isNull,
    );
  });
}
