import 'dart:io';

import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  test('non-card source keeps stored last four when present', () {
    final source = PaymentSource(
      id: PaymentSourceId('debit-1'),
      name: 'Debit',
      type: PaymentSourceType.debitCard,
      lastFour: '1234',
    );
    expect(paymentSourceDisplayLabel(source), 'Debit •••• 1234');
  });

  test('legacy wallet provider labels still show their branded icons', () {
    const providers = <String, String>{
      'Alipay': 'alipay',
      'PayPal': 'paypal',
      'Venmo': 'venmo',
      'WeChat Pay': 'wechatPay',
    };
    for (final entry in providers.entries) {
      final source = PaymentSource(
        id: PaymentSourceId(entry.value),
        name: 'My wallet',
        type: PaymentSourceType.wallet,
        network: entry.key,
      );
      expect(paymentMarkFor(source), entry.value, reason: entry.key);
    }
  });

  test('explicit network and wallet/cash fallback resolve correctly', () {
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
    final cash = PaymentSource(
      id: PaymentSourceId('cash'),
      name: 'Cash',
      type: PaymentSourceType.cash,
    );
    expect(paymentMarkFor(cash), 'cash');
    expect(paymentNetworkFromText('AMEX'), 'americanExpress');
    expect(paymentNetworkFromText('Capital One'), isNull);
    expect(paymentNetworkFromText('Alipay'), 'alipay');
    expect(paymentNetworkFromText('Ali Pay'), 'alipay');
    expect(paymentNetworkFromText('支付宝'), 'alipay');
    expect(paymentNetworkFromText('WeChat Pay'), 'wechatPay');
    expect(paymentNetworkFromText('WeChatPay'), 'wechatPay');
    expect(paymentNetworkFromText('Weixin Pay'), 'wechatPay');
    expect(paymentNetworkFromText('微信支付'), 'wechatPay');
    expect(paymentNetworkFromText('微信钱包'), 'wechatPay');
    expect(paymentNetworkFromText('WeChat messages'), isNull);
    expect(walletPaymentProviderLabels['alipay'], 'Alipay');
    expect(walletPaymentProviderLabels['wechatPay'], 'WeChat Pay');
  });

  testWidgets('Alipay and WeChat Pay use bundled payment SVG marks', (
    tester,
  ) async {
    final sources = [
      PaymentSource(
        id: PaymentSourceId('alipay-wallet'),
        name: '支付宝',
        type: PaymentSourceType.wallet,
      ),
      PaymentSource(
        id: PaymentSourceId('wechat-pay-wallet'),
        name: '微信支付',
        type: PaymentSourceType.wallet,
      ),
      PaymentSource(
        id: PaymentSourceId('explicit-wechat'),
        name: 'My wallet',
        type: PaymentSourceType.wallet,
        network: 'wechatPay',
      ),
    ];
    expect(sources.map(paymentMarkFor), ['alipay', 'wechatPay', 'wechatPay']);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final source in sources)
                ButlerlyPaymentSourceIcon(source: source),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });


  test('all four wallet brands ship offline SVG assets', () {
    for (final filename in [
      'alipay',
      'paypal',
      'venmo',
      'wechatpay',
    ]) {
      final path = 'assets/icons/payment_sources/$filename.svg';
      final asset = File(path);
      expect(asset.existsSync(), isTrue, reason: path);
      final svg = asset.readAsStringSync();
      expect(svg, contains('<svg'), reason: path);
      expect(svg, contains('</svg>'), reason: path);
    }
  });

  testWidgets('all four wallet providers resolve to bundled SVG marks', (
    tester,
  ) async {
    final sources = [
      PaymentSource(
        id: PaymentSourceId('paypal-wallet'),
        name: 'PayPal',
        type: PaymentSourceType.wallet,
      ),
      PaymentSource(
        id: PaymentSourceId('venmo-wallet'),
        name: 'Venmo',
        type: PaymentSourceType.wallet,
      ),
      PaymentSource(
        id: PaymentSourceId('alipay-wallet'),
        name: '支付宝',
        type: PaymentSourceType.wallet,
      ),
      PaymentSource(
        id: PaymentSourceId('wechat-wallet'),
        name: '微信支付',
        type: PaymentSourceType.wallet,
      ),
    ];
    expect(sources.map(paymentMarkFor), [
      'paypal',
      'venmo',
      'alipay',
      'wechatPay',
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final source in sources)
                ButlerlyPaymentSourceIcon(source: source),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected wallet provider keeps its brand icon in the field', (
    tester,
  ) async {
    for (final provider in ['alipay', 'paypal', 'venmo', 'wechatPay']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ButlerlySelectField<String>(
                label: 'Wallet provider',
                value: provider,
                leadingIcon: ButlerlyPaymentMarkIcon(
                  mark: provider,
                  size: 24,
                ),
                entries: [
                  DropdownMenuEntry(value: provider, label: provider),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final menu = tester.widget<DropdownMenu<String>>(
        find.byType(DropdownMenu<String>),
      );
      expect(menu.leadingIcon, isA<ButlerlyPaymentMarkIcon>());
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('renders transparent marks, cash and unknown fallback', (
    tester,
  ) async {
    final visa = PaymentSource(
      id: PaymentSourceId('visa'),
      name: 'Visa',
      type: PaymentSourceType.card,
      network: 'visa',
    );
    final cash = PaymentSource(
      id: PaymentSourceId('cash'),
      name: 'Cash',
      type: PaymentSourceType.cash,
    );
    final other = PaymentSource(
      id: PaymentSourceId('other'),
      name: 'Unknown',
      type: PaymentSourceType.card,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ButlerlyPaymentSourceIcon(source: visa),
              ButlerlyPaymentSourceIcon(source: cash),
              ButlerlyPaymentSourceIcon(source: other),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text(r'$'), findsOneWidget);
    expect(find.byIcon(Icons.credit_card_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
