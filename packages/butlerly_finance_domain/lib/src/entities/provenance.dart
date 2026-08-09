import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum ProvenanceSourceType {
  userEntry,
  import,
  scan,
  evidenceExtraction,
  integration,
  deterministicCalculation,
  localAi,
  externalAi,
  migration,
}

final class Provenance {
  Provenance({
    required this.id,
    required this.sourceType,
    required DateTime capturedAt,
    this.sourceId,
    this.originalRepresentation,
    this.sourceLanguage,
  }) : capturedAt = capturedAt.toUtc() {
    if (_requiresOriginalRepresentation(sourceType) &&
        (originalRepresentation == null || originalRepresentation!.isEmpty)) {
      invalid(
        code: DomainErrorCode.missingProvenance,
        field: 'originalRepresentation',
        message:
            'Imported, scanned, extracted, and AI-derived values require provenance.',
      );
    }
  }

  final ProvenanceId id;
  final ProvenanceSourceType sourceType;
  final DateTime capturedAt;
  final String? sourceId;
  final String? originalRepresentation;
  final String? sourceLanguage;

  static bool _requiresOriginalRepresentation(ProvenanceSourceType sourceType) {
    return switch (sourceType) {
      ProvenanceSourceType.import ||
      ProvenanceSourceType.scan ||
      ProvenanceSourceType.evidenceExtraction ||
      ProvenanceSourceType.localAi ||
      ProvenanceSourceType.externalAi => true,
      _ => false,
    };
  }
}
