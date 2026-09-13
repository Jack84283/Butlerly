import 'package:butlerly_finance_application/butlerly_finance_application.dart';

/// Converts Butlerly's application-layer result contract into a throwing
/// boundary for orchestration that must not continue after a failed operation.
///
/// Restore/recovery uses this before declaring activation successful. Most
/// application use cases intentionally return [ApplicationFailure] instead of
/// throwing repository errors, so merely awaiting a use case is not sufficient
/// at that boundary.
Future<void> requireApplicationSuccess<T>(
  Future<ApplicationResult<T>> operation,
) async {
  final result = await operation;
  if (result is ApplicationFailure<T>) {
    final failure = result.failure;
    throw StateError(
      'Application operation failed: ${failure.operation} '
      '(${failure.code.name}).',
    );
  }
}
