import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (financeServices == null) return _defaults();
    final result = await financeServices.loadUserPreference();
    if (result case ApplicationSuccess<UserPreference?>(:final value)) {
      return value ?? _defaults();
    }
    throw StateError('User preferences could not be loaded.');
  }

  Future<bool> saveChanges({
    String? locale,
    String? baseCurrency,
    String? timeZoneId,
    bool? externalAiEnabled,
  }) async {
    final current = state.value ?? _defaults();
    final next = UserPreference(
      locale: locale ?? current.locale,
      baseCurrency: CurrencyCode(baseCurrency ?? current.baseCurrency.value),
      timeZoneId: timeZoneId ?? current.timeZoneId,
      externalAiEnabled: externalAiEnabled ?? current.externalAiEnabled,
    );
    state = AsyncData(next);
    final financeServices = _services;
    if (financeServices == null) return true;
    final result = await financeServices.saveUserPreference(next);
    if (result is ApplicationSuccess<UserPreference>) return true;
    state = AsyncData(current);
    return false;
  }

  UserPreference _defaults() => UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: DateTime.now().timeZoneName,
  );
}
