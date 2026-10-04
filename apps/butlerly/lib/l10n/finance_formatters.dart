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
