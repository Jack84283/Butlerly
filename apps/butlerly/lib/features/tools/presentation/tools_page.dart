import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static const _showSearchTool = false;

  List<_ToolDefinition> _tools(BuildContext context) => [
    if (_showSearchTool)
      _ToolDefinition(
        Icons.search_rounded,
        context.l10n.text('search'),
        context.l10n.text('toolsSearchDescription'),
        '/search',
      ),
    _ToolDefinition(
      Icons.fact_check_rounded,
      context.l10n.text('review'),
      context.l10n.text('toolsReviewDescription'),
      '/review',
    ),
    _ToolDefinition(
      Icons.analytics_outlined,
      context.l10n.text('analysis'),
      context.l10n.text('toolsAnalysisDescription'),
      '/analysis',
    ),
    _ToolDefinition(
      Icons.lightbulb_outline_rounded,
      context.l10n.text('insights'),
      context.l10n.text('toolsInsightsDescription'),
      '/insights',
    ),
    _ToolDefinition(
      Icons.credit_score_outlined,
      context.l10n.text('paymentSettlements'),
      context.l10n.text('toolsPaymentSettlementsDescription'),
      '/payment-settlements',
    ),
  ];

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('tools'),
    subtitle: context.l10n.text('toolsSubtitle'),
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final tools = _tools(context);
          if (constraints.maxWidth < 640) {
            return ButlerlyActionGroup(
              actions: [
                for (final tool in tools)
                  ButlerlyActionItem(
                    icon: tool.icon,
                    title: tool.title,
                    subtitle: tool.description,
                    onTap: () => context.push(tool.route),
                  ),
              ],
            );
          }
          final cardWidth =
              (constraints.maxWidth - ButlerlySpacing.cardGap) / 2;
          return Wrap(
            spacing: ButlerlySpacing.cardGap,
            runSpacing: ButlerlySpacing.cardGap,
            children: [
              for (final tool in tools)
                SizedBox(
                  width: cardWidth,
                  child: _ToolPanel(tool: tool),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: ButlerlySpacing.structural),
    ],
  );
}

class _ToolDefinition {
  const _ToolDefinition(this.icon, this.title, this.description, this.route);
  final IconData icon;
  final String title;
  final String description;
  final String route;
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.tool});
  final _ToolDefinition tool;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    color: context.colors.subtleSurface,
    onTap: () => context.push(tool.route),
    semanticLabel: '${tool.title}, ${tool.description}',
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ButlerlyActionIcon(icon: tool.icon),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.tertiaryText,
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          Text(tool.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(tool.description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
