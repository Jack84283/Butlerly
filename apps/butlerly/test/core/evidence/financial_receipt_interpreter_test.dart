import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screenshot = r'''
Transaction Details
AMOUNT_TOKEN
5% cash back
+$0.25 rewards cash
Posted on Monday, November 23, 2026
DoorDash
Learn more about this merchant
DOORDASH
Appears on your statement as:
DD *DOORDASHDASHPASS 6505550100 CA 94107 USA
Made on Sunday, November 22, 2026
Call Merchant
Report a Problem
''';

  test('extracts a bank screenshot and preserves separate evidence', () {
    for (final amount in [r'$4.99', r'$4 99']) {
      final result = ReceiptTextParser.parse(
        screenshot.replaceFirst('AMOUNT_TOKEN', amount),
      );
      expect(result.merchant, 'DoorDash');
      expect(result.amount, '4.99');
      expect(result.currency, 'USD');
      expect(result.date, DateTime(2026, 11, 22));
      expect(result.postingDate, DateTime(2026, 11, 23));
      expect(
        result.toExtractionValues(),
        containsPair('cashBackReward', '0.25'),
      );
      expect(
        result.originalMerchantDescription,
        'DD *DOORDASHDASHPASS 6505550100 CA 94107 USA',
      );
      expect(result.cardLast4, isNull);
      expect(result.tax, isNull);
      expect(result.tip, isNull);
    }
  });

  test('uses the screenshot geometry when cents are separate observations', () {
    final lines = [
      const OcrObservation(
        text: 'Amount',
        confidence: .95,
        bounds: OcrBounds(left: .04, top: .15, width: .08, height: .02),
      ),
      for (final (index, text)
          in screenshot
              .replaceFirst(' CA 94107 USA', '\nCA 94107 USA')
              .trim()
              .split('\n')
              .indexed)
        if (text == 'AMOUNT_TOKEN') ...[
          const OcrObservation(
            text: r'$4',
            confidence: .95,
            bounds: OcrBounds(left: .04, top: .19, width: .08, height: .05),
          ),
          const OcrObservation(
            text: '99',
            confidence: .95,
            bounds: OcrBounds(left: .12, top: .19, width: .06, height: .026),
          ),
        ] else
          OcrObservation(
            text: text,
            confidence: .95,
            bounds: OcrBounds(
              left: text == 'DOORDASH' ? .75 : .04,
              top: .12 + index * .068,
              width: .8,
              height: .025,
            ),
          ),
    ];
    final result = ReceiptExtractor.extract(
      lines.map((line) => line.text).join('\n'),
      lines,
    );
    expect(result.amount, '4.99');
    expect(result.merchant, 'DoorDash');
    expect(result.cashBackReward, '0.25');
  });

  test(
    'flags a merged amount and never replaces purchase date with posting date',
    () {
      final result = ReceiptTextParser.parse(
        screenshot
            .replaceFirst('AMOUNT_TOKEN', r'$499')
            .replaceFirst('Made on Sunday, November 22, 2026', ''),
      );
      expect(result.amount, isNull);
      expect(result.amountNeedsReview, isTrue);
      expect(result.date, isNull);
      expect(result.dateNeedsReview, isTrue);
      expect(result.postingDate, DateTime(2026, 11, 23));
    },
  );

  test(
    'flags conflicting purchase dates and excludes an unlabeled later amount',
    () {
      final result = ReceiptTextParser.parse(
        screenshot.replaceFirst('AMOUNT_TOKEN', '').replaceFirst(
          'Call Merchant',
          r'''
Purchased on November 21, 2026
$57.00
Call Merchant''',
        ),
      );
      expect(result.amount, isNull);
      expect(result.date, isNull);
      expect(result.dateNeedsReview, isTrue);
    },
  );

  test(
    'extracts labeled transaction notification without a merchant profile',
    () {
      final result = ReceiptTextParser.parse(r'''
Amount: $32.47
Card
Ending In
1234
Merchant
QUICK SHOP 24680
DENVER US
Date
08/15/2026
Time
06:19 PM ET
''');
      expect(result.amount, '32.47');
      expect(result.merchant, 'QUICK SHOP');
      expect(result.cardLast4, '1234');
      expect(result.transactionTimeText, '06:19 PM ET');
      expect(result.date, DateTime(2026, 8, 15));
      expect(result.fieldEvidence['amount'], contains('32.47'));
    },
  );

  test('omits legacy metadata for unsupported screenshot fields', () {
    final result = ReceiptTextParser.parse(
      screenshot.replaceFirst('AMOUNT_TOKEN', r'$4.99') +
          r'''
Tip $1.00
Tax $0.50
Credit card expiry 01/2030
''',
    );
    final values = result.toExtractionValues();
    for (final field in [
      'tip',
      'tax',
      'cardNetwork',
      'cardType',
      'cardExpiry',
    ]) {
      expect(values.keys.where((key) => key.startsWith(field)), isEmpty);
    }
  });

  test('uses native glyph evidence for a merged amount', () {
    for (final amountToken in [r'$499', r'Amount: $499']) {
      final text = screenshot.replaceFirst('AMOUNT_TOKEN', amountToken);
      final observations = [
        for (final (index, line) in text.trim().split('\n').indexed)
          OcrObservation(
            text: line,
            confidence: .95,
            top: index.toDouble(),
            hasRaisedCents: line == amountToken,
          ),
      ];
      final result = ReceiptExtractor.extract(text, observations);
      expect(result.amount, '4.99');
      expect(result.amountNeedsReview, isFalse);
    }
  });

  test('accepts a USD suffix on a standalone header amount', () {
    final result = ReceiptTextParser.parse(
      screenshot.replaceFirst('AMOUNT_TOKEN', r'$4.99 USD'),
    );
    expect(result.amount, '4.99');
    expect(result.currency, 'USD');
  });

  test('recognizes explicitly labeled masked card suffixes', () {
    final result = ReceiptTextParser.parse(
      'Transaction Details\nCard ending in: •••• 1234',
    );
    expect(result.cardLast4, '1234');
  });

  test('uses explicit currency and flags conflicting currency evidence', () {
    const details = 'Transaction Details\nCurrency: CAD\nAmount: ';
    expect(ReceiptTextParser.parse(details + r'$4.99').currency, 'CAD');
    final ambiguous = ReceiptTextParser.parse(details + r'$499');
    expect(ambiguous.amount, isNull);
    expect(ambiguous.currency, 'CAD');
    expect(ambiguous.amountNeedsReview, isTrue);
    for (final values in [
      r'$4.99 USD',
      r'US$4.99'
          '\nAmount: '
          r'$4.99',
      r'$4.99'
          '\nAmount: '
          r'US$4.99',
    ]) {
      final conflict = ReceiptTextParser.parse(details + values);
      expect(conflict.amount, '4.99');
      expect(conflict.currency, isNull);
      expect(conflict.currencyNeedsReview, isTrue);
    }
  });

  test('accepts an explicit USD currency suffix on a labeled amount', () {
    final result = ReceiptTextParser.parse(r'''
Transaction Details
$120
Amount: $4.99 USD
Account balance €30.00
''');
    expect(result.amount, '4.99');
    expect(result.currency, 'USD');
  });

  test('separates payment-card product from merchant and posting date', () {
    final result = ReceiptTextParser.parse(r'''
Rewards Visa...2468
$9.42
Grocery Mart
Purchased on
Aug 16, 2026 08:46 PM ET
Posted on
Aug 17, 2026
Spend category
Grocery Store, Supermarket
On your statement as
GROCERY MART #4321 DENVER CO
Merchant details
''');
    expect(result.amount, '9.42');
    expect(result.merchant, 'Grocery Mart');
    expect(result.cardLast4, '2468');
    expect(result.date, DateTime(2026, 8, 16));
    expect(result.postingDate, DateTime(2026, 8, 17));
    expect(result.transactionTimeText, '08:46 PM ET');
    expect(result.issuerCategory, 'Grocery Store, Supermarket');
    expect(result.originalMerchantDescription, 'GROCERY MART #4321 DENVER CO');
    expect(result.toExtractionValues()['postingDate'], '2026-08-17');
  });

  test(
    'reconstructs raised cents and excludes unrelated cash-back rewards',
    () {
      const lines = [
        OcrObservation(
          text: 'Transaction Details',
          confidence: .96,
          left: .25,
          top: .01,
          width: .5,
          height: .04,
        ),
        OcrObservation(
          text: r'$120',
          confidence: .95,
          left: .03,
          top: .10,
          width: .25,
          height: .09,
        ),
        OcrObservation(
          text: '00',
          confidence: .95,
          left: .29,
          top: .108,
          width: .07,
          height: .04,
        ),
        OcrObservation(
          text: '5% cash back',
          confidence: .95,
          left: .67,
          top: .11,
          width: .3,
          height: .03,
        ),
        OcrObservation(
          text: r'+$6.00 rewards cash',
          confidence: .95,
          left: .67,
          top: .15,
          width: .3,
          height: .03,
        ),
        OcrObservation(
          text: 'Posted on Saturday, August 17, 2026',
          confidence: .95,
          left: .03,
          top: .25,
          width: .9,
          height: .04,
        ),
        OcrObservation(
          text: 'Mobile Service',
          confidence: .95,
          left: .03,
          top: .39,
          width: .5,
          height: .06,
        ),
        OcrObservation(
          text: 'Appears on your statement as:',
          confidence: .95,
          left: .03,
          top: .55,
          width: .8,
          height: .03,
        ),
        OcrObservation(
          text: 'MOBILE*BILL PAYMENT',
          confidence: .95,
          left: .03,
          top: .59,
          width: .8,
          height: .03,
        ),
        OcrObservation(
          text: 'Made on Friday, August 16, 2026',
          confidence: .95,
          left: .03,
          top: .65,
          width: .8,
          height: .03,
        ),
      ];
      final result = ReceiptExtractor.extract(
        lines.map((line) => line.text).join('\n'),
        lines,
      );
      expect(result.amount, '120.00');
      expect(result.merchant, 'Mobile Service');
      expect(result.date, DateTime(2026, 8, 16));
      expect(result.postingDate, DateTime(2026, 8, 17));
      expect(result.amount, isNot('6.00'));
    },
  );

  test('does not invent cents for an unsegmented integer OCR token', () {
    final result = ReceiptTextParser.parse(r'''
Transaction Details
$12000
5% cash back
+$6.00 rewards cash
Made on Friday, August 16, 2026
''');
    expect(result.amount, isNull);
  });

  test('does not promote rewards to a purchase when the total is missing', () {
    final result = ReceiptTextParser.parse(r'''
Transaction Details
5% cash back
+$6.00 rewards cash
Mobile Service
Made on Friday, August 16, 2026
''');
    expect(result.amount, isNull);
  });

  test('does not use marketing copy as a cash-back value label', () {
    final result = ReceiptTextParser.parse(r'''
Transaction Details
Earn 5% cash back
$4.99
Posted on November 23, 2026
''');
    expect(result.amount, '4.99');
    expect(result.cashBackReward, isNull);
  });

  test(
    'associates a split reward when its value precedes the label vertically',
    () {
      final result = ReceiptExtractor.extract(
        r'Transaction Details Cash back earned $0.25',
        const [
          OcrObservation(text: 'Transaction Details', confidence: .9),
          OcrObservation(
            text: 'Cash back earned',
            confidence: .9,
            bounds: OcrBounds(left: .05, top: .16, width: .45, height: .04),
          ),
          OcrObservation(
            text: r'$0.25',
            confidence: .9,
            bounds: OcrBounds(left: .65, top: .155, width: .22, height: .04),
          ),
        ],
      );
      expect(result.amount, isNull);
      expect(result.cashBackReward, '0.25');
    },
  );

  test('excludes separated rewards in every supported USD format', () {
    for (final reward in [r'$0.25 USD', r'US$0.25', r'+US$0.25']) {
      final result = ReceiptTextParser.parse('''
Transaction Details
Cash back earned
$reward
Posted on November 23, 2026
''');
      expect(result.amount, isNull);
      expect(result.cashBackReward, '0.25');
    }
  });

  test('does not promote a reward or balance separated from its label', () {
    for (final label in ['5% cash back', 'Cash back earned']) {
      final result = ReceiptTextParser.parse('''
Transaction Details
$label
\$0.25
Available balance
\$120.00
Posted on November 23, 2026
''');
      expect(result.amount, isNull);
      expect(result.cashBackReward, '0.25');
    }
  });

  test('does not treat a USPS line-item price as a verified total', () {
    final result = ReceiptTextParser.parse(r'''
UNITED STATES POSTAL SERVICE
08/15/2026 11:02 AM
TRACKING NUMBERS
9400 1111 2222 3333 4444 55
PURCHASE DETAILS
Product Qty Unit Price Price
USPS Ground Advantage 1 $21.50
''');
    expect(result.merchant, 'UNITED STATES POSTAL SERVICE');
    expect(result.amount, isNull);
  });

  test('retains conventional explicit total parsing', () {
    final result = ReceiptTextParser.parse(r'''
Transaction Details
GROCERY MART
Purchased on August 15, 2026
SUBTOTAL 40.00
TAX 3.56
TOTAL
$43.56
VISA **** 2468
''');
    expect(result.amount, '43.56');
    expect(result.cardLast4, '2468');
    expect(result.tax, '3.56');
    expect(result.date, DateTime(2026, 8, 15));
  });

  test('associates right-column values and multiline merchant evidence', () {
    const observations = [
      OcrObservation(
        text: 'Amount:',
        confidence: .94,
        left: .07,
        top: .12,
        width: .23,
        height: .04,
      ),
      OcrObservation(
        text: r'$32.47',
        confidence: .94,
        left: .46,
        top: .12,
        width: .21,
        height: .04,
      ),
      OcrObservation(
        text: 'Card Ending In',
        confidence: .94,
        left: .07,
        top: .21,
        width: .24,
        height: .04,
      ),
      OcrObservation(
        text: '1357',
        confidence: .94,
        left: .46,
        top: .21,
        width: .20,
        height: .04,
      ),
      OcrObservation(
        text: 'Merchant',
        confidence: .94,
        left: .07,
        top: .33,
        width: .22,
        height: .04,
      ),
      OcrObservation(
        text: 'CAFE EXPRESS #24680',
        confidence: .94,
        left: .46,
        top: .33,
        width: .40,
        height: .04,
      ),
      OcrObservation(
        text: 'DENVER US',
        confidence: .94,
        left: .46,
        top: .38,
        width: .36,
        height: .04,
      ),
      OcrObservation(
        text: 'Date',
        confidence: .94,
        left: .07,
        top: .50,
        width: .22,
        height: .04,
      ),
      OcrObservation(
        text: '08/15/2026',
        confidence: .94,
        left: .46,
        top: .50,
        width: .30,
        height: .04,
      ),
    ];
    final result = ReceiptExtractor.extract(
      observations.map((line) => line.text).join('\n'),
      observations,
    );
    expect(result.amount, '32.47');
    expect(result.merchant, 'CAFE EXPRESS');
    expect(result.cardLast4, '1357');
    expect(result.date, DateTime(2026, 8, 15));
    expect(result.fieldEvidence['merchant'], contains('DENVER US'));
  });

  test('joins fractional digits only when adjacent and visibly smaller', () {
    List<OcrObservation> observations(double centsLeft) => [
      const OcrObservation(
        text: 'Transaction Details',
        confidence: .9,
        left: .1,
        top: .02,
        width: .5,
        height: .04,
      ),
      const OcrObservation(
        text: r'$43',
        confidence: .9,
        left: .05,
        top: .14,
        width: .24,
        height: .09,
      ),
      OcrObservation(
        text: '.56',
        confidence: .9,
        left: centsLeft,
        top: .16,
        width: .07,
        height: .04,
      ),
    ];
    final adjacent = observations(.30);
    final result = ReceiptExtractor.extract(
      adjacent.map((line) => line.text).join('\n'),
      adjacent,
    );
    expect(result.amount, '43.56');

    final separated = observations(.80);
    final unresolved = ReceiptExtractor.extract(
      separated.map((line) => line.text).join('\n'),
      separated,
    );
    expect(unresolved.amount, isNull);
  });
}
