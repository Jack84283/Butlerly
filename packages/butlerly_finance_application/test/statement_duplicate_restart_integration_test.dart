import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'statement duplicate review survives restart and explicit linking',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-statement-duplicate-',
      );
      final path = '${directory.path}/butlerly.db';
      final schema = await File(
        '../butlerly_database/database/schema/v1.sql',
      ).readAsString();
      final now = DateTime.utc(2026, 9, 1);
      try {
        var database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        final evidence = SqliteEvidenceRepository(database);
        await evidence.save(
          EvidenceItem(
            id: EvidenceId('statement-evidence'),
            type: EvidenceType.document,
            originalName: 'statement.pdf',
            mediaType: 'application/pdf',
            provenance: Provenance(
              id: ProvenanceId('statement-provenance'),
              sourceType: ProvenanceSourceType.scan,
              capturedAt: now,
              originalRepresentation: 'statement.pdf',
            ),
            createdAt: now,
          ),
        );
        final transactions = SqliteTransactionRepository(database);
        await transactions.save(_transaction('existing'));
        final statements = SqliteStatementRepository(database);
        final groups = SqliteDuplicateCandidateGroupRepository(database);
        final statement = _statement();
        final row = _row();
        await statements.saveStatementWithRows(statement, [row]);
        final services = StatementServices(
          statements,
          transactions,
          statements,
          _Clock(now),
          duplicateGroups: groups,
          duplicateChecker: DuplicateTransactionChecker(transactions),
        );

        final imported = await services.importBatch(statement, [row], 'source');
        expect(imported, isA<ApplicationSuccess<StatementImportSummary>>());
        expect((await groups.list()).single.statementRows.single.rowId, row.id);
        await database.close();

        database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        addTearDown(database.close);
        final restartedStatements = SqliteStatementRepository(database);
        final restartedTransactions = SqliteTransactionRepository(database);
        final restartedGroups = SqliteDuplicateCandidateGroupRepository(
          database,
        );
        final restartedServices = StatementServices(
          restartedStatements,
          restartedTransactions,
          restartedStatements,
          _Clock(now.add(const Duration(minutes: 1))),
          duplicateGroups: restartedGroups,
          duplicateChecker: DuplicateTransactionChecker(restartedTransactions),
        );
        final visible = await ListDuplicateCandidateGroups(restartedGroups)();
        expect(
          (visible as ApplicationSuccess<List<DuplicateCandidateGroup>>).value,
          hasLength(1),
        );

        final restoredRow = (await restartedStatements.listRows(
          statement.id,
        )).single;
        await restartedServices.link(restoredRow, 'existing');
        expect(
          (await restartedStatements.listRows(statement.id)).single.status,
          StatementRowStatus.linked,
        );
        expect(await restartedGroups.list(), isEmpty);
      } finally {
        await Directory(directory.path).delete(recursive: true);
      }
    },
  );

  test(
    'SQLite retry preserves corrections on an unresolved duplicate row',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-statement-retry-',
      );
      final path = '${directory.path}/butlerly.db';
      final schema = await File(
        '../butlerly_database/database/schema/v1.sql',
      ).readAsString();
      final now = DateTime.utc(2026, 9, 1);
      try {
        var database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        final evidence = SqliteEvidenceRepository(database);
        await evidence.save(
          EvidenceItem(
            id: EvidenceId('statement-evidence'),
            type: EvidenceType.document,
            originalName: 'statement.pdf',
            mediaType: 'application/pdf',
            provenance: Provenance(
              id: ProvenanceId('statement-retry-provenance'),
              sourceType: ProvenanceSourceType.scan,
              capturedAt: now,
              originalRepresentation: 'statement.pdf',
            ),
            createdAt: now,
          ),
        );
        final transactions = SqliteTransactionRepository(database);
        await transactions.save(_transaction('retry-existing'));
        final statements = SqliteStatementRepository(database);
        final groups = SqliteDuplicateCandidateGroupRepository(database);
        final statement = _statement();
        final row = _row();
        await statements.saveStatementWithRows(statement, [row]);
        final services = StatementServices(
          statements,
          transactions,
          statements,
          _Clock(now),
          duplicateGroups: groups,
          duplicateChecker: DuplicateTransactionChecker(transactions),
        );

        final first = await services.importBatch(statement, [row], 'source');
        expect(
          (first as ApplicationSuccess<StatementImportSummary>)
              .value
              .possibleDuplicates,
          1,
        );
        final pending = (await statements.listRows(statement.id)).single;
        final corrected = StatementRow(
          id: pending.id,
          statementId: pending.statementId,
          position: pending.position,
          originalText: pending.originalText,
          transactionDate: pending.transactionDate,
          description: 'Corrected persisted merchant',
          amount: pending.amount,
          currency: pending.currency,
          direction: pending.direction,
          confidence: pending.confidence,
          sourceContext: 'User correction survives retry',
          status: StatementRowStatus.unresolved,
          createdAt: pending.createdAt,
          updatedAt: pending.updatedAt.add(const Duration(seconds: 1)),
        );
        expect(
          await services.correct(corrected),
          isA<ApplicationSuccess<void>>(),
        );

        final retry = await services.importBatch(statement, [row], 'source');
        expect(
          (retry as ApplicationSuccess<StatementImportSummary>)
              .value
              .possibleDuplicates,
          1,
        );
        final persisted = (await statements.listRows(statement.id)).single;
        expect(persisted.description, 'Corrected persisted merchant');
        expect(persisted.sourceContext, 'User correction survives retry');

        await database.close();
        database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        addTearDown(database.close);
        final restartedRows = await SqliteStatementRepository(
          database,
        ).listRows(statement.id);
        expect(
          restartedRows.single.description,
          'Corrected persisted merchant',
        );
        expect(
          restartedRows.single.sourceContext,
          'User correction survives retry',
        );
      } finally {
        await Directory(directory.path).delete(recursive: true);
      }
    },
  );
}

FinancialStatement _statement() => FinancialStatement(
  id: 'statement',
  evidenceId: 'statement-evidence',
  status: StatementStatus.ready,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

StatementRow _row() => StatementRow(
  id: 'row-existing-duplicate',
  statementId: 'statement',
  position: 0,
  originalText: 'Merchant 25 USD',
  transactionDate: DateTime.utc(2026, 9, 1),
  description: 'Merchant',
  amount: '25',
  currency: 'USD',
  direction: TransactionDirection.expense.name,
  status: StatementRowStatus.pending,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Transaction _transaction(String id) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(amount: DecimalValue.parse('25'), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: '2026-09-01',
  provenance: [
    Provenance(
      id: ProvenanceId('$id-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 9, 1),
    ),
  ],
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

final class _Clock implements ApplicationClock {
  const _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}
