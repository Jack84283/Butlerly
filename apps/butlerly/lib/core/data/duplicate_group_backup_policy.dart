/// Identifies unresolved duplicate groups whose historical decision or repair
/// context is durable enough to survive a backup, while ordinary generated
/// review groups remain rebuildable and are omitted.
abstract final class DuplicateGroupBackupPolicy {
  static Set<String> durableUnresolvedGroupIds({
    required List<Map<String, Object?>> groups,
    required List<Map<String, Object?>> memberships,
    required List<Map<String, Object?>> transactions,
  }) {
    final transactionsById = <String, Map<String, Object?>>{
      for (final row in transactions)
        if (row['id'] is String) row['id']! as String: row,
    };
    final membersByGroup = <String, Set<String>>{};
    for (final row in memberships) {
      final groupId = row['group_id'];
      final transactionId = row['transaction_id'];
      if (groupId is String && transactionId is String) {
        (membersByGroup[groupId] ??= <String>{}).add(transactionId);
      }
    }

    final repairable = <String>{};
    for (final group in groups) {
      final id = group['id'];
      if (id is! String || group['status'] != 'unresolved') continue;
      if (_hasStatementEvidence(group['statement_rows'])) continue;

      final members = membersByGroup[id] ?? const <String>{};
      // SQLite reconstruction treats malformed timestamps as repairable group
      // metadata. Keep the row portable so restore cannot silently turn that
      // state into an ordinary generated unresolved group.
      var needsRepair =
          !_isValidTimestamp(group['created_at']) ||
          !_isValidTimestamp(group['updated_at']);
      var hasMatchingMember = false;
      for (final memberId in members) {
        final transaction = transactionsById[memberId];
        if (transaction == null) {
          needsRepair = true;
          continue;
        }
        if (_matchesKey(transaction, group)) {
          hasMatchingMember = true;
        } else if (_hasDuplicateFacts(transaction)) {
          needsRepair = true;
        }
      }
      // A group with fewer than two currently matching members is repairable
      // when at least one member still proves the original duplicate key. A
      // hand-created/generated row that points at an undated transaction does
      // not meet that proof and remains rebuildable during merge cleanup.
      if (members.length < 2 && hasMatchingMember) needsRepair = true;

      // Archived records remain part of historical canonical analysis. Keep
      // an unresolved decision that includes one so restore does not turn a
      // one-representative history into two counted records.
      final hasArchivedMember = members.any(
        (memberId) => transactionsById[memberId]?['status'] == 'archived',
      );
      if (hasArchivedMember) needsRepair = true;

      // A newly matching record is also a membership integrity change. Keep
      // the saved group so restart/restore reopens it instead of silently
      // applying its old decision to only the original records.
      if (!needsRepair) {
        needsRepair = transactions.any(
          (transaction) =>
              transaction['id'] is String &&
              _matchesKey(transaction, group) &&
              !members.contains(transaction['id']),
        );
      }
      if (needsRepair) repairable.add(id);
    }
    return repairable;
  }

  static bool hasStatementEvidence(Object? value) {
    return _hasStatementEvidence(value);
  }

  static bool _hasStatementEvidence(Object? value) {
    if (value is! String) return false;
    final normalized = value.trim();
    return normalized.isNotEmpty && normalized != '[]';
  }

  static bool _isValidTimestamp(Object? value) {
    return value is String && DateTime.tryParse(value) != null;
  }

  static bool _matchesKey(
    Map<String, Object?> transaction,
    Map<String, Object?> group,
  ) {
    return transaction['transaction_date'] == group['transaction_date'] &&
        transaction['amount_coefficient'] == group['amount_coefficient'] &&
        transaction['amount_scale'] == group['amount_scale'] &&
        '${transaction['currency']}'.trim().toUpperCase() ==
            '${group['currency']}'.trim().toUpperCase() &&
        transaction['direction'] == group['direction'] &&
        (transaction['status'] == 'active' ||
            transaction['status'] == 'archived');
  }

  static bool _hasDuplicateFacts(Map<String, Object?> transaction) {
    return transaction['transaction_date'] is String &&
        (transaction['transaction_date']! as String).isNotEmpty &&
        transaction['amount_coefficient'] is String &&
        transaction['amount_scale'] is int &&
        transaction['currency'] is String &&
        (transaction['currency']! as String).isNotEmpty &&
        transaction['direction'] is String &&
        (transaction['direction']! as String).isNotEmpty &&
        (transaction['status'] == 'active' ||
            transaction['status'] == 'archived');
  }
}
