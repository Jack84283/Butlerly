import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum ReviewIssueReason {
  incomplete,
  uncertain,
  conflict,
  duplicateCandidate,
  other,
}

enum ReviewIssueStatus { active, resolved, dismissed }

final class ReviewIssue {
  ReviewIssue({
    required this.id,
    required this.transactionId,
    required this.reason,
    required DateTime createdAt,
    this.status = ReviewIssueStatus.active,
    this.detail,
    DateTime? closedAt,
  }) : createdAt = createdAt.toUtc(),
       closedAt = closedAt?.toUtc() {
    if (status == ReviewIssueStatus.active && closedAt != null) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'closedAt',
        message: 'An active review issue cannot have a close time.',
      );
    }
    if (status != ReviewIssueStatus.active && closedAt == null) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'closedAt',
        message: 'A closed review issue requires a close time.',
      );
    }
  }

  final ReviewIssueId id;
  final TransactionId transactionId;
  final ReviewIssueReason reason;
  final ReviewIssueStatus status;
  final String? detail;
  final DateTime createdAt;
  final DateTime? closedAt;

  ReviewIssue resolve(DateTime at) => _close(ReviewIssueStatus.resolved, at);
  ReviewIssue dismiss(DateTime at) => _close(ReviewIssueStatus.dismissed, at);

  ReviewIssue _close(ReviewIssueStatus nextStatus, DateTime at) {
    if (status != ReviewIssueStatus.active) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'status',
        message: 'Only an active review issue can be closed.',
      );
    }
    return ReviewIssue(
      id: id,
      transactionId: transactionId,
      reason: reason,
      createdAt: createdAt,
      status: nextStatus,
      detail: detail,
      closedAt: at,
    );
  }
}
