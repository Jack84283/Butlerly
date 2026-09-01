import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
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
    return ButlerlyCard(
      child: Column(
        children: [
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
