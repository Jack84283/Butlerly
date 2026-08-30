import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

String paymentSourceDisplayName(PaymentSource source) {
  final name = source.displayIdentity ?? source.name;
  return source.lastFour == null ? name : '$name ••••${source.lastFour}';
}

String statementDisplayTitle(
  BuildContext context,
  FinancialStatement statement,
  Iterable<PaymentSource> sources,
) {
  return statementDisplayTitleForLocale(
    statement,
    sources,
    locale: Localizations.localeOf(context).languageCode,
    fallback: context.l10n.text('statement'),
  );
}

String statementDisplayTitleForLocale(
  FinancialStatement statement,
  Iterable<PaymentSource> sources, {
  required String locale,
  required String fallback,
}) {
  final source = sources
      .where((value) => value.id.value == statement.paymentSourceId)
      .firstOrNull;
  final sourceName = source == null
      ? statement.institution ?? fallback
      : paymentSourceDisplayName(source);
  final date =
      statement.statementDate ?? statement.periodEnd ?? statement.createdAt;
  return '$sourceName · ${DateFormat.yMMMd(locale).format(date)}';
}
