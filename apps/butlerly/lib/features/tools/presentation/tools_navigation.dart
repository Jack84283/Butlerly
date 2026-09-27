import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shared metadata for the existing Tools destinations.
///
/// The Tools page and the Wide primary navigation both consume this list so
/// route ownership and ordering cannot drift between presentations.
class ToolNavigationItem {
  const ToolNavigationItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String description;
  final String route;
}

List<ToolNavigationItem> toolNavigationItems(BuildContext context) => [
  ToolNavigationItem(
    icon: Icons.fact_check_rounded,
    title: context.l10n.text('review'),
    description: context.l10n.text('toolsReviewDescription'),
    route: '/review',
  ),
  ToolNavigationItem(
    icon: Icons.analytics_outlined,
    title: context.l10n.text('analysis'),
    description: context.l10n.text('toolsAnalysisDescription'),
    route: '/analysis',
  ),
  ToolNavigationItem(
    icon: Icons.lightbulb_outline_rounded,
    title: context.l10n.text('insights'),
    description: context.l10n.text('toolsInsightsDescription'),
    route: '/insights',
  ),
  ToolNavigationItem(
    icon: Icons.credit_score_outlined,
    title: context.l10n.text('paymentSettlements'),
    description: context.l10n.text('toolsPaymentSettlementsDescription'),
    route: '/payment-settlements',
  ),
  ToolNavigationItem(
    icon: Icons.account_tree_outlined,
    title: context.l10n.text('masterData'),
    description: context.l10n.text('masterDataSubtitle'),
    route: '/master-data',
  ),
  ToolNavigationItem(
    icon: Icons.rule_outlined,
    title: context.l10n.text('ruleManagement'),
    description: context.l10n.text('ruleManagementSubtitle'),
    route: '/rules',
  ),
];
