enum RepositoryFailureCode {
  unavailable,
  busy,
  constraint,
  notFound,
  migration,
  integrity,
  permission,
  storageFull,
  unknown,
}

final class RepositoryException implements Exception {
  const RepositoryException(this.code, this.operation);

  final RepositoryFailureCode code;
  final String operation;

  @override
  String toString() => 'RepositoryException($code, $operation)';
}
