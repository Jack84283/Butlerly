import 'package:butlerly/core/application/application_result_guard.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful application result completes normally', () async {
    await expectLater(
      requireApplicationSuccess(
        Future.value(const ApplicationSuccess<int>(1)),
      ),
      completes,
    );
  });

  test('failed application result throws at orchestration boundary', () async {
    const failure = ApplicationFailure<int>(
      ApplicationFailureDetail(
        code: ApplicationFailureCode.storage,
        operation: 'seed initial master data',
        detail: 'disk full',
      ),
    );

    await expectLater(
      requireApplicationSuccess(Future.value(failure)),
      throwsA(isA<StateError>()),
    );
  });
}
