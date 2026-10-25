import 'package:butlerly_finance_application/src/analysis/canonical_transactions.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('canonical duplicate decisions are independent of input order', () {
    final first = _transaction('a', status: TransactionStatus.archived);
    final second = _transaction('b');
    final third = _transaction('c');
    final original = <Transaction>[third, first, second];

    for (final status in DuplicateCandidateGroupStatus.values) {
      final group = _group(
        'group',
        [first.id, second.id],
        status: status,
        selected: status == DuplicateCandidateGroupStatus.consolidated
            ? second.id
            : null,
      );
      final normal = selectCanonicalTransactions(
        source: original,
        duplicateGroups: [group],
      );
      final reversed = selectCanonicalTransactions(
        source: original.reversed.toList(),
        duplicateGroups: [group],
      );
      expect(
        normal.transactions.map((value) => value.id.value).toList(),
        reversed.transactions.map((value) => value.id.value).toList(),
        reason: 'Selection must be stable for $status',
      );
      expect(
        normal.qualityIssues.map((value) => value.code).toList(),
        reversed.qualityIssues.map((value) => value.code).toList(),
      );
      expect(
        normal.transactions.map((value) => value.id.value).toList(),
        status == DuplicateCandidateGroupStatus.keepBoth
            ? ['a', 'b', 'c']
            : status == DuplicateCandidateGroupStatus.consolidated
            ? ['b', 'c']
            : ['a', 'c'],
      );
    }
  });

  test('stale decision counts surviving changed facts independently', () {
    final first = _transaction('a');
    final changed = _transaction('b', amount: '30');
    final group = _group(
      'stale',
      [first.id, changed.id],
      status: DuplicateCandidateGroupStatus.consolidated,
      selected: first.id,
    );
    final result = selectCanonicalTransactions(
      source: [changed, first],
      duplicateGroups: [group],
    );
    expect(
      result.transactions.map((value) => value.id.value).toList(),
      ['a', 'b'],
    );
    expect(
      result.qualityIssues.any((value) => value.code == 'staleDuplicateGroup'),
      isTrue,
    );
  });

  test('current decisions take precedence over overlapping stale evidence', () {
    final first = _transaction('a');
    final second = _transaction('b');
    final changed = _transaction('c', amount: '30');
    final current = _group(
      'current',
      [first.id, second.id],
      status: DuplicateCandidateGroupStatus.consolidated,
      selected: second.id,
    );
    final stale = _group(
      'old',
      [first.id, changed.id],
      status: DuplicateCandidateGroupStatus.keepBoth,
    );
    for (final groups in <List<DuplicateCandidateGroup>>[
      [stale, current],
      [current, stale],
    ]) {
      final result = selectCanonicalTransactions(
        source: [changed, second, first],
        duplicateGroups: groups,
      );
      expect(
        result.transactions.map((value) => value.id.value).toList(),
        ['b', 'c'],
      );
      expect(
        result.qualityIssues.any((value) => value.code == 'staleDuplicateGroup'),
        isTrue,
      );
    }
  });
}

Transaction _transaction(
  String id, {
  String amount = '25',
  TransactionStatus status = TransactionStatus.active,
}) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: '2026-09-01',
  status: status,
  provenance: [
    Provenance(
      id: ProvenanceId('$id-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 9, 1),
    ),
  ],
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

DuplicateCandidateGroup _group(
  String id,
  List<TransactionId> ids, {
  required DuplicateCandidateGroupStatus status,
  TransactionId? selected,
}) => DuplicateCandidateGroup(
  id: id,
  transactionIds: ids,
  duplicateKey: DuplicateTransactionKey(
    transactionDate: '2026-09-01',
    amount: DecimalValue.parse('25'),
    currency: 'USD',
    direction: TransactionDirection.expense.name,
  ),
  status: status,
  selectedTransactionId: selected,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);
