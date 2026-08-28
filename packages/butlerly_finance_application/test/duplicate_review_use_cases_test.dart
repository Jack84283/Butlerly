import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('scan groups exact canonical keys and preserves Keep Both', () async {
    final repository = _Groups([_match('a', '25.0'), _match('b', '25.00')]);
    final clock = _Clock(DateTime.utc(2026, 1, 1));
    final scan = ScanExistingTransactionsForDuplicates(repository, clock);

    final first = await scan();
    expect(first, isA<ApplicationSuccess<List<DuplicateCandidateGroup>>>());
    final group = (first as ApplicationSuccess<List<DuplicateCandidateGroup>>)
        .value
        .single;
    expect(group.transactionIds.map((id) => id.value), ['a', 'b']);

    await repository.save(
      DuplicateCandidateGroup(
        id: group.id,
        transactionIds: group.transactionIds,
        duplicateKey: group.duplicateKey,
        status: DuplicateCandidateGroupStatus.keepBoth,
        createdAt: group.createdAt,
        updatedAt: clock.now(),
      ),
    );
    final second = await scan();
    expect(
      (second as ApplicationSuccess<List<DuplicateCandidateGroup>>)
          .value
          .single
          .status,
      DuplicateCandidateGroupStatus.keepBoth,
    );
  });

  test('scan creates one group for three matching transactions', () async {
    final repository = _Groups([
      _match('a', '25'),
      _match('b', '25.00'),
      _match('c', '25.000'),
    ]);
    final result = await ScanExistingTransactionsForDuplicates(
      repository,
      _Clock(DateTime.utc(2026, 1, 1)),
    )();
    final groups =
        (result as ApplicationSuccess<List<DuplicateCandidateGroup>>).value;
    expect(groups, hasLength(1));
    expect(groups.single.transactionIds, hasLength(3));
  });

  test('only the authoritative duplicate key creates a group', () async {
    final repository = _Groups([
      _match('same-a', '25.00'),
      _match('same-b', '25.0'),
      _match('other-amount', '26'),
      _match('other-date', '25', date: '2026-01-02'),
      _match('other-currency', '25', currency: 'EUR'),
      _match('other-direction', '25', direction: 'income'),
    ]);

    final result = await ScanExistingTransactionsForDuplicates(
      repository,
      _Clock(DateTime.utc(2026, 1, 1)),
    )();

    final groups =
        (result as ApplicationSuccess<List<DuplicateCandidateGroup>>).value;
    expect(groups, hasLength(1));
    expect(groups.single.transactionIds.map((id) => id.value), [
      'same-a',
      'same-b',
    ]);
  });

  test(
    'stale unresolved groups are removed while resolved history remains',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final scan = ScanExistingTransactionsForDuplicates(repository, clock);
      await scan();
      final group = repository.groups.single;

      repository.matches
        ..clear()
        ..addAll([_match('a', '25')]);
      await scan();
      expect(repository.groups, isEmpty);

      await repository.save(
        DuplicateCandidateGroup(
          id: group.id,
          transactionIds: group.transactionIds,
          duplicateKey: group.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: group.createdAt,
          updatedAt: clock.now(),
        ),
      );
      await scan();
      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.keepBoth,
      );
    },
  );

  test(
    'consolidated resolution requires and remembers explicit selection',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(repository, clock)();
      final group = repository.groups.single;
      final result = await ResolveDuplicateCandidateGroup(repository, clock)(
        group.id,
        DuplicateCandidateGroupStatus.consolidated,
        selectedTransactionId: TransactionId('b'),
      );
      expect(result, isA<ApplicationSuccess<void>>());
      expect(repository.groups.single.selectedTransactionId?.value, 'b');
    },
  );

  test(
    'new matching membership reopens the stable duplicate-key group',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final scan = ScanExistingTransactionsForDuplicates(repository, clock);
      await scan();
      final group = repository.groups.single;
      await repository.save(
        DuplicateCandidateGroup(
          id: group.id,
          transactionIds: group.transactionIds,
          duplicateKey: group.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: group.createdAt,
          updatedAt: clock.now(),
        ),
      );

      repository.matches.add(_match('c', '25'));
      await scan();

      expect(repository.groups, hasLength(1));
      expect(repository.groups.single.transactionIds, hasLength(3));
      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.unresolved,
      );
    },
  );

  test('incremental refresh queries only the current duplicate key', () async {
    final repository = _Groups([_match('a', '25'), _match('b', '25')]);
    final transaction = _transaction('c', amount: '25');

    final result = await RefreshDuplicateGroupForTransaction(
      repository,
      _Clock(DateTime.utc(2026, 1, 1)),
    )(current: transaction);

    expect(result, isA<ApplicationSuccess<void>>());
    expect(repository.fullScanCalls, 0);
    expect(repository.keyLookups, ['2026-01-01|25|USD|expense']);
    expect(repository.groups.single.transactionIds.map((id) => id.value), [
      'a',
      'b',
    ]);
  });

  test('incremental edit refreshes both old and new keys', () async {
    final repository = _Groups([
      _match('old-a', '25'),
      _match('old-b', '25'),
      _match('new-a', '30'),
      _match('new-b', '30'),
    ]);
    final previous = _transaction('old-b', amount: '25');
    final current = _transaction('old-b', amount: '30');
    repository.matches
      ..removeWhere((match) => match.transactionIds.single.value == 'old-b')
      ..add(_match('new-b', '30'));

    await RefreshDuplicateGroupForTransaction(
      repository,
      _Clock(DateTime.utc(2026, 1, 1)),
    )(previous: previous, current: current);

    expect(repository.fullScanCalls, 0);
    expect(
      repository.keyLookups,
      containsAll(['2026-01-01|25|USD|expense', '2026-01-01|30|USD|expense']),
    );
    expect(repository.groups, hasLength(1));
    expect(
      repository.groups.single.duplicateKey.amount,
      DecimalValue.parse('30'),
    );
  });

  test(
    'incremental refresh preserves Keep Both for unchanged membership',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(repository, clock)();
      final existing = repository.groups.single;
      await repository.save(
        DuplicateCandidateGroup(
          id: existing.id,
          transactionIds: existing.transactionIds,
          duplicateKey: existing.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );

      await RefreshDuplicateGroupForTransaction(repository, clock)(
        current: _transaction('a', amount: '25'),
      );

      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.keepBoth,
      );
    },
  );

  test(
    'incremental refresh reopens on add and updates membership on removal',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(repository, clock)();
      final existing = repository.groups.single;
      await repository.save(
        DuplicateCandidateGroup(
          id: existing.id,
          transactionIds: existing.transactionIds,
          duplicateKey: existing.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );
      repository.matches.add(_match('c', '25'));
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        current: _transaction('c', amount: '25'),
      );
      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.unresolved,
      );

      repository.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'b',
      );
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        previous: _transaction('b', amount: '25'),
      );
      expect(repository.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'c',
      ]);
    },
  );

  test('transaction wrapper never runs the full scan on save', () async {
    final repository = _Groups([_match('a', '25'), _match('b', '25')]);
    final delegate = _Transactions();
    final wrapper = DuplicateReviewingTransactionRepository(
      delegate,
      RefreshDuplicateGroupForTransaction(
        repository,
        _Clock(DateTime.utc(2026, 1, 1)),
      ),
    );

    await wrapper.save(_transaction('c', amount: '25'));

    expect(repository.fullScanCalls, 0);
  });

  test(
    'transaction deletion refreshes the previous duplicate key only',
    () async {
      final groups = _Groups([_match('a', '25'), _match('b', '25')]);
      final delegate = _Transactions()..values['b'] = _transaction('b');
      final wrapper = DuplicateReviewingTransactionRepository(
        delegate,
        RefreshDuplicateGroupForTransaction(
          groups,
          _Clock(DateTime.utc(2026, 1, 1)),
        ),
      );

      await wrapper.removePermanently(TransactionId('b'));

      expect(groups.fullScanCalls, 0);
      expect(groups.keyLookups, ['2026-01-01|25|USD|expense']);
    },
  );
}

DuplicateTransactionGroupMatch _match(
  String id,
  String amount, {
  String date = '2026-01-01',
  String currency = 'USD',
  String direction = 'expense',
}) => DuplicateTransactionGroupMatch(
  duplicateKey: DuplicateTransactionKey(
    transactionDate: date,
    amount: DecimalValue.parse(amount),
    currency: currency,
    direction: direction,
  ),
  transactionIds: [TransactionId(id)],
);

final class _Clock implements ApplicationClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

Transaction _transaction(
  String id, {
  String amount = '25',
  String date = '2026-01-01',
  TransactionStatus status = TransactionStatus.active,
}) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(
    amount: DecimalValue.parse(amount),
    currency: CurrencyCode('USD'),
  ),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: date,
  status: status,
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-$id'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 1, 1),
    ),
  ],
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

final class _Groups implements DuplicateCandidateGroupRepository {
  _Groups(this.matches, [List<DuplicateCandidateGroup>? groups])
    : groups = groups ?? [];

  final List<DuplicateTransactionGroupMatch> matches;
  final List<DuplicateCandidateGroup> groups;
  final keyLookups = <String>[];
  int fullScanCalls = 0;

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async {
    fullScanCalls++;
    return matches
        .fold<Map<String, List<TransactionId>>>({}, (result, match) {
          final key = match.duplicateKey.canonical;
          result.putIfAbsent(key, () => []).addAll(match.transactionIds);
          return result;
        })
        .entries
        .where((entry) => entry.value.length > 1)
        .map(
          (entry) => DuplicateTransactionGroupMatch(
            duplicateKey: matches
                .firstWhere(
                  (match) => match.duplicateKey.canonical == entry.key,
                )
                .duplicateKey,
            transactionIds: entry.value,
          ),
        )
        .toList();
  }

  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async {
    keyLookups.add(key.canonical);
    return matches
        .where((match) => match.duplicateKey.canonical == key.canonical)
        .expand((match) => match.transactionIds)
        .toList();
  }

  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async => groups
      .where((group) => status == null || group.status == status)
      .toList();

  @override
  Future<void> save(DuplicateCandidateGroup group) async {
    groups.removeWhere((value) => value.id == group.id);
    groups.add(group);
  }

  @override
  Future<void> remove(String id) async =>
      groups.removeWhere((value) => value.id == id);
}

final class _Transactions implements TransactionRepository {
  final values = <String, Transaction>{};

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values.toList();

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}
