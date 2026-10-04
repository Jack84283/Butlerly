import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String analysisPeriodDescription(
  BuildContext context,
  String period,
  AnalysisPeriod? value,
) {
  final label = context.l10n.text(switch (period) {
    'current_month' => 'thisMonth',
    'previous_month' => 'lastMonth',
    'year_to_date' => 'yearToDate',
    'rolling_30_days' => 'last30Days',
    'rolling_90_days' => 'last90Days',
    _ => 'custom',
  });
  return value == null
      ? label
      : '$label · ${localizedPeriodRange(context, startDate: value.startDate, endDate: value.endDate)}';
}

String analysisMoney(BuildContext context, AnalysisMetric metric) =>
    '${localizedDecimal(context, metric.value.toString())} ${metric.currency?.value ?? ''}'
        .trim();

String analysisValueMoney(BuildContext context, AnalysisValue value) =>
    '${localizedDecimal(context, value.value.toString())} ${value.currency?.value ?? ''}'
        .trim();

String analysisPercentageRatio(BuildContext context, DecimalValue ratio) =>
    '${localizedDecimal(context, ratio.multiply(DecimalValue.parse('100')).toString())}%';

String analysisMoneyValue(BuildContext context, Money money) =>
    '${localizedDecimal(context, money.amount.toString())} ${money.currency.value}';

String analysisComparisonText(
  BuildContext context,
  AnalysisComparison comparison,
) {
  final change = comparison.percentageChange;
  if (!isUsableComparison(comparison) || change == null) return '';
  final direction = change.isNegative ? '↓' : '↑';
  final magnitude = change.toString().replaceFirst('-', '');
  return '$direction ${localizedDecimal(context, magnitude)}% ${context.l10n.text('vsPreviousPeriod')}';
}

String analysisComparisonChangeText(
  BuildContext context,
  AnalysisComparison comparison,
) {
  final change = comparison.percentageChange;
  if (!isUsableComparison(comparison) || change == null) return '';
  final direction = change.isNegative ? '↓' : '↑';
  final magnitude = change.toString().replaceFirst('-', '');
  return '$direction ${localizedDecimal(context, magnitude)}%';
}

String analysisAbsoluteChange(
  BuildContext context,
  AnalysisComparison comparison,
  CurrencyCode? currency,
) {
  final change = comparison.absoluteChange;
  if (!isUsableComparison(comparison) || change == null) return '';
  final sign = change.isNegative ? '−' : '+';
  return '$sign${localizedDecimal(context, change.abs().toString())} ${currency?.value ?? ''}'
      .trim();
}

String analysisDimension(
  BuildContext context,
  AnalysisMetric metric,
  TransactionMasterData? masterData,
) {
  final raw = analysisRawDimension(metric);
  if (metric.rule.grouping == RuleGrouping.category) {
    return masterData?.categoryName(raw) ??
        context.l10n.text('unavailableCategory');
  }
  return raw;
}

String analysisDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String analysisPeriodLabel(BuildContext context, AnalysisMetric metric) {
  final raw = analysisPeriodKey(metric);
  final date = DateTime.tryParse('$raw-01');
  if (date == null) return raw;
  return DateFormat.MMM(
    Localizations.localeOf(context).toString(),
  ).format(date);
}
