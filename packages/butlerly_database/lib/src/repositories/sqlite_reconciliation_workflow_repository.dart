import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteReconciliationWorkflowRepository
    implements ReconciliationWorkflowRepository {
  const SqliteReconciliationWorkflowRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> confirm(
    ReconciliationCandidate candidate,
    ReconciliationLink link,
  ) async {
    if (link.candidateId != candidate.id ||
        link.receiptTransactionId != candidate.receiptTransactionId ||
        link.paymentTransactionId != candidate.paymentTransactionId) {
      throw const RepositoryException(
        RepositoryFailureCode.constraint,
        'reconciliation link does not match candidate',
      );
    }
    try {
      await database.transaction((transaction) async {
        final rows = await transaction.query(
          'reconciliation_candidates',
          columns: [
            'status',
            'receipt_transaction_id',
            'payment_transaction_id',
          ],
          where: 'id = ?',
          whereArgs: [candidate.id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'confirm reconciliation candidate',
          );
        }
        final endpointConflicts = await transaction.query(
          'reconciliation_links',
          columns: ['id'],
          where:
              '(receipt_transaction_id = ? OR payment_transaction_id = ?) '
              'AND candidate_id != ?',
          whereArgs: [
            candidate.receiptTransactionId.value,
            candidate.paymentTransactionId.value,
            candidate.id,
          ],
        );
        if (endpointConflicts.isNotEmpty) {
          throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'reconciliation endpoint is already linked',
          );
        }
        final row = rows.single;
        if (row['receipt_transaction_id'] !=
                candidate.receiptTransactionId.value ||
            row['payment_transaction_id'] !=
                candidate.paymentTransactionId.value) {
          throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'reconciliation candidate endpoints do not match',
          );
        }
        final status = row['status'] as String;
        if (status == ReconciliationCandidateStatus.confirmed.name) {
          final existing = await transaction.query(
            'reconciliation_links',
            where: 'candidate_id = ?',
            whereArgs: [candidate.id],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            final existingLink = existing.single;
            if (existingLink['receipt_transaction_id'] !=
                    candidate.receiptTransactionId.value ||
                existingLink['payment_transaction_id'] !=
                    candidate.paymentTransactionId.value) {
              throw const RepositoryException(
                RepositoryFailureCode.constraint,
                'stored reconciliation link endpoints do not match',
              );
            }
            return;
          }
        }
        if (status != ReconciliationCandidateStatus.proposed.name) {
          throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'reconciliation candidate is not proposed',
          );
        }
        final now = DateTime.now().toUtc().toIso8601String();
        await transaction.update(
          'reconciliation_candidates',
          {
            'status': ReconciliationCandidateStatus.confirmed.name,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [candidate.id],
        );
        await transaction.insert('reconciliation_links', {
          'id': link.id,
          'candidate_id': link.candidateId,
          'receipt_transaction_id': link.receiptTransactionId.value,
          'payment_transaction_id': link.paymentTransactionId.value,
          'created_at': link.createdAt.toUtc().toIso8601String(),
        });
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'confirm reconciliation');
    }
  }

  @override
  Future<void> reject(ReconciliationCandidate candidate) async {
    try {
      await database.transaction((transaction) async {
        final rows = await transaction.query(
          'reconciliation_candidates',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [candidate.id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'reject reconciliation candidate',
          );
        }
        if (rows.single['status'] !=
            ReconciliationCandidateStatus.proposed.name) {
          throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'reconciliation candidate is not proposed',
          );
        }
        await transaction.update(
          'reconciliation_candidates',
          {
            'status': ReconciliationCandidateStatus.rejected.name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [candidate.id],
        );
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'reject reconciliation');
    }
  }
}
