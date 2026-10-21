import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisSpendingBreakdown extends StatelessWidget {
  const AnalysisSpendingBreakdown({
    super.key,
    required this.model,
    required this.masterData,
    this.onCategoryTap,
    this.onViewAll,
    this.desktopLayout = false,
  });

  final AnalysisModel model;
  final TransactionMasterData? masterData;
  final ValueChanged<AnalysisMetric>? onCategoryTap;
  final VoidCallback? onViewAll;
  final bool desktopLayout;

  @override
  Widget build(BuildContext context) {
    if (model.categories.isEmpty) {
      return ButlerlyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ButlerlyCardHeader(title: context.l10n.text('spending')),
            Text(context.l10n.text('noSpendingInPeriod')),
          ],
        ),
      );
    }

    final availableCategories = model.categories
        .where(
          (metric) =>
              metric.availability == AnalysisDataAvailability.sufficient,
        )
        .toList(growable: false);
    final unavailableCategories = model.categories
        .where(
          (metric) =>
              metric.availability != AnalysisDataAvailability.sufficient,
        )
        .toList(growable: false);
    if (availableCategories.isEmpty) {
      return ButlerlyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ButlerlyCardHeader(title: context.l10n.text('spending')),
            Text(context.l10n.text('notAvailable')),
            _UnavailableCategoryList(
              categories: unavailableCategories,
              masterData: masterData,
            ),
          ],
        ),
      );
    }
    final chartValues = availableCategories.take(5).toList(growable: false);
    final remainingValue = availableCategories
        .skip(chartValues.length)
        .map(analysisNumber)
        .fold<double>(0, (sum, value) => sum + value);
    final chartSlices = [
      for (final metric in chartValues)
        _SpendingSlice(
          categoryId: analysisCategoryId(metric),
          label: analysisDimension(context, metric, masterData),
          value: analysisNumber(metric),
          currency: metric.currency?.value,
        ),
      if (remainingValue > 0)
        _SpendingSlice(
          categoryId: 'other',
          label: context.l10n.text('otherCategories'),
          value: remainingValue,
          currency: chartValues.first.currency?.value,
        ),
    ];
    final chartData = [
      for (final slice in chartSlices)
        ButlerlyChartDatum(
          label: slice.label,
          value: slice.value,
          color: ButlerlyChartColors.category(slice.categoryId),
          valueLabel:
              '${localizedDecimal(context, slice.value.toString())} ${slice.currency ?? ''}'
                  .trim(),
        ),
    ];
    return ButlerlyVisualizationCard(
      title: context.l10n.text('spendingDistribution'),
      child: Column(
        children: [
          ButlerlyDonutVisualization(
            density: ButlerlyVisualizationDensity.regular,
            data: chartData,
            valueLabel: (value, _) =>
                localizedDecimal(context, value.toString()),
            // On desktop the shared donut draws the chart on the left and
            // its localized legend on the right; device mode keeps it below.
            legendBelow: !desktopLayout,
            onDatumTap: onCategoryTap == null
                ? null
                : (datum) {
                    final index = chartData.indexOf(datum);
                    if (index >= 0 &&
                        index < chartValues.length &&
                        _canDrillThrough(chartValues[index])) {
                      onCategoryTap!(chartValues[index]);
                    }
                  },
          ),
          if (unavailableCategories.isNotEmpty)
            _UnavailableCategoryList(
              categories: unavailableCategories,
              masterData: masterData,
            ),
          if (onViewAll != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onViewAll,
                child: Text(context.l10n.text('viewAllCategories')),
              ),
            ),
        ],
      ),
    );
  }

  bool _canDrillThrough(AnalysisMetric metric) =>
      metric.availability == AnalysisDataAvailability.sufficient &&
      metric.evidence.isNotEmpty;
}

class _UnavailableCategoryList extends StatelessWidget {
  const _UnavailableCategoryList({
    required this.categories,
    required this.masterData,
  });

  final List<AnalysisMetric> categories;
  final TransactionMasterData? masterData;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ButlerlySpacing.compact),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text('spendingDistributionPartial'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final metric in categories)
          Padding(
            padding: const EdgeInsets.only(top: ButlerlySpacing.micro),
            child: Row(
              key: ValueKey('analysis-unavailable-category-${metric.id}'),
              children: [
                Expanded(
                  child: Text(
                    analysisDimension(context, metric, masterData),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.compact),
                Text(context.l10n.text('notAvailable')),
              ],
            ),
          ),
      ],
    ),
  );
}

class _SpendingSlice {
  const _SpendingSlice({
    required this.categoryId,
    required this.label,
    required this.value,
    required this.currency,
  });

  final String categoryId;
  final String label;
  final double value;
  final String? currency;
}
