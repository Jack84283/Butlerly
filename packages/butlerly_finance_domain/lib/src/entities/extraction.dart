import 'dart:collection';

import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import 'provenance.dart';

final class Extraction {
  Extraction({
    required this.id,
    required this.evidenceId,
    required Map<String, String> values,
    required this.provenance,
    required DateTime createdAt,
  }) : values = UnmodifiableMapView(Map.of(values)),
       createdAt = createdAt.toUtc() {
    if (values.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'values',
        message: 'An extraction requires at least one derived value.',
      );
    }
  }

  final ExtractionId id;
  final EvidenceId evidenceId;
  final Map<String, String> values;
  final Provenance provenance;
  final DateTime createdAt;
}
