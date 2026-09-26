import 'dart:collection';

import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum MerchantMatchingStatus { active, archived }

final class MerchantAlias {
  MerchantAlias({
    required this.id,
    required this.merchantId,
    required String alias,
    String? normalizedAlias,
    this.status = MerchantMatchingStatus.active,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : alias = _required(alias, 'alias'),
       normalizedAlias = _normalized(normalizedAlias, alias),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (this.normalizedAlias.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'normalizedAlias',
        message: 'A merchant alias must contain matchable text.',
      );
    }
  }

  final MerchantAliasId id;
  final MerchantId merchantId;
  final String alias;
  final String normalizedAlias;
  final MerchantMatchingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  MerchantAlias archive(DateTime at) => MerchantAlias(
    id: id,
    merchantId: merchantId,
    alias: alias,
    normalizedAlias: normalizedAlias,
    status: MerchantMatchingStatus.archived,
    createdAt: createdAt,
    updatedAt: at,
  );
}

final class MerchantNormalizationPattern {
  MerchantNormalizationPattern({
    required this.id,
    required this.merchantId,
    required String pattern,
    String? normalizedPattern,
    this.status = MerchantMatchingStatus.active,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : pattern = _required(pattern, 'pattern'),
       normalizedPattern = _normalized(normalizedPattern, pattern),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (this.normalizedPattern.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'normalizedPattern',
        message: 'A normalization pattern must contain matchable text.',
      );
    }
  }

  final MerchantNormalizationPatternId id;
  final MerchantId merchantId;
  final String pattern;
  final String normalizedPattern;
  final MerchantMatchingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  MerchantNormalizationPattern archive(DateTime at) =>
      MerchantNormalizationPattern(
        id: id,
        merchantId: merchantId,
        pattern: pattern,
        normalizedPattern: normalizedPattern,
        status: MerchantMatchingStatus.archived,
        createdAt: createdAt,
        updatedAt: at,
      );
}

UnmodifiableListView<MerchantAlias> immutableAliases(
  Iterable<MerchantAlias> values,
) => UnmodifiableListView(List.of(values));

UnmodifiableListView<MerchantNormalizationPattern> immutablePatterns(
  Iterable<MerchantNormalizationPattern> values,
) => UnmodifiableListView(List.of(values));

String normalizeMerchantName(String value) {
  var normalized = value.toLowerCase().trim();
  normalized = normalized.replaceAll(RegExp(r"[^a-z0-9]+"), ' ');
  normalized = normalized.replaceAll(
    RegExp(r'\b(store|location|#)?\s*\d{2,}\b'),
    ' ',
  );
  return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalized(String? value, String fallback) => normalizeMerchantName(
  value == null || value.trim().isEmpty ? fallback : value,
);

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    invalid(
      code: DomainErrorCode.emptyValue,
      field: field,
      message: '$field is required.',
    );
  }
  return normalized;
}
