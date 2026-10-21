import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_breakdown_leading_icon.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisMerchantBreakdown extends StatelessWidget {
  const AnalysisMerchantBreakdown({
    super.key,
    required this.model,
    required this.masterData,
    this.onMetricTap,
    this.desktopFourRows = false,
  });

  final AnalysisModel model;
  final TransactionMasterData? masterData;
  final ValueChanged<AnalysisMetric>? onMetricTap;
  final bool desktopFourRows;

  @override
  Widget build(BuildContext context) {
    if (model.merchants.isEmpty && !desktopFourRows) {
      return const SizedBox.shrink();
    }
    final visibleRows = desktopFourRows ? 4 : 5;
    return ButlerlyCard(
      key: const ValueKey('analysis-merchant-breakdown-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(
            title: context.l10n.text('spendingByMerchant'),
            subtitle: context.l10n.text('analysisMerchantBreakdownSubtitle'),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          if (model.merchants.isEmpty)
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.l10n.text('noSpendingInPeriod')),
              ),
            ),
          for (final metric in model.merchants.take(visibleRows)) ...[
            if (metric != model.merchants.first)
              const SizedBox(height: ButlerlySpacing.compact),
            InkWell(
              key: ValueKey('analysis-merchant-metric-${metric.id}'),
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
          if (desktopFourRows)
            for (
              var index = model.merchants.isEmpty
                  ? 1
                  : model.merchants.take(4).length;
              index < 4;
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
