import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteDuplicateCandidateGroupRepository
    implements DuplicateCandidateGroupRepository {
  const SqliteDuplicateCandidateGroupRepository(this.database)
    : _executor = null;

  const SqliteDuplicateCandidateGroupRepository.forExecutor(
    DatabaseExecutor executor,
  ) : database = null,
      _executor = executor;

  final ButlerlyDatabase? database;
  final DatabaseExecutor? _executor;

  DatabaseExecutor get _readExecutor => _executor ?? database!.connection;

  static Future<List<DuplicateCandidateGroup>> listWithExecutor(
    DatabaseExecutor executor, {
    DuplicateCandidateGroupStatus? status,
  }) => SqliteDuplicateCandidateGroupRepository.forExecutor(
    executor,
  ).list(status: status);

  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async {
    final rows = await _readExecutor.query(
      'duplicate_candidate_groups',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'transaction_date, id',
    );
    final result = <DuplicateCandidateGroup>[];
    for (final row in rows) {
      try {
        result.add(await _hydrate(row));
      } on Object {
        result.add(await _hydrateMalformed(row));
      }
    }
    return result;
  }

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async {
    final rows = await _readExecutor.rawQuery(
      '''
      SELECT t.transaction_date, t.amount_coefficient,
             t.amount_scale, UPPER(t.currency) AS currency, t.direction,
             GROUP_CONCAT(t.id) AS transaction_ids
      FROM transactions t
      WHERE t.status = ? AND t.transaction_date IS NOT NULL
      GROUP BY t.transaction_date, t.amount_coefficient,
               t.amount_scale, UPPER(t.currency), t.direction
      HAVING COUNT(*) > 1
      ORDER BY t.transaction_date, t.amount_coefficient,
               t.amount_scale, UPPER(t.currency), t.direction
    ''',
      [TransactionStatus.active.name],
    );
    return rows
        .map((row) {
          final key = DuplicateTransactionKey(
            transactionDate: row['transaction_date']! as String,
            amount: DecimalValue.fromParts(
              coefficient: BigInt.parse(row['amount_coefficient']! as String),
              scale: row['amount_scale']! as int,
            ),
            currency: row['currency']! as String,
            direction: row['direction']! as String,
          );
          final transactionIds =
              (row['transaction_ids']! as String)
                  .split(',')
                  .map(TransactionId.new)
                  .toList()
                ..sort((a, b) => a.value.compareTo(b.value));
          return DuplicateTransactionGroupMatch(
            duplicateKey: key,
            transactionIds: List.unmodifiable(transactionIds),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async {
    final rows = await _readExecutor.query(
      'transactions',
      columns: ['id'],
      where:
          'transaction_date = ? AND amount_coefficient = ? AND '
          'amount_scale = ? AND UPPER(currency) = ? AND direction = ? AND '
          'status = ?',
      whereArgs: [
        key.transactionDate,
        key.amount.coefficient.toString(),
        key.amount.scale,
        key.currency,
        key.direction,
        TransactionStatus.active.name,
      ],
      orderBy: 'id',
    );
    return rows
        .map((row) => TransactionId(row['id']! as String))
        .toList(growable: false);
  }

  @override
  Future<void> save(DuplicateCandidateGroup group) async {
    try {
      await database!.transaction((tx) async {
        await tx.insert(
          'duplicate_candidate_groups',
          _groupRow(group),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await tx.delete(
          'duplicate_candidate_group_transactions',
          where: 'group_id = ?',
          whereArgs: [group.id],
        );
        for (final id in group.transactionIds) {
          await tx.insert('duplicate_candidate_group_transactions', {
            'group_id': group.id,
            'transaction_id': id.value,
          });
        }
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save duplicate candidate group');
    }
  }

  @override
  Future<void> remove(String id) async {
    try {
      await database!.connection.delete(
        'duplicate_candidate_groups',
        where: 'id = ?',
        whereArgs: [id],
      );
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'remove duplicate candidate group');
    }
  }

  Map<String, Object?> _groupRow(DuplicateCandidateGroup group) => {
    'id': group.id,
    'transaction_date': group.duplicateKey.transactionDate,
    'amount_coefficient': group.duplicateKey.amount.coefficient.toString(),
    'amount_scale': group.duplicateKey.amount.scale,
    'currency': group.duplicateKey.currency.trim().toUpperCase(),
    'direction': group.duplicateKey.direction,
    'status': group.status.name,
    'selected_transaction_id': group.selectedTransactionId?.value,
    'statement_rows': jsonEncode([
      for (final row in group.statementRows)
        {'statementId': row.statementId, 'rowId': row.rowId},
    ]),
    'created_at': group.createdAt.toIso8601String(),
    'updated_at': group.updatedAt.toIso8601String(),
  };

  Future<DuplicateCandidateGroup> _hydrate(Map<String, Object?> row) async {
    final links = await _readExecutor.query(
      'duplicate_candidate_group_transactions',
      columns: ['transaction_id'],
      where: 'group_id = ?',
      whereArgs: [row['id']],
      orderBy: 'transaction_id',
    );
    final duplicateKey = DuplicateTransactionKey(
      transactionDate: row['transaction_date']! as String,
      amount: DecimalValue.fromParts(
        coefficient: BigInt.parse(row['amount_coefficient']! as String),
        scale: row['amount_scale']! as int,
      ),
      currency: row['currency']! as String,
      direction: row['direction']! as String,
    );
    final statementRows = _statementRows(row['statement_rows']);
    final statementRowsIssue = await _statementRowsIssue(row['statement_rows']);
    final membership = await _completeMembership(
      duplicateKey,
      links
          .map((link) => TransactionId(link['transaction_id']! as String))
          .toList(growable: false),
      statementRows,
    );
    final storedStatus = DuplicateCandidateGroupStatus.values.byName(
      row['status']! as String,
    );
    // Recheck all saved groups, including unresolved ones. A transaction can
    // be edited after a resolved decision is reopened, and the reopened state
    // must remain detectable after persistence/restart without relying on an
    // in-memory integrity marker.
    final stale = await _hasStaleTransactionFacts(duplicateKey, membership.ids);
    final integrityIssue = stale
        ? const DuplicateCandidateGroupIntegrityIssue(
            code: 'staleDuplicateGroup',
            detail:
                'A saved duplicate decision no longer matches one or more transaction facts; it was reopened for repair.',
          )
        : statementRowsIssue ?? membership.issue;
    final needsRepair =
        stale || statementRowsIssue != null || membership.issue != null;
    return DuplicateCandidateGroup(
      id: row['id']! as String,
      transactionIds: membership.ids,
      duplicateKey: duplicateKey,
      status: needsRepair
          ? DuplicateCandidateGroupStatus.unresolved
          : storedStatus,
      selectedTransactionId:
          needsRepair || row['selected_transaction_id'] == null
          ? null
          : TransactionId(row['selected_transaction_id']! as String),
      statementRows: statementRows,
      integrityIssue: integrityIssue,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  Future<DuplicateCandidateGroup> _hydrateMalformed(
    Map<String, Object?> row,
  ) async {
    final transactionIds = <TransactionId>[];
    try {
      final links = await _readExecutor.query(
        'duplicate_candidate_group_transactions',
        columns: ['transaction_id'],
        where: 'group_id = ?',
        whereArgs: [row['id']],
        orderBy: 'transaction_id',
      );
      for (final link in links) {
        final id = link['transaction_id'];
        if (id is String && id.isNotEmpty) {
          transactionIds.add(TransactionId(id));
        }
      }
    } on Object {
      // Preserve the group-level repair issue even if its membership links are
      // damaged as well; analysis will continue with a global limitation.
    }

    final key =
        _tryKey(row) ?? await _firstLinkedTransactionKey(transactionIds);
    final statementRows = _statementRows(row['statement_rows']);
    final statementRowsIssue = await _statementRowsIssue(row['statement_rows']);
    final membership = key == null
        ? (
            ids: List<TransactionId>.unmodifiable(transactionIds),
            issue: const DuplicateCandidateGroupIntegrityIssue(
              code: 'malformedDuplicateGroup',
              detail:
                  'A saved duplicate decision could not be reconstructed; a stable representative is used until the decision is repaired.',
            ),
          )
        : await _completeMembership(key, transactionIds, statementRows);
    return DuplicateCandidateGroup(
      id: row['id'] as String? ?? 'malformed-duplicate-group',
      transactionIds: membership.ids,
      duplicateKey:
          key ??
          DuplicateTransactionKey(
            transactionDate: '',
            amount: DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0),
            currency: '',
            direction: '',
          ),
      status: DuplicateCandidateGroupStatus.unresolved,
      selectedTransactionId: null,
      statementRows: statementRows,
      integrityIssue:
          statementRowsIssue ??
          membership.issue ??
          const DuplicateCandidateGroupIntegrityIssue(
            code: 'malformedDuplicateGroup',
            detail:
                'A saved duplicate decision could not be reconstructed; a stable representative is used until the decision is repaired.',
          ),
      createdAt:
          _tryDate(row['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          _tryDate(row['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<
    ({List<TransactionId> ids, DuplicateCandidateGroupIntegrityIssue? issue})
  >
  _completeMembership(
    DuplicateTransactionKey key,
    List<TransactionId> linkedIds,
    List<DuplicateCandidateStatementRow> statementRows,
  ) async {
    final matchingIds = await _findHistoricalTransactionIdsForKey(key);
    final linked = linkedIds.toSet();
    final missing = matchingIds.where((id) => !linked.contains(id)).toList();
    final ids = <TransactionId>{...linkedIds, ...matchingIds}.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    final issue =
        (ids.length < 2 && statementRows.isEmpty) ||
            (linkedIds.isEmpty && statementRows.isEmpty) ||
            missing.isNotEmpty
        ? const DuplicateCandidateGroupIntegrityIssue(
            code: 'incompleteDuplicateGroup',
            detail:
                'Saved duplicate membership was incomplete or has fewer than two surviving members; matching historical transactions were restored into the unresolved decision until it is repaired.',
          )
        : null;
    return (ids: List<TransactionId>.unmodifiable(ids), issue: issue);
  }

  Future<bool> _hasStaleTransactionFacts(
    DuplicateTransactionKey key,
    List<TransactionId> ids,
  ) async {
    for (final id in ids) {
      final rows = await _readExecutor.query(
        'transactions',
        columns: [
          'transaction_date',
          'amount_coefficient',
          'amount_scale',
          'currency',
          'direction',
        ],
        where: 'id = ?',
        whereArgs: [id.value],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final value = _tryKey(rows.single);
      if (value == null || value != key) return true;
    }
    return false;
  }

  List<DuplicateCandidateStatementRow> _statementRows(Object? value) {
    if (value is! String || value.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) {
            final statementId = entry['statementId'];
            final rowId = entry['rowId'];
            if (statementId is! String ||
                statementId.isEmpty ||
                rowId is! String ||
                rowId.isEmpty) {
              return null;
            }
            return DuplicateCandidateStatementRow(
              statementId: statementId,
              rowId: rowId,
            );
          })
          .whereType<DuplicateCandidateStatementRow>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<DuplicateCandidateGroupIntegrityIssue?> _statementRowsIssue(
    Object? value,
  ) async {
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return _malformedStatementRowsIssue;
      for (final entry in decoded) {
        if (entry is! Map) return _malformedStatementRowsIssue;
        final statementId = entry['statementId'];
        final rowId = entry['rowId'];
        if (statementId is! String ||
            statementId.isEmpty ||
            rowId is! String ||
            rowId.isEmpty) {
          return _malformedStatementRowsIssue;
        }
      }
      for (final reference in _statementRows(value)) {
        final rows = await _readExecutor.query(
          'statement_rows',
          columns: ['id'],
          where: 'id = ? AND statement_id = ?',
          whereArgs: [reference.rowId, reference.statementId],
          limit: 1,
        );
        if (rows.isEmpty) return _malformedStatementRowsIssue;
      }
      return null;
    } on Object {
      return _malformedStatementRowsIssue;
    }
  }

  static const _malformedStatementRowsIssue = DuplicateCandidateGroupIntegrityIssue(
    code: 'malformedStatementDuplicateEvidence',
    detail:
        'Statement duplicate evidence could not be reconstructed; the duplicate decision was reopened for repair.',
  );

  Future<List<TransactionId>> _findHistoricalTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async {
    final rows = await _readExecutor.query(
      'transactions',
      columns: ['id'],
      where:
          'transaction_date = ? AND amount_coefficient = ? AND '
          'amount_scale = ? AND UPPER(currency) = ? AND direction = ? AND '
          'status IN (?, ?)',
      whereArgs: [
        key.transactionDate,
        key.amount.coefficient.toString(),
        key.amount.scale,
        key.currency.trim().toUpperCase(),
        key.direction,
        TransactionStatus.active.name,
        TransactionStatus.archived.name,
      ],
      orderBy: 'id',
    );
    return rows
        .map((row) => TransactionId(row['id']! as String))
        .toList(growable: false);
  }

  Future<DuplicateTransactionKey?> _firstLinkedTransactionKey(
    List<TransactionId> transactionIds,
  ) async {
    for (final id in transactionIds) {
      final rows = await _readExecutor.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id.value],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final key = _tryKey(rows.single);
      if (key != null) return key;
    }
    return null;
  }

  DuplicateTransactionKey? _tryKey(Map<String, Object?> row) {
    final date = row['transaction_date'];
    final coefficient = row['amount_coefficient'];
    final scale = row['amount_scale'];
    final currency = row['currency'];
    final direction = row['direction'];
    if (date is! String ||
        coefficient is! String ||
        scale is! int ||
        currency is! String ||
        direction is! String) {
      return null;
    }
    try {
      return DuplicateTransactionKey(
        transactionDate: date,
        amount: DecimalValue.fromParts(
          coefficient: BigInt.parse(coefficient),
          scale: scale,
        ),
        currency: currency,
        direction: direction,
      );
    } on Object {
      return null;
    }
  }

  DateTime? _tryDate(Object? value) {
    if (value is! String) return null;
    try {
      return DateTime.parse(value);
    } on FormatException {
      return null;
    }
  }
}
