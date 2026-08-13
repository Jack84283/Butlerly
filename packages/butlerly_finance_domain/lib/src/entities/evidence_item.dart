import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import 'provenance.dart';

enum EvidenceType { receiptImage, document, importedRecord, other }

final class EvidenceItem {
  EvidenceItem({
    required this.id,
    required this.type,
    required String originalName,
    required String mediaType,
    required this.provenance,
    required DateTime createdAt,
    this.sourceLanguage,
    this.localFileName,
  }) : originalName = _required(originalName, 'originalName'),
       mediaType = _required(mediaType, 'mediaType'),
       createdAt = createdAt.toUtc();

  final EvidenceId id;
  final EvidenceType type;
  final String originalName;
  final String mediaType;
  final Provenance provenance;
  final DateTime createdAt;
  final String? sourceLanguage;
  final String? localFileName;

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: field,
        message: '$field is required for original evidence.',
      );
    }
    return normalized;
  }
}
