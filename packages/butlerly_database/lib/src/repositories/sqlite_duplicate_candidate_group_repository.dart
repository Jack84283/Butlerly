import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteDuplicateCandidateGroupRepository
    implements DuplicateCandidateGroupRepository {
  const SqliteDuplicateCandidateGroupRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async {
    final rows = await database.connection.query(
      'duplicate_candidate_groups',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'transaction_date, id',
    );
    return Future.wait(rows.map(_hydrate));
  }

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async {
    final rows = await database.connection.rawQuery(
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
  Future<void> save(DuplicateCandidateGroup group) async {
    try {
      await database.transaction((tx) async {
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
      await database.connection.delete(
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
    'created_at': group.createdAt.toIso8601String(),
    'updated_at': group.updatedAt.toIso8601String(),
  };

  Future<DuplicateCandidateGroup> _hydrate(Map<String, Object?> row) async {
    final links = await database.connection.query(
      'duplicate_candidate_group_transactions',
      columns: ['transaction_id'],
      where: 'group_id = ?',
      whereArgs: [row['id']],
      orderBy: 'transaction_id',
    );
    return DuplicateCandidateGroup(
      id: row['id']! as String,
      transactionIds: links
          .map((link) => TransactionId(link['transaction_id']! as String))
          .toList(growable: false),
      duplicateKey: DuplicateTransactionKey(
        transactionDate: row['transaction_date']! as String,
        amount: DecimalValue.fromParts(
          coefficient: BigInt.parse(row['amount_coefficient']! as String),
          scale: row['amount_scale']! as int,
        ),
        currency: row['currency']! as String,
        direction: row['direction']! as String,
      ),
      status: DuplicateCandidateGroupStatus.values.byName(
        row['status']! as String,
      ),
      selectedTransactionId: row['selected_transaction_id'] == null
          ? null
          : TransactionId(row['selected_transaction_id']! as String),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }
}
