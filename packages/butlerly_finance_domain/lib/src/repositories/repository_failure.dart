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
  const RepositoryException(this.code, this.operation, {this.detail});

  final RepositoryFailureCode code;
  final String operation;
  final String? detail;

  @override
  String toString() => 'RepositoryException($code, $operation)';
}
