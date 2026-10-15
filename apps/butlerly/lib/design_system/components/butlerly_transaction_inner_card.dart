import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Shared inset transaction-list surface used within a parent dashboard card.
///
/// Matches the inner card in Home's Recent Transactions section. Callers own
/// the surrounding spacing and the transaction rows or grouped list content.
class ButlerlyTransactionInnerCard extends StatelessWidget {
  const ButlerlyTransactionInnerCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    color: context.colors.subtleSurface,
    padding: const EdgeInsets.all(ButlerlySpacing.micro),
    child: child,
  );
}
