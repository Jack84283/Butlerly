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

  test(
    'changed transaction facts stop a resolved duplicate decision applying',
    () {
      final original = _transaction('original', '2026-01-01');
      final edited = _transaction('edited', '2026-02-01');
      final selected = selectCanonicalTransactions(
        source: [original, edited],
        duplicateGroups: [
          DuplicateCandidateGroup(
            id: 'resolved-group',
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

      expect(selected.transactions.map((value) => value.id.value), ['edited']);
      expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
    },
  );

  test('stale Keep Both decisions count one representative until repaired', () {
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

    expect(selected.transactions.map((value) => value.id.value), ['edited']);
    expect(selected.qualityIssues.single.code, 'staleDuplicateGroup');
  });

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
}

Transaction _transaction(
  String id,
  String date, {
  String description = 'Fixture merchant',
  bool archived = false,
}) {
  final instant = DateTime.parse('${date}T12:00:00Z');
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(instant),
    money: Money(
      amount: DecimalValue.parse('10'),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
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
