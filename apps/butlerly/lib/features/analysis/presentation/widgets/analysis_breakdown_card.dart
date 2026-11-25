import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_breakdown_leading_icon.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

/// Shared presentation for the three Analysis dimension breakdowns.
class AnalysisBreakdownCard extends StatelessWidget {
  const AnalysisBreakdownCard({
    required this.metrics,
    required this.masterData,
    required this.dimension,
    required this.title,
    required this.subtitle,
    required this.desktopFourRows,
    this.onMetricTap,
    super.key,
  });

  final List<AnalysisMetric> metrics;
  final TransactionMasterData? masterData;
  final String dimension;
  final String title;
  final String subtitle;
  final bool desktopFourRows;
  final ValueChanged<AnalysisMetric>? onMetricTap;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty && !desktopFourRows) {
      return const SizedBox.shrink();
    }
    final visibleRows = desktopFourRows ? 4 : 5;
    return ButlerlyCard(
      key: ValueKey('analysis-$dimension-breakdown-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(title: title, subtitle: subtitle),
          const SizedBox(height: ButlerlySpacing.small),
          if (metrics.isEmpty)
            SizedBox(
              height: ButlerlySize.minimumTarget,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.l10n.text('noSpendingInPeriod')),
              ),
            ),
          for (final metric in metrics.take(visibleRows)) ...[
            if (metric != metrics.first)
              const SizedBox(height: ButlerlySpacing.compact),
            InkWell(
              key: ValueKey('analysis-$dimension-metric-${metric.id}'),
              onTap: onMetricTap != null && _canDrillThrough(metric)
                  ? () => onMetricTap!(metric)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ButlerlySize.minimumTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: ButlerlySpacing.xxs,
                  ),
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
          if (desktopFourRows)
            for (
              var index = metrics.isEmpty ? 1 : metrics.take(4).length;
              index < 4;
              index++
            ) ...[
              const SizedBox(height: ButlerlySpacing.compact),
              const SizedBox(height: ButlerlySize.minimumTarget),
            ],
        ],
      ),
    );
  }

  bool _canDrillThrough(AnalysisMetric metric) =>
      metric.availability == AnalysisDataAvailability.sufficient;
}
