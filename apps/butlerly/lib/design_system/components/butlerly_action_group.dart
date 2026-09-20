import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Reusable quiet-premium action model for hub-style rows.
class ButlerlyActionItem {
  const ButlerlyActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// Groups related actions on a subtle surface with consistent dividers.
class ButlerlyActionGroup extends StatelessWidget {
  const ButlerlyActionGroup({required this.actions, super.key});

  final List<ButlerlyActionItem> actions;

  static const double _dividerInset = ButlerlySpacing.standard;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.subtleSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      side: BorderSide(color: context.colors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          ButlerlyActionRow(action: actions[index]),
          if (index < actions.length - 1)
            Divider(
              height: 1,
              indent: _dividerInset,
              endIndent: ButlerlySpacing.standard,
              color: context.colors.cardDivider,
            ),
        ],
      ],
    ),
  );
}

/// Standard action row used by Add, Tools, and compatible future hubs.
class ButlerlyActionRow extends StatelessWidget {
  const ButlerlyActionRow({required this.action, super.key});

  final ButlerlyActionItem action;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${action.title}, ${action.subtitle}',
    child: InkWell(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.standard,
          vertical: ButlerlySpacing.small,
        ),
        child: Row(
          children: [
            ButlerlyActionIcon(icon: action.icon),
            const SizedBox(width: ButlerlySpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: ButlerlySpacing.xxs),
                  Text(
                    action.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: ButlerlySpacing.small),
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.tertiaryText,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shared circular icon treatment for quiet-premium action surfaces.
class ButlerlyActionIcon extends StatelessWidget {
  const ButlerlyActionIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: ButlerlySize.preferredTarget,
    height: ButlerlySize.preferredTarget,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.colors.selection,
    ),
    child: Icon(icon, color: context.colors.interactive),
  );
}
