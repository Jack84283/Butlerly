import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteReconciliationCandidateRepository
    implements ReconciliationCandidateRepository {
  const SqliteReconciliationCandidateRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> save(ReconciliationCandidate value) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await database.connection.insert('reconciliation_candidates', {
        'id': value.id,
        'receipt_transaction_id': value.receiptTransactionId.value,
        'payment_transaction_id': value.paymentTransactionId.value,
        'score': value.score,
        'reasons_json': jsonEncode(value.reasons),
        'status': value.status.name,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save reconciliation candidate');
    }
  }

  @override
  Future<ReconciliationCandidate?> findById(String id) async {
    final rows = await database.connection.query(
      'reconciliation_candidates',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<ReconciliationCandidate>> listAll() async {
    final rows = await database.connection.query(
      'reconciliation_candidates',
      orderBy: 'score DESC, created_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  static ReconciliationCandidate _fromRow(Map<String, Object?> row) {
    final reasons = jsonDecode(row['reasons_json']! as String) as List<dynamic>;
    return ReconciliationCandidate(
      id: row['id']! as String,
      receiptTransactionId: TransactionId(
        row['receipt_transaction_id']! as String,
      ),
      paymentTransactionId: TransactionId(
        row['payment_transaction_id']! as String,
      ),
      score: (row['score']! as num).toDouble(),
      reasons: reasons.cast<String>(),
      status: ReconciliationCandidateStatus.values.byName(
        row['status']! as String,
      ),
    );
  }
}
