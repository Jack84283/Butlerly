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

    final sections = [
      (
        title: context.l10n.text('toolsActNow'),
        routes: const ['/review', '/payment-settlements'],
      ),
      (
        title: context.l10n.text('toolsUnderstand'),
        routes: const ['/analysis', '/insights'],
      ),
      (
        title: context.l10n.text('toolsMaintain'),
        routes: const ['/master-data', '/rules'],
      ),
    ];

    return ButlerlyPage(
      title: context.l10n.text('tools'),
      subtitle: context.l10n.text('toolsSubtitle'),
      fullWidth: desktop,
      padding: const EdgeInsets.fromLTRB(
        ButlerlySize.contentGutter,
        ButlerlySpacing.cardGap,
        ButlerlySize.contentGutter,
        ButlerlySpacing.large,
      ),
      children: [
        if (desktop)
          Row(
            key: const ValueKey('desktop-tools-three-columns'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, section) in sections.indexed) ...[
                if (index > 0) const SizedBox(width: ButlerlySpacing.cardGap),
                Expanded(
                  child: Column(
                    key: ValueKey(
                      index == 0
                          ? 'desktop-tools-actions'
                          : 'desktop-tools-actions-$index',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: ButlerlySpacing.small,
                        ),
                        child: Text(
                          section.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final tool in tools.where(
                        (item) => section.routes.contains(item.route),
                      )) ...[
                        _ToolPanel(tool: tool),
                        const SizedBox(height: ButlerlySpacing.cardGap),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          )
        else
          for (final (index, section) in sections.indexed) ...[
            Padding(
              padding: EdgeInsets.only(
                top: index == 0
                    ? ButlerlySpacing.none
                    : ButlerlySpacing.cardGap,
                bottom: ButlerlySpacing.small,
              ),
              child: Text(
                section.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ButlerlyActionGroup(
              actions: [
                for (final tool in tools.where(
                  (item) => section.routes.contains(item.route),
                ))
                  ButlerlyActionItem(
                    icon: tool.icon,
                    title: tool.title,
                    subtitle: tool.description,
                    onTap: () => context.push(tool.route),
                  ),
              ],
            ),
          ],
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
