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

  test('extracts restaurant subtotal tax tip and total', () {
    final result = ReceiptTextParser.parse('''
Harbor Grill
08/21/2026 7:42 PM
SUBTOTAL 42.00
TAX 3.78
TIP 8.00
TOTAL 53.78
Mastercard **** 2468
''');
    expect(result.merchant, 'Harbor Grill');
    expect(result.amount, '53.78');
    expect(result.tax, '3.78');
    expect(result.tip, '8.00');
    expect(result.cardLast4, '2468');
    expect(result.fieldConfidence['amount'], greaterThan(0));
    expect(result.fieldEvidence['amount'], contains('TOTAL'));
  });

  test('handles retail, grocery, masked PAN and Apple Pay formats', () {
    const cases = [
      ('NORTH MART\nTOTAL USD 18.20\nVISA XXXXXXXXXXXX1234', '1234'),
      ('FRESH MARKET\nTOTAL \$64.11\nDEBIT CARD **** **** 9988', '9988'),
      ('APPLE PAY\nTOTAL \$12.84\nAMEX •••• 7777', '7777'),
      ('DISCOVER CREDIT\nTOTAL \$29.99\nENDING 1357', '1357'),
    ];
    for (final item in cases) {
      final result = ReceiptTextParser.parse(item.$1);
      expect(result.cardLast4, item.$2, reason: item.$1);
      expect(result.amount, isNotNull, reason: item.$1);
    }
  });

  test('uses layout observations and ignores noisy header text', () {
    const observations = [
      OcrObservation(
        text: 'THANK YOU FOR SHOPPING',
        confidence: .99,
        left: 0,
        top: .02,
        width: 1,
        height: .04,
      ),
      OcrObservation(
        text: 'GREEN GROCER',
        confidence: .94,
        left: 0,
        top: .12,
        width: .8,
        height: .05,
      ),
      OcrObservation(
        text: 'Item 9999',
        confidence: .80,
        left: 0,
        top: .42,
        width: .5,
        height: .05,
      ),
      OcrObservation(
        text: 'TOTAL 21.50',
        confidence: .91,
        left: .5,
        top: .82,
        width: .5,
        height: .05,
      ),
      OcrObservation(
        text: '08/20/2026',
        confidence: .88,
        left: 0,
        top: .25,
        width: .5,
        height: .05,
      ),
    ];
    final result = ReceiptExtractor.extract(
      observations.map((value) => value.text).join('\n'),
      observations,
    );
    expect(result.merchant, 'GREEN GROCER');
    expect(result.amount, '21.50');
    expect(result.date, DateTime(2026, 8, 20));
    expect(result.observations, hasLength(5));
  });

  test('preserves low-quality OCR text and reports lower confidence', () {
    final result = ReceiptExtractor.extract('C0STC0\nT0TAL 12.84', const [
      OcrObservation(
        text: 'C0STC0',
        confidence: .31,
        left: 0,
        top: 0,
        width: 1,
        height: .1,
      ),
      OcrObservation(
        text: 'T0TAL 12.84',
        confidence: .42,
        left: 0,
        top: .8,
        width: 1,
        height: .1,
      ),
    ]);
    expect(result.rawText, contains('T0TAL'));
    expect(result.amount, '12.84');
    expect(result.fieldConfidence['amount'], lessThan(.5));
  });
}
