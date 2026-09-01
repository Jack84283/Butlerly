import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisInsightPreview extends StatelessWidget {
  const AnalysisInsightPreview({
    super.key,
    required this.finding,
    required this.onTap,
  });
  final AnalysisFinding finding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    semanticLabel: context.l10n.text('notable'),
    child: ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.info_outline, color: context.colors.info),
      title: Text(context.l10n.text('notable')),
      subtitle: Text(context.l10n.text(finding.rule.nameKey)),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
