import '../value_objects/currency_code.dart';

final class UserPreference {
  const UserPreference({
    required this.locale,
    required this.baseCurrency,
    required this.timeZoneId,
    this.externalAiEnabled = false,
  });

  final String locale;
  final CurrencyCode baseCurrency;
  final String timeZoneId;
  final bool externalAiEnabled;
}
