import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../use_cases/duplicate_review_use_cases.dart';

/// Keeps possible-duplicate review metadata current after any transaction
/// mutation without copying duplicate identity rules into each use case.
final class DuplicateReviewingTransactionRepository
    implements TransactionRepository, ReviewTransactionRepository {
  const DuplicateReviewingTransactionRepository(this.delegate, this.refresh);

  final TransactionRepository delegate;
  final RefreshDuplicateGroupForTransaction refresh;

  @override
  Future<void> save(Transaction transaction) async {
    final previous = await delegate.findById(transaction.id);
    await delegate.save(transaction);
    await _refreshReviewMetadata(previous: previous, current: transaction);
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    final previous = await delegate.findById(id);
    await delegate.removePermanently(id);
    await _refreshReviewMetadata(previous: previous);
  }

  @override
  Future<Transaction?> findById(TransactionId id) => delegate.findById(id);

  @override
  Future<List<Transaction>> listAll() => delegate.listAll();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) =>
      delegate.query(query);

  @override
  Future<List<Transaction>> queryTransactionsForReview() =>
      delegate is ReviewTransactionRepository
          ? (delegate as ReviewTransactionRepository).queryTransactionsForReview()
          : delegate.query(
              const TransactionRepositoryQuery(
                needsReview: true,
                status: TransactionStatus.active,
              ),
            );

  Future<void> _refreshReviewMetadata({
    Transaction? previous,
    Transaction? current,
  }) async {
    // A transaction mutation must remain authoritative even if review metadata
    // cannot be refreshed immediately; the Review rescan repairs it later.
    try {
      await refresh(previous: previous, current: current);
    } on Object {
      // Persistence failures are surfaced by the explicit rescan operation.
    }
  }
}
