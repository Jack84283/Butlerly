import 'package:butlerly/features/foundation/presentation/settlement_transaction_visibility.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hides only transactions backing payment settlements', () {
    final settlementPayment = _transaction(
      id: 'settlement-payment',
      direction: 'transfer',
    );
    final ordinaryTransfer = _transaction(
      id: 'ordinary-transfer',
      direction: 'transfer',
    );
    final purchase = _transaction(id: 'purchase', direction: 'expense');

    final visible = excludeSettlementPaymentTransactions(
      [settlementPayment, ordinaryTransfer, purchase],
      const {'settlement-payment'},
    );

    expect(
      visible.map((transaction) => transaction.id),
      ['ordinary-transfer', 'purchase'],
    );
  });
}

TransactionDto _transaction({
  required String id,
  required String direction,
}) {
  final now = DateTime.utc(2026, 9, 25);
  return TransactionDto(
    id: id,
    amount: '100.00',
    currency: 'USD',
    direction: direction,
    status: 'active',
    reviewState: 'clean',
    createdAt: now,
    updatedAt: now,
  );
}
