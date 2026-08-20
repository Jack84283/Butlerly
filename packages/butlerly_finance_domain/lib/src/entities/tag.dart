import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum TagStatus { active, archived }

final class Tag {
  Tag({required this.id, required String name, this.status = TagStatus.active})
    : name = _validate(name);

  final TagId id;
  final String name;
  final TagStatus status;

  Tag archive() => Tag(id: id, name: name, status: TagStatus.archived);

  static String _validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'name',
        message: 'A tag name is required.',
      );
    }
    return normalized;
  }
}
