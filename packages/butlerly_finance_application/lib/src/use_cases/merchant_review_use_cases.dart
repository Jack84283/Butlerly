import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'classification_use_cases.dart';

const merchantReviewIssuePrefix = 'merchant-review:';

String merchantEvidenceFor(Transaction transaction) =>
    transaction.rawCounterparty?.trim().isNotEmpty == true
    ? transaction.rawCounterparty!.trim()
    : transaction.description?.trim() ?? '';

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
  final hasDeterministicMerchant =
      resolveMerchantFromEvidence(
        merchants,
        merchantEvidenceFor(transaction),
      ) !=
      null;
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
    return existing.status == ReviewIssueStatus.active
        ? transaction
        : transaction.reopenReviewIssue(issueId, at);
  }

  return existing?.status == ReviewIssueStatus.active
      ? transaction.resolveReviewIssue(issueId, at)
      : transaction;
}
