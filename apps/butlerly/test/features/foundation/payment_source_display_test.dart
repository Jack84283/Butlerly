import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
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
    expect(paymentMarkFor(source), 'card');
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

  test('explicit card network, wallet and cash marks are resolved', () {
    final visa = PaymentSource(
      id: PaymentSourceId('chase'),
      name: 'Chase Sapphire',
      type: PaymentSourceType.card,
      issuer: 'Chase',
      network: 'visa',
      lastFour: '8421',
    );
    expect(paymentMarkFor(visa), 'visa');
    expect(visa.archive().network, 'visa');

    final venmo = PaymentSource(
      id: PaymentSourceId('venmo'),
      name: 'Venmo wallet',
      type: PaymentSourceType.wallet,
    );
    expect(paymentMarkFor(venmo), 'venmo');
    expect(
      paymentMarkFor(
        PaymentSource(
          id: PaymentSourceId('cash'),
          name: 'Cash',
          type: PaymentSourceType.cash,
        ),
      ),
      'cash',
    );
    expect(paymentNetworkFromText('AMEX'), 'americanExpress');
    expect(paymentNetworkFromText('Capital One'), isNull);
  });
}
