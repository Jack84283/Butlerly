import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';

Future<Set<String>> settlementPaymentTransactionIds(
  FinanceServices finance,
) async {
  final listSettlements = finance.listPaymentSettlements;
  if (listSettlements == null) return const {};

  final result = await listSettlements();
  return switch (result) {
    ApplicationSuccess<List<PaymentSettlementDto>>(:final value) => {
      for (final settlement in value) settlement.settlementTransactionId,
    },
    ApplicationFailure<List<PaymentSettlementDto>>() => throw StateError(
      'Payment settlement visibility could not be resolved.',
    ),
  };
}

List<TransactionDto> excludeSettlementPaymentTransactions(
  List<TransactionDto> transactions,
  Set<String> settlementTransactionIds,
) => transactions
    .where((transaction) => !settlementTransactionIds.contains(transaction.id))
    .toList(growable: false);
