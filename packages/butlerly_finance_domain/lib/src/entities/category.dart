import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum CategoryOrigin { system, user }

final class Category {
  Category({required this.id, required String name, required this.origin})
    : name = _validate(name);

  final CategoryId id;
  final String name;
  final CategoryOrigin origin;

  static String _validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'name',
        message: 'A category name is required.',
      );
    }
    return normalized;
  }
}
