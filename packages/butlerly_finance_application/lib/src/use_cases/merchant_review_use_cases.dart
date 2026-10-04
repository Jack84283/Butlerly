import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import 'classification_use_cases.dart';

const merchantReviewIssuePrefix = 'merchant-review:';

String merchantEvidenceForValues({
  String? rawCounterparty,
  String? description,
}) => description?.trim().isNotEmpty == true
    ? description!.trim()
    : rawCounterparty?.trim() ?? '';

String merchantEvidenceFor(Transaction transaction) =>
    merchantEvidenceForValues(
      rawCounterparty: transaction.rawCounterparty,
      description: transaction.description,
    );

/// Keeps the persisted merchant-review issue aligned with deterministic
/// merchant evidence. This does not perform fuzzy matching or mutate a
/// transaction's merchant assignment.
Transaction synchronizeMerchantReviewIssue(
  Transaction transaction,
  DateTime at, {
  Iterable<Merchant> merchants = const [],
}) {
  final issueId = ReviewIssueId(
    '$merchantReviewIssuePrefix${transaction.id.value}',
  );
  final existing = transaction.reviewIssues
      .where((issue) => issue.id == issueId)
      .firstOrNull;
  final usableEvidence = normalizeMerchantName(
    merchantEvidenceFor(transaction),
  ).isNotEmpty;
  final alternateEvidence = transaction.rawCounterparty?.trim() ?? '';
  final hasDeterministicMerchant =
      resolveMerchantFromEvidence(
            merchants,
            merchantEvidenceFor(transaction),
          ) !=
          null ||
      (alternateEvidence != merchantEvidenceFor(transaction) &&
          resolveMerchantFromEvidence(merchants, alternateEvidence) != null);
  final needsReview =
      transaction.status == TransactionStatus.active &&
      transaction.merchantId == null &&
      usableEvidence &&
      !hasDeterministicMerchant;

  if (needsReview) {
    if (existing == null) {
      return transaction.addReviewIssue(
        ReviewIssue(
          id: issueId,
          transactionId: transaction.id,
          reason: ReviewIssueReason.merchantNeedsReview,
          detail: 'Merchant identity needs review.',
          createdAt: at,
        ),
        at,
      );
    }
    return switch (existing.status) {
      ReviewIssueStatus.active => transaction,
      // Dismissal is a user decision. Ordinary synchronization must not
      // silently turn it back into an active review item.
      ReviewIssueStatus.dismissed => transaction,
      ReviewIssueStatus.resolved => transaction.reopenReviewIssue(issueId, at),
    };
  }

  return existing?.status == ReviewIssueStatus.active
      ? transaction.resolveReviewIssue(issueId, at)
      : transaction;
}

/// Reconciles merchant-review issues for transactions that predate the
/// persisted lifecycle synchronization.
///
/// This is intentionally idempotent so it can run during application startup
/// without changing already synchronized transactions.
final class SynchronizeMerchantReviewIssues {
  const SynchronizeMerchantReviewIssues(
    this.transactions,
    this.merchants,
    this.now,
  );

  final TransactionRepository transactions;
  final MerchantRepository merchants;
  final DateTime Function() now;

  Future<ApplicationResult<int>> call() =>
      runApplication('synchronize merchant review issues', () async {
        final values = await transactions.listAll();
        final configuredMerchants = await merchants.listAll();
        final at = now();
        var updatedCount = 0;
        for (final transaction in values) {
          final synchronized = synchronizeMerchantReviewIssue(
            transaction,
            at,
            merchants: configuredMerchants,
          );
          if (identical(synchronized, transaction)) continue;
          await transactions.save(synchronized);
          updatedCount++;
        }
        return updatedCount;
      });
}
