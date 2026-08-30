import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static DateTime? debugCurrentDate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<_HomeData> _data;
  String? _loadedLanguageCode;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _data = Future.value(const _HomeData([], 0, 0));
    transactionChanges.addListener(_handleTransactionChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _data = _load(languageCode: languageCode);
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_handleTransactionChange);
    super.dispose();
  }

  void _handleTransactionChange() {
    if (mounted) _refresh();
  }

  Future<_HomeData> _load({String? languageCode}) async {
    final finance = _finance;
    if (finance == null) return const _HomeData([], 0, 0);
    final activeLanguageCode =
        languageCode ??
        _loadedLanguageCode ??
        Localizations.localeOf(context).languageCode;
    final results = await Future.wait([
      finance.listTransactions(const ListTransactionsQuery()),
      finance.listReviewItems(),
      TransactionMasterData.load(finance, languageCode: activeLanguageCode),
    ]);
    final transactions = switch (results[0]) {
      ApplicationSuccess<List<TransactionDto>>(:final value) => value,
      _ => const <TransactionDto>[],
    };
    final reviewItems = switch (results[1]) {
      ApplicationSuccess<List<ReviewItemDto>>(:final value) => value,
      _ => const <ReviewItemDto>[],
    };
    return _HomeData(
      transactions.take(4).toList(growable: false),
      transactions.length,
      reviewItems.length,
      results[2] as TransactionMasterData,
    );
  }

  Future<void> _refresh() async {
    final refreshed = _load();
    setState(() {
      _data = refreshed;
    });
    await refreshed;
  }

  Future<void> _open(TransactionDto transaction) async {
    final finance = _finance;
    if (finance == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ButlerlyPage(
      title: context.l10n.text('appName'),
      actions: [
        IconButton(
          tooltip: context.l10n.text('notifications'),
          onPressed: () => context.push('/notifications'),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
      children: [
        Text(
          context.l10n.text(
            homeGreetingKey(HomePage.debugCurrentDate ?? DateTime.now()),
          ),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: ButlerlySpacing.micro),
        Text(
          MaterialLocalizations.of(
            context,
          ).formatFullDate(HomePage.debugCurrentDate ?? DateTime.now()),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        FutureBuilder<_HomeData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _HomeLoading();
            }
            final data = snapshot.data ?? const _HomeData([], 0, 0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LocalSummary(data: data),
                ButlerlySectionHeader(title: context.l10n.text('quickActions')),
                _QuickActions(onRefresh: _refresh),
                ButlerlySectionHeader(
                  title: context.l10n.text('needsAttention'),
                  action: data.reviewCount > 0
                      ? ButlerlyStatusChip(
                          label: '${data.reviewCount}',
                          status: ButlerlyStatus.review,
                          icon: Icons.flag_outlined,
                        )
                      : null,
                ),
                _AttentionCard(reviewCount: data.reviewCount),
                ButlerlySectionHeader(
                  title: context.l10n.text('recentTransactions'),
                  action: TextButton(
                    onPressed: () => context.go('/transactions'),
                    child: Text(context.l10n.text('viewAll')),
                  ),
                ),
                if (data.transactions.isEmpty)
                  const _HomeEmptyTransactions()
                else
                  ButlerlyTransactionList(
                    children: data.transactions
                        .map(
                          (value) => ButlerlyTransactionListItem(
                            title:
                                value.description ??
                                context.l10n.text('untitledTransaction'),
                            subtitle: data.masterData.summary(value),
                            meta: _date(value, context),
                            amount: localizedTransactionAmount(
                              context,
                              value.amount,
                            ),
                            currency: value.currency,
                            isIncome:
                                value.direction ==
                                TransactionDirection.income.name,
                            needsReview: value.reviewState == 'needsReview',
                            onTap: () => _open(value),
                            showNavigationIndicator: true,
                          ),
                        )
                        .toList(growable: false),
                  ),
                const SizedBox(height: ButlerlySpacing.structural),
              ],
            );
          },
        ),
      ],
    ),
  );
}

String homeGreetingKey(DateTime localTime) {
  if (localTime.hour < 12) return 'greetingMorning';
  if (localTime.hour < 18) return 'greetingAfternoon';
  return 'greetingEvening';
}

class _LocalSummary extends StatelessWidget {
  const _LocalSummary({required this.data});

  final _HomeData data;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    semanticLabel: context.l10n.text('localOnlyStatus'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: context.colors.interactive),
            const SizedBox(width: ButlerlySpacing.compact),
            Expanded(
              child: Text(
                context.l10n.text('localRecords'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Tooltip(
              message: context.l10n.text('localOnlyStatus'),
              child: Icon(
                Icons.phonelink_lock_outlined,
                color: context.colors.secondaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                value: '${data.transactionCount}',
                label: context.l10n.text('recordsOnDevice'),
              ),
            ),
            Container(
              width: 1,
              height: ButlerlySize.preferredTarget,
              color: context.colors.border,
            ),
            Expanded(
              child: _SummaryMetric(
                value: '${data.reviewCount}',
                label: context.l10n.text('attentionItems'),
              ),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Text(
          context.l10n.text('localOnlyBody'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ButlerlySpacing.small),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = ButlerlySpacing.compact;
      final columns = constraints.maxWidth < 350 ? 2 : 4;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      final actions = [
        _QuickAction(
          icon: Icons.add_rounded,
          label: context.l10n.text('addTransaction'),
          onTap: () async {
            await context.push('/transactions/add');
            await onRefresh();
          },
        ),
        _QuickAction(
          icon: Icons.file_open_outlined,
          label: context.l10n.text('importData'),
          onTap: () => context.push('/import-export'),
        ),
        _QuickAction(
          icon: Icons.search_rounded,
          label: context.l10n.text('searchRecords'),
          onTap: () => context.go('/search'),
        ),
        _QuickAction(
          icon: Icons.insights_outlined,
          label: context.l10n.text('analysis'),
          onTap: () => context.push('/analysis'),
        ),
      ];
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: actions
            .map((action) => SizedBox(width: width, child: action))
            .toList(growable: false),
      );
    },
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: onTap,
    semanticLabel: label,
    padding: const EdgeInsets.symmetric(
      horizontal: ButlerlySpacing.micro,
      vertical: ButlerlySpacing.small,
    ),
    child: SizedBox(
      height: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: context.colors.interactive),
          const SizedBox(height: ButlerlySpacing.compact),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    ),
  );
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: reviewCount > 0 ? () => context.go('/review') : null,
    child: Row(
      children: [
        Icon(
          reviewCount > 0
              ? Icons.flag_outlined
              : Icons.check_circle_outline_rounded,
          color: reviewCount > 0
              ? context.colors.warning
              : context.colors.success,
        ),
        const SizedBox(width: ButlerlySpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reviewCount > 0
                    ? context.l10n.text('needsReview')
                    : context.l10n.text('nothingNeedsAttention'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                context.l10n.text('nothingNeedsAttentionBody'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (reviewCount > 0) const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

class _HomeEmptyTransactions extends StatelessWidget {
  const _HomeEmptyTransactions();

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: () => context.push('/transactions/add'),
    child: Row(
      children: [
        Icon(Icons.receipt_long_outlined, color: context.colors.secondaryText),
        const SizedBox(width: ButlerlySpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.text('noTransactions'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                context.l10n.text('noTransactionsBody'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 240,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _HomeData {
  const _HomeData(
    this.transactions,
    this.transactionCount,
    this.reviewCount, [
    this.masterData = const TransactionMasterData(),
  ]);

  final List<TransactionDto> transactions;
  final int transactionCount;
  final int reviewCount;
  final TransactionMasterData masterData;
}

String _date(TransactionDto value, BuildContext context) =>
    transactionDateLabel(
      value,
      pendingLabel: context.l10n.text('datePending'),
      locale: Localizations.localeOf(context).toLanguageTag(),
    );
