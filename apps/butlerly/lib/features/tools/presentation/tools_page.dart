import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  List<_ToolDefinition> _tools(BuildContext context) => [
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
      Icons.analytics_rounded,
      context.l10n.text('analysis'),
      context.l10n.text('toolsAnalysisDescription'),
      '/analysis',
    ),
    _ToolDefinition(
      Icons.insights_rounded,
      context.l10n.text('insights'),
      context.l10n.text('toolsInsightsDescription'),
      '/insights',
    ),
  ];

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('tools'),
    subtitle: context.l10n.text('toolsSubtitle'),
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 640 ? 2 : 1;
          final tools = _tools(context);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: ButlerlySpacing.cardGap,
              mainAxisSpacing: ButlerlySpacing.cardGap,
              mainAxisExtent: 144,
            ),
            itemCount: tools.length,
            itemBuilder: (context, index) => _ToolCard(tool: tools[index]),
          );
        },
      ),
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

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});
  final _ToolDefinition tool;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: () => context.push(tool.route),
    semanticLabel: '${tool.title}, ${tool.description}',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(tool.icon, color: context.colors.interactive, size: 28),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tool.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: ButlerlySpacing.compact),
              Expanded(
                child: Text(
                  tool.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}
