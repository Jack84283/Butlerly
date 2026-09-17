import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credit-card display includes stored last four digits', () {
    final source = PaymentSource(
      id: PaymentSourceId('card-1'),
      name: 'Chase Sapphire',
      type: PaymentSourceType.card,
      lastFour: '8421',
    );

    expect(paymentSourceDisplayLabel(source), 'Chase Sapphire •••• 8421');
    expect(paymentSourceRequiresLastFour(source.type), isTrue);
  });

  test('display identity is preferred and digits are never invented', () {
    final source = PaymentSource(
      id: PaymentSourceId('account-1'),
      name: 'Checking',
      type: PaymentSourceType.account,
      displayIdentity: 'Everyday Checking',
    );

    expect(paymentSourceDisplayLabel(source), 'Everyday Checking');
    expect(paymentSourceRequiresLastFour(source.type), isFalse);
  });

  test('non-card source keeps a stored last four when one exists', () {
    final source = PaymentSource(
      id: PaymentSourceId('debit-1'),
      name: 'Debit',
      type: PaymentSourceType.debitCard,
      lastFour: '1234',
    );

    expect(paymentSourceDisplayLabel(source), 'Debit •••• 1234');
  });
}
