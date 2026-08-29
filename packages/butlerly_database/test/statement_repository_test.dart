import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  late ButlerlyDatabase database;
  late SqliteStatementRepository statements;
  late SqliteTransactionRepository transactions;
  setUp(() async {
    sqfliteFfiInit();
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    statements = SqliteStatementRepository(database);
    transactions = SqliteTransactionRepository(database);
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
        (await statements.findStatement('statement'))?.status,
        StatementStatus.completed,
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

  test(
    'statement link targets a receipt-created transaction and preserves one canonical record',
    () async {
      final now = DateTime.utc(2026, 8, 26);
      await statements.saveStatement(
        FinancialStatement(
          id: 'multi-evidence-statement',
          evidenceId: 'evidence',
          paymentSourceId: 'source',
          status: StatementStatus.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final row = StatementRow(
        id: 'multi-evidence-row',
        statementId: 'multi-evidence-statement',
        position: 0,
        originalText: 'Cafe 12.00',
        amount: '12.00',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        status: StatementRowStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      await statements.saveRows([row]);
      final transaction = Transaction(
        id: TransactionId('multi-evidence-transaction'),
        timing: const UnknownTransactionTime(
          UnknownTransactionTimeReason.unknown,
        ),
        money: Money(
          amount: DecimalValue.parse('99.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.evidenceCapture,
        transactionDate: '2026-08-26',
        description: 'Canonical value',
        paymentSourceId: PaymentSourceId('source'),
        provenance: [
          Provenance(
            id: ProvenanceId('multi-evidence-tx-p'),
            sourceType: ProvenanceSourceType.scan,
            capturedAt: now,
            originalRepresentation: 'receipt.jpg',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await transactions.save(transaction);
      await statements.linkRow(
        StatementRow(
          id: row.id,
          statementId: row.statementId,
          position: row.position,
          originalText: row.originalText,
          amount: row.amount,
          currency: row.currency,
          direction: row.direction,
          status: StatementRowStatus.linked,
          transactionId: transaction.id.value,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final evidenceRepository = SqliteEvidenceRepository(database);
      await evidenceRepository.save(
        EvidenceItem(
          id: EvidenceId('receipt-evidence'),
          type: EvidenceType.receiptImage,
          originalName: 'receipt.jpg',
          mediaType: 'image/jpeg',
          provenance: Provenance(
            id: ProvenanceId('receipt-evidence-p'),
            sourceType: ProvenanceSourceType.scan,
            capturedAt: now,
            originalRepresentation: 'receipt.jpg',
          ),
          createdAt: now,
        ),
      );
      await evidenceRepository.link(
        AttachmentLink(
          id: AttachmentLinkId('receipt-link'),
          transactionId: transaction.id,
          evidenceId: EvidenceId('receipt-evidence'),
          createdAt: now,
        ),
      );
      await evidenceRepository.link(
        AttachmentLink(
          id: AttachmentLinkId('receipt-link-duplicate'),
          transactionId: transaction.id,
          evidenceId: EvidenceId('receipt-evidence'),
          createdAt: now,
        ),
      );
      expect((await transactions.listAll()), hasLength(1));
      expect(
        (await statements.listRows(row.statementId)).single.transactionId,
        transaction.id.value,
      );
      expect(
        (await evidenceRepository.listForTransaction(transaction.id)),
        hasLength(1),
      );
      expect(
        (await transactions.findById(transaction.id))?.description,
        'Canonical value',
      );
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

  test('close and reopen preserves both evidence relationships', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-reopen-');
    final path = '${directory.path}/finance.sqlite';
    final first = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: path,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await first.open();
    final txRepo = SqliteTransactionRepository(first);
    final statementRepo = SqliteStatementRepository(first);
    final evidenceRepo = SqliteEvidenceRepository(first);
    final now = DateTime.utc(2026, 8, 27);
    final tx = Transaction(
      id: TransactionId('reopen-transaction'),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.unknown,
      ),
      money: Money(
        amount: DecimalValue.parse('42'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      transactionDate: '2026-08-27',
      description: 'Canonical purchase',
      provenance: [
        Provenance(
          id: ProvenanceId('reopen-tx-p'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await txRepo.save(tx);
    await evidenceRepo.save(
      EvidenceItem(
        id: EvidenceId('reopen-receipt'),
        type: EvidenceType.receiptImage,
        originalName: 'receipt.jpg',
        mediaType: 'image/jpeg',
        provenance: Provenance(
          id: ProvenanceId('reopen-receipt-p'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: now,
          originalRepresentation: 'receipt.jpg',
        ),
        createdAt: now,
      ),
    );
    await evidenceRepo.link(
      AttachmentLink(
        id: AttachmentLinkId('reopen-link'),
        transactionId: tx.id,
        evidenceId: EvidenceId('reopen-receipt'),
        createdAt: now,
      ),
    );
    await statementRepo.saveStatement(
      FinancialStatement(
        id: 'reopen-statement',
        evidenceId: 'reopen-receipt',
        status: StatementStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final row = StatementRow(
      id: 'reopen-row',
      statementId: 'reopen-statement',
      position: 0,
      originalText: 'source row',
      status: StatementRowStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    await statementRepo.saveRows([row]);
    await statementRepo.linkRow(
      StatementRow(
        id: row.id,
        statementId: row.statementId,
        position: row.position,
        originalText: row.originalText,
        status: StatementRowStatus.linked,
        transactionId: tx.id.value,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await first.close();

    final second = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: path,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await second.open();
    final reopenedTx = SqliteTransactionRepository(second);
    final reopenedStatements = SqliteStatementRepository(second);
    final reopenedEvidence = SqliteEvidenceRepository(second);
    expect(await reopenedTx.findById(tx.id), isNotNull);
    expect((await reopenedTx.listAll()), hasLength(1));
    expect((await reopenedEvidence.listForTransaction(tx.id)), hasLength(1));
    expect(
      (await reopenedStatements.listRows(
        'reopen-statement',
      )).single.transactionId,
      tx.id.value,
    );
    await second.close();
    await directory.delete(recursive: true);
  });

  test(
    'recalculates parent progress without losing setup or archive state',
    () async {
      final now = DateTime.utc(2026, 8, 26);
      await statements.saveStatement(
        FinancialStatement(
          id: 'progress-statement',
          evidenceId: 'evidence',
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final first = StatementRow(
        id: 'progress-row-1',
        statementId: 'progress-statement',
        position: 0,
        originalText: 'row 1',
        status: StatementRowStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final second = StatementRow(
        id: 'progress-row-2',
        statementId: 'progress-statement',
        position: 1,
        originalText: 'row 2',
        status: StatementRowStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      await statements.saveRows([first, second]);
      await statements.updateRow(
        StatementRow(
          id: first.id,
          statementId: first.statementId,
          position: first.position,
          originalText: first.originalText,
          status: StatementRowStatus.skipped,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        (await statements.findStatement('progress-statement'))?.status,
        StatementStatus.needsSource,
      );

      await statements.assignPaymentSource('progress-statement', 'source', now);
      expect(
        (await statements.findStatement('progress-statement'))?.status,
        StatementStatus.partial,
      );
      await statements.updateRow(
        StatementRow(
          id: second.id,
          statementId: second.statementId,
          position: second.position,
          originalText: second.originalText,
          status: StatementRowStatus.skipped,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        (await statements.findStatement('progress-statement'))?.status,
        StatementStatus.completed,
      );
      await database.connection.update(
        'financial_statements',
        {'status': StatementStatus.archived.name},
        where: 'id = ?',
        whereArgs: ['progress-statement'],
      );
      await statements.updateRow(
        StatementRow(
          id: second.id,
          statementId: second.statementId,
          position: second.position,
          originalText: second.originalText,
          status: StatementRowStatus.skipped,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        (await statements.findStatement('progress-statement'))?.status,
        StatementStatus.archived,
      );
    },
  );

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
      expect(await statements.canDeleteStatement('statement'), isTrue);
      await statements.removeStatement('statement');
      expect(await statements.findStatement('statement'), isNull);
      expect(
        (await database.connection.query(
          'statement_rows',
          where: 'statement_id = ?',
          whereArgs: ['statement'],
        )),
        isEmpty,
      );
      expect(
        (await database.connection.query(
          'evidence_items',
          where: 'id = ?',
          whereArgs: ['evidence'],
        )),
        isEmpty,
      );
      expect(
        (await database.connection.query(
          'provenances',
          where: 'id = ?',
          whereArgs: ['provenance'],
        )),
        isEmpty,
      );
    },
  );

  test(
    'statement removal refuses rows already linked to a transaction',
    () async {
      final now = DateTime.utc(2026);
      await statements.saveStatement(
        FinancialStatement(
          id: 'protected-statement',
          evidenceId: 'evidence',
          status: StatementStatus.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await transactions.save(
        Transaction(
          id: TransactionId('existing-transaction'),
          timing: const UnknownTransactionTime(
            UnknownTransactionTimeReason.unknown,
          ),
          money: Money(
            amount: DecimalValue.parse('10'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          sourceType: TransactionSourceType.import,
          transactionDate: '2026-08-12',
          paymentSourceId: PaymentSourceId('source'),
          provenance: [
            Provenance(
              id: ProvenanceId('existing-transaction-p'),
              sourceType: ProvenanceSourceType.import,
              capturedAt: now,
              sourceId: 'protected-statement',
              originalRepresentation: '08/12 Store 10.00',
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await statements.saveRows([
        StatementRow(
          id: 'protected-row',
          statementId: 'protected-statement',
          position: 0,
          originalText: '08/12 Store 10.00',
          amount: '10',
          currency: 'USD',
          transactionDate: DateTime.utc(2026, 8, 12),
          direction: TransactionDirection.expense.name,
          status: StatementRowStatus.pending,
          transactionId: 'existing-transaction',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      expect(
        () => statements.removeStatement('protected-statement'),
        throwsA(isA<RepositoryException>()),
      );
      expect(await statements.findStatement('protected-statement'), isNotNull);
    },
  );

  test(
    'statement deletion eligibility includes provenance dependencies',
    () async {
      final now = DateTime.utc(2026);
      await statements.saveStatement(
        FinancialStatement(
          id: 'provenance-statement',
          evidenceId: 'evidence',
          status: StatementStatus.completed,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await transactions.save(
        Transaction(
          id: TransactionId('provenance-transaction'),
          timing: const UnknownTransactionTime(
            UnknownTransactionTimeReason.unknown,
          ),
          money: Money(
            amount: DecimalValue.parse('10'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          sourceType: TransactionSourceType.import,
          transactionDate: '2026-08-12',
          paymentSourceId: PaymentSourceId('source'),
          provenance: [
            Provenance(
              id: ProvenanceId('provenance-transaction-origin'),
              sourceType: ProvenanceSourceType.import,
              capturedAt: now,
              originalRepresentation: 'source',
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await database.connection.insert('transaction_provenances', {
        'transaction_id': 'provenance-transaction',
        'provenance_id': 'evidence-p',
      });
      expect(
        await statements.canDeleteStatement('provenance-statement'),
        isFalse,
      );
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
