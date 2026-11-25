import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// A destination tile for the wide Add and Tools action grids.
class ButlerlyDesktopActionCard extends StatelessWidget {
  const ButlerlyDesktopActionCard({required this.action, super.key});

  final ButlerlyActionItem action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ButlerlySemanticButton(
      label: '${action.title}, ${action.subtitle}',
      onPressed: action.onTap,
      child: ButlerlyCard(
        onTap: action.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ButlerlySize.wideActionCardContentMinHeight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ButlerlyActionIcon(icon: action.icon),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded),
                ],
              ),
              const SizedBox(height: ButlerlySpacing.standard),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.title, style: textTheme.titleMedium),
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(action.subtitle, style: textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
