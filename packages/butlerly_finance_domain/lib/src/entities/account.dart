import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum PaymentSourceType { account, card, cash, wallet, other }

enum PaymentSourceStatus { active, archived }

final class PaymentSource {
  PaymentSource({
    required this.id,
    required String name,
    required this.type,
    this.status = PaymentSourceStatus.active,
  }) : name = _requiredName(name);

  final PaymentSourceId id;
  final String name;
  final PaymentSourceType type;
  final PaymentSourceStatus status;

  PaymentSource archive() => PaymentSource(
    id: id,
    name: name,
    type: type,
    status: PaymentSourceStatus.archived,
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
}

typedef Account = PaymentSource;
