import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/tools/presentation/tools_navigation.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsActionCounts {
  const _ToolsActionCounts(this.reviewTransactions, this.duplicateGroups);

  final int? reviewTransactions;
  final int? duplicateGroups;
}

class _ToolsPageState extends State<ToolsPage> {
  _ToolsActionCounts? _counts;

  @override
  void initState() {
    super.initState();
    transactionChanges.addListener(_refreshCounts);
    _refreshCounts();
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_refreshCounts);
    super.dispose();
  }

  void _refreshCounts() {
    _counts = null;
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    if (!services.isRegistered<FinanceServices>()) return;
    final finance = services<FinanceServices>();
    int? reviews;
    int? duplicates;
    try {
      final result = await finance.listReviewItems(
        ListReviewItemsQuery(scope: const ReviewPeriodScope.unscoped()),
      );
      if (result is ApplicationSuccess<List<ReviewItemDto>>) {
        reviews = result.value.map((item) => item.transactionId).toSet().length;
      }
    } catch (_) {
      // A failed read never becomes a confirmed zero.
    }
    try {
      final list = finance.listDuplicateCandidateGroups;
      if (list != null) {
        final result = await list(scope: const ReviewPeriodScope.unscoped());
        if (result is ApplicationSuccess<List<DuplicateCandidateGroup>>) {
          duplicates = result.value.where((group) => group.isUnresolved).length;
        }
      }
    } catch (_) {
      // A failed read never becomes a confirmed zero.
    }
    if (mounted) {
      setState(() => _counts = _ToolsActionCounts(reviews, duplicates));
    }
  }

  List<ToolNavigationItem> _tools(BuildContext context) =>
      toolNavigationItems(context);

  String? _reviewCountsLabel(BuildContext context) {
    final counts = _counts;
    if (counts == null ||
        (counts.reviewTransactions == null && counts.duplicateGroups == null)) {
      return null;
    }
    final parts = <String>[
      if (counts.reviewTransactions != null)
        context.l10n
            .text('toolsReviewPendingCount')
            .replaceAll('{count}', '${counts.reviewTransactions}'),
      if (counts.duplicateGroups != null)
        context.l10n
            .text('toolsDuplicatePendingCount')
            .replaceAll('{count}', '${counts.duplicateGroups}'),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    final tools = _tools(context);
    final reviewStatus = _reviewCountsLabel(context);

    final sections = [
      (
        title: context.l10n.text('toolsActNow'),
        routes: const ['/review', '/payment-settlements'],
      ),
      (
        title: context.l10n.text('toolsUnderstand'),
        routes: const ['/analysis', '/insights'],
      ),
      (
        title: context.l10n.text('toolsMaintain'),
        routes: const ['/master-data', '/rules'],
      ),
    ];

    return ButlerlyPage(
      title: context.l10n.text('tools'),
      subtitle: context.l10n.text('toolsSubtitle'),
      fullWidth: desktop,
      padding: const EdgeInsets.fromLTRB(
        ButlerlySize.contentGutter,
        ButlerlySpacing.cardGap,
        ButlerlySize.contentGutter,
        ButlerlySpacing.large,
      ),
      children: [
        if (desktop)
          Row(
            key: const ValueKey('desktop-tools-three-columns'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, section) in sections.indexed) ...[
                if (index > 0) const SizedBox(width: ButlerlySpacing.cardGap),
                Expanded(
                  child: Column(
                    key: ValueKey(
                      index == 0
                          ? 'desktop-tools-actions'
                          : 'desktop-tools-actions-$index',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: ButlerlySpacing.small,
                        ),
                        child: Text(
                          section.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final tool in tools.where(
                        (item) => section.routes.contains(item.route),
                      )) ...[
                        _ToolPanel(
                          tool: tool,
                          reviewStatus: tool.route == '/review'
                              ? reviewStatus
                              : null,
                        ),
                        const SizedBox(height: ButlerlySpacing.cardGap),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          )
        else
          for (final (index, section) in sections.indexed) ...[
            Padding(
              padding: EdgeInsets.only(
                top: index == 0
                    ? ButlerlySpacing.none
                    : ButlerlySpacing.cardGap,
                bottom: ButlerlySpacing.small,
              ),
              child: Text(
                section.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ButlerlyActionGroup(
              actions: [
                for (final tool in tools.where(
                  (item) => section.routes.contains(item.route),
                ))
                  ButlerlyActionItem(
                    icon: tool.icon,
                    title: tool.title,
                    subtitle: tool.route == '/review' && reviewStatus != null
                        ? reviewStatus
                        : tool.description,
                    onTap: () => context.push(tool.route),
                  ),
              ],
            ),
          ],
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.tool, this.reviewStatus});
  final ToolNavigationItem tool;
  final String? reviewStatus;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: () => context.push(tool.route),
    semanticLabel: '${tool.title}, ${tool.description}',
    child: SizedBox(
      height: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ButlerlyActionIcon(icon: tool.icon),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
          const Spacer(),
          Text(
            tool.title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            reviewStatus ?? tool.description,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
