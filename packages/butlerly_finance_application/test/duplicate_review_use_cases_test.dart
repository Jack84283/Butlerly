import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'explicit scan preserves Keep Both groups with unchanged membership',
    () async {
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
      final secondGroups =
          (second as ApplicationSuccess<List<DuplicateCandidateGroup>>).value;
      expect(
        secondGroups.single.status,
        DuplicateCandidateGroupStatus.keepBoth,
      );
      expect(secondGroups.single.selectedTransactionId, isNull);
    },
  );

  test(
    'scoped listing returns only groups with transactions in the period',
    () async {
      final repository = _Groups(const [], [
        _group('in-period', ['in-period-a', 'in-period-b']),
        _group('outside-period', ['outside-period-a', 'outside-period-b']),
      ]);
      final transactions = _Transactions()
        ..values['in-period-a'] = _transaction(
          'in-period-a',
          date: '2026-09-02',
        )
        ..values['in-period-b'] = _transaction(
          'in-period-b',
          date: '2026-09-03',
        )
        ..values['outside-period-a'] = _transaction(
          'outside-period-a',
          date: '2026-08-02',
        )
        ..values['outside-period-b'] = _transaction(
          'outside-period-b',
          date: '2026-08-03',
        );

      final result =
          await ListDuplicateCandidateGroups(
            repository,
            transactions: ListTransactions(transactions),
          )(
            scope: ReviewPeriodScope.fromDateValues(
              startDate: '2026-09-01',
              endDate: '2026-09-30',
              timeZoneId: 'UTC',
            ),
          );

      expect(
        (result as ApplicationSuccess<List<DuplicateCandidateGroup>>).value.map(
          (group) => group.id,
        ),
        ['in-period'],
      );
    },
  );

  test('integrity-error groups remain visible for repair', () async {
    final group = DuplicateCandidateGroup(
      id: 'damaged-group',
      transactionIds: [TransactionId('only-surviving-member')],
      duplicateKey: DuplicateTransactionKey(
        transactionDate: '2026-09-01',
        amount: DecimalValue.parse('25'),
        currency: 'USD',
        direction: 'expense',
      ),
      status: DuplicateCandidateGroupStatus.consolidated,
      selectedTransactionId: TransactionId('only-surviving-member'),
      integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
        code: 'incompleteDuplicateGroup',
        detail: 'A persisted duplicate group is missing linked members.',
      ),
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

    final result = await ListDuplicateCandidateGroups(
      _Groups(const [], [group]),
    )();

    expect(
      (result as ApplicationSuccess<List<DuplicateCandidateGroup>>).value,
      [group],
    );
  });

  test(
    'repairs malformed statement evidence without changing source records',
    () async {
      final group = DuplicateCandidateGroup(
        id: 'malformed-statement-group',
        transactionIds: [TransactionId('existing-transaction')],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-09-01',
          amount: DecimalValue.parse('25'),
          currency: 'USD',
          direction: 'expense',
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        statementRows: const [
          DuplicateCandidateStatementRow(
            statementId: 'missing-statement',
            rowId: 'missing-row',
          ),
        ],
        integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
          code: 'malformedStatementDuplicateEvidence',
          detail: 'The referenced statement row is unavailable.',
        ),
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final repository = _Groups(const [], [group]);

      final result = await RepairDuplicateCandidateGroup(
        repository,
        _Clock(DateTime.utc(2026, 9, 2)),
      )(group.id);

      expect(result, isA<ApplicationSuccess<void>>());
      expect(repository.groups, isEmpty);
    },
  );

  test(
    'explicit scan preserves consolidated groups with unchanged membership',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final scan = ScanExistingTransactionsForDuplicates(repository, clock);
      final first =
          (await scan() as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;
      await repository.save(
        DuplicateCandidateGroup(
          id: first.id,
          transactionIds: first.transactionIds,
          duplicateKey: first.duplicateKey,
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('a'),
          createdAt: first.createdAt,
          updatedAt: clock.now(),
        ),
      );
      final result =
          (await scan() as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;
      expect(result.status, DuplicateCandidateGroupStatus.consolidated);
      expect(result.selectedTransactionId, TransactionId('a'));
    },
  );

  test(
    'restore rebuild preserves Keep Both for unchanged membership',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final scan = ScanExistingTransactionsForDuplicates(repository, clock);
      final original =
          (await scan() as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;
      await repository.save(
        DuplicateCandidateGroup(
          id: original.id,
          transactionIds: original.transactionIds,
          duplicateKey: original.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: original.createdAt,
          updatedAt: clock.now(),
        ),
      );

      final rebuilt =
          (await RebuildDuplicateGroupsAfterRestore(repository, clock)()
                  as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;

      expect(rebuilt.status, DuplicateCandidateGroupStatus.keepBoth);
    },
  );

  test(
    'restore rebuild preserves consolidated selection for unchanged membership',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final scan = ScanExistingTransactionsForDuplicates(repository, clock);
      final original =
          (await scan() as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;
      await repository.save(
        DuplicateCandidateGroup(
          id: original.id,
          transactionIds: original.transactionIds,
          duplicateKey: original.duplicateKey,
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('a'),
          createdAt: original.createdAt,
          updatedAt: clock.now(),
        ),
      );

      final rebuilt =
          (await RebuildDuplicateGroupsAfterRestore(repository, clock)()
                  as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;

      expect(rebuilt.status, DuplicateCandidateGroupStatus.consolidated);
      expect(rebuilt.selectedTransactionId, TransactionId('a'));
    },
  );

  test('explicit scan preserves statement-only duplicate candidates', () async {
    final row = const DuplicateCandidateStatementRow(
      statementId: 'statement-scan',
      rowId: 'row-scan',
    );
    final group = DuplicateCandidateGroup(
      id: 'duplicate:2026-01-01|25|USD|expense',
      transactionIds: [TransactionId('existing')],
      duplicateKey: DuplicateTransactionKey(
        transactionDate: '2026-01-01',
        amount: DecimalValue.parse('25'),
        currency: 'USD',
        direction: 'expense',
      ),
      status: DuplicateCandidateGroupStatus.unresolved,
      statementRows: [row],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final repository = _Groups(const [], [group]);

    final result = await ScanExistingTransactionsForDuplicates(
      repository,
      _Clock(DateTime.utc(2026, 1, 2)),
    )();

    expect(result, isA<ApplicationSuccess<List<DuplicateCandidateGroup>>>());
    expect(repository.groups.single.statementRows, [row]);
  });

  test(
    'restore rebuild preserves statement-only duplicate candidates',
    () async {
      final row = const DuplicateCandidateStatementRow(
        statementId: 'statement-restore',
        rowId: 'row-restore',
      );
      final group = DuplicateCandidateGroup(
        id: 'duplicate:2026-01-01|25|USD|expense',
        transactionIds: const [],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-01-01',
          amount: DecimalValue.parse('25'),
          currency: 'USD',
          direction: 'expense',
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        statementRows: [row],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final repository = _Groups(const [], [group]);

      final result = await RebuildDuplicateGroupsAfterRestore(
        repository,
        _Clock(DateTime.utc(2026, 1, 2)),
      )();

      expect(result, isA<ApplicationSuccess<List<DuplicateCandidateGroup>>>());
      expect(repository.groups.single.statementRows, [row]);
    },
  );

  test(
    'restore rebuild reopens a resolved group when membership changes',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final scan = ScanExistingTransactionsForDuplicates(repository, clock);
      final original =
          (await scan() as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;
      await repository.save(
        DuplicateCandidateGroup(
          id: original.id,
          transactionIds: original.transactionIds,
          duplicateKey: original.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: original.createdAt,
          updatedAt: clock.now(),
        ),
      );
      repository.matches.add(_match('c', '25'));

      final rebuilt =
          (await RebuildDuplicateGroupsAfterRestore(repository, clock)()
                  as ApplicationSuccess<List<DuplicateCandidateGroup>>)
              .value
              .single;

      expect(rebuilt.status, DuplicateCandidateGroupStatus.unresolved);
      expect(rebuilt.transactionIds.map((id) => id.value), ['a', 'b', 'c']);
    },
  );

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

  test('Keep Both and Consolidate invalidate Analysis caches', () async {
    for (final status in [
      DuplicateCandidateGroupStatus.keepBoth,
      DuplicateCandidateGroupStatus.consolidated,
    ]) {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(repository, clock)();
      final results = _InvalidationResults();
      final resolved =
          await ResolveDuplicateCandidateGroup(
            repository,
            clock,
            invalidateAnalysis: InvalidateAnalysis(
              _InvalidationFindings(),
              results: results,
            ),
          )(
            repository.groups.single.id,
            status,
            selectedTransactionId:
                status == DuplicateCandidateGroupStatus.consolidated
                ? TransactionId('b')
                : null,
          );

      expect(resolved, isA<ApplicationSuccess<void>>());
      expect(results.markStaleCalls, 1);
      expect(repository.groups.single.status, status);
    }
  });

  test(
    'editing a duplicate-key field reopens the old resolved group',
    () async {
      final repository = _Groups([
        _match('old-a', '25'),
        _match('old-b', '25'),
        _match('new-a', '30'),
        _match('new-b', '30'),
      ]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(repository, clock)();
      final oldGroup = repository.groups.firstWhere(
        (group) => group.duplicateKey.amount == DecimalValue.parse('25'),
      );
      await repository.save(
        DuplicateCandidateGroup(
          id: oldGroup.id,
          transactionIds: oldGroup.transactionIds,
          duplicateKey: oldGroup.duplicateKey,
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('old-a'),
          createdAt: oldGroup.createdAt,
          updatedAt: oldGroup.updatedAt,
        ),
      );
      repository.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'old-b',
      );
      repository.matches.add(_match('new-b', '30'));

      await RefreshDuplicateGroupForTransaction(repository, clock)(
        previous: _transaction('old-b', amount: '25'),
        current: _transaction('old-b', amount: '30'),
      );

      final reopened = repository.groups.firstWhere(
        (group) => group.id == oldGroup.id,
      );
      expect(reopened.status, DuplicateCandidateGroupStatus.unresolved);
      expect(reopened.selectedTransactionId, isNull);
      expect(reopened.transactionIds.map((id) => id.value), ['old-a', 'old-b']);
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
    'incremental refresh reopens on add and preserves deletion history',
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
        'b',
        'c',
      ]);
    },
  );

  test(
    'incremental refresh keeps archived history when a new match arrives later',
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
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('a'),
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );

      repository.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'b',
      );
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        previous: _transaction('b'),
        current: _transaction('b', status: TransactionStatus.archived),
      );
      expect(repository.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'b',
      ]);

      repository.matches.add(_match('c', '25'));
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        current: _transaction('c', amount: '25'),
      );

      expect(repository.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'b',
        'c',
      ]);
      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.unresolved,
      );
      expect(repository.groups.single.selectedTransactionId, isNull);
    },
  );

  test(
    'incremental refresh preserves resolved history when a member archives',
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
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('a'),
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );

      repository.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'b',
      );
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        previous: _transaction('b'),
        current: _transaction('b', status: TransactionStatus.archived),
      );

      expect(repository.groups, hasLength(1));
      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.consolidated,
      );
      expect(repository.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'b',
      ]);
    },
  );

  test(
    'incremental refresh preserves a pending statement candidate across archive restore',
    () async {
      final repository = _Groups([_match('a', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      final group = DuplicateCandidateGroup(
        id: 'duplicate:2026-01-01|25|USD|expense',
        transactionIds: [TransactionId('a')],
        duplicateKey: _match('a', '25').duplicateKey,
        status: DuplicateCandidateGroupStatus.unresolved,
        statementRows: const [
          DuplicateCandidateStatementRow(
            statementId: 'statement',
            rowId: 'row',
          ),
        ],
        createdAt: clock.now(),
        updatedAt: clock.now(),
      );
      await repository.save(group);

      repository.matches.clear();
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        previous: _transaction('a', amount: '25'),
        current: _transaction(
          'a',
          amount: '25',
          status: TransactionStatus.archived,
        ),
      );
      expect(repository.groups.single.statementRows, hasLength(1));

      repository.matches.add(_match('a', '25'));
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        current: _transaction('a', amount: '25'),
      );
      expect(repository.groups.single.statementRows, hasLength(1));
    },
  );

  test(
    'incremental refresh preserves a resolved group when one of three members archives',
    () async {
      final repository = _Groups([
        _match('a', '25'),
        _match('b', '25'),
        _match('c', '25'),
      ]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(repository, clock)();
      final existing = repository.groups.single;
      await repository.save(
        DuplicateCandidateGroup(
          id: existing.id,
          transactionIds: existing.transactionIds,
          duplicateKey: existing.duplicateKey,
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('a'),
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );

      repository.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'c',
      );
      await RefreshDuplicateGroupForTransaction(repository, clock)(
        previous: _transaction('c'),
        current: _transaction('c', status: TransactionStatus.archived),
      );

      expect(
        repository.groups.single.status,
        DuplicateCandidateGroupStatus.consolidated,
      );
      expect(
        repository.groups.single.selectedTransactionId,
        TransactionId('a'),
      );
      expect(repository.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'b',
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
    'transaction mutation invalidates materialized analysis at the boundary',
    () async {
      final repository = _Groups([_match('a', '25'), _match('b', '25')]);
      final delegate = _Transactions();
      final results = _InvalidationResults();
      final wrapper = DuplicateReviewingTransactionRepository(
        delegate,
        RefreshDuplicateGroupForTransaction(
          repository,
          _Clock(DateTime.utc(2026, 1, 1)),
        ),
        invalidateAnalysis: InvalidateAnalysis(
          _InvalidationFindings(),
          results: results,
        ),
      );

      await wrapper.save(_transaction('c', amount: '25'));

      expect(results.markStaleCalls, 1);
    },
  );

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

  test(
    'transaction wrapper preserves Keep Both history across permanent deletion',
    () async {
      final groups = _Groups([
        _match('a', '25'),
        _match('b', '25'),
        _match('c', '25'),
      ]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(groups, clock)();
      final existing = groups.groups.single;
      await groups.save(
        DuplicateCandidateGroup(
          id: existing.id,
          transactionIds: existing.transactionIds,
          duplicateKey: existing.duplicateKey,
          status: DuplicateCandidateGroupStatus.keepBoth,
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );
      groups.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'b',
      );
      final wrapper = DuplicateReviewingTransactionRepository(
        _Transactions()..values['b'] = _transaction('b'),
        RefreshDuplicateGroupForTransaction(groups, clock),
      );

      await wrapper.removePermanently(TransactionId('b'));

      expect(
        groups.groups.single.status,
        DuplicateCandidateGroupStatus.keepBoth,
      );
      expect(groups.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'b',
        'c',
      ]);
    },
  );

  test(
    'transaction wrapper preserves a consolidated selection across deleting it',
    () async {
      final groups = _Groups([_match('a', '25'), _match('b', '25')]);
      final clock = _Clock(DateTime.utc(2026, 1, 1));
      await ScanExistingTransactionsForDuplicates(groups, clock)();
      final existing = groups.groups.single;
      await groups.save(
        DuplicateCandidateGroup(
          id: existing.id,
          transactionIds: existing.transactionIds,
          duplicateKey: existing.duplicateKey,
          status: DuplicateCandidateGroupStatus.consolidated,
          selectedTransactionId: TransactionId('a'),
          createdAt: existing.createdAt,
          updatedAt: clock.now(),
        ),
      );
      groups.matches.removeWhere(
        (match) => match.transactionIds.single.value == 'a',
      );
      final wrapper = DuplicateReviewingTransactionRepository(
        _Transactions()..values['a'] = _transaction('a'),
        RefreshDuplicateGroupForTransaction(groups, clock),
      );

      await wrapper.removePermanently(TransactionId('a'));

      expect(
        groups.groups.single.status,
        DuplicateCandidateGroupStatus.consolidated,
      );
      expect(groups.groups.single.selectedTransactionId, TransactionId('a'));
      expect(groups.groups.single.transactionIds.map((id) => id.value), [
        'a',
        'b',
      ]);
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

final class _InvalidationResults implements AnalysisRuleResultRepository {
  var markStaleCalls = 0;

  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async => const [];

  @override
  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  }) async => null;

  @override
  Future<void> save(AnalysisRuleResult result) async {}

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async => markStaleCalls++;
}

final class _InvalidationFindings implements AnalysisFindingRepository {
  @override
  Future<void> save(AnalysisFinding finding) async {}

  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async =>
      const [];

  @override
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) async {}
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

DuplicateCandidateGroup _group(String id, List<String> transactionIds) =>
    DuplicateCandidateGroup(
      id: id,
      transactionIds: transactionIds.map(TransactionId.new).toList(),
      duplicateKey: DuplicateTransactionKey(
        transactionDate: '2026-09-01',
        amount: DecimalValue.parse('25'),
        currency: 'USD',
        direction: 'expense',
      ),
      status: DuplicateCandidateGroupStatus.unresolved,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

final class _Transactions implements TransactionRepository {
  final values = <String, Transaction>{};

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    return values.values
        .where(
          (value) =>
              (query.from == null ||
                  value.transactionDate!.compareTo(
                        query.from!.toIso8601String().substring(0, 10),
                      ) >=
                      0) &&
              (query.to == null ||
                  value.transactionDate!.compareTo(
                        query.to!.toIso8601String().substring(0, 10),
                      ) <=
                      0) &&
              (query.status == null || value.status == query.status),
        )
        .toList();
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}
