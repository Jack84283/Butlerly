import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_breakdown_leading_icon.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisSubcategoryBreakdown extends StatelessWidget {
  const AnalysisSubcategoryBreakdown({
    super.key,
    required this.model,
    required this.masterData,
    this.onMetricTap,
    this.fillToFiveRows = false,
  });

  final AnalysisModel model;
  final TransactionMasterData? masterData;
  final ValueChanged<AnalysisMetric>? onMetricTap;
  final bool fillToFiveRows;

  @override
  Widget build(BuildContext context) {
    if (model.subcategories.isEmpty) return const SizedBox.shrink();
    return ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(
            title: context.l10n.text('spendingBySubcategory'),
            subtitle: context.l10n.text('analysisSubcategoryBreakdownSubtitle'),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          for (final metric in model.subcategories.take(5)) ...[
            if (metric != model.subcategories.first)
              const SizedBox(height: ButlerlySpacing.compact),
            InkWell(
              key: ValueKey('analysis-subcategory-metric-${metric.id}'),
              onTap: onMetricTap != null && _canDrillThrough(metric)
                  ? () => onMetricTap!(metric)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      AnalysisBreakdownLeadingIcon(
                        metric: metric,
                        masterData: masterData,
                      ),
                      const SizedBox(width: ButlerlySpacing.compact),
                      Expanded(
                        child: Text(
                          analysisDimension(context, metric, masterData),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: ButlerlySpacing.compact),
                      Text(analysisMetricMoney(context, metric)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (fillToFiveRows)
            for (
              var index = model.subcategories.length;
              index < 5;
              index++
            ) ...[
              const SizedBox(height: ButlerlySpacing.compact),
              const SizedBox(height: 44),
            ],
        ],
      ),
    );
  }

  bool _canDrillThrough(AnalysisMetric metric) =>
      metric.availability == AnalysisDataAvailability.sufficient;
}
