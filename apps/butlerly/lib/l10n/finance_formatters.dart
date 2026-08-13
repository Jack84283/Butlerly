import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

String localizedDecimal(BuildContext context, String canonicalValue) {
  final value = num.tryParse(canonicalValue);
  if (value == null) return canonicalValue;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final fraction = canonicalValue.contains('.')
      ? canonicalValue.length - canonicalValue.indexOf('.') - 1
      : 0;
  return NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: fraction,
  ).format(value);
}
