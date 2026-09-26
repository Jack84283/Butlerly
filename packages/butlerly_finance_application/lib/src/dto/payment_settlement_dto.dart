import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'transaction_dto.dart';

final class PaymentSettlementDto {
  const PaymentSettlementDto({
    required this.id,
    required this.paymentSourceId,
    required this.payment,
    required this.paymentDate,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.statementBalance,
    this.description,
    this.externalReference,
  });

  factory PaymentSettlementDto.fromDomain(PaymentSettlement value) =>
      PaymentSettlementDto(
        id: value.id.value,
        paymentSourceId: value.paymentSourceId.value,
        payment: value.payment,
        paymentDate: value.paymentDate,
        periodStart: value.periodStart,
        periodEnd: value.periodEnd,
        statementBalance: value.statementBalance,
        status: value.status,
        description: value.description,
        externalReference: value.externalReference,
        createdAt: value.createdAt,
        updatedAt: value.updatedAt,
      );

  final String id;
  final String paymentSourceId;
  final Money payment;
  final String paymentDate;
  final String periodStart;
  final String periodEnd;
  final Money? statementBalance;
  final PaymentSettlementStatus status;
  final String? description;
  final String? externalReference;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class PaymentSettlementDetailDto {
  const PaymentSettlementDetailDto({
    required this.settlement,
    required this.transactions,
  });

  final PaymentSettlementDto settlement;
  final List<TransactionDto> transactions;

  int get transactionCount => transactions.length;

  Money? get recordedTransactionTotal {
    final currency = settlement.payment.currency;
    var total = DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);
    for (final transaction in transactions) {
      if (transaction.currency.trim().toUpperCase() != currency.value) {
        return null;
      }
      final amount = DecimalValue.parse(transaction.amount);
      total = switch (TransactionDirection.values.byName(transaction.direction)) {
        TransactionDirection.expense => total.add(amount),
        TransactionDirection.refund || TransactionDirection.income =>
          total.subtract(amount),
        TransactionDirection.adjustment => total.add(amount),
        TransactionDirection.transfer => total,
      };
    }
    return Money(amount: total, currency: currency);
  }

  Money? get paymentDifference {
    final recorded = recordedTransactionTotal;
    if (recorded == null) return null;
    return Money(
      amount: settlement.payment.amount.subtract(recorded.amount),
      currency: settlement.payment.currency,
    );
  }
}
