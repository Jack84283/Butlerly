import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_category_icon.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_group_visualization.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

enum InsightPresentationGroup {
  unusual,
  category,
  subcategory,
  tag,
  merchant,
  paymentSource,
  other,
}

InsightPresentationGroup insightPresentationGroup(InsightResult insight) =>
    switch (insight.rule.grouping) {
      RuleGrouping.transaction
          when insight.presentation.semanticType == InsightSemanticType.attention =>
        InsightPresentationGroup.unusual,
      RuleGrouping.transaction => InsightPresentationGroup.other,
      RuleGrouping.category => InsightPresentationGroup.category,
      RuleGrouping.subcategory => InsightPresentationGroup.subcategory,
      RuleGrouping.tag => InsightPresentationGroup.tag,
      RuleGrouping.merchant => InsightPresentationGroup.merchant,
      RuleGrouping.paymentSource => InsightPresentationGroup.paymentSource,
      _ => InsightPresentationGroup.other,
    };

bool insightGroupIsPositiveOnly(List<InsightResult> items) =>
    items.isNotEmpty &&
    items.every(
      (item) => item.presentation.semanticType == InsightSemanticType.positive,
    );

class InsightGroupedList extends StatelessWidget {
  const InsightGroupedList({
    super.key,
    required this.results,
    this.visualizationResults = const [],
    required this.masterData,
    required this.canViewTransactions,
    required this.onViewTransactions,
  });

  final List<InsightResult> results;
  final List<InsightResult> visualizationResults;
  final TransactionMasterData masterData;
  final bool Function(InsightResult) canViewTransactions;
  final ValueChanged<InsightResult> onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final grouped = <InsightPresentationGroup, List<InsightResult>>{};
    for (final result in results) {
      if (result.outputType == InsightOutputType.dataQuality) continue;
      grouped.putIfAbsent(insightPresentationGroup(result), () => []).add(result);
    }

    final groupedVisualizations =
        <InsightPresentationGroup, List<InsightResult>>{};
    for (final result in visualizationResults) {
      if (result.outputType == InsightOutputType.dataQuality) continue;
      final type = result.presentation.visualizationType;
      if (type != InsightVisualizationType.bar &&
          type != InsightVisualizationType.trend) {
        continue;
      }
      groupedVisualizations
          .putIfAbsent(insightPresentationGroup(result), () => [])
          .add(result);
    }

    const order = [
      InsightPresentationGroup.unusual,
      InsightPresentationGroup.category,
      InsightPresentationGroup.subcategory,
      InsightPresentationGroup.tag,
      InsightPresentationGroup.merchant,
      InsightPresentationGroup.paymentSource,
      InsightPresentationGroup.other,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in order)
          if (grouped[group] case final items? when items.isNotEmpty) ...[
            ButlerlySectionHeader(title: _groupTitle(context, group, items)),
            if (groupedVisualizations[group] case final chartResults?
                when chartResults.isNotEmpty)
              InsightGroupVisualizations(
                results: chartResults,
                masterData: masterData,
              ),
            ButlerlyCard(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _InsightItem(
                      insight: items[index],
                      masterData: masterData,
                      onViewTransactions: canViewTransactions(items[index])
                          ? () => onViewTransactions(items[index])
                          : null,
                    ),
                    if (index != items.length - 1)
                      const Divider(height: ButlerlySpacing.section),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _InsightItem extends StatelessWidget {
  const _InsightItem({
    required this.insight,
    required this.masterData,
    required this.onViewTransactions,
  });

  final InsightResult insight;
  final TransactionMasterData masterData;
  final VoidCallback? onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final semantic = _semanticPresentation(
      context,
      insight.presentation.semanticType,
    );
    final identity = _identityLabel(context, insight, masterData);
    final current = _formattedValue(context, insight, insight.currentValue);
    final baseline = _formattedValue(context, insight, insight.baselineValue);
    final difference = _formattedValue(context, insight, insight.absoluteChange);
    final percent = insight.percentageChange == null
        ? null
        : '${localizedDecimal(context, insight.percentageChange.toString())}%';

    return Semantics(
      container: true,
      label: [
        identity,
        context.l10n.text(insight.rule.nameKey),
        context.l10n.text(insight.rule.descriptionKey),
      ].whereType<String>().join('. '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IdentityIcon(insight: insight, masterData: masterData),
          const SizedBox(width: ButlerlySpacing.small),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        identity ?? context.l10n.text(insight.rule.nameKey),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Icon(semantic.icon, color: semantic.color, size: 18),
                  ],
                ),
                if (identity != null) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(
                    context.l10n.text(insight.rule.nameKey),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: ButlerlySpacing.micro),
                Text(context.l10n.text(insight.rule.descriptionKey)),
                if (current != null || baseline != null) ...[
                  const SizedBox(height: ButlerlySpacing.small),
                  Wrap(
                    spacing: ButlerlySpacing.small,
                    runSpacing: ButlerlySpacing.micro,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (current != null)
                        Text(
                          current,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      if (current != null && baseline != null)
                        Text(
                          '↔',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (baseline != null)
                        Text(
                          baseline,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                    ],
                  ),
                ],
                if (difference != null || percent != null) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(
                    [difference, percent].whereType<String>().join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: semantic.color,
                    ),
                  ),
                ],
                if (onViewTransactions != null) ...[
                  const SizedBox(height: ButlerlySpacing.small),
                  TextButton.icon(
                    onPressed: onViewTransactions,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(_drillDownLabel(context, insight)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityIcon extends StatelessWidget {
  const _IdentityIcon({required this.insight, required this.masterData});

  final InsightResult insight;
  final TransactionMasterData masterData;

  @override
  Widget build(BuildContext context) {
    final categoryId = _categoryIconId(insight, masterData);
    if (categoryId != null &&
        ButlerlyCategoryIdentity.forBuiltInId(categoryId) != null) {
      return ButlerlyCategoryIcon(
        categoryId: categoryId,
        semanticLabel: _identityLabel(context, insight, masterData),
      );
    }

    final icon = switch (insightPresentationGroup(insight)) {
      InsightPresentationGroup.unusual => Icons.priority_high_rounded,
      InsightPresentationGroup.merchant => Icons.storefront_outlined,
      InsightPresentationGroup.paymentSource => Icons.credit_card_outlined,
      InsightPresentationGroup.tag => Icons.sell_outlined,
      InsightPresentationGroup.category ||
      InsightPresentationGroup.subcategory =>
        Icons.category_outlined,
      InsightPresentationGroup.other => Icons.insights_outlined,
    };
    return SizedBox.square(
      dimension: ButlerlySize.categoryIconContainer,
      child: Center(child: Icon(icon)),
    );
  }
}

String? _categoryIconId(InsightResult insight, TransactionMasterData masterData) {
  final dimension = insight.dimension;
  if (dimension == null || dimension == 'uncategorized') return null;
  return switch (insight.rule.grouping) {
    RuleGrouping.category => dimension,
    RuleGrouping.subcategory => masterData.categoryParentId(dimension),
    _ => null,
  };
}

String _groupTitle(
  BuildContext context,
  InsightPresentationGroup group,
  List<InsightResult> items,
) => switch (group) {
  InsightPresentationGroup.unusual => context.l10n.text('needsAttention'),
  InsightPresentationGroup.category => context.l10n.text('categories'),
  InsightPresentationGroup.subcategory => context.l10n.text('subcategories'),
  InsightPresentationGroup.tag => context.l10n.text('tags'),
  InsightPresentationGroup.merchant => context.l10n.text('merchant'),
  InsightPresentationGroup.paymentSource => context.l10n.text('paymentSources'),
  InsightPresentationGroup.other when insightGroupIsPositiveOnly(items) =>
    context.l10n.text('insightsPositiveChanges'),
  InsightPresentationGroup.other => context.l10n.text('otherInsights'),
};

String? _identityLabel(
  BuildContext context,
  InsightResult insight,
  TransactionMasterData masterData,
) {
  final dimension = insight.dimension;
  if (dimension == null) return null;
  return switch (insight.rule.grouping) {
    RuleGrouping.category =>
      masterData.categoryName(dimension) ??
          (dimension == 'uncategorized'
              ? context.l10n.text('uncategorized')
              : context.l10n.text('unavailableCategory')),
    RuleGrouping.subcategory =>
      masterData.subcategoryName(dimension) ??
          (dimension == 'uncategorized'
              ? context.l10n.text('uncategorized')
              : context.l10n.text('unavailableSubcategory')),
    RuleGrouping.merchant =>
      masterData.merchantName(dimension) ??
          context.l10n.text('unavailableMerchant'),
    RuleGrouping.paymentSource =>
      masterData.paymentSourceName(dimension) ??
          context.l10n.text('unavailablePaymentSource'),
    RuleGrouping.tag =>
      masterData.tagName(dimension) ?? context.l10n.text('unavailableTag'),
    _ => null,
  };
}

String? _formattedValue(
  BuildContext context,
  InsightResult insight,
  DecimalValue? value,
) {
  if (value == null) return null;
  final formatted = localizedDecimal(context, value.toString());
  if (insight.rule.measure.operation == RuleOperation.share) return '$formatted%';
  final currency = insight.currency?.value;
  return currency == null || currency.isEmpty ? formatted : '$formatted $currency';
}

String _drillDownLabel(BuildContext context, InsightResult insight) {
  if (insight.evidence.isEmpty) return context.l10n.text('viewTransactions');
  final supporting = context.l10n.text('supportingTransactions', {
    'count': '${insight.evidence.length}',
  });
  return '${context.l10n.text('viewTransactions')} · $supporting';
}

({IconData icon, Color color}) _semanticPresentation(
  BuildContext context,
  InsightSemanticType semanticType,
) => switch (semanticType) {
  InsightSemanticType.positive => (
    icon: Icons.check_circle_outline,
    color: context.colors.success,
  ),
  InsightSemanticType.attention => (
    icon: Icons.priority_high,
    color: context.colors.warning,
  ),
  InsightSemanticType.neutral => (
    icon: Icons.info_outline,
    color: context.colors.info,
  ),
};
