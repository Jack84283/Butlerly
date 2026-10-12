import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_category_icon.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

/// Reuses the canonical category icon for Analysis breakdown rows.
///
/// Subcategories show their parent category's identity. Merchants show their
/// assigned category identity when available. Unmapped/custom categories
/// use a neutral glyph rather than asserting on an unknown built-in ID.
class AnalysisBreakdownLeadingIcon extends StatelessWidget {
  const AnalysisBreakdownLeadingIcon({
    required this.metric,
    required this.masterData,
    super.key,
  });

  final AnalysisMetric metric;
  final TransactionMasterData? masterData;

  @override
  Widget build(BuildContext context) {
    final rawDimension = analysisRawDimension(metric);
    final categoryId = switch (metric.rule.grouping) {
      RuleGrouping.subcategory => _parentCategoryId(rawDimension),
      RuleGrouping.merchant => _parentCategoryId(
        masterData?.merchantCategoryId(rawDimension),
      ),
      _ => null,
    };
    if (categoryId != null &&
        ButlerlyCategoryIdentity.forBuiltInId(categoryId) != null) {
      return ButlerlyCategoryIcon(
        categoryId: categoryId,
        containerSize: ButlerlySize.categoryIconContainer,
        glyphSize: ButlerlySize.categoryIconGlyph,
      );
    }

    final theme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      child: SizedBox.square(
        dimension: ButlerlySize.categoryIconContainer,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              metric.rule.grouping == RuleGrouping.merchant
                  ? Icons.storefront_outlined
                  : Icons.category_outlined,
              size: ButlerlySize.categoryIconGlyph,
              color: theme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  String? _parentCategoryId(String? categoryId) {
    if (categoryId == null) return null;
    final storedParent = masterData?.categoryParentId(categoryId);
    if (storedParent != null) return storedParent;

    // Built-in subcategories may be absent from a partial master-data
    // projection. Use their canonical ID hierarchy rather than their labels.
    if (categoryId.startsWith('category.')) {
      final separator = categoryId.lastIndexOf('.');
      if (separator > 'category.'.length) {
        final candidate = categoryId.substring(0, separator);
        if (ButlerlyCategoryIdentity.forBuiltInId(candidate) != null) {
          return candidate;
        }
      }
    }
    return categoryId;
  }
}
