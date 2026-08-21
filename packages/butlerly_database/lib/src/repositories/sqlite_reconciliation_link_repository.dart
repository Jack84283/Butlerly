import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteReconciliationLinkRepository
    implements ReconciliationLinkRepository {
  const SqliteReconciliationLinkRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> save(ReconciliationLink link) async {
    try {
      await database.connection.insert('reconciliation_links', {
        'id': link.id,
        'candidate_id': link.candidateId,
        'receipt_transaction_id': link.receiptTransactionId.value,
        'payment_transaction_id': link.paymentTransactionId.value,
        'created_at': link.createdAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save reconciliation link');
    }
  }

  @override
  Future<List<ReconciliationLink>> listAll() async {
    final rows = await database.connection.query(
      'reconciliation_links',
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => ReconciliationLink(
            id: row['id']! as String,
            candidateId: row['candidate_id']! as String,
            receiptTransactionId: TransactionId(
              row['receipt_transaction_id']! as String,
            ),
            paymentTransactionId: TransactionId(
              row['payment_transaction_id']! as String,
            ),
            createdAt: DateTime.parse(row['created_at']! as String),
          ),
        )
        .toList(growable: false);
  }
}
