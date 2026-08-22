import '../value_objects/currency_code.dart';

final class UserPreference {
  const UserPreference({
    required this.locale,
    required this.baseCurrency,
    required this.timeZoneId,
    this.externalAiEnabled = false,
    this.firstUseCompleted = false,
    this.appearance = 'system',
    this.colorTheme = 'butlerRed',
  });

  final String locale;
  final CurrencyCode baseCurrency;
  final String timeZoneId;
  final bool externalAiEnabled;
  final bool firstUseCompleted;
  final String appearance;
  final String colorTheme;
}
