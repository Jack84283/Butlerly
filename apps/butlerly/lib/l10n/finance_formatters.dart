import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
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

String localizedExactMoney(
  BuildContext context,
  String canonicalValue,
  String currency,
) {
  final value = DecimalValue.parse(canonicalValue);
  final code = currency.trim().toUpperCase();
  final locale = _currencyLocale(context);
  final decimalFormatter = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: value.scale,
  );
  final exactDecimal = _localizedExactDecimal(value.toString(), locale);
  final currencyFormatter = NumberFormat.simpleCurrency(
    locale: locale,
    name: code,
    decimalDigits: value.scale,
  );
  final currencySymbol = currencyFormatter.currencySymbol.trim();
  final probe = decimalFormatter.format(1);
  final currencyProbe = currencyFormatter.format(1);
  if (currencySymbol.isEmpty ||
      currencySymbol.toUpperCase() == code ||
      !currencyProbe.contains(probe)) {
    return '$exactDecimal $code';
  }
  return currencyProbe.replaceFirst(probe, exactDecimal);
}

String localizedExactDecimal(BuildContext context, String canonicalValue) {
  if (canonicalValue.trim().isEmpty) return '';
  final value = DecimalValue.parse(canonicalValue);
  return _localizedExactDecimal(value.toString(), _currencyLocale(context));
}

String? parseLocalizedDecimal(String raw, {required String locale}) {
  final symbols = NumberFormat.decimalPattern(_numberLocale(locale)).symbols;
  var input = raw.trim();
  if (input.isEmpty) return '';
  if (symbols.GROUP_SEP.trim().isEmpty) {
    input = input.replaceAll(RegExp(r'\s'), symbols.GROUP_SEP);
  } else if (RegExp(r'\s').hasMatch(input)) {
    return null;
  }

  final decimalParts = input.split(symbols.DECIMAL_SEP);
  if (decimalParts.length > 2) return null;
  final integerPart = decimalParts.first;
  final fractionPart = decimalParts.length == 2 ? decimalParts[1] : null;
  if (fractionPart != null &&
      (fractionPart.isEmpty || !_asciiDigits.hasMatch(fractionPart))) {
    return null;
  }

  final integerGroups = integerPart.split(symbols.GROUP_SEP);
  if (integerGroups.any((group) => group.isEmpty)) return null;
  if (integerGroups.length > 1 &&
      (integerGroups.first.length > 3 ||
          integerGroups.skip(1).any((group) => group.length != 3))) {
    return null;
  }
  if (integerGroups.any((group) => !_asciiDigits.hasMatch(group))) {
    return null;
  }
  final canonical =
      integerGroups.join() + (fractionPart == null ? '' : '.$fractionPart');
  try {
    return DecimalValue.parse(canonical).toString();
  } on DomainValidationException {
    return null;
  }
}

final _asciiDigits = RegExp(r'^\d+$');

String _localizedExactDecimal(String canonicalValue, String locale) {
  final negative = canonicalValue.startsWith('-');
  final unsigned = negative ? canonicalValue.substring(1) : canonicalValue;
  final parts = unsigned.split('.');
  final integer = parts.first;
  final grouped = StringBuffer();
  final firstGroupLength = integer.length % 3 == 0 ? 3 : integer.length % 3;
  grouped.write(integer.substring(0, firstGroupLength));
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  for (var index = firstGroupLength; index < integer.length; index += 3) {
    grouped.write(symbols.GROUP_SEP);
    grouped.write(integer.substring(index, index + 3));
  }
  if (parts.length == 2) {
    grouped.write(symbols.DECIMAL_SEP);
    grouped.write(parts[1]);
  }
  return '${negative ? '-' : ''}$grouped';
}

String _numberLocale(String locale) {
  final normalized = locale.replaceAll('-', '_');
  if (normalized.contains('_')) return normalized;
  return switch (normalized) {
    'zh' => 'zh_CN',
    'es' => 'es_ES',
    _ => 'en_US',
  };
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
