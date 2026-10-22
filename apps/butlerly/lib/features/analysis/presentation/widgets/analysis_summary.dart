import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisSummary extends StatelessWidget {
  const AnalysisSummary({
    super.key,
    required this.model,
    this.compactDesktop = false,
  });

  final AnalysisModel model;
  final bool compactDesktop;

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
                : analysisMetricMoney(context, model.spending!),
            style: _isCompact(context)
                ? Theme.of(context).textTheme.headlineMedium
                : Theme.of(context).textTheme.displaySmall,
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
          SizedBox(
            height: _isCompact(context)
                ? ButlerlySpacing.micro
                : ButlerlySpacing.standard,
          ),
          Row(
            children: [
              Expanded(
                child: _SupportingMetric(
                  metric: model.income,
                  label: context.l10n.text('income'),
                  compact: _isCompact(context),
                ),
              ),
              Expanded(
                child: _SupportingMetric(
                  metric: model.net,
                  label: context.l10n.text('netCashFlow'),
                  compact: _isCompact(context),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  bool _isCompact(BuildContext context) =>
      compactDesktop && MediaQuery.textScalerOf(context).scale(1) <= 1.3;
}

class _SupportingMetric extends StatelessWidget {
  const _SupportingMetric({
    required this.metric,
    required this.label,
    required this.compact,
  });
  final AnalysisMetric? metric;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$label, ${metric == null ? context.l10n.text('notAvailable') : analysisMetricMoney(context, metric!)}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          metric == null ? '—' : analysisMetricMoney(context, metric!),
          style: compact
              ? Theme.of(context).textTheme.titleMedium
              : Theme.of(context).textTheme.titleLarge,
        ),
      ],
    ),
  );
}
