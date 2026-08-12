import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum CategoryOrigin { system, user }

final class Category {
  Category({
    required this.id,
    required String name,
    required this.origin,
    this.parentId,
  }) : name = _validate(name) {
    if (parentId == id) {
      invalid(
        code: DomainErrorCode.relationshipMismatch,
        field: 'parentId',
        message: 'A category cannot be its own parent.',
      );
    }
  }

  final CategoryId id;
  final String name;
  final CategoryOrigin origin;

  /// The optional parent in Butlerly's maximum two-level V1 taxonomy.
  final CategoryId? parentId;

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
