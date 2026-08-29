import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts multiple statement rows without inventing header values', () {
    final rows = LocalStatementExtractor.parse('''
Statement for account ****1234
2026-08-12 Grocery Store -42.10 USD
08/13/2026 PAYROLL +1500.00 USD
Balance forward 100.00
''');

    expect(rows, hasLength(2));
    expect(rows.first.description, 'Grocery Store');
    expect(rows.first.amount, '42.1');
    expect(rows.first.direction, TransactionDirection.expense.name);
    expect(rows.last.direction, TransactionDirection.income.name);
  });

  test('preserves plausible unsupported lines as unresolved evidence', () {
    final rows = LocalStatementExtractor.parse(
      '2026-08-12 unreadable amount USD',
    );
    expect(rows, hasLength(1));
    expect(rows.single.isUnresolved, isTrue);
  });

  test('leaves an unsigned amount unresolved', () {
    final rows = LocalStatementExtractor.parse(
      '2026-08-12 Grocery Store 42.10 USD',
    );

    expect(rows, hasLength(1));
    expect(rows.single.amount, '42.1');
    expect(rows.single.direction, isNull);
  });

  test('uses explicit debit and credit markers for direction', () {
    final rows = LocalStatementExtractor.parse('''
2026-08-12 Grocery Store 42.10 DR USD
2026-08-13 Refund 10.00 CREDIT USD
''');

    expect(rows[0].direction, TransactionDirection.expense.name);
    expect(rows[1].direction, TransactionDirection.income.name);
  });

  test('rejects overflowing calendar dates', () {
    final rows = LocalStatementExtractor.parse(
      '02/30/2026 Grocery Store -42.10 USD',
    );

    expect(rows, hasLength(1));
    expect(rows.single.date, isNull);
    expect(LocalStatementExtractor.parseDate('202-1-1'), isNull);
  });

  test('reconstructs spatial columns delivered out of reading order', () {
    const observations = [
      OcrObservation(
        text: '126.47',
        confidence: .9,
        left: .82,
        top: .30,
        width: .1,
        height: .03,
        order: 0,
      ),
      OcrObservation(
        text: 'COSTCO WHSE #1234',
        confidence: .9,
        left: .25,
        top: .30,
        width: .3,
        height: .03,
        order: 1,
      ),
      OcrObservation(
        text: '08/12',
        confidence: .9,
        left: .05,
        top: .30,
        width: .1,
        height: .03,
        order: 2,
      ),
    ];
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026\nUSD',
      observations,
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.date, DateTime(2026, 8, 12));
    expect(result.rows.single.description, contains('COSTCO'));
    expect(result.rows.single.amount, '126.47');
  });

  test('reconstructs date, description and amount from separate OCR lines', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026',
      const [
        OcrObservation(
          text: '08/12',
          confidence: .9,
          left: 0,
          top: .30,
          width: .1,
          height: .03,
          order: 0,
        ),
        OcrObservation(
          text: 'COSTCO WHSE #1234',
          confidence: .9,
          left: 0,
          top: .34,
          width: .3,
          height: .03,
          order: 1,
        ),
        OcrObservation(
          text: '126.47',
          confidence: .9,
          left: .8,
          top: .38,
          width: .1,
          height: .03,
          order: 2,
        ),
      ],
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.description, contains('COSTCO'));
    expect(result.rows.single.amount, '126.47');
  });

  test('infers MM/DD dates from a period crossing December and January', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 12/15/2025 - 01/14/2026\n12/31 Grocery 12.00\n01/02 Grocery 8.00',
      const [],
    );
    expect(result.rows, hasLength(2));
    expect(result.rows[0].date, DateTime(2025, 12, 31));
    expect(result.rows[1].date, DateTime(2026, 1, 2));
  });

  test('supports posting date, credits, grouped amounts and diagnostics', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026\n08/12 08/14 Refund (1,234.56) CR',
      const [],
    );
    expect(result.rows.single.postingDate, DateTime(2026, 8, 14));
    expect(result.rows.single.amount, '1234.56');
    expect(result.rows.single.direction, TransactionDirection.income.name);
    expect(result.diagnostics?.candidatesReconstructed, 1);
  });

  test('retains transaction-like evidence with an ambiguous amount', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026\n08/12 UNKNOWN MERCHANT ???',
      const [],
    );
    expect(result.outcome, StatementExtractionOutcome.unresolvedEvidence);
    expect(result.rows.single.isUnresolved, isTrue);
  });

  test(
    'confidence is based on the row observations, including exactly .50',
    () {
      final result = LocalStatementExtractor.fromObservations(
        'Statement period 08/01/2026 - 08/31/2026',
        const [
          OcrObservation(
            text: '08/12',
            confidence: .5,
            left: 0,
            top: .3,
            width: .1,
            height: .03,
            order: 0,
          ),
          OcrObservation(
            text: 'Merchant',
            confidence: .5,
            left: .2,
            top: .3,
            width: .2,
            height: .03,
            order: 1,
          ),
          OcrObservation(
            text: '10.00',
            confidence: .5,
            left: .8,
            top: .3,
            width: .1,
            height: .03,
            order: 2,
          ),
        ],
      );
      expect(result.rows.single.confidence, lessThanOrEqualTo(.5));
      expect(result.diagnostics?.lowConfidenceCandidates, 1);
    },
  );
}
