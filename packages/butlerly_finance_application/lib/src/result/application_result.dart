import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

sealed class ApplicationResult<T> {
  const ApplicationResult();
}

final class ApplicationSuccess<T> extends ApplicationResult<T> {
  const ApplicationSuccess(this.value);

  final T value;
}

final class ApplicationFailure<T> extends ApplicationResult<T> {
  const ApplicationFailure(this.failure);

  final ApplicationFailureDetail failure;
}

enum ApplicationFailureCode {
  validation,
  notFound,
  conflict,
  unavailable,
  permission,
  storage,
  unknown,
}

final class ApplicationFailureDetail {
  const ApplicationFailureDetail({
    required this.code,
    required this.operation,
    this.field,
    this.detail,
  });

  final ApplicationFailureCode code;
  final String operation;
  final String? field;
  final String? detail;
}

Future<ApplicationResult<T>> runApplication<T>(
  String operation,
  Future<T> Function() action,
) async {
  try {
    return ApplicationSuccess<T>(await action());
  } on DomainValidationException catch (error) {
    return ApplicationFailure<T>(
      ApplicationFailureDetail(
        code: ApplicationFailureCode.validation,
        operation: operation,
        field: error.field,
        detail: error.message,
      ),
    );
  } on RepositoryException catch (error) {
    return ApplicationFailure<T>(
      ApplicationFailureDetail(
        code: _mapRepositoryCode(error.code),
        operation: operation,
        detail: error.detail,
      ),
    );
  }
}

ApplicationFailureCode _mapRepositoryCode(RepositoryFailureCode code) {
  return switch (code) {
    RepositoryFailureCode.notFound => ApplicationFailureCode.notFound,
    RepositoryFailureCode.constraint => ApplicationFailureCode.conflict,
    RepositoryFailureCode.unavailable ||
    RepositoryFailureCode.busy ||
    RepositoryFailureCode.migration ||
    RepositoryFailureCode.integrity => ApplicationFailureCode.unavailable,
    RepositoryFailureCode.permission => ApplicationFailureCode.permission,
    RepositoryFailureCode.storageFull => ApplicationFailureCode.storage,
    RepositoryFailureCode.unknown => ApplicationFailureCode.unknown,
  };
}

ApplicationFailure<T> notFound<T>(String operation) => ApplicationFailure<T>(
  ApplicationFailureDetail(
    code: ApplicationFailureCode.notFound,
    operation: operation,
  ),
);
