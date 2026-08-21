import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum PaymentSourceType { account, card, debitCard, cash, wallet, other }

enum PaymentSourceStatus { active, archived }

final class PaymentSource {
  PaymentSource({
    required this.id,
    required String name,
    required this.type,
    this.status = PaymentSourceStatus.active,
    this.displayIdentity,
    String? lastFour,
    this.issuer,
    this.currency,
    this.note,
  }) : name = _requiredName(name),
       lastFour = _safeLastFour(lastFour);

  final PaymentSourceId id;
  final String name;
  final PaymentSourceType type;
  final PaymentSourceStatus status;
  final String? displayIdentity;
  final String? lastFour;
  final String? issuer;
  final String? currency;
  final String? note;

  PaymentSource archive() => PaymentSource(
    id: id,
    name: name,
    type: type,
    status: PaymentSourceStatus.archived,
    displayIdentity: displayIdentity,
    lastFour: lastFour,
    issuer: issuer,
    currency: currency,
    note: note,
  );

  static String _requiredName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'name',
        message: 'A payment source name is required.',
      );
    }
    return normalized;
  }

  static String? _safeLastFour(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(normalized)) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'lastFour',
        message: 'Only four card digits may be stored.',
      );
    }
    return normalized;
  }
}

typedef Account = PaymentSource;
