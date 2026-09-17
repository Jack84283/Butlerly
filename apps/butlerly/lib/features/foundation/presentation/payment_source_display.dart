import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Canonical display label for a payment source.
///
/// Card digits are never invented. When a valid stored last-four value exists,
/// it is shown consistently everywhere the payment source is presented.
String paymentSourceDisplayLabel(PaymentSource source) {
  final identity = (source.displayIdentity ?? source.name).trim();
  final lastFour = source.lastFour;
  return lastFour == null ? identity : '$identity •••• $lastFour';
}

/// Credit cards must have four stored digits before they can be saved from UI.
bool paymentSourceRequiresLastFour(PaymentSourceType type) =>
    type == PaymentSourceType.card;
