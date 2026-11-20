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

  test('account-typed sources retain branded wallet icons', () {
    const providers = <String, String>{
      'Alipay': 'alipay',
      'PayPal': 'paypal',
      'Venmo': 'venmo',
      '微信支付': 'wechatPay',
    };
    for (final entry in providers.entries) {
      final source = PaymentSource(
        id: PaymentSourceId(entry.value),
        name: entry.key,
        type: PaymentSourceType.account,
      );
      expect(paymentMarkFor(source), entry.value, reason: entry.key);
      expect(source.type, PaymentSourceType.account);
    }

    final alias = PaymentSource(
      id: PaymentSourceId('alias'),
      name: 'Everyday wallet',
      displayIdentity: '支付宝',
      type: PaymentSourceType.account,
    );
    expect(paymentMarkFor(alias), 'alipay');

    final oldNetwork = PaymentSource(
      id: PaymentSourceId('old-network'),
      name: 'My money',
      type: PaymentSourceType.account,
      network: 'WeChat Pay',
    );
    expect(paymentMarkFor(oldNetwork), 'wechatPay');

    final ordinaryAccount = PaymentSource(
      id: PaymentSourceId('checking'),
      name: 'Checking',
      issuer: 'PayPal',
      type: PaymentSourceType.account,
    );
    expect(paymentMarkFor(ordinaryAccount), 'account');
    expect(paymentNetworkFromText('WeChat messages'), isNull);
  });

  testWidgets('account-typed wallet records display branded SVGs', (
    tester,
  ) async {
    final sources = [
      for (final provider in ['Alipay', 'PayPal', 'Venmo', '微信支付'])
        PaymentSource(
          id: PaymentSourceId(provider),
          name: provider,
          type: PaymentSourceType.account,
        ),
    ];
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

  testWidgets(
    'legacy account wallets keep provider marks even with bank issuers',
    (tester) async {
      final sources = <String, PaymentSource>{
        'no-artwork': PaymentSource(
          id: PaymentSourceId('legacy-paypal-capital-one'),
          name: 'Everyday wallet',
          issuer: 'Capital One',
          network: 'paypal',
          type: PaymentSourceType.account,
        ),
        'verified-artwork': PaymentSource(
          id: PaymentSourceId('legacy-paypal-chase'),
          name: 'My funds',
          issuer: 'Chase',
          network: 'PayPal',
          type: PaymentSourceType.account,
        ),
        'name-alias': PaymentSource(
          id: PaymentSourceId('legacy-venmo'),
          name: 'Venmo wallet',
          issuer: 'Chase',
          type: PaymentSourceType.account,
        ),
        'identity-alias': PaymentSource(
          id: PaymentSourceId('legacy-alipay'),
          name: 'My wallet',
          displayIdentity: '支付宝',
          issuer: 'Capital One',
          type: PaymentSourceType.account,
        ),
        'ordinary-bank': PaymentSource(
          id: PaymentSourceId('ordinary-bank'),
          name: 'Checking',
          issuer: 'Chase',
          network: 'ach',
          type: PaymentSourceType.account,
        ),
        'ordinary-no-logo': PaymentSource(
          id: PaymentSourceId('ordinary-custom'),
          name: 'Checking',
          issuer: 'My local credit union',
          network: 'visa',
          type: PaymentSourceType.account,
        ),
        'issuer-only-wallet-name': PaymentSource(
          id: PaymentSourceId('issuer-only-wallet-name'),
          name: 'Checking',
          issuer: 'PayPal',
          type: PaymentSourceType.account,
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final entry in sources.entries)
                  KeyedSubtree(
                    key: ValueKey(entry.key),
                    child: ButlerlyPaymentSourceIcon(source: entry.value),
                  ),
              ],
            ),
          ),
        ),
      );
      for (final (id, mark) in const [
        ('no-artwork', 'paypal'),
        ('verified-artwork', 'paypal'),
        ('name-alias', 'venmo'),
        ('identity-alias', 'alipay'),
      ]) {
        final icon = find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.byType(ButlerlyPaymentMarkIcon),
        );
        expect(icon, findsOneWidget, reason: id);
        expect(tester.widget<ButlerlyPaymentMarkIcon>(icon).mark, mark);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ordinary-bank')),
          matching: find.byType(ButlerlyIssuerIcon),
        ),
        findsOneWidget,
      );
      for (final id in ['ordinary-no-logo', 'issuer-only-wallet-name']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.byIcon(Icons.account_balance_outlined),
          ),
          findsOneWidget,
          reason: id,
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.byType(ButlerlyPaymentMarkIcon),
          ),
          findsNothing,
          reason: id,
        );
      }
      expect(
        sources.values.every(
          (source) => source.type == PaymentSourceType.account,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
    for (final filename in ['alipay', 'paypal', 'venmo', 'wechatpay']) {
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
                leadingIcon: ButlerlyPaymentMarkIcon(mark: provider, size: 24),
                entries: [DropdownMenuEntry(value: provider, label: provider)],
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
      expect((menu.leadingIcon! as ButlerlyPaymentMarkIcon).mark, provider);
      // Flutter also builds the dropdown's option artwork, so more than one
      // SVG may be present even when the selected field has only one mark.
      expect(find.byType(SvgPicture), findsWidgets);
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
