import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

enum ReferenceDataOrigin { system, user }

enum ReferenceDataStatus { active, archived }

final class ReferenceData {
  ReferenceData({
    required this.id,
    required String code,
    required String type,
    this.origin = ReferenceDataOrigin.system,
    this.status = ReferenceDataStatus.active,
  }) : code = _required(code),
       type = _required(type);

  final ReferenceDataId id;
  final String code;
  final String type;
  final ReferenceDataOrigin origin;
  final ReferenceDataStatus status;

  ReferenceData archive() => ReferenceData(
    id: id,
    code: code,
    type: type,
    origin: origin,
    status: ReferenceDataStatus.archived,
  );

  static String _required(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'referenceData',
        message: 'Reference data values cannot be empty.',
      );
    }
    return normalized;
  }
}
