import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

final class Merchant {
  Merchant({required this.id, required String name}) : name = _validate(name);

  final MerchantId id;
  final String name;

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
