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
  });

  final AnalysisModel model;
  final TransactionMasterData? masterData;
  final ValueChanged<AnalysisMetric>? onCategoryTap;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    if (model.categories.isEmpty) {
      return ButlerlyCard(child: Text(context.l10n.text('noSpendingInPeriod')));
    }

    final max = model.categories
        .map(analysisNumber)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final chartValues = model.categories.take(5).toList(growable: false);
    final remainingValue = model.categories
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
    final colorsByCategory = ButlerlyChartColors.forCategories(
      chartSlices.map((slice) => slice.categoryId),
    );

    return ButlerlyVisualizationCard(
      title: context.l10n.text('spendingDistribution'),
      child: Column(
        children: [
          ButlerlyDonutVisualization(
            density: ButlerlyVisualizationDensity.regular,
            data: [
              for (final slice in chartSlices)
                ButlerlyChartDatum(
                  label: slice.label,
                  value: slice.value,
                  color: colorsByCategory[slice.categoryId],
                ),
            ],
            valueLabel: (value, _) =>
                '${localizedDecimal(context, value.toString())} ${chartSlices.first.currency ?? ''}'
                    .trim(),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          for (final metric in model.categories.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
              child: Semantics(
                label:
                    '${analysisDimension(context, metric, masterData)}, ${analysisMoney(context, metric)}',
                button: onCategoryTap != null,
                child: InkWell(
                  onTap: onCategoryTap == null
                      ? null
                      : () => onCategoryTap!(metric),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              analysisDimension(context, metric, masterData),
                            ),
                          ),
                          Text(analysisMoney(context, metric)),
                        ],
                      ),
                      const SizedBox(height: ButlerlySpacing.micro),
                      LinearProgressIndicator(
                        value: max == 0 ? 0 : analysisNumber(metric) / max,
                      ),
                    ],
                  ),
                ),
              ),
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
