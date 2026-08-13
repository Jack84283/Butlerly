import 'dart:ui';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

final userPreferenceProvider =
    AsyncNotifierProvider<UserPreferenceController, UserPreference>(
      UserPreferenceController.new,
    );

final localeProvider = Provider<Locale?>((ref) {
  final preference = ref.watch(userPreferenceProvider).value;
  return preference == null ? null : Locale(preference.locale);
});

final class UserPreferenceController extends AsyncNotifier<UserPreference> {
  FinanceServices? get _services => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  Future<UserPreference> build() async {
    final financeServices = _services;
    if (financeServices == null) {
      return _defaults(firstUseCompleted: true, timeZoneId: 'UTC');
    }
    final result = await financeServices.loadUserPreference();
    if (result case ApplicationSuccess<UserPreference?>(:final value)) {
      if (value != null) return value;
      final timezone = await FlutterTimezone.getLocalTimezone();
      return _defaults(timeZoneId: timezone.identifier);
    }
    throw StateError('User preferences could not be loaded.');
  }

  Future<bool> saveChanges({
    String? locale,
    String? baseCurrency,
    String? timeZoneId,
    bool? externalAiEnabled,
    bool? firstUseCompleted,
  }) async {
    final current = state.value ?? _defaults(timeZoneId: 'UTC');
    final next = UserPreference(
      locale: locale ?? current.locale,
      baseCurrency: CurrencyCode(baseCurrency ?? current.baseCurrency.value),
      timeZoneId: timeZoneId ?? current.timeZoneId,
      externalAiEnabled: externalAiEnabled ?? current.externalAiEnabled,
      firstUseCompleted: firstUseCompleted ?? current.firstUseCompleted,
    );
    state = AsyncData(next);
    final financeServices = _services;
    if (financeServices == null) return true;
    final result = await financeServices.saveUserPreference(next);
    if (result is ApplicationSuccess<UserPreference>) return true;
    state = AsyncData(current);
    return false;
  }

  UserPreference _defaults({
    required String timeZoneId,
    bool firstUseCompleted = false,
  }) {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final language =
        const {'en', 'es', 'zh'}.contains(deviceLocale.languageCode)
        ? deviceLocale.languageCode
        : 'en';
    final currency = switch (deviceLocale.countryCode) {
      'CN' => 'CNY',
      'GB' => 'GBP',
      'JP' => 'JPY',
      'AT' ||
      'BE' ||
      'DE' ||
      'ES' ||
      'FI' ||
      'FR' ||
      'IE' ||
      'IT' ||
      'NL' ||
      'PT' => 'EUR',
      _ => 'USD',
    };
    return UserPreference(
      locale: language,
      baseCurrency: CurrencyCode(currency),
      timeZoneId: timeZoneId,
      firstUseCompleted: firstUseCompleted,
    );
  }
}
