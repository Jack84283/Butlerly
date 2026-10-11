import '../value_objects/decimal_value.dart';
import '../value_objects/domain_id.dart';
import 'transaction.dart';

enum DuplicateCandidateGroupStatus { unresolved, keepBoth, consolidated }

/// The only fields that define a possible duplicate.
final class DuplicateTransactionKey {
  const DuplicateTransactionKey({
    required this.transactionDate,
    required this.amount,
    required this.currency,
    required this.direction,
  });

  final String transactionDate;
  final DecimalValue amount;
  final String currency;
  final String direction;

  /// Returns the duplicate key only when the transaction participates in the
  /// active duplicate-review population.
  static DuplicateTransactionKey? fromTransaction(Transaction transaction) {
    final date = transaction.transactionDate;
    if (transaction.status != TransactionStatus.active || date == null) {
      return null;
    }
    return fromTransactionFacts(transaction);
  }

  /// Returns the key represented by the persisted duplicate facts regardless
  /// of whether the record is currently active or archived. Review candidate
  /// generation remains Active-only, but archived records still participate in
  /// historical canonical decisions and can be edited after resolution.
  static DuplicateTransactionKey? fromTransactionFacts(
    Transaction transaction,
  ) {
    final date = transaction.transactionDate;
    if (date == null) return null;
    return DuplicateTransactionKey(
      transactionDate: date,
      amount: transaction.money.amount,
      currency: transaction.money.currency.value,
      direction: transaction.direction.name,
    );
  }

  String get canonical =>
      '$transactionDate|$amount|${currency.trim().toUpperCase()}|$direction';

  @override
  bool operator ==(Object other) =>
      other is DuplicateTransactionKey && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;
}

final class DuplicateCandidateGroup {
  DuplicateCandidateGroup({
    required this.id,
    required List<TransactionId> transactionIds,
    required this.duplicateKey,
    required this.status,
    this.selectedTransactionId,
    List<DuplicateCandidateStatementRow> statementRows = const [],
    this.integrityIssue,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : transactionIds = _sortedIds(transactionIds),
       statementRows = _sortedStatementRows(statementRows),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final List<TransactionId> transactionIds;
  final DuplicateTransactionKey duplicateKey;
  final DuplicateCandidateGroupStatus status;

  /// User-selected record for a future safe consolidation/link operation.
  /// This metadata never mutates financial records.
  final TransactionId? selectedTransactionId;

  /// Non-persisted diagnostic attached when a saved derived row could not be
  /// reconstructed exactly. The safe unresolved fallback remains usable by
  /// historical analysis while exposing the repair-needed state.
  final DuplicateCandidateGroupIntegrityIssue? integrityIssue;

  /// Statement rows that are waiting for an explicit duplicate decision.
  ///
  /// A statement candidate may have zero or one canonical transaction
  /// members. It is still a possible duplicate because the source row itself
  /// is the pending financial event; importing it must not create a second
  /// canonical record just to populate Review.
  final List<DuplicateCandidateStatementRow> statementRows;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUnresolved => status == DuplicateCandidateGroupStatus.unresolved;

  bool get hasStatementCandidates =>
      statementRows.isNotEmpty ||
      integrityIssue?.code == 'malformedStatementDuplicateEvidence';

  static List<TransactionId> _sortedIds(List<TransactionId> ids) {
    final values = ids.map((id) => id.value).toList()..sort();
    return List.unmodifiable(values.map(TransactionId.new));
  }

  static List<DuplicateCandidateStatementRow> _sortedStatementRows(
    List<DuplicateCandidateStatementRow> rows,
  ) {
    final result = [...rows]
      ..sort((left, right) => left.canonical.compareTo(right.canonical));
    return List.unmodifiable(result);
  }
}

/// A persisted reference to a statement row waiting for duplicate resolution.
/// The statement row remains the source evidence and is not a canonical
/// transaction until the user chooses a supported resolution.
final class DuplicateCandidateStatementRow {
  const DuplicateCandidateStatementRow({
    required this.statementId,
    required this.rowId,
  });

  final String statementId;
  final String rowId;

  String get canonical => '$statementId:$rowId';

  @override
  bool operator ==(Object other) =>
      other is DuplicateCandidateStatementRow &&
      other.statementId == statementId &&
      other.rowId == rowId;

  @override
  int get hashCode => Object.hash(statementId, rowId);
}

final class DuplicateCandidateGroupIntegrityIssue {
  const DuplicateCandidateGroupIntegrityIssue({
    required this.code,
    required this.detail,
  });

  final String code;
  final String detail;
}
