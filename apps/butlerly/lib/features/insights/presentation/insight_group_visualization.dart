import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_presentation.dart';
import 'package:butlerly/features/insights/presentation/insight_visualization.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class InsightGroupVisualizations extends StatelessWidget {
  const InsightGroupVisualizations({
    super.key,
    required this.results,
    required this.masterData,
  });

  final List<InsightResult> results;
  final TransactionMasterData masterData;

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
          .where((entry) => entry.currentValue != null && entry.dimension != null)
          .map(
            (entry) => InsightChartDatum(
              label: _dimensionLabel(context, entry),
              value: double.tryParse(entry.currentValue.toString()) ?? 0,
            ),
          )
          .toList(growable: false);
      if (data.length < 2) continue;
      if (type == InsightVisualizationType.trend) {
        data.sort((a, b) => a.label.compareTo(b.label));
      }
      final currency = first.currency?.value ?? '';
      final isShare = first.presentation.primaryMetric == InsightPrimaryMetric.share;
      String valueLabel(double value) => isShare
          ? '${value.toStringAsFixed(1)}%'
          : '${value.toStringAsFixed(2)}${currency.isEmpty ? '' : ' $currency'}';
      final visualization = switch (type) {
        InsightVisualizationType.pie => InsightDonutVisualization(data: data),
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
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
          child: ButlerlyVisualizationCard(
            title: context.l10n.text(first.rule.nameKey),
            child: visualization,
          ),
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
