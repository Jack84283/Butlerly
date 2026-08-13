import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:intl/intl.dart';

String transactionDateLabel(
  TransactionDto transaction, {
  required String pendingLabel,
  String locale = 'en',
}) {
  final businessDate = transaction.transactionDate?.trim();
  if (businessDate != null && businessDate.isNotEmpty) {
    final parsed = DateTime.tryParse(businessDate);
    if (parsed != null) return DateFormat.yMMMd(locale).format(parsed);
    return businessDate;
  }

  final occurredAt = transaction.occurredAt;
  if (occurredAt == null) return pendingLabel;
  return DateFormat.yMMMd(locale).format(occurredAt.toLocal());
}

DateTime transactionCalendarDate(
  TransactionDto transaction, {
  required DateTime fallback,
}) {
  final businessDate = transaction.transactionDate?.trim();
  if (businessDate != null && businessDate.isNotEmpty) {
    final parsed = DateTime.tryParse(businessDate);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
  }

  final occurredAt = transaction.occurredAt;
  if (occurredAt != null) {
    final local = occurredAt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  return DateTime(fallback.year, fallback.month, fallback.day);
}

String shortDateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
