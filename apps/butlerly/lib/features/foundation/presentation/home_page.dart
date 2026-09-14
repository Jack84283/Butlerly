import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
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
      finance.listPaymentSources(),
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
      switch (results[3]) {
        ApplicationSuccess<List<PaymentSource>>(:final value) => {
          for (final source in value)
            source.id.value: source.lastFour == null
                ? source.name
                : '${source.name} ••••${source.lastFour}',
        },
        _ => const {},
      },
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
        const SizedBox(height: ButlerlySpacing.section),
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
                      ? Text(
                          '${data.reviewCount}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: context.colors.interactive,
                          ),
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
                  TransactionRecordList(
                    transactions: data.transactions,
                    masterData: data.masterData,
                    paymentSourceNames: data.paymentSourceNames,
                    onTap: _open,
                    navigates: true,
                    showDateInRows: true,
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
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: context.l10n.text('localOnlyStatus'),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.subtleSurface,
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        border: Border.all(color: context.colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ButlerlySpacing.standard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: context.colors.interactive,
                ),
                const SizedBox(width: ButlerlySpacing.compact),
                Expanded(
                  child: Text(
                    context.l10n.text('localRecords'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.compact),
                Icon(
                  Icons.phonelink_lock_outlined,
                  size: 18,
                  color: context.colors.tertiaryText,
                ),
              ],
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _SummaryMetric(
                    value: '${data.transactionCount}',
                    label: context.l10n.text('recordsOnDevice'),
                  ),
                ),
                Container(
                  width: 1,
                  height: 52,
                  color: context.colors.cardDivider,
                ),
                Expanded(
                  child: _SummaryMetric(
                    value: '${data.reviewCount}',
                    label: context.l10n.text('attentionItems'),
                    accent: data.reviewCount > 0,
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
      ),
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.value,
    required this.label,
    this.accent = false,
  });

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ButlerlySpacing.small),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: accent ? context.colors.interactive : null,
          ),
        ),
        const SizedBox(height: ButlerlySpacing.micro),
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
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.add_rounded,
        label: context.l10n.text('addData'),
        onTap: () async {
          await context.push('/add');
          await onRefresh();
        },
      ),
      _QuickAction(
        icon: Icons.analytics_outlined,
        label: context.l10n.text('analysis'),
        onTap: () => context.push('/analysis'),
      ),
      _QuickAction(
        icon: Icons.lightbulb_outline_rounded,
        label: context.l10n.text('insights'),
        onTap: () => context.push('/insights'),
      ),
      _QuickAction(
        icon: Icons.notifications_none_rounded,
        label: context.l10n.text('notifications'),
        onTap: () => context.push('/notifications'),
      ),
    ];

    Widget divider() => SizedBox(
      height: 46,
      child: VerticalDivider(width: 1, color: context.colors.cardDivider),
    );

    Widget pair(int first, int second) => Row(
      children: [
        Expanded(child: actions[first]),
        divider(),
        Expanded(child: actions[second]),
      ],
    );

    return Material(
      color: context.colors.subtleSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        side: BorderSide(color: context.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final useTwoRows = constraints.maxWidth < 360 || textScale > 1.2;
          if (useTwoRows) {
            return Column(
              children: [
                pair(0, 1),
                Divider(height: 1, color: context.colors.cardDivider),
                pair(2, 3),
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                Expanded(child: actions[index]),
                if (index < actions.length - 1) divider(),
              ],
            ],
          );
        },
      ),
    );
  }
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.micro,
          vertical: ButlerlySpacing.small,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.selection,
              ),
              child: Icon(
                icon,
                size: 20,
                color: context.colors.interactive,
              ),
            ),
            const SizedBox(height: ButlerlySpacing.compact),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final active = reviewCount > 0;
    final color = active ? context.colors.interactive : context.colors.success;
    return Material(
      color: active
          ? context.colors.selection
          : context.colors.success.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        side: BorderSide(color: color.withValues(alpha: 0.32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        onTap: active ? () => context.go('/review') : null,
        child: Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          child: Row(
            children: [
              Container(
                width: ButlerlySize.preferredTarget,
                height: ButlerlySize.preferredTarget,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.13),
                ),
                child: Icon(
                  active
                      ? Icons.notifications_none_rounded
                      : Icons.check_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: ButlerlySpacing.standard),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active
                          ? context.l10n.text('needsReview')
                          : context.l10n.text('nothingNeedsAttention'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: ButlerlySpacing.xxs),
                    Text(
                      context.l10n.text(
                        active
                            ? 'reviewRecommendation'
                            : 'nothingNeedsAttentionBody',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.tertiaryText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeEmptyTransactions extends StatelessWidget {
  const _HomeEmptyTransactions();

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.subtleSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      side: BorderSide(color: context.colors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      onTap: () => context.push('/add'),
      child: Padding(
        padding: const EdgeInsets.all(ButlerlySpacing.standard),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: context.colors.secondaryText,
            ),
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
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.tertiaryText,
            ),
          ],
        ),
      ),
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
    this.paymentSourceNames = const {},
  ]);

  final List<TransactionDto> transactions;
  final int transactionCount;
  final int reviewCount;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
}
