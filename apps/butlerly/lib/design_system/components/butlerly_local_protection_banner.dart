import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Local protection status shown on the desktop More and Privacy pages.
class ButlerlyLocalProtectionBanner extends StatelessWidget {
  const ButlerlyLocalProtectionBanner({
    required this.title,
    required this.description,
    this.surfaceKey,
    this.dense = false,
    super.key,
  });

  final String title;
  final String description;
  final Key? surfaceKey;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ButlerlyProtectionColors.of(theme.brightness);
    return Container(
      key: surfaceKey,
      padding: EdgeInsets.symmetric(
        horizontal: ButlerlySpacing.standard,
        vertical: dense ? ButlerlySpacing.small : ButlerlySpacing.standard,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(
          dense ? ButlerlyRadius.standard : ButlerlyRadius.card,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: palette.iconSurface,
            child: Icon(
              Icons.shield_outlined,
              color: context.colors.success,
              size: dense ? 23 : null,
            ),
          ),
          const SizedBox(width: ButlerlySpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ButlerlySpacing.standard),
          Icon(
            Icons.check_circle_rounded,
            color: context.colors.success,
            size: dense ? 25 : null,
          ),
        ],
      ),
    );
  }
}
