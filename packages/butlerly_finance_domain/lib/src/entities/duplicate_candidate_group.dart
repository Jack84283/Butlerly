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
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : transactionIds = _sortedIds(transactionIds),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final List<TransactionId> transactionIds;
  final DuplicateTransactionKey duplicateKey;
  final DuplicateCandidateGroupStatus status;

  /// User-selected record for a future safe consolidation/link operation.
  /// This metadata never mutates financial records.
  final TransactionId? selectedTransactionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUnresolved => status == DuplicateCandidateGroupStatus.unresolved;

  static List<TransactionId> _sortedIds(List<TransactionId> ids) {
    final values = ids.map((id) => id.value).toList()..sort();
    return List.unmodifiable(values.map(TransactionId.new));
  }
}
