import '../value_objects/domain_id.dart';

final class AttachmentLink {
  AttachmentLink({
    required this.id,
    required this.transactionId,
    required this.evidenceId,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc();

  final AttachmentLinkId id;
  final TransactionId transactionId;
  final EvidenceId evidenceId;
  final DateTime createdAt;
}
