import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisSummary extends StatelessWidget {
  const AnalysisSummary({super.key, required this.model});
  final AnalysisModel model;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: context.l10n.text('analysisSummary'),
    child: ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.spending == null
                ? context.l10n.text('noSpendingInPeriod')
                : analysisMoney(context, model.spending!),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          Text(context.l10n.text('totalSpending')),
          if (model.comparison != null)
            Text(
              analysisComparisonText(context, model.comparison!),
              semanticsLabel: analysisComparisonText(
                context,
                model.comparison!,
              ),
            ),
          const SizedBox(height: ButlerlySpacing.standard),
          Row(
            children: [
              Expanded(
                child: _SupportingMetric(
                  metric: model.income,
                  label: context.l10n.text('income'),
                ),
              ),
              Expanded(
                child: _SupportingMetric(
                  metric: model.net,
                  label: context.l10n.text('netCashFlow'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SupportingMetric extends StatelessWidget {
  const _SupportingMetric({required this.metric, required this.label});
  final AnalysisMetric? metric;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$label, ${metric == null ? context.l10n.text('notAvailable') : analysisMoney(context, metric!)}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          metric == null ? '—' : analysisMoney(context, metric!),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    ),
  );
}
