import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/theme/butlerly_responsive_design_tokens.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// The inset and inner content padding use one responsive design token source,
/// independent of which page owns the surrounding outer card.
class ButlerlyInsetTransactionCard extends StatelessWidget {
  const ButlerlyInsetTransactionCard({
    required this.child,
    this.innerCardKey,
    this.topInset = 0,
    this.bottomInset = 0,
    super.key,
  });

  final Widget child;
  final Key? innerCardKey;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final gutter = context.designTokens.geometry.innerCardGutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, topInset, gutter, bottomInset),
      child: ButlerlyTransactionInnerCard(key: innerCardKey, child: child),
    );
  }
}

/// Shared inset transaction-list surface used within a parent dashboard card.
///
/// When nested within an outer card, prefer [ButlerlyInsetTransactionCard]
/// so page-specific layout cannot silently change its horizontal gutter.
class ButlerlyTransactionInnerCard extends StatelessWidget {
  const ButlerlyTransactionInnerCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    color: context.colors.subtleSurface,
    padding: EdgeInsets.all(context.designTokens.geometry.innerCardPadding),
    child: child,
  );
}

/// The desktop Home inner-card surface, reused by desktop Search results.
///
/// Padding, rounding and surface color are shared to avoid visual drift.
class ButlerlyDesktopInnerCard extends StatelessWidget {
  const ButlerlyDesktopInnerCard({required this.child, super.key});

  static const double outerGutter = 10;
  static const double cornerRadius = 8;
  static const double contentPadding = ButlerlySpacing.small;

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(cornerRadius),
    child: ColoredBox(
      color: context.colors.subtleSurface,
      child: Padding(
        padding: const EdgeInsets.all(contentPadding),
        child: child,
      ),
    ),
  );
}
