import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class ReviewItemDto {
  const ReviewItemDto({
    required this.issueId,
    required this.transactionId,
    required this.reason,
    required this.createdAt,
    required this.amount,
    required this.currency,
    this.description,
    this.detail,
  });

  final String issueId;
  final String transactionId;
  final String reason;
  final DateTime createdAt;
  final String amount;
  final String currency;
  final String? description;
  final String? detail;

  factory ReviewItemDto.fromDomain(
    Transaction transaction,
    ReviewIssue issue,
  ) => ReviewItemDto(
    issueId: issue.id.value,
    transactionId: transaction.id.value,
    reason: issue.reason.name,
    createdAt: issue.createdAt,
    amount: transaction.money.amount.toString(),
    currency: transaction.money.currency.value,
    description: transaction.description,
    detail: issue.detail,
  );
}
