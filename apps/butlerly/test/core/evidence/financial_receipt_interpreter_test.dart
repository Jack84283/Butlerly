import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts labeled transaction notification without a merchant profile', () {
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
    expect(
      result.originalMerchantDescription,
      'GROCERY MART #4321 DENVER CO',
    );
    expect(
      result.toExtractionValues()['postingDate'],
      '2026-08-17',
    );
  });

  test('reconstructs raised cents and excludes unrelated cash-back rewards', () {
    const lines = [
      OcrObservation(
        text: 'Transaction Details', confidence: .96,
        left: .25, top: .01, width: .5, height: .04,
      ),
      OcrObservation(
        text: r'$120', confidence: .95,
        left: .03, top: .10, width: .25, height: .09,
      ),
      OcrObservation(
        text: '00', confidence: .95,
        left: .29, top: .108, width: .07, height: .04,
      ),
      OcrObservation(
        text: '5% cash back', confidence: .95,
        left: .67, top: .11, width: .3, height: .03,
      ),
      OcrObservation(
        text: r'+$6.00 rewards cash', confidence: .95,
        left: .67, top: .15, width: .3, height: .03,
      ),
      OcrObservation(
        text: 'Posted on Saturday, August 17, 2026',
        confidence: .95, left: .03, top: .25, width: .9, height: .04,
      ),
      OcrObservation(
        text: 'Mobile Service', confidence: .95,
        left: .03, top: .39, width: .5, height: .06,
      ),
      OcrObservation(
        text: 'Appears on your statement as:',
        confidence: .95, left: .03, top: .55, width: .8, height: .03,
      ),
      OcrObservation(
        text: 'MOBILE*BILL PAYMENT', confidence: .95,
        left: .03, top: .59, width: .8, height: .03,
      ),
      OcrObservation(
        text: 'Made on Friday, August 16, 2026', confidence: .95,
        left: .03, top: .65, width: .8, height: .03,
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
  });

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
GROCERY MART
08/15/2026
SUBTOTAL 40.00
TAX 3.56
TOTAL $43.56
VISA **** 2468
''');
    expect(result.amount, '43.56');
    expect(result.cardLast4, '2468');
    expect(result.date, DateTime(2026, 8, 15));
  });

  test('associates right-column values and multiline merchant evidence', () {
    const observations = [
      OcrObservation(
        text: 'Amount:', confidence: .94,
        left: .07, top: .12, width: .23, height: .04,
      ),
      OcrObservation(
        text: r'$32.47', confidence: .94,
        left: .46, top: .12, width: .21, height: .04,
      ),
      OcrObservation(
        text: 'Card Ending In', confidence: .94,
        left: .07, top: .21, width: .24, height: .04,
      ),
      OcrObservation(
        text: '1357', confidence: .94,
        left: .46, top: .21, width: .20, height: .04,
      ),
      OcrObservation(
        text: 'Merchant', confidence: .94,
        left: .07, top: .33, width: .22, height: .04,
      ),
      OcrObservation(
        text: 'CAFE EXPRESS #24680', confidence: .94,
        left: .46, top: .33, width: .40, height: .04,
      ),
      OcrObservation(
        text: 'DENVER US', confidence: .94,
        left: .46, top: .38, width: .36, height: .04,
      ),
      OcrObservation(
        text: 'Date', confidence: .94,
        left: .07, top: .50, width: .22, height: .04,
      ),
      OcrObservation(
        text: '08/15/2026', confidence: .94,
        left: .46, top: .50, width: .30, height: .04,
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
