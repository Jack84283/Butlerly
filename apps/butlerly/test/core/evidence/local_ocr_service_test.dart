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

  test('payment-source card scan extracts last four from a full PAN', () {
    final result = CardTextParser.parse('''
VISA
JOHN DOE
4111 1111 1111 1234
''');
    expect(result.issuer, 'Visa');
    expect(result.lastFour, '1234');
    expect(result.lastFour, isNot('4111'));
  });

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

  test('normalizes degraded total and supports named and two-digit dates', () {
    final result = ReceiptTextParser.parse('''
RESTAURANT
Aug 21, 2026 19:42
SUBTOTAL 20.00
TAX 1.80
T0TA1 21.80
''');
    expect(result.amount, '21.80');
    expect(result.date, DateTime(2026, 8, 21));

    expect(
      ReceiptTextParser.parse('SHOP\n08/21/26\nTOTAL 10.00').date,
      DateTime(2026, 8, 21),
    );
  });

  test('supports split total label and split payment observations', () {
    const observations = [
      OcrObservation(
        text: 'V1SA',
        confidence: .88,
        left: .05,
        top: .78,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: '**** ****',
        confidence: .82,
        left: .28,
        top: .78,
        width: .3,
        height: .04,
      ),
      OcrObservation(
        text: '1234',
        confidence: .91,
        left: .62,
        top: .78,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: 'TOTAL',
        confidence: .91,
        left: .05,
        top: .70,
        width: .3,
        height: .04,
      ),
      OcrObservation(
        text: '42.18',
        confidence: .90,
        left: .65,
        top: .70,
        width: .2,
        height: .04,
      ),
    ];
    final result = ReceiptExtractor.extract(
      'V1SA **** **** 1234\nTOTAL 42.18',
      observations,
    );
    expect(result.amount, '42.18');
    expect(result.cardLast4, '1234');
  });

  test('does not promote generic header text to merchant', () {
    final result = ReceiptTextParser.parse('''
WELCOME
THANK YOU FOR SHOPPING
RECEIPT
TOTAL 24.50
''');
    expect(result.merchant, isNull);
    expect(result.amount, '24.50');
  });

  test('rejects invoice and reference identifiers as amounts', () {
    final result = ReceiptTextParser.parse('''
GOOD MARKET
INVOICE NO 999999.99
ORDER 888888
AUTH 123456
TOTAL 24.50
''');
    expect(result.merchant, 'GOOD MARKET');
    expect(result.amount, '24.50');
  });

  test('leaves date unresolved when the receipt has no transaction date', () {
    final result = ReceiptTextParser.parse('''
GOOD MARKET
LOYALTY ID 20260821
RETURN BY 12/31/2027
TOTAL 24.50
''');
    expect(result.date, isNull);
  });

  test('extracts structured card metadata only from a payment region', () {
    final result = ReceiptTextParser.parse('''
GOOD MARKET
STORE NO 1234
TOTAL \$24.50
VISA
CREDIT **** **** 5678
EXP 08/29
''');
    expect(result.cardLast4, '5678');
    expect(result.cardNetwork, 'Visa');
    expect(result.cardType, 'credit');
    expect(result.cardExpiry, '08/29');
    expect(result.toExtractionValues(), isNot(contains('5678')));
    expect(result.toExtractionValues()['cardLast4'], '5678');
  });

  test('does not treat unrelated four-digit values as card last four', () {
    final result = ReceiptTextParser.parse('''
GOOD MARKET
STORE NO 1234
AUTH 5678
ZIP 90210
TOTAL \$24.50
''');
    expect(result.cardLast4, isNull);
    expect(result.cardExpiry, isNull);
  });

  test('handles split tax receipt totals and a complete PAN safely', () {
    const observations = [
      OcrObservation(
        text: 'SUBTOTAL',
        confidence: .9,
        left: .05,
        top: .68,
        width: .3,
        height: .04,
      ),
      OcrObservation(
        text: '20.00',
        confidence: .9,
        left: .7,
        top: .68,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: 'TAX',
        confidence: .9,
        left: .05,
        top: .74,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: '1.80',
        confidence: .9,
        left: .7,
        top: .74,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: 'TOTAL',
        confidence: .9,
        left: .05,
        top: .80,
        width: .3,
        height: .04,
      ),
      OcrObservation(
        text: '21.80',
        confidence: .9,
        left: .7,
        top: .80,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: 'VISA',
        confidence: .9,
        left: .05,
        top: .88,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: '4111 1111 1111 1234',
        confidence: .8,
        left: .3,
        top: .92,
        width: .6,
        height: .04,
      ),
    ];
    final result = ReceiptExtractor.extract(
      observations.map((value) => value.text).join('\n'),
      observations,
    );
    expect(result.amount, '21.80');
    expect(result.cardLast4, '1234');
    expect(
      result.toExtractionValues().values,
      isNot(contains('4111 1111 1111 1234')),
    );
  });

  test('redacts PANs from every persisted OCR text representation', () {
    const cases = [
      'VISA 4111 1111 1111 1234',
      'VISA 4111111111111234',
      'VISA 4111-1111-1111-1234',
      'VISA\n4111 1111 1111 1234',
    ];
    for (final text in cases) {
      final result = ReceiptExtractor.extract(text);
      final persisted = <String>[
        result.rawText,
        ...result.toExtractionValues().values,
        ...result.observations.map((value) => value.text),
      ];
      expect(
        persisted.every((value) => !value.contains('4111 1111 1111 1234')),
        isTrue,
        reason: text,
      );
      expect(
        persisted.every((value) => !value.contains('4111111111111234')),
        isTrue,
        reason: text,
      );
      expect(
        persisted.every((value) => !value.contains('4111-1111-1111-1234')),
        isTrue,
        reason: text,
      );
      expect(result.cardLast4, '1234');
    }

    final masked = ReceiptExtractor.extract('VISA **** **** **** 1234');
    expect(masked.rawText, contains('**** **** **** 1234'));
    expect(masked.cardLast4, '1234');
  });

  test('does not let an adjacent tax row win over the total row', () {
    const observations = [
      OcrObservation(
        text: 'TAX',
        confidence: .95,
        left: .05,
        top: .70,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: '1.80',
        confidence: .95,
        left: .7,
        top: .70,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: 'TOTAL',
        confidence: .95,
        left: .05,
        top: .76,
        width: .2,
        height: .04,
      ),
      OcrObservation(
        text: '21.80',
        confidence: .95,
        left: .7,
        top: .76,
        width: .2,
        height: .04,
      ),
    ];
    final result = ReceiptExtractor.extract(
      'TAX 1.80\nTOTAL 21.80',
      observations,
    );
    expect(result.amount, '21.80');
  });

  test('associates slightly skewed horizontal label and amount boxes', () {
    const observations = [
      OcrObservation(
        text: 'TOTAL',
        confidence: .9,
        left: .04,
        top: .70,
        width: .25,
        height: .05,
      ),
      OcrObservation(
        text: '21.80',
        confidence: .9,
        left: .72,
        top: .712,
        width: .18,
        height: .05,
      ),
      OcrObservation(
        text: 'TAX',
        confidence: .9,
        left: .04,
        top: .80,
        width: .2,
        height: .05,
      ),
      OcrObservation(
        text: '1.80',
        confidence: .9,
        left: .72,
        top: .812,
        width: .18,
        height: .05,
      ),
    ];
    final result = ReceiptExtractor.extract(
      'TOTAL 21.80\nTAX 1.80',
      observations,
    );
    expect(result.amount, '21.80');
  });

  test('recognizes a card number separated from its credit-card label', () {
    const observations = [
      OcrObservation(
        text: 'CREDIT CARD',
        confidence: .92,
        left: .05,
        top: .58,
        width: .35,
        height: .05,
      ),
      OcrObservation(
        text: '4111 1111 1111 1234',
        confidence: .82,
        left: .05,
        top: .91,
        width: .8,
        height: .05,
      ),
    ];
    final result = ReceiptExtractor.extract(
      'CREDIT CARD\n4111 1111 1111 1234',
      observations,
    );
    expect(result.cardType, 'credit');
    expect(result.cardLast4, '1234');
    expect(
      result.toExtractionValues().values,
      isNot(contains('4111 1111 1111 1234')),
    );
  });

  test('uses deterministic single-transaction amount label precedence', () {
    const cases = <(String, String)>[
      ('Grand Total 25.00\nAmount 24.00\nTotal 22.00', '25.00'),
      ('Total Due 25.00\nAmount Due 24.00\nTotal 22.00', '25.00'),
      ('Amount Due 24.00\nAmount Paid 23.00\nTotal 22.00', '24.00'),
      ('Amount Paid 24.00\nPurchase Total 23.00\nTotal 22.00', '24.00'),
      ('Purchase Total 24.00\nPayment Amount 23.00\nTotal 22.00', '24.00'),
      ('Payment Amount 24.00\nAmount 23.00\nTotal 22.00', '24.00'),
      ('Amount 24.00\nBalance 23.00\nTotal 22.00', '24.00'),
      ('Balance 23.00\nTotal 22.00', '23.00'),
      ('Total 22.00\nSale 21.00', '22.00'),
      ('Sale 21.00', '21.00'),
      ('Subtotal 20.00\nTax 2.00\nTip 4.00\nTotal 22.00', '22.00'),
      ('Balance Before 100.00\nBalance 23.00\nTotal 22.00', '23.00'),
      ('Previous Balance 100.00\nTotal 22.00', '22.00'),
      ('TOTAL DUE: \$25.00', '25.00'),
    ];
    for (final (text, expected) in cases) {
      expect(ReceiptExtractor.extract(text).amount, expected, reason: text);
    }
  });
}
