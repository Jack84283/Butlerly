import '../value_objects/domain_id.dart';

enum ReconciliationCandidateStatus { proposed, confirmed, rejected, undone }

final class ReconciliationCandidate {
  const ReconciliationCandidate({
    required this.id,
    required this.receiptTransactionId,
    required this.paymentTransactionId,
    required this.score,
    required this.reasons,
    this.status = ReconciliationCandidateStatus.proposed,
  });

  final String id;
  final TransactionId receiptTransactionId;
  final TransactionId paymentTransactionId;
  final double score;
  final List<String> reasons;
  final ReconciliationCandidateStatus status;

  ReconciliationCandidate confirm() => ReconciliationCandidate(
    id: id,
    receiptTransactionId: receiptTransactionId,
    paymentTransactionId: paymentTransactionId,
    score: score,
    reasons: reasons,
    status: ReconciliationCandidateStatus.confirmed,
  );

  ReconciliationCandidate reject() => ReconciliationCandidate(
    id: id,
    receiptTransactionId: receiptTransactionId,
    paymentTransactionId: paymentTransactionId,
    score: score,
    reasons: reasons,
    status: ReconciliationCandidateStatus.rejected,
  );

  ReconciliationCandidate undo() => ReconciliationCandidate(
    id: id,
    receiptTransactionId: receiptTransactionId,
    paymentTransactionId: paymentTransactionId,
    score: score,
    reasons: reasons,
    status: ReconciliationCandidateStatus.undone,
  );
}
