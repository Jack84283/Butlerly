import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class ProvenanceDto {
  const ProvenanceDto({
    required this.sourceType,
    required this.capturedAt,
    this.sourceLanguage,
  });

  final String sourceType;
  final DateTime capturedAt;
  final String? sourceLanguage;

  factory ProvenanceDto.fromDomain(Provenance value) => ProvenanceDto(
    sourceType: value.sourceType.name,
    capturedAt: value.capturedAt,
    sourceLanguage: value.sourceLanguage,
  );
}
