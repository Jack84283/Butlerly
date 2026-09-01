import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:flutter/material.dart';

class AnalysisDataQuality extends StatelessWidget {
  const AnalysisDataQuality({super.key, required this.model});
  final AnalysisModel model;

  @override
  Widget build(BuildContext context) {
    final count = model.qualityCount;
    final notEvaluated = !model.qualityEvaluated;
    final limited = model.qualityLimited;
    final needsAttention = count > 0 && !limited && !notEvaluated;
    final status = notEvaluated
        ? context.l10n.text('dataQualityNotEvaluated')
        : limited
        ? context.l10n.text('dataQualityLimited')
        : needsAttention
        ? context.l10n.text('dataQualityNeedsAttention', {
            'count': localizedCount(context, count.toString()),
          })
        : context.l10n.text('dataQualityGood');
    final (icon, color) = notEvaluated
        ? (Icons.help_outline, context.colors.info)
        : limited
        ? (Icons.info_outline, context.colors.warning)
        : needsAttention
        ? (Icons.warning_amber_outlined, context.colors.warning)
        : (Icons.check_circle_outline, context.colors.success);
    return ButlerlyCard(
      semanticLabel: '${context.l10n.text('dataQuality')}: $status',
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: ButlerlySpacing.small),
          Expanded(child: Text(status)),
        ],
      ),
    );
  }
}
