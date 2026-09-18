import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:flutter/material.dart';

class AnalysisTrend extends StatelessWidget {
  const AnalysisTrend({
    super.key,
    required this.model,
    required this.masterData,
  });

  final AnalysisModel model;
  final TransactionMasterData? masterData;

  @override
  Widget build(BuildContext context) {
    if (model.trend.isEmpty) {
      return ButlerlyCard(
        child: Text(context.l10n.text('insufficientTrendData')),
      );
    }

    return ButlerlyVisualizationCard(
      title: context.l10n.text('spendingTrend'),
      semanticLabel: context.l10n.text('spendingTrend'),
      child: ButlerlyTrendVisualization(
        density: ButlerlyVisualizationDensity.regular,
        showLabels: true,
        lineColor: context.colors.interactive,
        data: [
          for (final metric in model.trend)
            ButlerlyChartDatum(
              label: analysisPeriodLabel(context, metric),
              value: analysisNumber(metric),
              valueLabel: analysisMoney(context, metric),
            ),
        ],
        valueLabel: (value) => localizedDecimal(context, value.toString()),
      ),
    );
  }
}
