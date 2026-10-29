import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('every duplicate policy produces independently specified totals', () {
    final a = _transaction('duplicate-a', '10');
    final b = _transaction('duplicate-b', '10');
    final archived = _transaction(
      'archived',
      '4',
      status: TransactionStatus.archived,
    );
    final receipt = _transaction('receipt-side', '30');
    final payment = _transaction('payment-side', '30');
    final links = [
      ReconciliationLink(
        id: 'receipt-link',
        candidateId: 'receipt-candidate',
        receiptTransactionId: receipt.id,
        paymentTransactionId: payment.id,
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    ];
    final source = [a, b, archived, receipt, payment];
    final key = _key(amount: '10');

    _expectPolicy(
      source: source,
      links: links,
      groups: [
        _group(
          'keep-both',
          [a.id, b.id],
          key: key,
          status: DuplicateCandidateGroupStatus.keepBoth,
        ),
      ],
      ids: ['archived', 'duplicate-a', 'duplicate-b', 'payment-side'],
      count: 4,
      total: '54',
      issueCodes: const [],
    );
    _expectPolicy(
      source: source,
      links: links,
      groups: [
        _group(
          'consolidated',
          [a.id, b.id],
          key: key,
          status: DuplicateCandidateGroupStatus.consolidated,
          selected: b.id,
        ),
      ],
      ids: ['archived', 'duplicate-b', 'payment-side'],
      count: 3,
      total: '44',
      issueCodes: const [],
    );
    _expectPolicy(
      source: source,
      links: links,
      groups: [
        _group(
          'unresolved',
          [b.id, a.id],
          key: key,
          status: DuplicateCandidateGroupStatus.unresolved,
        ),
      ],
      ids: ['archived', 'duplicate-a', 'payment-side'],
      count: 3,
      total: '44',
      issueCodes: const ['unresolvedDuplicate'],
    );
    final changedB = _transaction('duplicate-b', '12');
    _expectPolicy(
      source: [a, changedB, archived, receipt, payment],
      links: links,
      groups: [
        _group(
          'stale',
          [a.id, b.id],
          key: key,
          status: DuplicateCandidateGroupStatus.consolidated,
          selected: a.id,
        ),
      ],
      ids: ['archived', 'duplicate-a', 'duplicate-b', 'payment-side'],
      count: 4,
      total: '56',
      issueCodes: const ['staleDuplicateGroup'],
    );
  });

  test(
    'missing members, malformed decisions, and overlapping groups are conservative',
    () {
      final a = _transaction('a', '10');
      final b = _transaction('b', '10');
      final c = _transaction('c', '10');
      final archived = _transaction(
        'archived',
        '4',
        status: TransactionStatus.archived,
      );
      final missing = TransactionId('permanently-deleted');
      final key = _key(amount: '10');

      final missingMember = selectCanonicalTransactions(
        source: [b, archived, a],
        duplicateGroups: [
          _group(
            'missing',
            [a.id, b.id, missing],
            key: key,
            status: DuplicateCandidateGroupStatus.consolidated,
            selected: a.id,
          ),
        ],
      );
      expect(missingMember.transactions.map((value) => value.id.value), [
        'a',
        'archived',
        'b',
      ]);
      expect(_total(missingMember.transactions), DecimalValue.parse('24'));
      expect(
        missingMember.qualityIssues.map((issue) => issue.code),
        contains('staleDuplicateGroup'),
      );

      final malformed = selectCanonicalTransactions(
        source: [b, archived, a],
        duplicateGroups: [
          _group(
            'malformed',
            [a.id, b.id],
            key: key,
            status: DuplicateCandidateGroupStatus.consolidated,
            selected: b.id,
            integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
              code: 'malformedDuplicateGroup',
              detail: 'The persisted decision is malformed.',
            ),
          ),
        ],
      );
      expect(malformed.transactions.map((value) => value.id.value), [
        'archived',
        'b',
      ]);
      expect(_total(malformed.transactions), DecimalValue.parse('14'));
      expect(
        malformed.qualityIssues.map((issue) => issue.code),
        contains('malformedDuplicateGroup'),
      );

      final overlap = selectCanonicalTransactions(
        source: [c, archived, b, a],
        duplicateGroups: [
          _group(
            'overlap-b',
            [b.id, c.id],
            key: key,
            status: DuplicateCandidateGroupStatus.consolidated,
            selected: c.id,
          ),
          _group(
            'overlap-a',
            [a.id, b.id],
            key: key,
            status: DuplicateCandidateGroupStatus.consolidated,
            selected: a.id,
          ),
        ],
      );
      expect(overlap.transactions.map((value) => value.id.value), [
        'a',
        'archived',
      ]);
      expect(_total(overlap.transactions), DecimalValue.parse('14'));
      expect(
        overlap.qualityIssues.map((issue) => issue.code),
        contains('overlappingDuplicateGroups'),
      );
    },
  );

  test(
    'shuffled transactions and groups keep IDs, totals, and issues stable',
    () {
      final values = [
        _transaction('a', '10'),
        _transaction('b', '10'),
        _transaction('c', '4', status: TransactionStatus.archived),
      ];
      final groups = [
        _group(
          'group-b',
          [values[0].id, values[1].id],
          key: _key(amount: '10'),
          status: DuplicateCandidateGroupStatus.unresolved,
        ),
      ];
      final expectedIds = ['a', 'c'];
      final expectedTotal = DecimalValue.parse('14');
      final expectedIssues = ['unresolvedDuplicate'];

      for (final source in [
        values,
        [values[2], values[1], values[0]],
        [values[1], values[0], values[2]],
      ]) {
        for (final orderedGroups in [groups, groups.reversed.toList()]) {
          for (var repeat = 0; repeat < 2; repeat++) {
            final result = selectCanonicalTransactions(
              source: source,
              duplicateGroups: orderedGroups,
            );
            expect(
              result.transactions.map((value) => value.id.value),
              expectedIds,
            );
            expect(_total(result.transactions), expectedTotal);
            expect(
              result.qualityIssues.map((issue) => issue.code),
              expectedIssues,
            );
          }
        }
      }
    },
  );
}

void _expectPolicy({
  required List<Transaction> source,
  required List<ReconciliationLink> links,
  required List<DuplicateCandidateGroup> groups,
  required List<String> ids,
  required int count,
  required String total,
  required List<String> issueCodes,
}) {
  final result = selectCanonicalTransactions(
    source: source,
    links: links,
    duplicateGroups: groups,
  );
  expect(result.transactions.map((value) => value.id.value), ids);
  expect(result.transactions, hasLength(count));
  expect(_total(result.transactions), DecimalValue.parse(total));
  expect(result.qualityIssues.map((issue) => issue.code), issueCodes);
}

DecimalValue _total(Iterable<Transaction> values) =>
    DecimalValue.sum(values.map((value) => value.money.amount));

DuplicateTransactionKey _key({required String amount}) =>
    DuplicateTransactionKey(
      transactionDate: '2026-09-01',
      amount: DecimalValue.parse(amount),
      currency: 'USD',
      direction: TransactionDirection.expense.name,
    );

DuplicateCandidateGroup _group(
  String id,
  List<TransactionId> ids, {
  required DuplicateTransactionKey key,
  required DuplicateCandidateGroupStatus status,
  TransactionId? selected,
  DuplicateCandidateGroupIntegrityIssue? integrityIssue,
}) => DuplicateCandidateGroup(
  id: id,
  transactionIds: ids,
  duplicateKey: key,
  status: status,
  selectedTransactionId: selected,
  integrityIssue: integrityIssue,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Transaction _transaction(
  String id,
  String amount, {
  TransactionStatus status = TransactionStatus.active,
  String date = '2026-09-01',
  String currency = 'USD',
  TransactionDirection direction = TransactionDirection.expense,
}) {
  final now = DateTime.utc(2026, 9, 1);
  return Transaction(
    id: TransactionId(id),
    timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode(currency),
    ),
    direction: direction,
    sourceType: TransactionSourceType.manual,
    transactionDate: date,
    status: status,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: now,
        originalRepresentation: id,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}
