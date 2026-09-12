import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
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
  largePurchase,
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
          when insight.outputType == InsightOutputType.pattern &&
              insight.rule.measure.operation == RuleOperation.maximum &&
              insight.presentation.visualizationType ==
                  InsightVisualizationType.comparison &&
              insight.presentation.primaryMetric == InsightPrimaryMetric.amount =>
        InsightPresentationGroup.largePurchase,
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
    final presented = _consolidateEquivalentComparisons(
      results
          .where((result) => result.outputType != InsightOutputType.dataQuality)
          .toList(growable: false),
    );
    final grouped = <InsightPresentationGroup, List<_PresentedInsight>>{};
    for (final item in presented) {
      grouped
          .putIfAbsent(insightPresentationGroup(item.primary), () => [])
          .add(item);
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
      InsightPresentationGroup.largePurchase,
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
            ButlerlySectionHeader(
              title: _groupTitle(
                context,
                group,
                items.map((item) => item.primary).toList(growable: false),
              ),
            ),
            if (_groupSubtitle(
              context,
              group,
              items.map((item) => item.primary).toList(growable: false),
            ) case final subtitle?) ...[
              const SizedBox(height: ButlerlySpacing.micro),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ButlerlySpacing.small),
            ],
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
                    Builder(
                      builder: (context) {
                        final item = items[index];
                        final escalation = item.escalation;
                        final drillDownInsight = escalation != null &&
                                canViewTransactions(escalation)
                            ? escalation
                            : item.primary;
                        return _InsightItem(
                          insight: item.primary,
                          escalation: escalation,
                          drillDownInsight: drillDownInsight,
                          masterData: masterData,
                          showRuleCopy: !_groupOwnsRuleCopy(group),
                          onViewTransactions:
                              canViewTransactions(drillDownInsight)
                                  ? () => onViewTransactions(drillDownInsight)
                                  : null,
                        );
                      },
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

final class _PresentedInsight {
  const _PresentedInsight({required this.primary, this.escalation});

  final InsightResult primary;
  final InsightResult? escalation;
}

List<_PresentedInsight> _consolidateEquivalentComparisons(
  List<InsightResult> results,
) {
  final escalations = <InsightResult>{};
  final escalationByPattern = <InsightResult, InsightResult>{};

  for (final pattern in results) {
    if (pattern.outputType != InsightOutputType.pattern ||
        pattern.presentation.visualizationType !=
            InsightVisualizationType.comparison) {
      continue;
    }
    final escalation = results
        .where(
          (candidate) =>
              candidate.outputType == InsightOutputType.alert &&
              !escalations.contains(candidate) &&
              _sameComparison(pattern, candidate),
        )
        .firstOrNull;
    if (escalation != null) {
      escalations.add(escalation);
      escalationByPattern[pattern] = escalation;
    }
  }

  return [
    for (final result in results)
      if (!escalations.contains(result))
        _PresentedInsight(
          primary: result,
          escalation: escalationByPattern[result],
        ),
  ];
}

bool _sameComparison(InsightResult pattern, InsightResult alert) {
  if (pattern.rule.grouping != alert.rule.grouping ||
      pattern.rule.period != alert.rule.period ||
      pattern.rule.surface != alert.rule.surface ||
      pattern.rule.measure.operation != alert.rule.measure.operation ||
      pattern.rule.measure.field != alert.rule.measure.field ||
      pattern.rule.measure.key != alert.rule.measure.key ||
      pattern.rule.measure.currencyBasis != alert.rule.measure.currencyBasis ||
      !_sameFilters(pattern.rule.measure.filters, alert.rule.measure.filters) ||
      !_sameFilters(pattern.rule.filters, alert.rule.filters) ||
      pattern.rule.baseline != alert.rule.baseline ||
      pattern.presentation.semanticType != alert.presentation.semanticType ||
      pattern.presentation.visualizationType !=
          alert.presentation.visualizationType ||
      pattern.presentation.primaryMetric != alert.presentation.primaryMetric ||
      pattern.dimension != alert.dimension ||
      pattern.currency?.value != alert.currency?.value ||
      !_sameDecimal(pattern.currentValue, alert.currentValue) ||
      !_sameDecimal(pattern.baselineValue, alert.baselineValue) ||
      !_sameDecimal(pattern.absoluteChange, alert.absoluteChange) ||
      !_sameDecimal(pattern.percentageChange, alert.percentageChange)) {
    return false;
  }
  return _sameContext(pattern.context, alert.context) &&
      _sameOptionalContext(pattern.baselineContext, alert.baselineContext);
}

bool _sameFilters(List<AnalysisFilter> left, List<AnalysisFilter> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].kind != right[index].kind ||
        !_sameStrings(left[index].values, right[index].values)) {
      return false;
    }
  }
  return true;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameDecimal(DecimalValue? left, DecimalValue? right) =>
    left?.toString() == right?.toString();

bool _sameOptionalContext(AnalysisContext? left, AnalysisContext? right) {
  if (left == null || right == null) return left == right;
  return _sameContext(left, right);
}

bool _sameContext(AnalysisContext left, AnalysisContext right) =>
    left.period.startDate == right.period.startDate &&
    left.period.endDate == right.period.endDate &&
    left.period.timeZoneId == right.period.timeZoneId &&
    left.periodType == right.periodType &&
    left.datasetMode == right.datasetMode &&
    left.currencyBasis == right.currencyBasis &&
    left.baseCurrency?.value == right.baseCurrency?.value;

class _InsightItem extends StatelessWidget {
  const _InsightItem({
    required this.insight,
    required this.escalation,
    required this.drillDownInsight,
    required this.masterData,
    required this.showRuleCopy,
    required this.onViewTransactions,
  });

  final InsightResult insight;
  final InsightResult? escalation;
  final InsightResult drillDownInsight;
  final TransactionMasterData masterData;
  final bool showRuleCopy;
  final VoidCallback? onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final semantic = _semanticPresentation(
      context,
      escalation?.presentation.semanticType ?? insight.presentation.semanticType,
    );
    final identity = _identityLabel(context, insight, masterData);
    final current = _formattedValue(context, insight, insight.currentValue);
    final baseline = _formattedValue(context, insight, insight.baselineValue);
    final difference = _formattedValue(context, insight, insight.absoluteChange);
    final percent = insight.percentageChange == null
        ? null
        : '${localizedDecimal(context, insight.percentageChange.toString())}%';
    final direction = _changeDirection(insight);
    final ruleName = context.l10n.text(insight.rule.nameKey);
    final escalationName = escalation == null
        ? null
        : context.l10n.text(escalation!.rule.nameKey);
    final showHeading = identity != null || showRuleCopy;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: [ruleName, ?identity, ?escalationName].join(': '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IdentityIcon(insight: insight, masterData: masterData),
          const SizedBox(width: ButlerlySpacing.small),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeading)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          identity ?? ruleName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(semantic.icon, color: semantic.color, size: 18),
                    ],
                  )
                else
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Icon(semantic.icon, color: semantic.color, size: 18),
                  ),
                if (showRuleCopy && identity != null) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(
                    ruleName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (showRuleCopy) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(context.l10n.text(insight.rule.descriptionKey)),
                ],
                if (escalationName != null) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: semantic.color,
                      ),
                      const SizedBox(width: ButlerlySpacing.micro),
                      Flexible(
                        child: Text(
                          escalationName,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: semantic.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (current != null || baseline != null) ...[
                  const SizedBox(height: ButlerlySpacing.small),
                  Wrap(
                    spacing: ButlerlySpacing.small,
                    runSpacing: ButlerlySpacing.micro,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (baseline != null)
                        Text(
                          baseline,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      if (baseline != null && current != null)
                        Text(
                          '→',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (current != null)
                        Text(
                          current,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                    ],
                  ),
                ],
                if (difference != null || percent != null) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(
                    [direction, difference, percent]
                        .whereType<String>()
                        .join(' · '),
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
                    label: Text(
                      drillDownInsight.evidence.isEmpty
                          ? context.l10n.text('viewTransactions')
                          : _viewSupportingTransactionsLabel(
                              context,
                              drillDownInsight.evidence.length,
                            ),
                    ),
                  ),
                ] else if (drillDownInsight.evidence.isNotEmpty) ...[
                  const SizedBox(height: ButlerlySpacing.small),
                  Text(
                    context.l10n.text('supportingTransactions', {
                      'count': '${drillDownInsight.evidence.length}',
                    }),
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
      InsightPresentationGroup.largePurchase => Icons.shopping_bag_outlined,
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
  InsightPresentationGroup.largePurchase =>
    context.l10n.text(items.first.rule.nameKey),
  InsightPresentationGroup.category =>
    context.l10n.text('analysis.rule.r021.name'),
  InsightPresentationGroup.subcategory =>
    context.l10n.text('analysis.rule.r022.name'),
  InsightPresentationGroup.tag => context.l10n.text('tags'),
  InsightPresentationGroup.merchant =>
    context.l10n.text('analysis.rule.r023.name'),
  InsightPresentationGroup.paymentSource => context.l10n.text('paymentSources'),
  InsightPresentationGroup.other when insightGroupIsPositiveOnly(items) =>
    context.l10n.text('insightsPositiveChanges'),
  InsightPresentationGroup.other => context.l10n.text('otherInsights'),
};

String? _groupSubtitle(
  BuildContext context,
  InsightPresentationGroup group,
  List<InsightResult> items,
) => switch (group) {
  InsightPresentationGroup.category ||
  InsightPresentationGroup.subcategory ||
  InsightPresentationGroup.merchant ||
  InsightPresentationGroup.largePurchase =>
    context.l10n.text(items.first.rule.descriptionKey),
  _ => null,
};

bool _groupOwnsRuleCopy(InsightPresentationGroup group) => switch (group) {
  InsightPresentationGroup.category ||
  InsightPresentationGroup.subcategory ||
  InsightPresentationGroup.merchant ||
  InsightPresentationGroup.largePurchase => true,
  _ => false,
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

String? _changeDirection(InsightResult insight) {
  final change = double.tryParse(insight.absoluteChange?.toString() ?? '');
  if (change == null || change == 0) return null;
  return change > 0 ? '↑' : '↓';
}

String _viewSupportingTransactionsLabel(BuildContext context, int count) {
  final l10n = context.l10n;
  final action = l10n.text('viewTransactions');
  final noun = l10n.text('transactions');
  final supporting = l10n.text('supportingTransactions', {'count': '$count'});
  return action.replaceFirst(
    RegExp(RegExp.escape(noun), caseSensitive: false),
    supporting,
  );
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
