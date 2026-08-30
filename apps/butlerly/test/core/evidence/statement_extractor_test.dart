import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses short transaction dates and infers their year from context', () {
    for (final value in ['8/15', '08/15', '8-15', '08-15']) {
      final result = LocalStatementExtractor.fromObservations(
        'Statement period: 2026-08-01 - 2026-08-31',
        [_observation('$value SHOP 42.19', .1, .3, order: 0)],
      );
      expect(result.rows, hasLength(1), reason: value);
      expect(result.rows.single.date, DateTime(2026, 8, 15), reason: value);
      expect(result.rows.single.amount, '42.19', reason: value);
    }
  });

  test('short dates resolve across a statement year boundary', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 12/20/2025 - 1/19/2026',
      [
        _observation('12/28 SHOP 10.00', .1, .3, order: 0),
        _observation('1/05 CAFE 8.00', .1, .4, order: 1),
      ],
    );
    expect(result.rows, hasLength(2));
    expect(result.rows[0].date, DateTime(2025, 12, 28));
    expect(result.rows[1].date, DateTime(2026, 1, 5));
  });

  test('short date without safe year remains unresolved evidence', () {
    final result = LocalStatementExtractor.fromObservations('SHOP 42.19', [
      _observation('8/15 SHOP 42.19', .1, .3, order: 0),
    ]);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.date, isNull);
    expect(result.rows.single.amount, '42.19');
    expect(result.rows.single.isUnresolved, isTrue);
  });

  test('purchase and posting date columns map independently with geometry', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period: 2026-08-01 - 2026-08-31\n'
      'Purchase Date Post Date Description Amount',
      [
        _observation('8/15', .05, .3, order: 0),
        _observation('8/17', .25, .305, order: 1),
        _observation('SAFEWAY STORE', .45, .31, order: 2),
        _observation('\$42.19', .82, .315, order: 3),
      ],
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.date, DateTime(2026, 8, 15));
    expect(result.rows.single.postingDate, DateTime(2026, 8, 17));
    expect(result.rows.single.amount, '42.19');
    expect(result.rows.single.description, 'SAFEWAY STORE');
  });

  test(
    'supports combined and incomplete purchase-date rows without dropping evidence',
    () {
      final combined = LocalStatementExtractor.parse(
        'Statement period: 2026-08-01 - 2026-08-31\n'
        '8/15 8/17 SAFEWAY STORE 42.19',
      ).single;
      expect(combined.date, DateTime(2026, 8, 15));
      expect(combined.postingDate, DateTime(2026, 8, 17));
      expect(combined.amount, '42.19');

      final missingPosting = LocalStatementExtractor.parse(
        'Statement period: 2026-08-01 - 2026-08-31\n8/15 SAFEWAY STORE 42.19',
      ).single;
      expect(missingPosting.date, DateTime(2026, 8, 15));
      expect(missingPosting.postingDate, isNull);
      expect(missingPosting.amount, '42.19');

      final missingAmount = LocalStatementExtractor.parse(
        'Statement period: 2026-08-01 - 2026-08-31\n8/15 8/17 SAFEWAY STORE',
      ).single;
      expect(missingAmount.amount, isNull);
      expect(missingAmount.isUnresolved, isTrue);
    },
  );
  test(
    'complementary incomplete rows stay separate in text and Vision paths',
    () {
      const first = '2026-08-12 FIRST SHOP ???';
      const second = 'SECOND SHOP 20.00';
      for (final observations in <List<OcrObservation>>[
        [],
        [
          const OcrObservation(
            text: first,
            confidence: .9,
            left: .05,
            top: .30,
            width: .8,
            height: .012,
            order: 0,
          ),
          const OcrObservation(
            text: second,
            confidence: .9,
            left: .05,
            top: .36,
            width: .8,
            height: .012,
            order: 1,
          ),
        ],
      ]) {
        final rows = LocalStatementExtractor.parse(
          '$first\n$second',
          observations,
        );
        expect(rows, hasLength(2));
        expect(rows.first.date, DateTime(2026, 8, 12));
        expect(rows.first.amount, isNull);
        expect(rows.first.originalText, first);
        expect(rows.last.date, isNull);
        expect(rows.last.amount, '20');
        expect(rows.last.originalText, second);
        expect(rows.every((row) => row.isUnresolved), isTrue);
      }
    },
  );

  test(
    'equidistant amount evidence stays unresolved without guessed values',
    () {
      final result = LocalStatementExtractor.fromObservations('', [
        _observation('2026-08-12', .05, .30, order: 0),
        _observation('SHOP A', .30, .30, order: 1),
        _observation('20.00', .82, .315, order: 2),
        _observation('2026-08-13', .05, .33, order: 3),
        _observation('SHOP B', .30, .33, order: 4),
      ]);
      expect(result.rows, hasLength(2));
      expect(result.rows.every((row) => row.amount == null), isTrue);
      expect(result.rows.every((row) => row.isUnresolved), isTrue);
      expect(result.rows.every((row) => row.confidence! <= .5), isTrue);
      expect(
        result.rows.any((row) => row.originalText.contains('20.00')),
        isTrue,
      );
    },
  );

  test('neighboring incomplete rows never steal the next date or amount', () {
    for (final tops in [
      [.300, .301, .302],
      [.33, .31, .29],
      [.29, .31, .33],
    ]) {
      for (final missing in ['date', 'amount']) {
        final result = LocalStatementExtractor.fromObservations('', [
          if (missing != 'date')
            _observation('2026-08-12', .05, tops[0], order: 0),
          _observation('SHOP A', .30, tops[1], order: 1),
          if (missing != 'amount')
            _observation('10.00', .82, tops[2], order: 2),
          _observation('2026-08-13', .05, tops[0] + .03, order: 3),
          _observation('SHOP B', .30, tops[1] + .03, order: 4),
          _observation('20.00', .82, tops[2] + .03, order: 5),
        ]);
        expect(result.rows, hasLength(2), reason: '$tops missing $missing');
        final first = result.rows.first;
        expect(first.description, 'SHOP A');
        expect(
          first.date,
          missing == 'date' ? isNull : anyOf(isNull, DateTime(2026, 8, 12)),
        );
        expect(
          first.amount,
          missing == 'amount' ? isNull : anyOf(isNull, '10'),
          reason: '$tops missing $missing',
        );
        expect(first.isUnresolved, isTrue);
        final second = result.rows.last;
        expect(second.description, 'SHOP B');
        expect(second.date, anyOf(isNull, DateTime(2026, 8, 13)));
        expect(second.amount, anyOf(isNull, '20'));
        if (second.date == null || second.amount == null) {
          expect(second.isUnresolved, isTrue);
        }
        if (tops[0] == .300) {
          expect(second.date, DateTime(2026, 8, 13));
          expect(second.amount, '20');
        }
      }
    }
  });

  test('amount header never turns a merchant number into a missing amount', () {
    final result = LocalStatementExtractor.fromObservations('', [
      _observation('Amount', .82, .1, order: 0),
      _observation('2026-08-12', .05, .30, order: 1),
      _observation('STORE 42', .30, .30, order: 2),
      _observation('???', .82, .30, order: 3),
    ]);
    expect(result.rows.single.amount, isNull);
    expect(result.rows.single.description, 'STORE 42 ???');
    expect(result.rows.single.isUnresolved, isTrue);
  });

  test('integer in the actual amount column remains supported', () {
    final result = LocalStatementExtractor.fromObservations('', [
      _observation('Amount', .82, .1, order: 0),
      _observation('2026-08-12', .05, .30, order: 1),
      _observation('STORE 42', .30, .30, order: 2),
      _observation('123', .82, .30, order: 3),
    ]);
    expect(result.rows.single.amount, '123');
    expect(result.rows.single.description, 'STORE 42');
  });

  test('dense skewed rows retain their own dates in both slope directions', () {
    for (final reversed in [false, true]) {
      final result = LocalStatementExtractor.fromObservations('', [
        _observation('2026-08-12', .05, reversed ? .29 : .33, order: 0),
        _observation('SHOP A', .30, .31, order: 1),
        _observation('10.00', .82, reversed ? .33 : .29, order: 2),
        _observation('2026-08-13', .05, reversed ? .32 : .36, order: 3),
        _observation('SHOP B', .30, .34, order: 4),
        _observation('20.00', .82, reversed ? .36 : .32, order: 5),
      ]);
      expect(result.rows, hasLength(2), reason: 'reversed=$reversed');
      expect(result.rows.map((row) => row.date), [
        DateTime(2026, 8, 12),
        DateTime(2026, 8, 13),
      ]);
      expect(result.rows.map((row) => row.description), ['SHOP A', 'SHOP B']);
      expect(result.rows.map((row) => row.amount), ['10', '20']);
    }
  });

  test('dated balance summaries never become transaction candidates', () {
    for (final label in [
      'Balance forward',
      'Previous balance',
      'Opening balance',
      'Closing balance',
      'Statement balance',
    ]) {
      expect(
        LocalStatementExtractor.parse('08/01/2026 $label 100.00'),
        isEmpty,
        reason: label,
      );
    }
  });

  test('split currency with amount header cannot select a merchant number', () {
    final result = LocalStatementExtractor.fromObservations('', [
      _observation('Amount', .82, .1, order: 0),
      _observation('2026-08-12', .05, .30, order: 1),
      _observation('STORE 42', .30, .303, order: 2),
      _observation(r'$', .78, .306, order: 3),
      _observation('123.45', .82, .307, order: 4),
    ]);
    expect(result.rows.single.amount, '123.45');
    expect(result.rows.single.description, 'STORE 42');
    expect(result.rows.single.originalText, contains(r'$ 123.45'));
  });

  test('balance merchant survives while a balance summary stays excluded', () {
    final rows = LocalStatementExtractor.parse(
      'New balance 200.00\n2026-08-12 NEW BALANCE 123.45',
    );
    expect(rows, hasLength(1));
    expect(rows.single.description, 'NEW BALANCE');
    expect(rows.single.amount, '123.45');
  });

  test(
    'multiple amounts in one observation remain ambiguous with a header',
    () {
      final result = LocalStatementExtractor.fromObservations('', [
        _observation('Amount', .82, .1, order: 0),
        _observation('2026-08-12 SHOP 12.00 18.00', .05, .30, order: 1),
      ]);
      expect(result.rows.single.amount, isNull);
      expect(result.rows.single.isUnresolved, isTrue);
    },
  );

  test('nearby transaction and posting date columns remain one row', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026',
      [
        _observation('08/12', .05, .30, order: 0),
        _observation('08/14', .16, .303, order: 1),
        _observation('SHOP', .35, .306, order: 2),
        _observation('10.00', .82, .309, order: 3),
      ],
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.date, DateTime(2026, 8, 12));
    expect(result.rows.single.postingDate, DateTime(2026, 8, 14));
  });

  test('ambiguous multi-year context does not choose a year', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 01/01/2025 - 12/31/2026\n08/12 SHOP 10.00',
      const [],
    );
    expect(result.rows.single.date, isNull);
  });

  test('merchant text cannot fabricate a currency code', () {
    final row = LocalStatementExtractor.parse(
      '2026-08-12 NEURO SHOP 10.00',
    ).single;
    expect(row.currency, isNull);
  });

  test(
    'a later row missing its date is not appended to a complete transaction',
    () {
      final result = LocalStatementExtractor.fromObservations(
        '2026-08-12 FIRST SHOP 10.00\nSECOND SHOP 20.00',
        const [],
      );
      expect(result.rows, hasLength(2));
      expect(result.rows.first.description, 'FIRST SHOP');
      expect(result.rows.last.description, 'SECOND SHOP');
      expect(result.rows.last.amount, '20');
      expect(result.rows.last.date, isNull);
    },
  );

  test('small offsets preserve separate adjacent transaction rows', () {
    final observations = [
      _observation('2026-08-12', .05, .30, order: 0),
      _observation('SHOP A', .30, .308, order: 1),
      _observation('10.00', .82, .316, order: 2),
      _observation('2026-08-13', .05, .36, order: 3),
      _observation('SHOP B', .30, .368, order: 4),
      _observation('20.00', .82, .376, order: 5),
    ];
    final result = LocalStatementExtractor.fromObservations(
      observations.map((value) => value.text).join('\n'),
      observations,
    );
    expect(result.rows.map((row) => row.description), ['SHOP A', 'SHOP B']);
    expect(result.rows.map((row) => row.amount), ['10', '20']);
  });

  test('multiline merchant descriptions retain their original evidence', () {
    const source = '2026-08-12 LONG MERCHANT\nDOWNTOWN LOCATION 42\n\$123.45';
    final result = LocalStatementExtractor.fromObservations(source, const []);
    expect(result.rawText, source);
    expect(
      result.rows.single.description,
      'LONG MERCHANT DOWNTOWN LOCATION 42',
    );
    expect(result.rows.single.amount, '123.45');
    expect(result.rows.single.originalText, contains('DOWNTOWN LOCATION 42'));
  });

  test('supports common dates amounts and explicit debit-credit markers', () {
    for (final date in ['08/12/26', '08/12/2026', '2026-08-12']) {
      for (final item in <(String, String, String?)>[
        (r'$123.45', '123.45', null),
        ('123.45', '123.45', null),
        ('1,234.56', '1234.56', null),
        ('-123.45', '123.45', 'expense'),
        ('(123.45)', '123.45', 'expense'),
        ('123.45 CREDIT', '123.45', 'income'),
        ('123.45 CR', '123.45', 'income'),
        ('123.45 DEBIT', '123.45', 'expense'),
        ('123.45 DR', '123.45', 'expense'),
        ('CREDIT 123.45', '123.45', 'income'),
        ('DR 123.45', '123.45', 'expense'),
        ('REFUND 123.45', '123.45', 'refund'),
      ]) {
        final row = LocalStatementExtractor.parse(
          '$date SHOP ${item.$1}',
        ).single;
        expect(row.date, DateTime(2026, 8, 12));
        expect(row.amount, item.$2, reason: item.$1);
        expect(row.direction, item.$3, reason: item.$1);
        expect(row.description, 'SHOP', reason: item.$1);
        expect(
          row.currency,
          isNull,
          reason: 'Intake owns absent currency defaults.',
        );
      }
    }
  });

  test('date and amount with unreadable description survive unresolved', () {
    final row = LocalStatementExtractor.parse('2026-08-12 ??? 123.45').single;
    expect(row.amount, '123.45');
    expect(row.date, DateTime(2026, 8, 12));
    expect(row.description, isNull);
    expect(row.isUnresolved, isTrue);
  });

  test(
    'diagnostics count ignored headers and balances without retaining text',
    () {
      final result = LocalStatementExtractor.fromObservations(
        'Transaction Date Description Amount\nPrevious balance 100.00\n2026-08-12 SHOP 12.00',
        const [],
      );
      expect(result.rows, hasLength(1));
      expect(result.diagnostics?.visualRowsIgnored, 2);
      expect(result.diagnostics?.nonTransactionObservationsIgnored, 2);
      expect(result.debugSummary, isNot(contains('SHOP')));
    },
  );

  test('keeps a perspective-skewed Vision row whose amount arrives first', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026',
      [
        _observation('123.45', .82, .29, order: 0),
        _observation('MARKET 42', .30, .31, order: 1),
        _observation('08/12', .05, .33, order: 2),
      ],
    );
    expect(result.rows, hasLength(1));
    expect(result.rows.single.amount, '123.45');
    expect(result.rows.single.description, 'MARKET 42');
    expect(result.rows.single.date, DateTime(2026, 8, 12));
  });

  test('merchant and amount without a readable date survive for review', () {
    final result =
        LocalStatementExtractor.fromObservations('COFFEE SHOP\n18.25', [
          _observation('COFFEE SHOP', .25, .30, order: 0),
          _observation('18.25', .82, .305, order: 1),
        ]);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.date, isNull);
    expect(result.rows.single.amount, '18.25');
    expect(result.rows.single.description, 'COFFEE SHOP');
    expect(result.rows.single.isUnresolved, isTrue);
    expect(result.outcome, StatementExtractionOutcome.unresolvedEvidence);
  });

  test('split dollar symbol is not retained as merchant description', () {
    final result =
        LocalStatementExtractor.fromObservations('08/12 SHOP \$ 123.45', [
          _observation('08/12', .05, .30, order: 0),
          _observation('SHOP', .25, .303, order: 1),
          _observation(r'$', .78, .306, order: 2),
          _observation('123.45', .82, .307, order: 3),
        ]);
    expect(result.rows.single.description, 'SHOP');
    expect(result.rows.single.amount, '123.45');
    expect(result.rows.single.date, isNull);
    expect(result.rows.single.originalText, contains(r'$ 123.45'));
  });

  test('transaction dates cannot masquerade as a statement period', () {
    final result = LocalStatementExtractor.fromObservations(
      '08/01/2026 SHOP 10.00\n08/31/2026 SHOP 20.00\n08/12 SHOP 30.00',
      const [],
    );
    expect(result.context.periodStart, isNull);
    expect(result.context.periodEnd, isNull);
    expect(result.rows.last.date, isNull);
  });

  test('MM/DD year inference rejects an overflowing calendar date', () {
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 02/01/2026 - 03/31/2026\n02/30 SHOP 10.00',
      const [],
    );
    expect(result.rows.single.date, isNull);
    expect(result.rows.single.originalText, contains('02/30'));
  });

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

  test('headers drive amount selection and activate the generic profile', () {
    const observations = [
      OcrObservation(
        text: 'Transaction Date',
        confidence: .9,
        left: .02,
        top: .1,
        width: .15,
        height: .03,
        order: 0,
      ),
      OcrObservation(
        text: 'Posting Date',
        confidence: .9,
        left: .20,
        top: .1,
        width: .15,
        height: .03,
        order: 1,
      ),
      OcrObservation(
        text: 'Description',
        confidence: .9,
        left: .40,
        top: .1,
        width: .2,
        height: .03,
        order: 2,
      ),
      OcrObservation(
        text: 'Amount',
        confidence: .9,
        left: .82,
        top: .1,
        width: .1,
        height: .03,
        order: 3,
      ),
      OcrObservation(
        text: '08/12',
        confidence: .9,
        left: .02,
        top: .2,
        width: .1,
        height: .03,
        order: 4,
      ),
      OcrObservation(
        text: '08/14',
        confidence: .9,
        left: .20,
        top: .2,
        width: .1,
        height: .03,
        order: 5,
      ),
      OcrObservation(
        text: 'HOTEL 2 NIGHTS',
        confidence: .9,
        left: .40,
        top: .2,
        width: .3,
        height: .03,
        order: 6,
      ),
      OcrObservation(
        text: '420.00',
        confidence: .9,
        left: .82,
        top: .2,
        width: .1,
        height: .03,
        order: 7,
      ),
    ];
    final result = LocalStatementExtractor.fromObservations(
      'Statement period 08/01/2026 - 08/31/2026 Transaction Date Posting Date Description Amount',
      observations,
    );
    expect(result.context.columns, hasLength(4));
    expect(result.context.profile?.id, 'generic-date-posting-amount');
    expect(result.rows.single.amount, '420');
    expect(result.rows.single.postingDate, DateTime(2026, 8, 14));
  });

  test('does not merge pages and ignores repeated headers', () {
    const observations = [
      OcrObservation(
        text: '08/31',
        confidence: .9,
        left: .02,
        top: .2,
        width: .1,
        height: .03,
        pageIndex: 0,
        order: 0,
      ),
      OcrObservation(
        text: 'Store A',
        confidence: .9,
        left: .3,
        top: .2,
        width: .2,
        height: .03,
        pageIndex: 0,
        order: 1,
      ),
      OcrObservation(
        text: '10.00',
        confidence: .9,
        left: .8,
        top: .2,
        width: .1,
        height: .03,
        pageIndex: 0,
        order: 2,
      ),
      OcrObservation(
        text: 'Transaction Date Description Amount',
        confidence: .9,
        left: .02,
        top: .1,
        width: .5,
        height: .03,
        pageIndex: 1,
        order: 3,
      ),
      OcrObservation(
        text: '09/01',
        confidence: .9,
        left: .02,
        top: .2,
        width: .1,
        height: .03,
        pageIndex: 1,
        order: 4,
      ),
      OcrObservation(
        text: 'Store B',
        confidence: .9,
        left: .3,
        top: .2,
        width: .2,
        height: .03,
        pageIndex: 1,
        order: 5,
      ),
      OcrObservation(
        text: '20.00',
        confidence: .9,
        left: .8,
        top: .2,
        width: .1,
        height: .03,
        pageIndex: 1,
        order: 6,
      ),
    ];
    final result = LocalStatementExtractor.fromObservations(
      '08/01/2026 - 09/30/2026',
      observations,
    );
    expect(result.rows, hasLength(2));
    expect(
      result.rows.map((row) => row.description),
      everyElement(isNot(contains('Transaction Date'))),
    );
    expect(result.diagnostics?.pagesProcessed, 2);
  });

  test(
    'distinguishes empty, no-candidate, unresolved-only and mixed outcomes',
    () {
      expect(
        LocalStatementExtractor.fromObservations('', const []).outcome,
        StatementExtractionOutcome.noText,
      );
      expect(
        LocalStatementExtractor.fromObservations(
          'Welcome to your account',
          const [],
        ).outcome,
        StatementExtractionOutcome.textWithoutCandidates,
      );
      expect(
        LocalStatementExtractor.fromObservations(
          '08/12 UNKNOWN ???',
          const [],
        ).outcome,
        StatementExtractionOutcome.unresolvedEvidence,
      );
      final mixed = LocalStatementExtractor.fromObservations(
        'Statement period 08/01/2026 - 08/31/2026\n08/12 Good 10.00\n08/13 Unknown ???',
        const [],
      );
      expect(mixed.outcome, StatementExtractionOutcome.reconstructedCandidates);
      expect(mixed.diagnostics?.unresolvedCandidates, 1);
    },
  );
}

OcrObservation _observation(
  String text,
  double left,
  double top, {
  required int order,
  double confidence = .9,
}) => OcrObservation(
  text: text,
  confidence: confidence,
  left: left,
  top: top,
  width: .12,
  height: .012,
  order: order,
);
