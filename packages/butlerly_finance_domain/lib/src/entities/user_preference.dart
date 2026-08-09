import '../value_objects/currency_code.dart';

final class UserPreference {
  const UserPreference({
    required this.locale,
    required this.baseCurrency,
    this.externalAiEnabled = false,
  });

  final String locale;
  final CurrencyCode baseCurrency;
  final bool externalAiEnabled;
}
