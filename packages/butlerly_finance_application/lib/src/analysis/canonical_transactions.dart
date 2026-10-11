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
  final eligible = source
      .where(
        (value) =>
            (value.status == TransactionStatus.active ||
                value.status == TransactionStatus.archived) &&
            !receiptIds.contains(value.id),
      )
      .toList(growable: false);
  final byId = {for (final value in eligible) value.id: value};
  final groupByTransaction = <TransactionId, DuplicateCandidateGroup>{};
  for (final group in [
    ...duplicateGroups,
  ]..sort((left, right) => left.id.compareTo(right.id))) {
    for (final id in group.transactionIds) {
      groupByTransaction.putIfAbsent(id, () => group);
    }
  }

  final selectedIds = <TransactionId>{};
  final issuesByTransaction = <TransactionId, List<DataQualityIssue>>{};
  final globalIssues = <DataQualityIssue>[];
  final processedGroups = <String>{};
  for (final transaction in eligible) {
    final group = groupByTransaction[transaction.id];
    if (group == null) {
      selectedIds.add(transaction.id);
      continue;
    }
    if (!processedGroups.add(group.id)) continue;
    final members = group.transactionIds
        .map((id) => byId[id])
        .whereType<Transaction>()
        .toList(growable: false);
    if (members.isEmpty) {
      final integrityIssue = group.integrityIssue;
      if (integrityIssue != null) {
        globalIssues.add(
          DataQualityIssue(
            code: integrityIssue.code,
            detail: integrityIssue.detail,
          ),
        );
      }
      continue;
    }
    members.sort((left, right) => left.id.value.compareTo(right.id.value));
    final integrityIssue = group.integrityIssue;
    if (integrityIssue != null) {
      issuesByTransaction
          .putIfAbsent(members.first.id, () => [])
          .add(
            DataQualityIssue(
              code: integrityIssue.code,
              detail: integrityIssue.detail,
              transactionId: members.first.id,
            ),
          );
    }
    if (integrityIssue == null &&
        (members.length < 2 || group.transactionIds.length < 2)) {
      issuesByTransaction
          .putIfAbsent(members.first.id, () => [])
          .add(
            DataQualityIssue(
              code: 'staleDuplicateGroup',
              detail:
                  'A saved duplicate decision has fewer than two surviving members and needs repair.',
              transactionId: members.first.id,
            ),
          );
    }
    final hasStaleFacts = members.any(
      (value) => !_matchesDuplicateKey(value, group.duplicateKey),
    );
    if (hasStaleFacts) {
      // A later edit invalidates every saved decision, including Keep Both.
      // The old relationship must not suppress a member that is now a
      // financially distinct record. Keep the relationship visible as a
      // quality issue, but count every surviving member using current facts.
      selectedIds.addAll(members.map((value) => value.id));
      issuesByTransaction
          .putIfAbsent(members.first.id, () => [])
          .add(
            DataQualityIssue(
              code: 'staleDuplicateGroup',
              detail:
                  'A saved duplicate decision no longer matches current transaction facts; all surviving members are counted until the relationship is refreshed.',
              transactionId: members.first.id,
            ),
          );
      continue;
    }
    // A current duplicate relationship supersedes any stale relationship
    // that still contains one of the same records. Remove the members before
    // applying the current decision so an edited record is not selected once
    // by stale history and again by the current group.
    selectedIds.removeAll(members.map((value) => value.id));
    if (group.status == DuplicateCandidateGroupStatus.keepBoth) {
      selectedIds.addAll(members.map((value) => value.id));
      if (members.length != group.transactionIds.length) {
        issuesByTransaction
            .putIfAbsent(members.first.id, () => [])
            .add(
              DataQualityIssue(
                code: 'staleDuplicateGroup',
                detail:
                    'A saved duplicate group refers to a missing transaction.',
                transactionId: members.first.id,
              ),
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
    if (issueCode != null &&
        !hasInsufficientMembers &&
        (members.length > 1 || hasMissingMembers)) {
      issuesByTransaction
          .putIfAbsent(representative.id, () => [])
          .add(
            DataQualityIssue(
              code: issueCode,
              detail: group.status == DuplicateCandidateGroupStatus.unresolved
                  ? 'Duplicate candidates are counted once until resolved.'
                  : group.status ==
                            DuplicateCandidateGroupStatus.consolidated &&
                        group.selectedTransactionId == null
                  ? 'A consolidated duplicate group has no selected transaction; a stable representative is used until it is repaired.'
                  : 'Saved duplicate selection is unavailable; a stable representative is used.',
              transactionId: representative.id,
            ),
          );
    }
  }

  for (final group in duplicateGroups) {
    if (processedGroups.contains(group.id)) continue;
    // A pending statement row is not a canonical transaction yet. It remains
    // visible in Review through the statement reference and must not create a
    // global historical-data issue before the user explicitly resolves it.
    if (group.hasStatementCandidates && group.transactionIds.isEmpty) {
      continue;
    }
    final hasHistoricalMember = group.transactionIds.any(
      historicalById.containsKey,
    );
    if (group.integrityIssue != null ||
        group.transactionIds.isEmpty ||
        !hasHistoricalMember) {
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

  // A damaged or repeatedly rebuilt duplicate index can contain overlapping
  // groups. Treat connected non-Keep-Both groups as one ambiguous component so
  // a transaction cannot be selected once per overlapping decision.
  for (final component in _overlappingDuplicateGroupComponents(
    duplicateGroups,
    byId,
  )) {
    if (component.length < 2 ||
        component.every(
          (group) => group.status == DuplicateCandidateGroupStatus.keepBoth,
        )) {
      continue;
    }
    final memberIds = component.expand((group) => group.transactionIds).toSet();
    final members =
        memberIds
            .map((id) => byId[id])
            .whereType<Transaction>()
            .toList(growable: false)
          ..sort((left, right) => left.id.value.compareTo(right.id.value));
    if (members.length < 2) continue;
    final keepBothIds = component
        .where(
          (group) => group.status == DuplicateCandidateGroupStatus.keepBoth,
        )
        .expand((group) => group.transactionIds)
        .where(byId.containsKey)
        .toSet();
    selectedIds.removeAll(memberIds);
    final representative = members.firstWhere(
      (value) => !keepBothIds.contains(value.id),
      orElse: () => members.first,
    );
    selectedIds.addAll(keepBothIds);
    if (keepBothIds.isEmpty) selectedIds.add(representative.id);
    issuesByTransaction
        .putIfAbsent(representative.id, () => [])
        .add(
          DataQualityIssue(
            code: 'overlappingDuplicateGroups',
            detail:
                'Overlapping duplicate decisions were combined and counted once using a stable representative until the groups are refreshed.',
            transactionId: representative.id,
          ),
        );
  }

  final selected = eligible
      .where((value) => selectedIds.contains(value.id))
      .toList(growable: false);
  final qualityIssues = [
    ...globalIssues,
    ...issuesByTransaction.values.expand((value) => value),
  ];
  return CanonicalTransactionSelection(
    transactions: selected,
    qualityIssues: qualityIssues,
    issuesByTransaction: {
      for (final entry in issuesByTransaction.entries)
        entry.key: List.unmodifiable(entry.value),
    },
  );
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
    final memberIds = <TransactionId>{...sorted[index].transactionIds};
    for (var cursor = 0; cursor < componentIndexes.length; cursor++) {
      for (var candidate = 0; candidate < sorted.length; candidate++) {
        if (visited.contains(candidate)) continue;
        final overlaps = sorted[candidate].transactionIds.any(
          memberIds.contains,
        );
        if (!overlaps) continue;
        visited.add(candidate);
        componentIndexes.add(candidate);
        memberIds.addAll(sorted[candidate].transactionIds);
      }
    }
    components.add(
      componentIndexes.map((value) => sorted[value]).toList(growable: false),
    );
  }
  return components;
}
