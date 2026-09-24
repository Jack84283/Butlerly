import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'transaction_dto.dart';

final class PaymentSettlementDto {
  const PaymentSettlementDto({
    required this.id,
    required this.settlementTransactionId,
    required this.paymentSourceId,
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
        settlementTransactionId: value.settlementTransactionId.value,
        paymentSourceId: value.paymentSourceId.value,
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
  final String settlementTransactionId;
  final String paymentSourceId;
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
    required this.paymentTransaction,
    required this.transactions,
  });

  final PaymentSettlementDto settlement;
  final TransactionDto paymentTransaction;
  final List<TransactionDto> transactions;

  int get transactionCount => transactions.length;
}
