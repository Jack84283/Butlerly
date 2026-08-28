import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../use_cases/duplicate_review_use_cases.dart';

/// Keeps possible-duplicate review metadata current after any transaction
/// mutation without copying duplicate identity rules into each use case.
final class DuplicateReviewingTransactionRepository
    implements TransactionRepository {
  const DuplicateReviewingTransactionRepository(this.delegate, this.groups);

  final TransactionRepository delegate;
  final ScanExistingTransactionsForDuplicates groups;

  @override
  Future<void> save(Transaction transaction) async {
    await delegate.save(transaction);
    await _refreshReviewMetadata();
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    await delegate.removePermanently(id);
    await _refreshReviewMetadata();
  }

  @override
  Future<Transaction?> findById(TransactionId id) => delegate.findById(id);

  @override
  Future<List<Transaction>> listAll() => delegate.listAll();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) =>
      delegate.query(query);

  Future<void> _refreshReviewMetadata() async {
    // A transaction mutation must remain authoritative even if review metadata
    // cannot be refreshed immediately; the Review rescan repairs it later.
    try {
      await groups();
    } on Object {
      // Persistence failures are surfaced by the explicit rescan operation.
    }
  }
}
