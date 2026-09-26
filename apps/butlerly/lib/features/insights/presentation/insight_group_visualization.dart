import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_presentation.dart';
import 'package:butlerly/features/insights/presentation/insight_visualization.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

export 'package:butlerly/features/insights/presentation/insight_presentation.dart';

class InsightGroupVisualizations extends StatelessWidget {
  const InsightGroupVisualizations({
    super.key,
    required this.results,
    required this.masterData,
    this.embedded = false,
    this.externalTitle = false,
    this.pieDensity = ButlerlyVisualizationDensity.compact,
    this.pieLegendBelow = false,
    this.pieValueLabel,
  });

  final List<InsightResult> results;
  final TransactionMasterData masterData;
  final bool embedded;
  final bool externalTitle;
  final ButlerlyVisualizationDensity pieDensity;
  final bool pieLegendBelow;
  final String Function(InsightResult result)? pieValueLabel;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<InsightResult>>{};
    for (final result in results) {
      final type = result.presentation.visualizationType;
      if (type != InsightVisualizationType.pie &&
          type != InsightVisualizationType.bar &&
          type != InsightVisualizationType.trend) {
        continue;
      }
      grouped.putIfAbsent(result.rule.identity.value, () => []).add(result);
    }

    final widgets = <Widget>[];
    for (final entries in grouped.values) {
      if (entries.length < 2) continue;
      final first = entries.first;
      final type = first.presentation.visualizationType;
      final data = entries
          .where(
            (entry) => entry.currentValue != null && entry.dimension != null,
          )
          .map(
            (entry) => InsightChartDatum(
              label: _dimensionLabel(context, entry),
              value: double.tryParse(entry.currentValue.toString()) ?? 0,
              color: entry.rule.grouping == RuleGrouping.category
                  ? ButlerlyChartColors.category(_rawDimension(entry))
                  : null,
              valueLabel: type == InsightVisualizationType.pie
                  ? pieValueLabel?.call(entry)
                  : null,
            ),
          )
          .toList(growable: false);
      if (data.length < 2) continue;
      if (type == InsightVisualizationType.trend) {
        data.sort((a, b) => a.label.compareTo(b.label));
      }
      final currency = first.currency?.value ?? '';
      final isShare =
          first.presentation.primaryMetric == InsightPrimaryMetric.share;
      String decimal(double value) =>
          localizedDecimal(context, value.toString());
      String percentage(double value) => '${decimal(value)}%';
      String valueLabel(double value) => isShare
          ? percentage(value)
          : '${decimal(value)}${currency.isEmpty ? '' : ' $currency'}';
      final visualization = switch (type) {
        InsightVisualizationType.pie => InsightDonutVisualization(
          data: data,
          percentageLabel: percentage,
          density: pieDensity,
          legendBelow: pieLegendBelow,
        ),
        InsightVisualizationType.bar => InsightBarVisualization(
          data: data,
          valueLabel: valueLabel,
        ),
        InsightVisualizationType.trend => InsightTrendVisualization(
          data: data,
          valueLabel: valueLabel,
        ),
        _ => const SizedBox.shrink(),
      };
      final title = context.l10n.text(first.rule.nameKey);
      final child = externalTitle
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ButlerlySectionHeader(title: title),
                ButlerlyCard(child: visualization),
              ],
            )
          : embedded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: ButlerlySpacing.small),
                visualization,
              ],
            )
          : ButlerlyVisualizationCard(title: title, child: visualization);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
          child: child,
        ),
      );
    }

    return Column(children: widgets);
  }

  String _dimensionLabel(BuildContext context, InsightResult insight) {
    final dimension = _rawDimension(insight);
    return switch (insight.rule.grouping) {
      RuleGrouping.category =>
        masterData.categoryName(dimension) ??
            (dimension == 'uncategorized'
                ? context.l10n.text('uncategorized')
                : context.l10n.text('unavailableCategory')),
      RuleGrouping.subcategory =>
        masterData.subcategoryName(dimension) ??
            (dimension == 'uncategorized'
                ? context.l10n.text('uncategorized')
                : context.l10n.text('unavailableSubcategory')),
      RuleGrouping.merchant =>
        masterData.merchantName(dimension) ??
            context.l10n.text('unavailableMerchant'),
      RuleGrouping.paymentSource =>
        masterData.paymentSourceName(dimension) ??
            context.l10n.text('unavailablePaymentSource'),
      RuleGrouping.tag =>
        masterData.tagName(dimension) ?? context.l10n.text('unavailableTag'),
      _ => dimension,
    };
  }

  String _rawDimension(InsightResult insight) {
    final dimension = insight.dimension!;
    if (insight.finding != null) return dimension;
    final suffix = ':${insight.rule.measure.key}';
    if (dimension.endsWith(suffix) && dimension.length > suffix.length) {
      return dimension.substring(0, dimension.length - suffix.length);
    }
    return dimension;
  }
}
