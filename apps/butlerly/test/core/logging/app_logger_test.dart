import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts financial values and user-entered fields from log messages', () {
    final message = AppLogger.redact(
      'merchant: Corner Cafe, amount: 42.50 USD, receipt=IMG_1234.jpg, card 4242424242424242',
    );

    expect(message, isNot(contains('Corner Cafe')));
    expect(message, isNot(contains('42.50')));
    expect(message, isNot(contains('IMG_1234')));
    expect(message, isNot(contains('4242424242424242')));
    expect(message, contains('[redacted]'));
  });
}
