import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import '../value_objects/money.dart';

enum PaymentSettlementStatus { open, reconciled, needsReview }

final class PaymentSettlement {
  PaymentSettlement({
    required this.id,
    required this.paymentSourceId,
    required this.payment,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required this.status,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.statementBalance,
    this.description,
    this.externalReference,
  }) : paymentDate = _financialDate(paymentDate, 'paymentDate'),
       periodStart = _financialDate(periodStart, 'periodStart'),
       periodEnd = _financialDate(periodEnd, 'periodEnd'),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (this.periodEnd.compareTo(this.periodStart) < 0) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'periodEnd',
        message: 'A payment settlement period cannot end before it starts.',
      );
    }
    if (statementBalance != null &&
        statementBalance!.currency != payment.currency) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'statementBalance',
        message:
            'Payment settlement balance currency must match payment currency.',
      );
    }
    if (this.updatedAt.isBefore(this.createdAt)) {
      invalid(
        code: DomainErrorCode.invalidTimestamp,
        field: 'updatedAt',
        message: 'A payment settlement cannot be updated before it is created.',
      );
    }
  }

  final PaymentSettlementId id;

  /// Payment source whose activity is reconciled by this settlement.
  final PaymentSourceId paymentSourceId;

  /// Payment amount and currency. A settlement is not a Transaction.
  final Money payment;

  /// ISO-8601 financial date on which the settlement payment was made.
  final String paymentDate;

  /// Inclusive ISO-8601 financial period start.
  final String periodStart;

  /// Inclusive ISO-8601 financial period end.
  final String periodEnd;

  final Money? statementBalance;
  final PaymentSettlementStatus status;
  final String? description;
  final String? externalReference;
  final DateTime createdAt;
  final DateTime updatedAt;

  static String _financialDate(String value, String field) {
    final normalized = value.trim();
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(normalized);
    final parsed = match == null ? null : DateTime.tryParse(normalized);
    final canonical = parsed == null ? null : _formatDate(parsed);
    if (canonical != normalized) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: field,
        message: 'Payment settlement dates must use YYYY-MM-DD.',
      );
    }
    return normalized;
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
