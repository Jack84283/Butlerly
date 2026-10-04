import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

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
  DateTime at,
) {
  final issueId = ReviewIssueId(
    '$merchantReviewIssuePrefix${transaction.id.value}',
  );
  final existing = transaction.reviewIssues
      .where((issue) => issue.id == issueId)
      .firstOrNull;
  final usableEvidence = normalizeMerchantName(
    merchantEvidenceFor(transaction),
  ).isNotEmpty;
  final needsReview =
      transaction.status == TransactionStatus.active &&
      transaction.merchantId == null &&
      usableEvidence;

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
