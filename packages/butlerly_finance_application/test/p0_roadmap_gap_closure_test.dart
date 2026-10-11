import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'historical canonical selection includes archive and applies decisions',
    () {
      final active = _transaction('active', '2026-01-01');
      final archived = _transaction('archived', '2026-01-01', archived: true);
      final group = DuplicateCandidateGroup(
        id: 'group-1',
        transactionIds: [active.id, archived.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-01-01',
          amount: DecimalValue.parse('10'),
          currency: 'USD',
          direction: 'expense',
        ),
        status: DuplicateCandidateGroupStatus.consolidated,
        selectedTransactionId: archived.id,
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final selected = selectCanonicalTransactions(
        source: [active, archived],
        duplicateGroups: [group],
      );
      expect(selected.transactions.map((value) => value.id.value), [
        'archived',
      ]);

      final keepBoth = selectCanonicalTransactions(
        source: [active, archived],
        duplicateGroups: [
          DuplicateCandidateGroup(
            id: group.id,
            transactionIds: group.transactionIds,
            duplicateKey: group.duplicateKey,
            status: DuplicateCandidateGroupStatus.keepBoth,
            createdAt: group.createdAt,
            updatedAt: group.updatedAt,
          ),
        ],
      );
      expect(
        keepBoth.transactions.map((value) => value.id.value),
        unorderedEquals(['active', 'archived']),
      );
    },
  );

  test('unresolved duplicates count once and expose a quality issue', () {
    final values = [
      _transaction('a', '2026-01-01'),
      _transaction('b', '2026-01-01'),
    ];
    final selected = selectCanonicalTransactions(
      source: values,
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'group-1',
          transactionIds: values.map((value) => value.id).toList(),
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.unresolved,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );
    expect(selected.transactions, hasLength(1));
    expect(selected.qualityIssues.single.code, 'unresolvedDuplicate');
  });

  test('stale duplicate membership remains visible as a quality issue', () {
    final survivor = _transaction('survivor', '2026-01-01');
    final selected = selectCanonicalTransactions(
      source: [survivor],
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'stale-group',
          transactionIds: [survivor.id, TransactionId('deleted')],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: survivor.id,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );
    expect(selected.transactions.single.id, survivor.id);
    expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
  });

  test('orphan duplicate groups remain visible as a global quality issue', () {
    final selected = selectCanonicalTransactions(
      source: [_transaction('survivor', '2026-01-01')],
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'orphan-group',
          transactionIds: [TransactionId('deleted')],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('deleted'),
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(selected.transactions.single.id, TransactionId('survivor'));
    expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
  });

  test('one-member duplicate decisions remain quality-limited', () {
    final survivor = _transaction('survivor', '2026-01-01');
    final selected = selectCanonicalTransactions(
      source: [survivor],
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'one-member-group',
          transactionIds: [survivor.id],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: survivor.id,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(selected.transactions.single.id, survivor.id);
    expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
  });

  test('missing consolidated selection remains a quality issue', () {
    final values = [
      _transaction('a', '2026-01-01'),
      _transaction('b', '2026-01-01'),
    ];
    final selected = selectCanonicalTransactions(
      source: values,
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'invalid-group',
          transactionIds: values.map((value) => value.id).toList(),
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.consolidated,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(selected.transactions, hasLength(1));
    expect(selected.qualityIssues.single.code, 'invalidDuplicateSelection');
  });

  test(
    'overlapping duplicate groups cannot select multiple representatives',
    () {
      final values = [
        _transaction('a', '2026-01-01'),
        _transaction('b', '2026-01-01'),
        _transaction('c', '2026-01-01'),
      ];
      final key = DuplicateTransactionKey(
        transactionDate: '2026-01-01',
        amount: DecimalValue.parse('10'),
        currency: 'USD',
        direction: 'expense',
      );
      final selected = selectCanonicalTransactions(
        source: values,
        duplicateGroups: [
          DuplicateCandidateGroup(
            id: 'group-a',
            transactionIds: [values[0].id, values[1].id],
            duplicateKey: key,
            status: DuplicateCandidateGroupStatus.consolidated,
            selectedTransactionId: values[0].id,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
          DuplicateCandidateGroup(
            id: 'group-b',
            transactionIds: [values[1].id, values[2].id],
            duplicateKey: key,
            status: DuplicateCandidateGroupStatus.consolidated,
            selectedTransactionId: values[2].id,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      expect(selected.transactions.map((value) => value.id.value), ['a']);
      expect(selected.qualityIssues.single.code, 'overlappingDuplicateGroups');
    },
  );

  test('overlapping groups preserve every member of Keep Both decisions', () {
    final values = [
      _transaction('a', '2026-01-01'),
      _transaction('b', '2026-01-01'),
      _transaction('c', '2026-01-01'),
    ];
    final key = DuplicateTransactionKey(
      transactionDate: '2026-01-01',
      amount: DecimalValue.parse('10'),
      currency: 'USD',
      direction: 'expense',
    );
    final selected = selectCanonicalTransactions(
      source: values,
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'keep-both',
          transactionIds: [values[0].id, values[1].id],
          duplicateKey: key,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        DuplicateCandidateGroup(
          id: 'consolidated',
          transactionIds: [values[1].id, values[2].id],
          duplicateKey: key,
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: values[2].id,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(selected.transactions.map((value) => value.id.value), ['a', 'b']);
    expect(selected.qualityIssues.single.code, 'overlappingDuplicateGroups');
  });

  test('overlapping Keep Both groups preserve their union', () {
    final values = [
      _transaction('a', '2026-01-01'),
      _transaction('b', '2026-01-01'),
      _transaction('c', '2026-01-01'),
    ];
    final key = DuplicateTransactionKey(
      transactionDate: '2026-01-01',
      amount: DecimalValue.parse('10'),
      currency: 'USD',
      direction: 'expense',
    );
    final selected = selectCanonicalTransactions(
      source: values,
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'keep-both-a',
          transactionIds: [values[0].id, values[1].id],
          duplicateKey: key,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        DuplicateCandidateGroup(
          id: 'keep-both-b',
          transactionIds: [values[1].id, values[2].id],
          duplicateKey: key,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(
      selected.transactions.map((value) => value.id.value),
      unorderedEquals(['a', 'b', 'c']),
    );
    expect(selected.qualityIssues, isEmpty);
  });

  test('stale resolved duplicate decisions count every current member', () {
    final cases = [
      (
        'date',
        _transaction('edited-date', '2026-02-01'),
        '2026-01-01',
        DecimalValue.parse('10'),
        'USD',
        TransactionDirection.expense,
      ),
      (
        'amount',
        _transaction('edited-amount', '2026-01-01', amount: '11'),
        '2026-01-01',
        DecimalValue.parse('10'),
        'USD',
        TransactionDirection.expense,
      ),
      (
        'currency',
        _transaction('edited-currency', '2026-01-01', currency: 'EUR'),
        '2026-01-01',
        DecimalValue.parse('10'),
        'USD',
        TransactionDirection.expense,
      ),
      (
        'direction',
        _transaction(
          'edited-direction',
          '2026-01-01',
          direction: TransactionDirection.income,
        ),
        '2026-01-01',
        DecimalValue.parse('10'),
        'USD',
        TransactionDirection.expense,
      ),
    ];

    for (final value in cases) {
      final original = _transaction('original-${value.$1}', '2026-01-01');
      final edited = value.$2;
      final selected = selectCanonicalTransactions(
        source: [original, edited],
        duplicateGroups: [
          DuplicateCandidateGroup(
            id: 'resolved-${value.$1}',
            transactionIds: [original.id, edited.id],
            duplicateKey: DuplicateTransactionKey(
              transactionDate: value.$3,
              amount: value.$4,
              currency: value.$5,
              direction: value.$6.name,
            ),
            status: DuplicateCandidateGroupStatus.consolidated,
            selectedTransactionId: original.id,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      expect(
        selected.transactions.map((transaction) => transaction.id),
        unorderedEquals([original.id, edited.id]),
        reason: value.$1,
      );
      expect(
        selected.qualityIssues.single.code,
        'staleDuplicateGroup',
        reason: value.$1,
      );
    }
  });

  test('stale Keep Both decisions do not suppress a distinct member', () {
    final original = _transaction('original', '2026-01-01');
    final edited = _transaction('edited', '2026-02-01');
    final selected = selectCanonicalTransactions(
      source: [original, edited],
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'keep-both-group',
          transactionIds: [original.id, edited.id],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(
      selected.transactions.map((value) => value.id),
      unorderedEquals([original.id, edited.id]),
    );
    expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
  });

  test(
    'stale and current duplicate groups do not collapse distinct history',
    () {
      final original = _transaction('original', '2026-01-01');
      final edited = _transaction('edited', '2026-02-01');
      final currentMatch = _transaction('current-match', '2026-02-01');
      final selected = selectCanonicalTransactions(
        source: [original, edited, currentMatch],
        duplicateGroups: [
          DuplicateCandidateGroup(
            id: 'stale-group',
            transactionIds: [original.id, edited.id],
            duplicateKey: DuplicateTransactionKey(
              transactionDate: '2026-01-01',
              amount: DecimalValue.parse('10'),
              currency: 'USD',
              direction: 'expense',
            ),
            status: DuplicateCandidateGroupStatus.consolidated,
            selectedTransactionId: original.id,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
          DuplicateCandidateGroup(
            id: 'current-group',
            transactionIds: [edited.id, currentMatch.id],
            duplicateKey: DuplicateTransactionKey(
              transactionDate: '2026-02-01',
              amount: DecimalValue.parse('10'),
              currency: 'USD',
              direction: 'expense',
            ),
            status: DuplicateCandidateGroupStatus.unresolved,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      expect(
        selected.transactions.map((value) => value.id),
        unorderedEquals([original.id, currentMatch.id]),
      );
    },
  );

  test(
    'canonical selection is independent of transaction and group ordering',
    () {
      final original = _transaction('a-original', '2026-01-01', amount: '25');
      final edited = _transaction('b-edited', '2026-01-01', amount: '30');
      final currentMatch = _transaction(
        'c-current-match',
        '2026-01-01',
        amount: '30',
      );
      final stale = DuplicateCandidateGroup(
        id: 'stale-history',
        transactionIds: [original.id, edited.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-01-01',
          amount: DecimalValue.parse('25'),
          currency: 'USD',
          direction: 'expense',
        ),
        status: DuplicateCandidateGroupStatus.consolidated,
        selectedTransactionId: original.id,
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      final current = DuplicateCandidateGroup(
        id: 'current-review',
        transactionIds: [edited.id, currentMatch.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-01-01',
          amount: DecimalValue.parse('30'),
          currency: 'USD',
          direction: 'expense',
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final results = <String>[];
      for (final source in [
        [original, edited, currentMatch],
        [currentMatch, original, edited],
        [edited, currentMatch, original],
      ]) {
        for (final groups in [
          [stale, current],
          [current, stale],
        ]) {
          final selected = selectCanonicalTransactions(
            source: source,
            duplicateGroups: groups,
          );
          results.add(
            '${selected.transactions.map((value) => value.id.value).join(',')}|'
            '${selected.transactions.map((value) => value.money.amount).join(',')}',
          );
          expect(selected.transactions.map((value) => value.id.value), [
            'a-original',
            'b-edited',
          ]);
          expect(
            selected.transactions
                .map((value) => value.money.amount)
                .reduce((left, right) => left.add(right)),
            DecimalValue.parse('55'),
          );
          expect(
            selected.qualityIssues,
            contains(
              predicate<DataQualityIssue>(
                (issue) => issue.code == 'staleDuplicateGroup',
              ),
            ),
          );
          expect(
            selected.qualityIssues,
            contains(
              predicate<DataQualityIssue>(
                (issue) => issue.code == 'unresolvedDuplicate',
              ),
            ),
          );
        }
      }
      expect(results.toSet(), hasLength(1));
    },
  );

  test('canonical selection preserves receipt reconciliation exclusions', () {
    final receipt = _transaction('receipt', '2026-01-01');
    final payment = _transaction('payment', '2026-01-01');
    final selected = selectCanonicalTransactions(
      source: [payment, receipt],
      links: [
        ReconciliationLink(
          id: 'link-receipt-payment',
          candidateId: 'candidate-receipt-payment',
          receiptTransactionId: receipt.id,
          paymentTransactionId: payment.id,
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ],
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'duplicate:receipt-payment',
          transactionIds: [receipt.id, payment.id],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(selected.transactions.map((value) => value.id), [payment.id]);
  });

  test('receipt-only overlap does not merge independent payment groups', () {
    final receipt = _transaction('receipt-overlap', '2026-01-01');
    final firstPayment = _transaction('payment-first', '2026-01-01');
    final secondPayment = _transaction('payment-second', '2026-01-01');
    final selected = selectCanonicalTransactions(
      source: [secondPayment, receipt, firstPayment],
      links: [
        ReconciliationLink(
          id: 'link-receipt-overlap',
          candidateId: 'candidate-receipt-overlap',
          receiptTransactionId: receipt.id,
          paymentTransactionId: firstPayment.id,
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ],
      duplicateGroups: [
        DuplicateCandidateGroup(
          id: 'duplicate:receipt-first',
          transactionIds: [receipt.id, firstPayment.id],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        DuplicateCandidateGroup(
          id: 'duplicate:receipt-second',
          transactionIds: [receipt.id, secondPayment.id],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-01-01',
            amount: DecimalValue.parse('10'),
            currency: 'USD',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: secondPayment.id,
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    expect(selected.transactions.map((value) => value.id), [
      firstPayment.id,
      secondPayment.id,
    ]);
  });

  test(
    'editing an archived duplicate member still invalidates its decision',
    () {
      final original = _transaction('archived-original', '2026-01-01');
      final edited = _transaction(
        'archived-edited',
        '2026-01-01',
        amount: '11',
        archived: true,
      );
      final selected = selectCanonicalTransactions(
        source: [original, edited],
        duplicateGroups: [
          DuplicateCandidateGroup(
            id: 'archived-stale-group',
            transactionIds: [original.id, edited.id],
            duplicateKey: DuplicateTransactionKey(
              transactionDate: '2026-01-01',
              amount: DecimalValue.parse('10'),
              currency: 'USD',
              direction: 'expense',
            ),
            status: DuplicateCandidateGroupStatus.consolidated,
            selectedTransactionId: original.id,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      expect(
        selected.transactions.map((value) => value.id),
        unorderedEquals([original.id, edited.id]),
      );
      expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
    },
  );

  test(
    'recurring detection is deterministic, archived-aware, and reviewable',
    () {
      final values = [
        _transaction('jan', '2026-01-01', description: 'Cloud hosting'),
        _transaction('feb', '2026-02-01', description: 'Cloud hosting'),
        _transaction(
          'mar',
          '2026-03-01',
          description: 'Cloud hosting',
          archived: true,
        ),
      ];
      final patterns = const RecurringPatternDetector(
        timeZoneId: 'UTC',
      ).detect(values);
      expect(patterns, hasLength(1));
      final pattern = patterns.single;
      expect(pattern.cadence, RecurringCadence.monthly);
      expect(pattern.transactionIds, hasLength(3));
      expect(pattern.status, RecurringPatternStatus.detected);
      expect(pattern.expectedNextDate, '2026-04-01');
      expect(pattern.confirm().status, RecurringPatternStatus.confirmed);
      expect(pattern.correct(intervalDays: 31).intervalDays, 31);
      final corrected = pattern.applyDecision(
        RecurringPatternDecision(
          id: 'decision-1',
          patternKey: pattern.patternKey,
          status: RecurringPatternDecisionStatus.corrected,
          cadence: RecurringPatternDecisionCadence.weekly,
          intervalDays: 7,
          expectedAmount: pattern.expectedAmount,
          createdAt: DateTime.utc(2026, 3, 2),
          updatedAt: DateTime.utc(2026, 3, 2),
        ),
      );
      expect(corrected.expectedNextDate, '2026-03-08');
      final limited = const RecurringPatternDetector(timeZoneId: 'UTC').detect(
        values,
        qualityIssues: [
          DataQualityIssue(
            code: 'unresolvedDuplicate',
            detail: 'Needs review.',
            transactionId: TransactionId('mar'),
          ),
        ],
      );
      expect(limited.single.qualityIssues.single.code, 'unresolvedDuplicate');
    },
  );

  test('insufficient recurring evidence produces no candidate', () {
    expect(
      RecurringPatternDetector(
        timeZoneId: 'UTC',
      ).detect([_RecurringFixture.one, _RecurringFixture.two]),
      isEmpty,
    );
  });

  test('same-day records do not produce a recurring candidate', () {
    final values = [
      _transaction('same-day-a', '2026-08-09', description: 'Same-day shop'),
      _transaction('same-day-b', '2026-08-09', description: 'Same-day shop'),
      _transaction('same-day-c', '2026-08-09', description: 'Same-day shop'),
    ];

    expect(
      const RecurringPatternDetector(timeZoneId: 'UTC').detect(values),
      isEmpty,
    );
  });

  test('regular weekly and biweekly evidence supports predictions', () {
    final weekly = const RecurringPatternDetector(timeZoneId: 'UTC').detect([
      _transaction('weekly-1', '2026-01-01', description: 'Weekly service'),
      _transaction('weekly-2', '2026-01-08', description: 'Weekly service'),
      _transaction('weekly-3', '2026-01-15', description: 'Weekly service'),
    ]).single;
    final biweekly = const RecurringPatternDetector(timeZoneId: 'UTC').detect([
      _transaction('biweekly-1', '2026-01-01', description: 'Biweekly service'),
      _transaction('biweekly-2', '2026-01-15', description: 'Biweekly service'),
      _transaction('biweekly-3', '2026-01-29', description: 'Biweekly service'),
    ]).single;

    expect(weekly.cadence, RecurringCadence.weekly);
    expect(weekly.expectedNextDate, '2026-01-22');
    expect(biweekly.cadence, RecurringCadence.biweekly);
    expect(biweekly.expectedNextDate, '2026-02-12');
  });

  test('irregular or amount-unstable evidence has no prediction date', () {
    final irregular = const RecurringPatternDetector(timeZoneId: 'UTC').detect([
      _transaction('irregular-1', '2026-01-01', description: 'Occasional shop'),
      _transaction('irregular-2', '2026-01-10', description: 'Occasional shop'),
      _transaction('irregular-3', '2026-02-05', description: 'Occasional shop'),
    ]).single;
    final variableAmounts =
        const RecurringPatternDetector(timeZoneId: 'UTC').detect([
          _transaction(
            'variable-1',
            '2026-01-01',
            description: 'Variable bill',
          ),
          _transaction(
            'variable-2',
            '2026-02-01',
            description: 'Variable bill',
            amount: '20',
          ),
          _transaction(
            'variable-3',
            '2026-03-01',
            description: 'Variable bill',
          ),
        ]).single;

    expect(irregular.cadence, RecurringCadence.irregular);
    expect(irregular.expectedNextDate, isNull);
    expect(
      irregular.evidence,
      contains('next occurrence unavailable: cadence is irregular'),
    );
    expect(variableAmounts.cadence, RecurringCadence.monthly);
    expect(variableAmounts.expectedNextDate, isNull);
    expect(
      variableAmounts.evidence,
      contains('next occurrence unavailable: amounts are inconsistent'),
    );
    expect(
      irregular.correct(cadence: RecurringCadence.irregular).expectedNextDate,
      isNull,
    );
  });
}

Transaction _transaction(
  String id,
  String date, {
  String description = 'Fixture merchant',
  String amount = '10',
  String currency = 'USD',
  TransactionDirection direction = TransactionDirection.expense,
  bool archived = false,
}) {
  final instant = DateTime.parse('${date}T12:00:00Z');
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(instant),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode(currency),
    ),
    direction: direction,
    sourceType: TransactionSourceType.import,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-source'),
        sourceType: ProvenanceSourceType.import,
        capturedAt: instant,
        originalRepresentation: description,
      ),
    ],
    transactionDate: date,
    description: description,
    createdAt: instant,
    updatedAt: instant,
    status: archived ? TransactionStatus.archived : TransactionStatus.active,
  );
}

final class _RecurringFixture {
  static final one = _transaction('one', '2026-01-01');
  static final two = _transaction('two', '2026-02-01');
}
