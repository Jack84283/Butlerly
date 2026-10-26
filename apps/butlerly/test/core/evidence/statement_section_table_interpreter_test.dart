import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly/core/evidence/ocr_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts sectioned card statement purchases and autopay only', () {
    var order = 0;
    final lines = <OcrObservation>[];
    void add(String text, double left, double top,
        {double width = .14, int page = 0}) {
      lines.add(OcrObservation(
        text: text,
        confidence: .94,
        left: left,
        top: top,
        width: width,
        height: .012,
        pageIndex: page,
        order: order++,
      ));
    }

    add('Discover More Card ending in 2468', .18, .10, width: .35);
    add('OPEN TO CLOSE DATE: 07/29/2026 - 08/28/2026',
        .18, .13, width: .46);
    add('Transactions', .08, .20, width: .40);
    add('Rewards Summary', .70, .20, width: .23);
    add('TEST CUSTOMER #2468: PAYMENTS AND CREDITS', .08, .25,
        width: .48);
    add('TRANS. DATE', .08, .28);
    add('PAYMENTS AND CREDITS', .20, .28, width: .34);
    add('AMOUNT', .59, .28, width: .08);
    add('08/22', .08, .31, width: .08);
    add('CARD AUTOPAY PYMT', .20, .31, width: .32);
    add(r'- $245.67', .59, .31, width: .09);

    add('TEST CUSTOMER #2468: PURCHASES', .08, .35, width: .45);
    add('TRANS. DATE', .08, .38);
    add('PURCHASES', .20, .38, width: .18);
    add('AMOUNT', .59, .38, width: .08);

    void purchase(String date, String desc, String amount, double top) {
      add(date, .08, top, width: .08);
      add(desc, .20, top, width: .36);
      add(amount, .59, top, width: .09);
    }

    purchase('08/03', 'YMCA LOCAL FITNESS', r'$27.50', .42);
    purchase('08/05', 'APPLE.COM/BILL', r'$2.49', .45);
    purchase('08/08', 'ONLINE MARKETPLACE/BILL', r'$64.20', .48);
    add('WA', .20, .493, width: .05);
    purchase('08/16', 'WIRELESS BILL PAYMENT 800-555-0100',
        r'$110.25', .52);
    purchase('08/18', 'FARM INSURANCE BILLING', r'$321.99', .55);
    purchase('08/19', 'MUSIC SUBSCRIPTION', r'$6.75', .58);
    purchase('08/26', 'SCHOOL BOOKS EDUCATION', r'$42.16', .61);
    purchase('08/27', 'BOOK PUBLISHER', r'$19.95', .64);

    add('PREVIOUS BALANCE', .70, .24, width: .19);
    add(r'$78.22', .91, .24, width: .07);
    add('EARNED THIS PERIOD', .70, .27, width: .20);
    add(r'$3.88', .91, .27, width: .07);
    add('REDEEMED THIS PERIOD', .70, .30, width: .20);
    add(r'-$12.21', .91, .30, width: .07);
    add('CASHBACK BONUS BALANCE', .70, .33, width: .22);
    add(r'$41.00', .91, .33, width: .07);
    add('5% Cashback Bonus', .70, .39, width: .20);
    add('Fees and Interest Charged', .08, .70, width: .48);
    add('TOTAL FEES FOR THIS PERIOD', .08, .73, width: .45);
    add(r'$0.00', .59, .73, width: .09);
    add('Interest Charge Calculation', .08, .81, width: .45);
    add('27.49% D', .26, .84, width: .11);

    // Native OCR can deliver text and observations in independent orders.
    final text = lines.map((entry) => entry.text).join('\n');
    final result = LocalStatementExtractor.fromObservations(
      text, lines.reversed.toList(),
    );

    expect(result.context.periodStart, DateTime(2026, 7, 29));
    expect(result.context.periodEnd, DateTime(2026, 8, 28));
    expect(result.institution, 'Discover');
    expect(result.maskedAccountIdentifier, '••••2468');
    expect(result.context.profile?.id, 'sectioned-card-transaction-tables');
    expect(result.rows, hasLength(9));

    final payment = result.rows.singleWhere(
      (value) => value.description!.contains('AUTOPAY'),
    );
    expect(payment.date, DateTime(2026, 8, 22));
    expect(payment.amount, '245.67');
    expect(payment.direction, 'transfer');
    expect(payment.currency, 'USD');

    final purchaseRows = result.rows
        .where((value) => value.direction == 'expense')
        .toList();
    expect(purchaseRows, hasLength(8));
    expect(purchaseRows.map((row) => row.amount).toList(),
        ['27.50', '2.49', '64.20', '110.25', '321.99',
         '6.75', '42.16', '19.95']);
    expect(purchaseRows[2].description,
        'ONLINE MARKETPLACE/BILL WA');
    expect(purchaseRows[3].description,
        'WIRELESS BILL PAYMENT 800-555-0100');
    expect(purchaseRows[3].direction, 'expense');
    expect(purchaseRows.every((row) =>
        row.date != null && row.currency == 'USD' && !row.isUnresolved),
        isTrue);
    expect(result.rows.every((row) => !row.isUnresolved), isTrue);
    expect(result.rows.any((row) =>
        row.description!.contains('BALANCE') ||
        row.description!.contains('CASHBACK') ||
        row.description!.contains('FEES')), isFalse);
    expect(result.diagnostics?.transactionRegionsDetected,
        greaterThanOrEqualTo(2));
    expect(result.debugSummary, isNot(contains('TEST CUSTOMER')));
  });

  test('does not invent year when statement period is missing', () {
    final input = [
      const OcrObservation(text: 'Transactions', confidence: .9,
          left: .08, top: .1, width: .40, height: .015),
      const OcrObservation(text: 'PAYMENTS AND CREDITS', confidence: .9,
          left: .08, top: .2, width: .3, height: .015),
      const OcrObservation(text: 'AMOUNT', confidence: .9,
          left: .59, top: .22, width: .08, height: .015),
      const OcrObservation(text: '08/22', confidence: .9,
          left: .08, top: .25, width: .08, height: .015),
      const OcrObservation(text: 'AUTOPAY PYMT', confidence: .9,
          left: .2, top: .25, width: .24, height: .015),
      const OcrObservation(text: r'-$245.67', confidence: .9,
          left: .59, top: .25, width: .08, height: .015),
      const OcrObservation(text: 'PURCHASES', confidence: .9,
          left: .08, top: .40, width: .3, height: .015),
      const OcrObservation(text: '08/23', confidence: .9,
          left: .08, top: .44, width: .08, height: .015),
      const OcrObservation(text: 'MARKET', confidence: .9,
          left: .2, top: .44, width: .24, height: .015),
      const OcrObservation(text: r'$12.00', confidence: .9,
          left: .59, top: .44, width: .08, height: .015),
    ];
    final result = LocalStatementExtractor.fromObservations(
      input.map((value) => value.text).join('\n'), input,
    );
    expect(result.rows, hasLength(2));
    expect(result.rows.every((value) =>
        value.date == null && value.isUnresolved), isTrue);
  });

  test('ordinary one-column statement parser remains unchanged', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026\n'
      '08/12 SHOP 42.19 DR USD',
      const [],
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.amount, '42.19');
    expect(result.rows.single.direction, 'expense');
    expect(result.context.profile?.id,
        isNot('sectioned-card-transaction-tables'));
  });

  test('ambiguous row amounts never become confirmed transaction values', () {
    const observations = [
      OcrObservation(text: 'Discover More Card ending in 2468',
          confidence: .9, left: .16, top: .05, width: .3, height: .012),
      OcrObservation(
          text: 'OPEN TO CLOSE DATE: 07/29/2026 - 08/28/2026',
          confidence: .9, left: .16, top: .08, width: .4, height: .012),
      OcrObservation(text: 'Transactions',
          confidence: .9, left: .08, top: .12, width: .4, height: .012),
      OcrObservation(text: 'PAYMENTS AND CREDITS',
          confidence: .9, left: .08, top: .20, width: .3, height: .012),
      OcrObservation(text: 'PURCHASES',
          confidence: .9, left: .08, top: .30, width: .3, height: .012),
      OcrObservation(text: 'AMOUNT',
          confidence: .9, left: .59, top: .32, width: .08, height: .012),
      OcrObservation(text: '08/12',
          confidence: .9, left: .08, top: .40, width: .08, height: .012),
      OcrObservation(text: 'CAFE',
          confidence: .9, left: .20, top: .40, width: .24, height: .012),
      OcrObservation(text: r'$12.00',
          confidence: .9, left: .59, top: .40, width: .06, height: .012),
      OcrObservation(text: r'$13.00',
          confidence: .9, left: .60, top: .41, width: .06, height: .012),
      OcrObservation(text: 'Fees and Interest Charged',
          confidence: .9, left: .08, top: .60, width: .4, height: .012),
    ];
    final result = LocalStatementExtractor.fromObservations(
      observations.map((v) => v.text).join('\n'), observations,
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.date, DateTime(2026, 8, 12));
    expect(result.rows.single.amount, isNull);
    expect(result.rows.single.isUnresolved, isTrue);
  });

  test('multi-page documents do not enter the one-page specialized path', () {
    const observations = [
      OcrObservation(text: 'Transactions',
          confidence: .9, left: .08, top: .10,
          width: .4, height: .012, pageIndex: 0),
      OcrObservation(text: 'PAYMENTS AND CREDITS',
          confidence: .9, left: .08, top: .20,
          width: .3, height: .012, pageIndex: 0),
      OcrObservation(text: 'PURCHASES',
          confidence: .9, left: .08, top: .30,
          width: .3, height: .012, pageIndex: 0),
      OcrObservation(text: 'AMOUNT',
          confidence: .9, left: .59, top: .32,
          width: .08, height: .012, pageIndex: 0),
      OcrObservation(text: '08/12 SHOP 12.00',
          confidence: .9, left: .08, top: .40,
          width: .5, height: .012, pageIndex: 0),
      OcrObservation(text: '08/13 MARKET 15.00',
          confidence: .9, left: .08, top: .40,
          width: .5, height: .012, pageIndex: 1),
    ];
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026\n'
      'PAYMENTS AND CREDITS\nPURCHASES',
      observations,
    );
    expect(result.context.profile?.id,
        isNot('sectioned-card-transaction-tables'));
  });
}
