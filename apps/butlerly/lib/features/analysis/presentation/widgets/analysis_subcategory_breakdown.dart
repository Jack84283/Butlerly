import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_breakdown_card.dart';
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
    this.desktopFourRows = false,
  });

  final AnalysisModel model;
  final TransactionMasterData? masterData;
  final ValueChanged<AnalysisMetric>? onMetricTap;
  final bool desktopFourRows;

  @override
  Widget build(BuildContext context) => AnalysisBreakdownCard(
    metrics: model.subcategories,
    masterData: masterData,
    dimension: 'subcategory',
    title: context.l10n.text('spendingBySubcategory'),
    subtitle: context.l10n.text('analysisSubcategoryBreakdownSubtitle'),
    desktopFourRows: desktopFourRows,
    onMetricTap: onMetricTap,
  );
}
