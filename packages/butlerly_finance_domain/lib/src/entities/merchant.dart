import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum MerchantStatus { active, archived }

final class Merchant {
  Merchant({
    required this.id,
    required String name,
    this.status = MerchantStatus.active,
    this.rawName,
  }) : name = _validate(name);

  final MerchantId id;
  final String name;
  final MerchantStatus status;
  final String? rawName;

  Merchant archive() => Merchant(
    id: id,
    name: name,
    status: MerchantStatus.archived,
    rawName: rawName,
  );

  static String _validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'name',
        message: 'A normalized merchant name is required.',
      );
    }
    return normalized;
  }
}
