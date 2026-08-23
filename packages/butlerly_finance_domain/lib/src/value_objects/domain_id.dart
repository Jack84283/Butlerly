import '../errors/domain_error.dart';

abstract class DomainId {
  DomainId(String value) : value = _validate(value);

  final String value;

  static String _validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'id',
        message: 'A Butlerly-owned identifier is required.',
      );
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is DomainId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class PaymentSourceId extends DomainId {
  PaymentSourceId(super.value);
}

typedef AccountId = PaymentSourceId;

final class AttachmentLinkId extends DomainId {
  AttachmentLinkId(super.value);
}

final class CategoryId extends DomainId {
  CategoryId(super.value);
}

final class EvidenceId extends DomainId {
  EvidenceId(super.value);
}

final class ExchangeRateId extends DomainId {
  ExchangeRateId(super.value);
}

final class ExtractionId extends DomainId {
  ExtractionId(super.value);
}

final class MerchantId extends DomainId {
  MerchantId(super.value);
}

final class ProvenanceId extends DomainId {
  ProvenanceId(super.value);
}

final class ReviewIssueId extends DomainId {
  ReviewIssueId(super.value);
}

final class SuggestionId extends DomainId {
  SuggestionId(super.value);
}

final class TagId extends DomainId {
  TagId(super.value);
}

final class ReferenceDataId extends DomainId {
  ReferenceDataId(super.value);
}

final class TransactionId extends DomainId {
  TransactionId(super.value);
}
