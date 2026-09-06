import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;
import 'package:sqflite_common/sqlite_api.dart' as sqflite;

import '../database/butlerly_database.dart';
import 'sqlite_transaction_repository.dart';

final class SqliteStatementRepository
    implements StatementRepository, StatementWorkflowRepository {
  const SqliteStatementRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> saveStatement(FinancialStatement value) => _mapped(
    'save statement',
    () => database.connection.insert(
      'financial_statements',
      _statementRow(value),
      conflictAlgorithm: ConflictAlgorithm.replace,
    ),
  );

  @override
  Future<void> saveRows(List<StatementRow> rows) => _mapped(
    'save statement rows',
    () => database.transaction((tx) async {
      for (final row in rows) {
        await tx.insert(
          'statement_rows',
          _row(row),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    }),
  );

  @override
  Future<void> saveStatementWithRows(
    FinancialStatement statement,
    List<StatementRow> rows,
  ) => _mapped(
    'save statement with rows',
    () => database.transaction((tx) async {
      await tx.insert(
        'financial_statements',
        _statementRow(statement),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final row in rows) {
        await tx.insert(
          'statement_rows',
          _row(row),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    }),
  );

  @override
  Future<FinancialStatement?> findStatement(String id) async {
    return _mapped('find statement', () async {
      final rows = await database.connection.query(
        'financial_statements',
        where: 'id = ?',
        whereArgs: [id],
      );
      return rows.isEmpty ? null : _statement(rows.single);
    });
  }

  @override
  Future<List<FinancialStatement>> listStatements({
    bool includeArchived = false,
  }) => _mapped(
    'list statements',
    () async => (await database.connection.query(
      'financial_statements',
      where: includeArchived ? null : 'status != ?',
      whereArgs: includeArchived ? null : [StatementStatus.archived.name],
      orderBy: 'updated_at DESC',
    )).map(_statement).toList(growable: false),
  );

  @override
  Future<List<StatementRow>> listRows(String statementId) => _mapped(
    'list statement rows',
    () async => (await database.connection.query(
      'statement_rows',
      where: 'statement_id = ?',
      whereArgs: [statementId],
      orderBy: 'position',
    )).map(_statementRowFromDb).toList(growable: false),
  );

  @override
  Future<void> assignPaymentSource(
    String id,
    String paymentSourceId,
    DateTime updatedAt,
  ) async {
    try {
      await database.transaction((tx) async {
        final count = await tx.update(
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
        await _refreshStatementStatus(tx, id, updatedAt);
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'assign statement payment source');
    }
  }

  @override
  Future<void> updateRow(StatementRow row) async {
    try {
      await database.transaction((tx) async {
        final count = await tx.update(
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
        await _refreshStatementStatus(tx, row.statementId, row.updatedAt);
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'update statement row');
    }
  }

  @override
  Future<bool> canDeleteStatement(String id) async {
    return database.transaction((tx) async {
      final statement = await tx.query(
        'financial_statements',
        columns: ['evidence_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (statement.isEmpty) return false;
      final evidenceId = statement.single['evidence_id']! as String;
      final rows = await tx.query(
        'statement_rows',
        columns: ['transaction_id'],
        where: 'statement_id = ? AND transaction_id IS NOT NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) return false;
      final evidence = await tx.query(
        'evidence_items',
        columns: ['provenance_id'],
        where: 'id = ?',
        whereArgs: [evidenceId],
        limit: 1,
      );
      if (evidence.isEmpty) return false;
      final provenanceId = evidence.single['provenance_id']! as String;
      final dependencies = await tx.rawQuery(
        '''SELECT 1 FROM attachment_links WHERE evidence_id = ?
           UNION ALL SELECT 1 FROM transaction_provenances WHERE provenance_id = ?
           UNION ALL SELECT 1 FROM suggestions WHERE provenance_id = ?
           LIMIT 1''',
        [evidenceId, provenanceId, provenanceId],
      );
      return dependencies.isEmpty;
    });
  }

  @override
  Future<void> removeStatement(String id) async {
    try {
      await database.transaction((tx) async {
        final statement = await tx.query(
          'financial_statements',
          columns: ['evidence_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (statement.isEmpty) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'remove statement',
          );
        }
        final savedRows = await tx.query(
          'statement_rows',
          columns: ['transaction_id'],
          where: 'statement_id = ? AND transaction_id IS NOT NULL',
          whereArgs: [id],
          limit: 1,
        );
        if (savedRows.isNotEmpty) {
          throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'remove statement with financial records',
          );
        }
        final evidenceId = statement.single['evidence_id']! as String;
        final evidence = await tx.query(
          'evidence_items',
          columns: ['provenance_id'],
          where: 'id = ?',
          whereArgs: [evidenceId],
          limit: 1,
        );
        await tx.delete(
          'financial_statements',
          where: 'id = ?',
          whereArgs: [id],
        );
        await tx.delete(
          'evidence_items',
          where: 'id = ?',
          whereArgs: [evidenceId],
        );
        if (evidence.isNotEmpty) {
          final provenanceId = evidence.single['provenance_id']! as String;
          final remaining = await tx.rawQuery(
            '''SELECT 1 FROM evidence_items WHERE provenance_id = ?
               UNION ALL SELECT 1 FROM extractions WHERE provenance_id = ?
               UNION ALL SELECT 1 FROM transaction_provenances WHERE provenance_id = ?
               UNION ALL SELECT 1 FROM suggestions WHERE provenance_id = ?
               LIMIT 1''',
            [provenanceId, provenanceId, provenanceId, provenanceId],
          );
          if (remaining.isEmpty) {
            await tx.delete(
              'provenances',
              where: 'id = ?',
              whereArgs: [provenanceId],
            );
          }
        }
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'remove statement');
    }
  }

  @override
  Future<void> saveRowTransaction(StatementRow row, Transaction transaction) =>
      _mapped(
        'save statement row transaction',
        () => database.transaction((tx) async {
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
          await _refreshStatementStatus(tx, row.statementId, row.updatedAt);
        }),
      );

  @override
  Future<void> linkRow(StatementRow row) async {
    try {
      await database.transaction((tx) async {
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
            'link statement row once',
          );
        }
        await _refreshStatementStatus(tx, row.statementId, row.updatedAt);
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'link statement row');
    }
  }

  static Future<void> _refreshStatementStatus(
    sqflite.Transaction tx,
    String statementId,
    DateTime updatedAt,
  ) async {
    final parents = await tx.query(
      'financial_statements',
      columns: ['status', 'payment_source_id'],
      where: 'id = ?',
      whereArgs: [statementId],
      limit: 1,
    );
    if (parents.isEmpty) return;
    final currentStatus = parents.single['status'] as String;
    if (currentStatus == StatementStatus.archived.name) return;
    final statementRows = await tx.query(
      'statement_rows',
      columns: ['status'],
      where: 'statement_id = ?',
      whereArgs: [statementId],
    );
    if (statementRows.isEmpty) return;
    final terminal = statementRows.every(
      (row) => const ['saved', 'linked', 'skipped'].contains(row['status']),
    );
    final hasTerminal = statementRows.any(
      (row) => const ['saved', 'linked', 'skipped'].contains(row['status']),
    );
    final status = parents.single['payment_source_id'] == null
        ? StatementStatus.needsSource
        : terminal
        ? StatementStatus.completed
        : hasTerminal
        ? StatementStatus.partial
        : StatementStatus.ready;
    await tx.update(
      'financial_statements',
      {
        'status': status.name,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [statementId],
    );
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
    'statement_date': _date(v.statementDate),
    'currency': v.currency,
    'opening_balance': v.openingBalance,
    'closing_balance': v.closingBalance,
    'original_filename': v.originalFilename,
    'raw_text_reference': v.rawTextReference,
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
        statementDate: _parseDate(r['statement_date']),
        currency: r['currency'] as String?,
        openingBalance: r['opening_balance'] as String?,
        closingBalance: r['closing_balance'] as String?,
        originalFilename: r['original_filename'] as String?,
        rawTextReference: r['raw_text_reference'] as String?,
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
    'merchant_id': v.merchantId,
    'category_id': v.categoryId,
    'subcategory_id': v.subcategoryId,
    'tag_ids': jsonEncode(v.tagIds),
    'payment_source_id': v.paymentSourceId,
    'source_reference_id': v.sourceReferenceId,
    'review_reason': v.reviewReason,
    'disposition_reason': v.dispositionReason,
    'status_before_skip': v.statusBeforeSkip?.name,
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
        merchantId: r['merchant_id'] as String?,
        categoryId: r['category_id'] as String?,
        subcategoryId: r['subcategory_id'] as String?,
        tagIds: _decodeTags(r['tag_ids']),
        paymentSourceId: r['payment_source_id'] as String?,
        sourceReferenceId: r['source_reference_id'] as String?,
        reviewReason: r['review_reason'] as String?,
        dispositionReason: r['disposition_reason'] as String?,
        statusBeforeSkip: r['status_before_skip'] == null
            ? null
            : StatementRowStatus.values.byName(
                r['status_before_skip']! as String,
              ),
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
      );

  static String? _date(DateTime? value) =>
      value?.toIso8601String().substring(0, 10);
  static DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static List<String> _decodeTags(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    return decoded is List
        ? decoded.whereType<String>().toList(growable: false)
        : const [];
  }

  Future<T> _mapped<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on DatabaseException catch (error) {
      final mapped = mapDatabaseException(error, operation);
      try {
        final version = await database.connection.getVersion();
        final columns = await database.connection.rawQuery(
          'PRAGMA table_info(statement_rows)',
        );
        final hasDispositionColumn = columns.any(
          (row) => row['name'] == 'status_before_skip',
        );
        throw RepositoryException(
          mapped.code,
          mapped.operation,
          detail:
              '${mapped.detail ?? 'sqlite error'}; '
              'db_version=$version; '
              'statement_rows.status_before_skip=$hasDispositionColumn',
        );
      } on RepositoryException {
        rethrow;
      } catch (_) {
        throw mapped;
      }
    }
  }
}
