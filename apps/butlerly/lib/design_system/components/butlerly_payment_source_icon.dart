import 'package:butlerly/design_system/components/butlerly_issuer_catalog.dart';
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
  // Older payment sources often used the default Account type for wallets.
  // Resolve an explicitly named wallet for its icon only, without changing
  // the source's saved type or treating its bank issuer as a wallet provider.
  if (source.type == PaymentSourceType.account) {
    final stored = paymentNetworkFromText(source.network);
    final named = paymentNetworkFromText(
      '${source.displayIdentity ?? ''} ${source.name}',
    );
    if (walletPaymentProviderLabels.containsKey(source.network)) {
      return source.network!;
    }
    if (walletPaymentProviderLabels.containsKey(stored)) return stored!;
    return walletPaymentProviderLabels.containsKey(named) ? named! : 'account';
  }
  final named = paymentNetworkFromText(
    '${source.displayIdentity ?? ''} ${source.name} ${source.issuer ?? ''}',
  );
  // Older local records may retain a provider's display name instead of its
  // canonical key. Resolve it for presentation without changing stored data.
  final stored = paymentNetworkFromText(source.network);
  if (source.type == PaymentSourceType.card ||
      source.type == PaymentSourceType.debitCard) {
    if (cardPaymentNetworkLabels.containsKey(source.network)) {
      return source.network!;
    }
    if (cardPaymentNetworkLabels.containsKey(stored)) return stored!;
    return cardPaymentNetworkLabels.containsKey(named) ? named! : 'card';
  }
  if (source.type == PaymentSourceType.wallet) {
    if (walletPaymentProviderLabels.containsKey(source.network)) {
      return source.network!;
    }
    if (walletPaymentProviderLabels.containsKey(stored)) return stored!;
    return walletPaymentProviderLabels.containsKey(named) ? named! : 'wallet';
  }
  return named ?? 'other';
}

/// Presents the mark of a selected payment source without changing its data.
Widget? paymentSourceIconForId(
  Iterable<PaymentSource> sources,
  String? selectedId, {
  double size = 24,
}) {
  if (selectedId == null) return null;
  for (final source in sources) {
    if (source.id.value == selectedId) {
      return ButlerlyPaymentSourceIcon(source: source, size: size);
    }
  }
  return null;
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
  Widget build(BuildContext context) {
    // This icon represents the payment *source*, not its card network.
    // For a named institution, prefer its verified mark or an honest bank
    // placeholder; showing Visa/Mastercard here would misidentify the issuer.
    // Card networks remain visible in their own network-specific controls.
    // Wallet and cash sources continue to use their distinct provider marks.
    if (source.type != PaymentSourceType.wallet &&
        source.type != PaymentSourceType.cash) {
      final issuer =
          issuerForName(source.issuer) ??
          (source.type == PaymentSourceType.account
              ? issuerForName(source.name)
              : null);
      if (issuer != null) {
        return ButlerlyIssuerIcon(issuer: issuer, size: size);
      }
      final customIssuer = source.issuer?.trim();
      if (customIssuer != null && customIssuer.isNotEmpty) {
        return Icon(
          Icons.account_balance_outlined,
          size: size,
          color: Theme.of(context).colorScheme.onSurface,
          semanticLabel: customIssuer,
        );
      }
    }
    return ButlerlyPaymentMarkIcon(mark: paymentMarkFor(source), size: size);
  }
}

/// Displays bundled institution artwork, with a neutral fallback for any
/// institution whose correct logo has not yet been verified.
class ButlerlyIssuerIcon extends StatelessWidget {
  const ButlerlyIssuerIcon({required this.issuer, this.size = 24, super.key});

  final IssuerInstitution issuer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = issuer.assetPath;
    if (path == null) {
      return Icon(
        Icons.account_balance_outlined,
        size: size,
        color: Theme.of(context).colorScheme.onSurface,
        semanticLabel: issuer.name,
      );
    }
    return Semantics(
      label: issuer.name,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: SvgPicture.asset(path, fit: BoxFit.contain),
      ),
    );
  }
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
