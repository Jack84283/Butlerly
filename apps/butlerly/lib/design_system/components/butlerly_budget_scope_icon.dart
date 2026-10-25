import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Shared themed icon for budget scopes without a built-in category identity.
class ButlerlyBudgetScopeIcon extends StatelessWidget {
  const ButlerlyBudgetScopeIcon({required this.scope, super.key});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glyph = switch (scope) {
      'merchant' => Icons.storefront_outlined,
      'category' || 'subcategory' => Icons.category_outlined,
      _ => Icons.savings_outlined,
    };
    return SizedBox.square(
      dimension: ButlerlySize.categoryIconContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            glyph,
            size: ButlerlySize.categoryIconGlyph,
            color: colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
