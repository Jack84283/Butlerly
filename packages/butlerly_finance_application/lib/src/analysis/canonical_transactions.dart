import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Selects the economic transaction representatives used by historical
/// analysis. Review and candidate-generation workflows deliberately do not
/// use this helper: those workflows remain Active-only.
final class CanonicalTransactionSelection {
  const CanonicalTransactionSelection({
    required this.transactions,
    required this.qualityIssues,
    required this.issuesByTransaction,
  });

  final List<Transaction> transactions;
  final List<DataQualityIssue> qualityIssues;
  final Map<TransactionId, List<DataQualityIssue>> issuesByTransaction;
}

/// Applies the shared post-reconciliation canonical policy:
///
/// * active and archived records are historical economic records;
/// * receipt-side records linked to a payment are not counted;
/// * Keep Both counts every member while the saved key remains valid;
/// * Consolidated counts the selected member;
/// * unresolved groups count one deterministic representative and expose an
///   explainable quality issue until the user decides;
/// * stale groups no longer describe the same economic relationship, so every
///   surviving member is counted using its current facts while the stale
///   relationship remains a visible quality issue until repaired.
///
/// Missing/deleted records are naturally absent from [source]. Invalid
/// consolidation selections fall back to the stable lowest transaction ID.
CanonicalTransactionSelection selectCanonicalTransactions({
  required List<Transaction> source,
  List<ReconciliationLink> links = const [],
  List<DuplicateCandidateGroup> duplicateGroups = const [],
}) {
  final receiptIds = links.map((value) => value.receiptTransactionId).toSet();
  final historicalById = {
    for (final value in source)
      if (value.status == TransactionStatus.active ||
          value.status == TransactionStatus.archived)
        value.id: value,
  };
  final eligible =
      source
          .where(
            (value) =>
                (value.status == TransactionStatus.active ||
                    value.status == TransactionStatus.archived) &&
                !receiptIds.contains(value.id),
          )
          .toList()
        ..sort((left, right) => left.id.value.compareTo(right.id.value));
  final byId = {for (final value in eligible) value.id: value};

  final selectedIds = <TransactionId>{};
  final issuesByTransaction = <TransactionId, List<DataQualityIssue>>{};
  final globalIssues = <DataQualityIssue>[];
  final groups = [...duplicateGroups]
    ..sort((left, right) => left.id.compareTo(right.id));

  // A stale relationship is historical evidence only. Apply every
  // relationship whose saved key still matches its surviving transaction
  // facts first, so a valid current group always wins over obsolete history.
  final currentGroups = <DuplicateCandidateGroup>[];
  final staleGroups = <DuplicateCandidateGroup>[];
  for (final group in groups) {
    final historicalMembers = group.transactionIds
        .map((id) => historicalById[id])
        .whereType<Transaction>()
        .toList(growable: false);
    final hasStaleFacts =
        group.integrityIssue?.code == 'staleDuplicateGroup' ||
        historicalMembers.any(
          (value) => !_matchesDuplicateKey(value, group.duplicateKey),
        );
    (hasStaleFacts ? staleGroups : currentGroups).add(group);
  }

  final currentOwnedIds = <TransactionId>{};
  for (final component in _overlappingDuplicateGroupComponents(
    currentGroups,
    byId,
  )) {
    final memberIds = component.expand((group) => group.transactionIds).toSet();
    currentOwnedIds.addAll(memberIds);
    final members =
        memberIds.map((id) => byId[id]).whereType<Transaction>().toList()
          ..sort((left, right) => left.id.value.compareTo(right.id.value));
    if (members.isEmpty) continue;

    for (final group in component) {
      _addGroupIntegrityIssue(group, members, issuesByTransaction);
      final groupMembers = group.transactionIds
          .map((id) => byId[id])
          .whereType<Transaction>()
          .toList(growable: false);
      if (group.integrityIssue == null &&
          groupMembers.isNotEmpty &&
          (groupMembers.length < 2 ||
              group.transactionIds.length < 2 ||
              groupMembers.length != group.transactionIds.length)) {
        _addIssue(
          issuesByTransaction,
          groupMembers.first.id,
          'staleDuplicateGroup',
          groupMembers.length < 2
              ? 'A saved duplicate decision has fewer than two surviving members and needs repair.'
              : 'A saved duplicate decision refers to a missing transaction and needs repair.',
        );
      }
    }

    if (component.length > 1) {
      // Damaged/rebuilt indexes can contain overlapping current groups. Use a
      // stable component-wide policy so the representative cannot depend on
      // group or transaction iteration order.
      final allKeepBoth = component.every(
        (group) => group.status == DuplicateCandidateGroupStatus.keepBoth,
      );
      final keepBothIds = component
          .where(
            (group) => group.status == DuplicateCandidateGroupStatus.keepBoth,
          )
          .expand((group) => group.transactionIds)
          .where(byId.containsKey)
          .toSet();
      selectedIds.addAll(keepBothIds);
      if (keepBothIds.isEmpty) selectedIds.add(members.first.id);
      if (!allKeepBoth) {
        _addIssue(
          issuesByTransaction,
          members
              .firstWhere(
                (value) => selectedIds.contains(value.id),
                orElse: () => members.first,
              )
              .id,
          'overlappingDuplicateGroups',
          'Overlapping duplicate decisions were combined and counted once using a stable representative until the groups are refreshed.',
        );
      }
      continue;
    }

    final group = component.single;
    if (group.status == DuplicateCandidateGroupStatus.keepBoth) {
      selectedIds.addAll(members.map((value) => value.id));
      if (members.length != group.transactionIds.length) {
        _addIssue(
          issuesByTransaction,
          members.first.id,
          'staleDuplicateGroup',
          'A saved duplicate group refers to a missing transaction.',
        );
      }
      continue;
    }

    final selected = group.selectedTransactionId == null
        ? null
        : members
              .where((value) => value.id == group.selectedTransactionId)
              .firstOrNull;
    final representative = selected ?? members.first;
    selectedIds.add(representative.id);
    final hasMissingMembers = members.length != group.transactionIds.length;
    final hasInsufficientMembers =
        members.length < 2 || group.transactionIds.length < 2;
    final issueCode = group.status == DuplicateCandidateGroupStatus.unresolved
        ? 'unresolvedDuplicate'
        : group.status == DuplicateCandidateGroupStatus.consolidated &&
              group.selectedTransactionId == null
        ? 'invalidDuplicateSelection'
        : selected == null && group.selectedTransactionId != null
        ? 'invalidDuplicateSelection'
        : hasMissingMembers
        ? 'staleDuplicateGroup'
        : null;
    if (group.integrityIssue == null &&
        issueCode != null &&
        !hasInsufficientMembers &&
        (members.length > 1 || hasMissingMembers)) {
      _addIssue(
        issuesByTransaction,
        representative.id,
        issueCode,
        group.status == DuplicateCandidateGroupStatus.unresolved
            ? 'Duplicate candidates are counted once until resolved.'
            : group.status == DuplicateCandidateGroupStatus.consolidated &&
                  group.selectedTransactionId == null
            ? 'A consolidated duplicate group has no selected transaction; a stable representative is used until it is repaired.'
            : 'Saved duplicate selection is unavailable; a stable representative is used.',
      );
    }
  }

  for (final group in staleGroups) {
    final members =
        group.transactionIds
            .map((id) => byId[id])
            .whereType<Transaction>()
            .toList()
          ..sort((left, right) => left.id.value.compareTo(right.id.value));
    if (members.isEmpty) continue;
    selectedIds.addAll(
      members
          .map((value) => value.id)
          .where((id) => !currentOwnedIds.contains(id)),
    );
    final issueTarget = members
        .where((value) => selectedIds.contains(value.id))
        .firstOrNull;
    final detail =
        group.integrityIssue?.detail ??
        'A saved duplicate decision no longer matches current transaction facts; financially distinct members are counted independently until the relationship is repaired.';
    if (issueTarget == null) {
      globalIssues.add(
        DataQualityIssue(code: 'staleDuplicateGroup', detail: detail),
      );
    } else {
      _addIssue(
        issuesByTransaction,
        issueTarget.id,
        'staleDuplicateGroup',
        detail,
      );
    }
  }

  // Transactions that do not belong to a currently valid duplicate component
  // are independent historical records, including members retained only by a
  // stale relationship.
  selectedIds.addAll(
    eligible
        .map((value) => value.id)
        .where((id) => !currentOwnedIds.contains(id)),
  );

  for (final group in groups) {
    // A pending statement row is not a canonical transaction yet. It remains
    // visible in Review through the statement reference and must not create a
    // global historical-data issue before the user explicitly resolves it.
    if (group.hasStatementCandidates && group.transactionIds.isEmpty) {
      continue;
    }
    final hasHistoricalMember = group.transactionIds.any(
      historicalById.containsKey,
    );
    final hasEligibleMember = group.transactionIds.any(byId.containsKey);
    if (group.transactionIds.isEmpty ||
        !hasHistoricalMember ||
        !hasEligibleMember) {
      final integrityIssue = group.integrityIssue;
      globalIssues.add(
        DataQualityIssue(
          code: integrityIssue?.code ?? 'staleDuplicateGroup',
          detail:
              integrityIssue?.detail ??
              'A saved duplicate decision has no surviving historical member and needs repair.',
        ),
      );
    }
  }

  final selected = eligible
      .where((value) => selectedIds.contains(value.id))
      .toList(growable: false);
  final qualityIssues = <DataQualityIssue>[
    ...globalIssues,
    ...issuesByTransaction.values.expand((value) => value),
  ];
  qualityIssues.sort((left, right) {
    final transactionCompare = (left.transactionId?.value ?? '').compareTo(
      right.transactionId?.value ?? '',
    );
    if (transactionCompare != 0) return transactionCompare;
    final codeCompare = left.code.compareTo(right.code);
    if (codeCompare != 0) return codeCompare;
    return left.detail.compareTo(right.detail);
  });
  return CanonicalTransactionSelection(
    transactions: selected,
    qualityIssues: qualityIssues,
    issuesByTransaction: {
      for (final entry in issuesByTransaction.entries)
        entry.key: List.unmodifiable(entry.value),
    },
  );
}

void _addIssue(
  Map<TransactionId, List<DataQualityIssue>> issuesByTransaction,
  TransactionId transactionId,
  String code,
  String detail,
) {
  final issues = issuesByTransaction.putIfAbsent(transactionId, () => []);
  if (issues.any((issue) => issue.code == code && issue.detail == detail)) {
    return;
  }
  issues.add(
    DataQualityIssue(code: code, detail: detail, transactionId: transactionId),
  );
}

void _addGroupIntegrityIssue(
  DuplicateCandidateGroup group,
  List<Transaction> members,
  Map<TransactionId, List<DataQualityIssue>> issuesByTransaction,
) {
  final issue = group.integrityIssue;
  if (issue == null || members.isEmpty) return;
  _addIssue(issuesByTransaction, members.first.id, issue.code, issue.detail);
}

bool _matchesDuplicateKey(Transaction value, DuplicateTransactionKey key) =>
    value.transactionDate == key.transactionDate &&
    value.money.amount == key.amount &&
    value.money.currency.value.trim().toUpperCase() ==
        key.currency.trim().toUpperCase() &&
    value.direction.name == key.direction;

List<List<DuplicateCandidateGroup>> _overlappingDuplicateGroupComponents(
  List<DuplicateCandidateGroup> groups,
  Map<TransactionId, Transaction> currentTransactions,
) {
  // A stale group is evidence that an old relationship needs repair, not a
  // current duplicate edge. Excluding it here prevents an edited member from
  // being collapsed again by an unrelated, newly discovered duplicate group.
  final sorted =
      groups
          .where(
            (group) =>
                group.integrityIssue?.code != 'staleDuplicateGroup' &&
                !group.transactionIds.any(
                  (id) =>
                      currentTransactions[id] != null &&
                      !_matchesDuplicateKey(
                        currentTransactions[id]!,
                        group.duplicateKey,
                      ),
                ),
          )
          .toList()
        ..sort((left, right) => left.id.compareTo(right.id));
  final visited = <int>{};
  final components = <List<DuplicateCandidateGroup>>[];
  for (var index = 0; index < sorted.length; index++) {
    if (!visited.add(index)) continue;
    final componentIndexes = <int>[index];
    final memberIds = _eligibleMemberIds(sorted[index], currentTransactions);
    for (var cursor = 0; cursor < componentIndexes.length; cursor++) {
      for (var candidate = 0; candidate < sorted.length; candidate++) {
        if (visited.contains(candidate)) continue;
        final candidateMemberIds = _eligibleMemberIds(
          sorted[candidate],
          currentTransactions,
        );
        final overlaps = candidateMemberIds.any(memberIds.contains);
        if (!overlaps) continue;
        visited.add(candidate);
        componentIndexes.add(candidate);
        memberIds.addAll(candidateMemberIds);
      }
    }
    components.add(
      componentIndexes.map((value) => sorted[value]).toList(growable: false),
    );
  }
  return components;
}

Set<TransactionId> _eligibleMemberIds(
  DuplicateCandidateGroup group,
  Map<TransactionId, Transaction> currentTransactions,
) => {
  for (final id in group.transactionIds)
    if (currentTransactions.containsKey(id)) id,
};
