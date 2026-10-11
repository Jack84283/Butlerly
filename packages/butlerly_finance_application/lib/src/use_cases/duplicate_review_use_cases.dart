import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../commands/transaction_commands.dart';
import '../dto/review_period_scope.dart';
import '../dto/transaction_dto.dart';
import '../analysis/invalidation.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';

Future<void> _invalidateDuplicateAnalysis(
  InvalidateAnalysis? invalidateAnalysis,
  ApplicationClock clock,
) async {
  if (invalidateAnalysis == null) return;
  final result = await invalidateAnalysis(
    AnalysisInvalidationReason.duplicateDecisionChanged,
    clock.now(),
  );
  if (result is ApplicationFailure<void>) {
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'invalidate analysis after duplicate review rebuild',
    );
  }
}

final class ScanExistingTransactionsForDuplicates {
  const ScanExistingTransactionsForDuplicates(
    this.groups,
    this.clock, {
    this.invalidateAnalysis,
  });

  final DuplicateCandidateGroupRepository groups;
  final ApplicationClock clock;
  final InvalidateAnalysis? invalidateAnalysis;

  Future<ApplicationResult<List<DuplicateCandidateGroup>>> call() =>
      runApplication('scan existing transactions for duplicates', () async {
        final matches = await groups.findActiveDuplicateGroups();
        final existing = await groups.list();
        final existingById = {for (final group in existing) group.id: group};
        final activeIds = <String>{};
        final result = <DuplicateCandidateGroup>[];
        for (final match in matches) {
          final id = _groupId(match);
          activeIds.add(id);
          final previous = existingById[id];
          final transactionIds = _mergeHistoricalIds(
            previous?.transactionIds ?? const [],
            match.transactionIds,
          );
          final membershipUnchanged =
              previous != null &&
              _sameIds(previous.transactionIds, transactionIds);
          final group = DuplicateCandidateGroup(
            id: id,
            transactionIds: transactionIds,
            duplicateKey: match.duplicateKey,
            status: membershipUnchanged
                ? previous.status
                : DuplicateCandidateGroupStatus.unresolved,
            selectedTransactionId: membershipUnchanged
                ? previous.selectedTransactionId
                : null,
            statementRows: previous?.statementRows ?? const [],
            createdAt: previous?.createdAt ?? clock.now(),
            updatedAt: clock.now(),
          );
          await groups.save(group);
          result.add(group);
        }
        // Resolved groups remain as history, while stale unresolved groups are
        // removed so Review reflects only currently matching transactions.
        for (final group in existing) {
          if (!activeIds.contains(group.id) &&
              group.isUnresolved &&
              !group.hasStatementCandidates) {
            await groups.remove(group.id);
          }
        }
        await _invalidateDuplicateAnalysis(invalidateAnalysis, clock);
        return result;
      });

  String _groupId(DuplicateTransactionGroupMatch match) {
    return 'duplicate:${match.duplicateKey.canonical}';
  }
}

/// Rebuilds derived duplicate-review state after restore without reopening
/// restored user decisions when the duplicate membership is unchanged.
final class RebuildDuplicateGroupsAfterRestore {
  const RebuildDuplicateGroupsAfterRestore(
    this.groups,
    this.clock, {
    this.invalidateAnalysis,
  });

  final DuplicateCandidateGroupRepository groups;
  final ApplicationClock clock;
  final InvalidateAnalysis? invalidateAnalysis;

  Future<ApplicationResult<List<DuplicateCandidateGroup>>> call() =>
      runApplication('rebuild duplicate groups after restore', () async {
        final matches = await groups.findActiveDuplicateGroups();
        final existing = await groups.list();
        final existingById = {for (final group in existing) group.id: group};
        final activeIds = <String>{};
        final result = <DuplicateCandidateGroup>[];

        for (final match in matches) {
          final id = 'duplicate:${match.duplicateKey.canonical}';
          activeIds.add(id);
          final previous = existingById[id];
          final transactionIds = _mergeHistoricalIds(
            previous?.transactionIds ?? const [],
            match.transactionIds,
          );
          final membershipUnchanged =
              previous != null &&
              _sameIds(previous.transactionIds, transactionIds);
          final group = DuplicateCandidateGroup(
            id: id,
            transactionIds: transactionIds,
            duplicateKey: match.duplicateKey,
            status: membershipUnchanged
                ? previous.status
                : DuplicateCandidateGroupStatus.unresolved,
            selectedTransactionId: membershipUnchanged
                ? previous.selectedTransactionId
                : null,
            statementRows: previous?.statementRows ?? const [],
            createdAt: previous?.createdAt ?? clock.now(),
            updatedAt: clock.now(),
          );
          await groups.save(group);
          result.add(group);
        }

        for (final group in existing) {
          if (!activeIds.contains(group.id) &&
              group.isUnresolved &&
              !group.hasStatementCandidates) {
            await groups.remove(group.id);
          }
        }
        await _invalidateDuplicateAnalysis(invalidateAnalysis, clock);
        return result;
      });
}

/// Refreshes only the duplicate key(s) affected by one transaction mutation.
/// The historical scan remains reserved for explicit rescan/repair actions.
final class RefreshDuplicateGroupForTransaction {
  const RefreshDuplicateGroupForTransaction(this.groups, this.clock);

  final DuplicateCandidateGroupRepository groups;
  final ApplicationClock clock;

  Future<ApplicationResult<void>> call({
    Transaction? previous,
    Transaction? current,
  }) => runApplication('refresh possible duplicate group', () async {
    final keys = <String, DuplicateTransactionKey>{};
    final previousKey = previous == null
        ? null
        : DuplicateTransactionKey.fromTransaction(previous);
    final currentKey = current == null
        ? null
        : DuplicateTransactionKey.fromTransaction(current);
    if (previousKey != null) keys[previousKey.canonical] = previousKey;
    if (currentKey != null) keys[currentKey.canonical] = currentKey;
    if (keys.isEmpty) return;

    final existing = await groups.list();
    final existingById = {for (final group in existing) group.id: group};
    final duplicateKeyChanged =
        previousKey != null && currentKey != null && previousKey != currentKey;
    for (final key in keys.values) {
      await _refreshKey(
        key,
        existingById,
        preserveHistoricalMembership:
            current == null || current.status == TransactionStatus.archived,
        duplicateKeyChanged: duplicateKeyChanged && key == previousKey,
      );
    }
  });

  Future<void> _refreshKey(
    DuplicateTransactionKey key,
    Map<String, DuplicateCandidateGroup> existingById, {
    required bool preserveHistoricalMembership,
    required bool duplicateKeyChanged,
  }) async {
    final groupId = 'duplicate:${key.canonical}';
    final previous = existingById[groupId];
    final transactionIds = (await groups.findActiveTransactionIdsForKey(key))
      ..sort((left, right) => left.value.compareTo(right.value));

    if (transactionIds.length < 2) {
      if (previous != null && duplicateKeyChanged) {
        await groups.save(
          DuplicateCandidateGroup(
            id: previous.id,
            transactionIds: previous.transactionIds,
            duplicateKey: previous.duplicateKey,
            status: DuplicateCandidateGroupStatus.unresolved,
            statementRows: previous.statementRows,
            createdAt: previous.createdAt,
            updatedAt: clock.now(),
          ),
        );
        return;
      }
      if (previous?.hasStatementCandidates ?? false) return;
      if (preserveHistoricalMembership) return;
      if (previous != null && previous.isUnresolved) {
        await groups.remove(groupId);
      }
      return;
    }
    final effectiveTransactionIds = _mergeHistoricalIds(
      previous?.transactionIds ?? const [],
      transactionIds,
    );
    final membershipUnchanged =
        previous != null &&
        _sameIds(previous.transactionIds, effectiveTransactionIds);
    final group = DuplicateCandidateGroup(
      id: groupId,
      transactionIds: effectiveTransactionIds,
      duplicateKey: key,
      status: membershipUnchanged
          ? previous.status
          : DuplicateCandidateGroupStatus.unresolved,
      selectedTransactionId: membershipUnchanged
          ? previous.selectedTransactionId
          : null,
      statementRows: previous?.statementRows ?? const [],
      createdAt: previous?.createdAt ?? clock.now(),
      updatedAt: clock.now(),
    );
    await groups.save(group);
  }
}

List<TransactionId> _mergeHistoricalIds(
  List<TransactionId> historical,
  List<TransactionId> active,
) {
  final ids = {...historical, ...active}.toList()
    ..sort((left, right) => left.value.compareTo(right.value));
  return List.unmodifiable(ids);
}

bool _sameIds(List<TransactionId> left, List<TransactionId> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class ListDuplicateCandidateGroups {
  const ListDuplicateCandidateGroups(
    this.repository, {
    this.transactions,
    this.statements,
  });

  final DuplicateCandidateGroupRepository repository;
  final ListTransactions? transactions;
  final StatementRepository? statements;

  Future<ApplicationResult<List<DuplicateCandidateGroup>>> call({
    ReviewPeriodScope scope = const ReviewPeriodScope.unscoped(),
  }) => runApplication('list possible duplicate groups', () async {
    final groups = (await repository.list())
        .where((group) => group.isUnresolved || group.integrityIssue != null)
        .toList(growable: false);
    final eligibleIds = await _eligibleTransactionIds(scope);
    final eligibleStatementRows = await _eligibleStatementRows(scope);
    final activeIdsByGroup = eligibleIds == null && transactions != null
        ? {
            for (final group in groups)
              group.id: (await repository.findActiveTransactionIdsForKey(
                group.duplicateKey,
              )).toSet(),
          }
        : const <String, Set<TransactionId>>{};
    return groups
        .where(
          (group) =>
              group.integrityIssue != null ||
              group.hasStatementCandidates &&
                  (eligibleStatementRows == null ||
                      group.statementRows.any(
                        (row) => eligibleStatementRows.contains(row.canonical),
                      )) ||
              (eligibleIds == null && transactions == null
                  ? group.transactionIds.length > 1
                  : group.transactionIds
                            .where(
                              (id) =>
                                  (eligibleIds ?? activeIdsByGroup[group.id]!)
                                      .contains(id),
                            )
                            .length >
                        1),
        )
        .where(
          (group) =>
              group.integrityIssue != null ||
              (group.hasStatementCandidates &&
                  (eligibleStatementRows == null ||
                      group.statementRows.any(
                        (row) => eligibleStatementRows.contains(row.canonical),
                      ))) ||
              eligibleIds == null ||
              group.transactionIds.any(eligibleIds.contains),
        )
        .toList();
  });

  Future<Set<TransactionId>?> _eligibleTransactionIds(
    ReviewPeriodScope scope,
  ) async {
    if (scope.isInvalid) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidRange,
        field: 'period',
        message: 'The Review period is invalid.',
      );
    }
    if (!scope.isScoped) return null;
    final listTransactions = transactions;
    if (listTransactions == null) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list possible duplicate groups',
      );
    }
    final period = scope.period!;
    final result = await listTransactions(
      ListTransactionsQuery(
        from: DateTime.parse(period.startDate),
        to: DateTime.parse(period.endDate),
        timeZoneId: period.timeZoneId,
        status: TransactionStatus.active,
      ),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) =>
        value.map((transaction) => TransactionId(transaction.id)).toSet(),
      ApplicationFailure<List<TransactionDto>>() =>
        throw const RepositoryException(
          RepositoryFailureCode.unavailable,
          'list possible duplicate groups',
        ),
    };
  }

  Future<Set<String>?> _eligibleStatementRows(ReviewPeriodScope scope) async {
    if (!scope.isScoped) return null;
    final repository = statements;
    if (repository == null) return <String>{};
    final period = scope.period!;
    final values = <String>{};
    for (final statement in await repository.listStatements()) {
      for (final row in await repository.listRows(statement.id)) {
        final date = row.transactionDate;
        if (date == null) continue;
        final day = date.toIso8601String().substring(0, 10);
        if (day.compareTo(period.startDate) >= 0 &&
            day.compareTo(period.endDate) <= 0) {
          values.add('${row.statementId}:${row.id}');
        }
      }
    }
    return values;
  }
}

final class ResolveDuplicateCandidateGroup {
  const ResolveDuplicateCandidateGroup(
    this.repository,
    this.clock, {
    this.invalidateAnalysis,
  });

  final DuplicateCandidateGroupRepository repository;
  final ApplicationClock clock;
  final InvalidateAnalysis? invalidateAnalysis;

  Future<ApplicationResult<void>> call(
    String id,
    DuplicateCandidateGroupStatus status, {
    TransactionId? selectedTransactionId,
  }) => runApplication('resolve possible duplicate group', () async {
    final groups = await repository.list();
    DuplicateCandidateGroup? group;
    for (final value in groups) {
      if (value.id == id) {
        group = value;
        break;
      }
    }
    if (group == null) return;
    if (group.hasStatementCandidates) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidState,
        field: 'statementRows',
        message:
            'Statement duplicate candidates require an explicit row decision.',
      );
    }
    // Consolidation is currently a non-destructive review decision only. The
    // application has no safe financial-record merge operation, so resolving
    // this state must never delete, overwrite, archive, or mutate a transaction.
    if (status == DuplicateCandidateGroupStatus.consolidated &&
        (selectedTransactionId == null ||
            !group.transactionIds.contains(selectedTransactionId))) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidState,
        field: 'selectedTransactionId',
        message: 'A consolidated group requires a selected transaction.',
      );
    }
    await repository.save(
      DuplicateCandidateGroup(
        id: group.id,
        transactionIds: group.transactionIds,
        duplicateKey: group.duplicateKey,
        status: status,
        selectedTransactionId: selectedTransactionId,
        statementRows: group.statementRows,
        createdAt: group.createdAt,
        updatedAt: clock.now(),
      ),
    );
    final invalidation = invalidateAnalysis;
    if (invalidation != null) {
      final result = await invalidation.call(
        AnalysisInvalidationReason.duplicateDecisionChanged,
        clock.now(),
      );
      if (result is ApplicationFailure<void>) {
        throw const RepositoryException(
          RepositoryFailureCode.unavailable,
          'invalidate analysis after duplicate decision',
        );
      }
    }
  });
}

/// Clears only unreconstructable derived duplicate metadata so the source
/// statement row can return to ordinary review without changing financial
/// records or source evidence.
final class RepairDuplicateCandidateGroup {
  const RepairDuplicateCandidateGroup(
    this.repository,
    this.clock, {
    this.invalidateAnalysis,
  });

  final DuplicateCandidateGroupRepository repository;
  final ApplicationClock clock;
  final InvalidateAnalysis? invalidateAnalysis;

  Future<ApplicationResult<void>> call(String id) => runApplication(
    'repair possible duplicate group',
    () async {
      final group = (await repository.list())
          .where((value) => value.id == id)
          .firstOrNull;
      if (group == null) return;
      if (group.integrityIssue?.code != 'malformedStatementDuplicateEvidence') {
        throw const DomainValidationException(
          code: DomainErrorCode.invalidState,
          field: 'integrityIssue',
          message: 'This duplicate group does not require evidence repair.',
        );
      }
      await repository.remove(id);
      final invalidation = invalidateAnalysis;
      if (invalidation != null) {
        final result = await invalidation(
          AnalysisInvalidationReason.duplicateDecisionChanged,
          clock.now(),
        );
        if (result is ApplicationFailure<void>) {
          throw const RepositoryException(
            RepositoryFailureCode.unavailable,
            'invalidate analysis after duplicate evidence repair',
          );
        }
      }
    },
  );
}
