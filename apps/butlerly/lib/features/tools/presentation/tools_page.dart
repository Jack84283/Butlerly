import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/tools/presentation/tools_navigation.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  List<ToolNavigationItem> _tools(BuildContext context) =>
      toolNavigationItems(context);

  @override
  Widget build(BuildContext context) {
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    final tools = _tools(context);

    return ButlerlyPage(
      title: context.l10n.text('tools'),
      subtitle: context.l10n.text('toolsSubtitle'),
      fullWidth: desktop,
      children: [
        if (desktop)
          LayoutBuilder(
            key: const ValueKey('desktop-tools-actions'),
            builder: (context, constraints) {
              const gap = ButlerlySpacing.cardGap;
              final columns = constraints.maxWidth >= 1100 ? 3 : 2;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tool in tools)
                    SizedBox(
                      width: tileWidth,
                      child: _ToolPanel(tool: tool),
                    ),
                ],
              );
            },
          )
        else
          ButlerlyActionGroup(
            actions: [
              for (final tool in tools)
                ButlerlyActionItem(
                  icon: tool.icon,
                  title: tool.title,
                  subtitle: tool.description,
                  onTap: () => context.push(tool.route),
                ),
            ],
          ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.tool});
  final ToolNavigationItem tool;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: () => context.push(tool.route),
    semanticLabel: '${tool.title}, ${tool.description}',
    child: SizedBox(
      height: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ButlerlyActionIcon(icon: tool.icon),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
          const Spacer(),
          Text(
            tool.title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            tool.description,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
