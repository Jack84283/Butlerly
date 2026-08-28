import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class ScanExistingTransactionsForDuplicates {
  const ScanExistingTransactionsForDuplicates(this.groups, this.clock);

  final DuplicateCandidateGroupRepository groups;
  final ApplicationClock clock;

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
          final transactionIds = _sortedIds(match.transactionIds);
          final membershipUnchanged =
              previous != null &&
              _sameIds(previous.transactionIds, transactionIds);
          final status = membershipUnchanged
              ? previous.status
              : DuplicateCandidateGroupStatus.unresolved;
          final group = DuplicateCandidateGroup(
            id: id,
            transactionIds: transactionIds,
            duplicateKey: match.duplicateKey,
            status: status,
            selectedTransactionId: membershipUnchanged
                ? previous.selectedTransactionId
                : null,
            createdAt: previous?.createdAt ?? clock.now(),
            updatedAt: clock.now(),
          );
          await groups.save(group);
          result.add(group);
        }
        // Resolved groups remain as history, while stale unresolved groups are
        // removed so Review reflects only currently matching transactions.
        for (final group in existing) {
          if (!activeIds.contains(group.id) && group.isUnresolved) {
            await groups.remove(group.id);
          }
        }
        return result;
      });

  String _groupId(DuplicateTransactionGroupMatch match) {
    return 'duplicate:${match.duplicateKey.canonical}';
  }

  List<TransactionId> _sortedIds(List<TransactionId> ids) => List.unmodifiable(
    ids.toList()..sort((a, b) => a.value.compareTo(b.value)),
  );

  bool _sameIds(List<TransactionId> left, List<TransactionId> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

final class ListDuplicateCandidateGroups {
  const ListDuplicateCandidateGroups(this.repository);

  final DuplicateCandidateGroupRepository repository;

  Future<ApplicationResult<List<DuplicateCandidateGroup>>> call() =>
      runApplication('list possible duplicate groups', () async {
        final groups = await repository.list(
          status: DuplicateCandidateGroupStatus.unresolved,
        );
        return groups
            .where((group) => group.transactionIds.length > 1)
            .toList();
      });
}

final class ResolveDuplicateCandidateGroup {
  const ResolveDuplicateCandidateGroup(this.repository, this.clock);

  final DuplicateCandidateGroupRepository repository;
  final ApplicationClock clock;

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
        createdAt: group.createdAt,
        updatedAt: clock.now(),
      ),
    );
  });
}
