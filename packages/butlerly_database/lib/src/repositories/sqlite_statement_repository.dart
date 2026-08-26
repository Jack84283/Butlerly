import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

import '../database/butlerly_database.dart';
import 'sqlite_transaction_repository.dart';

final class SqliteStatementRepository
    implements StatementRepository, StatementWorkflowRepository {
  const SqliteStatementRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> saveStatement(FinancialStatement value) =>
      database.connection.insert(
        'financial_statements',
        _statementRow(value),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> saveRows(List<StatementRow> rows) =>
      database.transaction((tx) async {
        for (final row in rows) {
          await tx.insert(
            'statement_rows',
            _row(row),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      });

  @override
  Future<FinancialStatement?> findStatement(String id) async {
    final rows = await database.connection.query(
      'financial_statements',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _statement(rows.single);
  }

  @override
  Future<List<FinancialStatement>> listStatements({
    bool includeArchived = false,
  }) async => (await database.connection.query(
    'financial_statements',
    where: includeArchived ? null : 'status != ?',
    whereArgs: includeArchived ? null : [StatementStatus.archived.name],
    orderBy: 'updated_at DESC',
  )).map(_statement).toList(growable: false);

  @override
  Future<List<StatementRow>> listRows(String statementId) async =>
      (await database.connection.query(
        'statement_rows',
        where: 'statement_id = ?',
        whereArgs: [statementId],
        orderBy: 'position',
      )).map(_statementRowFromDb).toList(growable: false);

  @override
  Future<void> assignPaymentSource(
    String id,
    String paymentSourceId,
    DateTime updatedAt,
  ) async {
    final count = await database.connection.update(
      'financial_statements',
      {
        'payment_source_id': paymentSourceId,
        'status': StatementStatus.ready.name,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'assign statement payment source',
      );
    }
  }

  @override
  Future<void> updateRow(StatementRow row) async {
    final count = await database.connection.update(
      'statement_rows',
      _row(row),
      where: 'id = ?',
      whereArgs: [row.id],
    );
    if (count != 1) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'update statement row',
      );
    }
  }

  @override
  Future<void> removeStatement(String id) => database.connection.delete(
    'financial_statements',
    where: 'id = ?',
    whereArgs: [id],
  );

  @override
  Future<void> saveRowTransaction(StatementRow row, Transaction transaction) =>
      database.transaction((tx) async {
        await SqliteTransactionRepository.saveWithExecutor(tx, transaction);
        final count = await tx.update(
          'statement_rows',
          _row(row),
          where: 'id = ? AND status NOT IN (?, ?)',
          whereArgs: [
            row.id,
            StatementRowStatus.saved.name,
            StatementRowStatus.linked.name,
          ],
        );
        if (count != 1) {
          throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'complete statement row once',
          );
        }
      });

  @override
  Future<void> linkRow(StatementRow row) async {
    final count = await database.connection.update(
      'statement_rows',
      _row(row),
      where: 'id = ? AND status NOT IN (?, ?)',
      whereArgs: [
        row.id,
        StatementRowStatus.saved.name,
        StatementRowStatus.linked.name,
      ],
    );
    if (count != 1) {
      throw const RepositoryException(
        RepositoryFailureCode.constraint,
        'link statement row once',
      );
    }
  }

  static Map<String, Object?> _statementRow(FinancialStatement v) => {
    'id': v.id,
    'evidence_id': v.evidenceId,
    'payment_source_id': v.paymentSourceId,
    'status': v.status.name,
    'institution': v.institution,
    'masked_account_identifier': v.maskedAccountIdentifier,
    'period_start': _date(v.periodStart),
    'period_end': _date(v.periodEnd),
    'extraction_message': v.extractionMessage,
    'created_at': v.createdAt.toUtc().toIso8601String(),
    'updated_at': v.updatedAt.toUtc().toIso8601String(),
  };

  static FinancialStatement _statement(Map<String, Object?> r) =>
      FinancialStatement(
        id: r['id']! as String,
        evidenceId: r['evidence_id']! as String,
        paymentSourceId: r['payment_source_id'] as String?,
        status: StatementStatus.values.byName(r['status']! as String),
        institution: r['institution'] as String?,
        maskedAccountIdentifier: r['masked_account_identifier'] as String?,
        periodStart: _parseDate(r['period_start']),
        periodEnd: _parseDate(r['period_end']),
        extractionMessage: r['extraction_message'] as String?,
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
      );

  static Map<String, Object?> _row(StatementRow v) => {
    'id': v.id,
    'statement_id': v.statementId,
    'position': v.position,
    'original_text': v.originalText,
    'transaction_date': _date(v.transactionDate),
    'posting_date': _date(v.postingDate),
    'description': v.description,
    'amount': v.amount,
    'currency': v.currency,
    'direction': v.direction,
    'row_kind': v.kind.name,
    'confidence': v.confidence,
    'source_context': v.sourceContext,
    'status': v.status.name,
    'transaction_id': v.transactionId,
    'created_at': v.createdAt.toUtc().toIso8601String(),
    'updated_at': v.updatedAt.toUtc().toIso8601String(),
  };

  static StatementRow _statementRowFromDb(Map<String, Object?> r) =>
      StatementRow(
        id: r['id']! as String,
        statementId: r['statement_id']! as String,
        position: r['position']! as int,
        originalText: r['original_text']! as String,
        transactionDate: _parseDate(r['transaction_date']),
        postingDate: _parseDate(r['posting_date']),
        description: r['description'] as String?,
        amount: r['amount'] as String?,
        currency: r['currency'] as String?,
        direction: r['direction'] as String?,
        kind: StatementRowKind.values.byName(r['row_kind']! as String),
        confidence: (r['confidence'] as num?)?.toDouble(),
        sourceContext: r['source_context'] as String?,
        status: StatementRowStatus.values.byName(r['status']! as String),
        transactionId: r['transaction_id'] as String?,
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
      );

  static String? _date(DateTime? value) =>
      value?.toIso8601String().substring(0, 10);
  static DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
