import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parses representative receipt fields without translating source text',
    () {
      const text = '''
COSTCO WHOLESALE
08/16/2026
SUBTOTAL 118.92
TAX 7.50
TOTAL \$126.42
VISA **** 1234
''';

      final result = ReceiptTextParser.parse(text);

      expect(result.rawText, text);
      expect(result.merchant, 'COSTCO WHOLESALE');
      expect(result.amount, '126.42');
      expect(result.currency, 'USD');
      expect(result.date, DateTime(2026, 8, 16));
      expect(result.tax, '7.50');
      expect(result.cardLast4, '1234');
    },
  );

  test('prefers labeled total over unrelated larger values', () {
    const text = '''
STORE
ITEM CODE 9999.99
TOTAL 42.18
''';

    expect(ReceiptTextParser.parse(text).amount, '42.18');
  });

  test('parses whole-number receipt amounts', () {
    const text = '''
STORE
TOTAL \$25
''';

    expect(ReceiptTextParser.parse(text).amount, '25');
  });

  test(
    'extracts safe card recognition fields without retaining card number',
    () {
      const text = '''
VISA
JOHN DOE
**** **** **** 4321
''';

      final result = CardTextParser.parse(text);

      expect(result.issuer, 'Visa');
      expect(result.lastFour, '4321');
      expect(result.lastFour, isNot(contains('4111')));
    },
  );
}
