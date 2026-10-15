import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Recognized card networks and wallet providers, stored independently of banks.
const cardPaymentNetworkLabels = <String, String>{
  'visa': 'Visa',
  'mastercard': 'Mastercard',
  'discover': 'Discover',
  'americanExpress': 'American Express',
  'jcb': 'JCB',
  'dinersClub': 'Diners Club',
};

const walletPaymentProviderLabels = <String, String>{
  'paypal': 'PayPal',
  'venmo': 'Venmo',
  'applePay': 'Apple Pay',
  'googlePay': 'Google Pay',
  'alipay': 'Alipay',
  'wechatPay': 'WeChat Pay',
};

/// Only matches explicitly named networks, never an issuer or last-four digits.
String? paymentNetworkFromText(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final raw = input.toLowerCase();
  if (raw.contains('支付宝')) return 'alipay';
  if (raw.contains('微信支付') || raw.contains('微信钱包')) {
    return 'wechatPay';
  }
  final normalized =
      ' ${input.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), ' ').trim()} ';
  if (normalized.contains(' american express ') ||
      normalized.contains(' amex ')) {
    return 'americanExpress';
  }
  if (normalized.contains(' mastercard ') ||
      normalized.contains(' master card ')) {
    return 'mastercard';
  }
  if (normalized.contains(' discover ')) return 'discover';
  if (normalized.contains(' visa ')) return 'visa';
  if (normalized.contains(' jcb ')) return 'jcb';
  if (normalized.contains(' diners club ')) return 'dinersClub';
  if (normalized.contains(' paypal ') || normalized.contains(' pay pal ')) {
    return 'paypal';
  }
  if (normalized.contains(' venmo ')) return 'venmo';
  if (normalized.contains(' apple pay ')) return 'applePay';
  if (normalized.contains(' google pay ') || normalized.contains(' gpay ')) {
    return 'googlePay';
  }
  if (normalized.contains(' alipay ') || normalized.contains(' ali pay ')) {
    return 'alipay';
  }
  if (normalized.contains(' wechat pay ') ||
      normalized.contains(' wechatpay ') ||
      normalized.contains(' weixin pay ') ||
      normalized.contains(' weixinpay ')) {
    return 'wechatPay';
  }
  return null;
}

String paymentMarkFor(PaymentSource source) {
  if (source.type == PaymentSourceType.cash) return 'cash';
  if (source.type == PaymentSourceType.account) return 'account';
  final named = paymentNetworkFromText('${source.name} ${source.issuer ?? ''}');
  if (source.type == PaymentSourceType.card ||
      source.type == PaymentSourceType.debitCard) {
    if (cardPaymentNetworkLabels.containsKey(source.network)) {
      return source.network!;
    }
    return cardPaymentNetworkLabels.containsKey(named) ? named! : 'card';
  }
  if (source.type == PaymentSourceType.wallet) {
    if (walletPaymentProviderLabels.containsKey(source.network)) {
      return source.network!;
    }
    return walletPaymentProviderLabels.containsKey(named) ? named! : 'wallet';
  }
  return named ?? 'other';
}

/// No icon background, shape, outline or shadow: brand artwork only.
class ButlerlyPaymentSourceIcon extends StatelessWidget {
  const ButlerlyPaymentSourceIcon({
    required this.source,
    this.size = 30,
    super.key,
  });

  final PaymentSource source;
  final double size;

  @override
  Widget build(BuildContext context) =>
      ButlerlyPaymentMarkIcon(mark: paymentMarkFor(source), size: size);
}

class ButlerlyPaymentMarkIcon extends StatelessWidget {
  const ButlerlyPaymentMarkIcon({
    required this.mark,
    this.size = 30,
    super.key,
  });

  final String mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    const svgNames = <String, String>{
      'visa': 'visa',
      'mastercard': 'mastercard',
      'discover': 'discover',
      'americanExpress': 'americanexpress',
      'jcb': 'jcb',
      'dinersClub': 'dinersclub',
      'paypal': 'paypal',
      'venmo': 'venmo',
      'applePay': 'applepay',
      'googlePay': 'googlepay',
      'alipay': 'alipay',
      'wechatPay': 'wechatpay',
    };
    final name = svgNames[mark];
    Widget symbol;
    if (name != null) {
      symbol = SvgPicture.asset(
        'assets/icons/payment_sources/$name.svg',
        fit: BoxFit.contain,
      );
    } else if (mark == 'cash') {
      symbol = Center(
        child: Text(
          r'$',
          style: TextStyle(
            fontSize: size * .75,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    } else {
      symbol = Icon(
        switch (mark) {
          'account' => Icons.account_balance_outlined,
          'wallet' => Icons.account_balance_wallet_outlined,
          _ => Icons.credit_card_outlined,
        },
        size: size * .83,
        color: Theme.of(context).colorScheme.onSurface,
      );
    }
    return ExcludeSemantics(
      child: SizedBox.square(dimension: size, child: symbol),
    );
  }
}
