enum DomainErrorCode {
  emptyValue,
  invalidCurrency,
  invalidDecimal,
  invalidRange,
  invalidState,
  invalidTimestamp,
  missingProvenance,
  relationshipMismatch,
}

class DomainValidationException implements Exception {
  const DomainValidationException({
    required this.code,
    required this.field,
    required this.message,
  });

  final DomainErrorCode code;
  final String field;
  final String message;

  @override
  String toString() => 'DomainValidationException($code, $field, $message)';
}

Never invalid({
  required DomainErrorCode code,
  required String field,
  required String message,
}) {
  throw DomainValidationException(code: code, field: field, message: message);
}
