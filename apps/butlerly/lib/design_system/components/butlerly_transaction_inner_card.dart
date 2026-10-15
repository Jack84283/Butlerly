import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_responsive_design_tokens.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// The inset and inner content padding use one responsive design token source,
/// independent of which page owns the surrounding outer card.
class ButlerlyInsetTransactionCard extends StatelessWidget {
  const ButlerlyInsetTransactionCard({
    required this.child,
    this.topInset = 0,
    this.bottomInset = 0,
    super.key,
  });

  final Widget child;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final gutter = context.designTokens.geometry.innerCardGutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, topInset, gutter, bottomInset),
      child: ButlerlyTransactionInnerCard(child: child),
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
