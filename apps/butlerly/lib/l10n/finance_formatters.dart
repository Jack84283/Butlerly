import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'app_localizations.dart';

String localizedDecimal(BuildContext context, String canonicalValue) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  final locale = Localizations.localeOf(context).toLanguageTag();
  const fraction = 2;
  return NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: fraction,
  ).format(value);
}

String localizedCompactDecimal(BuildContext context, String canonicalValue) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  final formatter =
      NumberFormat.decimalPattern(
          Localizations.localeOf(context).toLanguageTag(),
        )
        ..minimumFractionDigits = 0
        ..maximumFractionDigits = 2;
  return formatter.format(value);
}

String localizedCompactPercentage(
  BuildContext context,
  String canonicalValue, {
  bool ratio = false,
}) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  final percentage = ratio ? value * 100 : value;
  return '${localizedCompactDecimal(context, percentage.toString())}%';
}

String localizedCompactMoney(
  BuildContext context,
  String canonicalValue,
  String currency,
) {
  final value = num.tryParse(canonicalValue);
  final normalizedCurrency = currency.trim().toUpperCase();
  if (value == null || normalizedCurrency.isEmpty) {
    return localizedTransactionAmount(context, canonicalValue);
  }

  final locale = _currencyLocale(context);
  final formatter = NumberFormat.simpleCurrency(
    locale: locale,
    name: normalizedCurrency,
    decimalDigits: 2,
  );
  final symbol = formatter.currencySymbol.trim();
  final symbolIsReliable =
      symbol.isNotEmpty && symbol.toUpperCase() != normalizedCurrency;
  if (symbolIsReliable) return formatter.format(value);

  return '${localizedTransactionAmount(context, value.toString())} '
      '$normalizedCurrency';
}

String _currencyLocale(BuildContext context) {
  final locale = Localizations.localeOf(context);
  if (locale.countryCode != null) {
    return locale.toLanguageTag().replaceAll('-', '_');
  }
  return switch (locale.languageCode) {
    'zh' => 'zh_CN',
    'es' => 'es_ES',
    _ => 'en_US',
  };
}

String localizedCompactSignedMoney(
  BuildContext context,
  String canonicalValue,
  String currency,
) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  final sign = value < 0 ? '-' : '+';
  return '$sign${localizedCompactMoney(context, value.abs().toString(), currency)}';
}

String localizedTransactionAmount(BuildContext context, String canonicalValue) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  final locale = Localizations.localeOf(context).toLanguageTag();
  return (NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 2
        ..maximumFractionDigits = 2)
      .format(value);
}

String localizedCount(BuildContext context, String canonicalValue) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  return NumberFormat.decimalPattern(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(value);
}

String localizedPeriodRange(
  BuildContext context, {
  required String startDate,
  required String endDate,
}) {
  final start = DateTime.tryParse(startDate);
  final end = DateTime.tryParse(endDate);
  if (start == null || end == null) return context.l10n.text('notAvailable');
  final locale = Localizations.localeOf(context).toLanguageTag();
  final formatter = DateFormat.yMMMd(locale);
  return '${formatter.format(DateTime.utc(start.year, start.month, start.day))}'
      ' – '
      '${formatter.format(DateTime.utc(end.year, end.month, end.day))}';
}
