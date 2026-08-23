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

final formattingLocaleProvider = Provider<String?>((ref) {
  final preference = ref.watch(userPreferenceProvider).value;
  return preference?.formattingLocale;
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
      if (value != null) {
        final canonical = canonicalTimeZoneId(
          value.timeZoneId,
          countryCode: PlatformDispatcher.instance.locale.countryCode,
        );
        if (canonical == value.timeZoneId) return value;
        final migrated = UserPreference(
          locale: value.locale,
          formattingLocale: value.formattingLocale,
          regionCode: value.regionCode,
          baseCurrency: value.baseCurrency,
          timeZoneId: canonical,
          externalAiEnabled: value.externalAiEnabled,
          firstUseCompleted: value.firstUseCompleted,
          appearance: value.appearance,
          colorTheme: value.colorTheme,
        );
        await financeServices.saveUserPreference(migrated);
        return migrated;
      }
      final timezone = await FlutterTimezone.getLocalTimezone();
      return _defaults(
        timeZoneId: canonicalTimeZoneId(
          timezone.identifier,
          countryCode: PlatformDispatcher.instance.locale.countryCode,
        ),
      );
    }
    throw StateError('User preferences could not be loaded.');
  }

  Future<bool> saveChanges({
    String? locale,
    String? formattingLocale,
    String? regionCode,
    String? baseCurrency,
    String? timeZoneId,
    bool? externalAiEnabled,
    bool? firstUseCompleted,
    String? appearance,
    String? colorTheme,
  }) async {
    final current = state.value ?? _defaults(timeZoneId: 'UTC');
    final next = UserPreference(
      locale: locale ?? current.locale,
      formattingLocale: formattingLocale ?? current.formattingLocale,
      regionCode: regionCode ?? current.regionCode,
      baseCurrency: CurrencyCode(baseCurrency ?? current.baseCurrency.value),
      timeZoneId: timeZoneId ?? current.timeZoneId,
      externalAiEnabled: externalAiEnabled ?? current.externalAiEnabled,
      firstUseCompleted: firstUseCompleted ?? current.firstUseCompleted,
      appearance: appearance ?? current.appearance,
      colorTheme: colorTheme ?? current.colorTheme,
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
      formattingLocale: deviceLocale.toLanguageTag(),
      regionCode: deviceLocale.countryCode,
      baseCurrency: CurrencyCode(currency),
      timeZoneId: timeZoneId,
      firstUseCompleted: firstUseCompleted,
    );
  }
}

String canonicalTimeZoneId(String candidate, {String? countryCode}) {
  final value = candidate.trim();
  if (value == 'UTC' || value == 'Etc/UTC' || value.contains('/')) {
    return value;
  }
  return switch ((countryCode, value.toUpperCase())) {
    ('US', 'PST') || ('US', 'PDT') => 'America/Los_Angeles',
    ('US', 'MST') || ('US', 'MDT') => 'America/Denver',
    ('US', 'CST') || ('US', 'CDT') => 'America/Chicago',
    ('US', 'EST') || ('US', 'EDT') => 'America/New_York',
    ('CN', 'CST') => 'Asia/Shanghai',
    ('JP', 'JST') => 'Asia/Tokyo',
    ('GB', 'GMT') || ('GB', 'BST') => 'Europe/London',
    (_, 'GMT') || (_, 'UTC') => 'UTC',
    _ => 'UTC',
  };
}
