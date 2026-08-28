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

final class _Groups implements DuplicateCandidateGroupRepository {
  _Groups(this.matches, [List<DuplicateCandidateGroup>? groups])
    : groups = groups ?? [];

  final List<DuplicateTransactionGroupMatch> matches;
  final List<DuplicateCandidateGroup> groups;

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async => matches
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
              .firstWhere((match) => match.duplicateKey.canonical == entry.key)
              .duplicateKey,
          transactionIds: entry.value,
        ),
      )
      .toList();

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
