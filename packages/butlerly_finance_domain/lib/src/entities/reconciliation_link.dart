import '../value_objects/domain_id.dart';

final class ReconciliationLink {
  const ReconciliationLink({
    required this.id,
    required this.candidateId,
    required this.receiptTransactionId,
    required this.paymentTransactionId,
    required this.createdAt,
  });

  final String id;
  final String candidateId;
  final TransactionId receiptTransactionId;
  final TransactionId paymentTransactionId;
  final DateTime createdAt;
}
