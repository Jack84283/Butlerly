import 'package:butlerly/app/locale/home_greeting.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_category_icon.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_transaction_table.dart';
import 'package:butlerly/design_system/components/butlerly_month_picker.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/theme/butlerly_responsive_design_tokens.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/budgets/application/budget_change_notifier.dart';
import 'package:butlerly/features/budgets/presentation/home_budgets_card.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// A desktop-only presentation surface. No device Home widgets are imported.
class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({super.key});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  DateTime? _month;
  late Future<HomeOverview?> _overview;
  int _trendMonths = 6;
  TransactionMasterData? _masterData;
  String? _masterDataLocale;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _reload();
    transactionChanges.addListener(_onTransactionChange);
    budgetChanges.addListener(_onTransactionChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (_masterDataLocale == locale) return;
    _masterDataLocale = locale;
    final finance = _finance;
    if (finance == null) return;
    TransactionMasterData.load(finance, languageCode: locale).then((value) {
      if (mounted && _masterDataLocale == locale) {
        setState(() => _masterData = value);
      }
    });
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_onTransactionChange);
    budgetChanges.removeListener(_onTransactionChange);
    super.dispose();
  }

  void _onTransactionChange() {
    if (mounted) setState(_reload);
  }

  void _reload() {
    _overview = _load();
  }

  Future<HomeOverview?> _load() async {
    final load = _finance?.loadHomeOverview;
    if (load == null) return null;
    try {
      final result = await load(
        instant: DateTime.now(),
        selectedMonth: _month,
        trendMonthCount: _trendMonths,
      );
      if (result is ApplicationSuccess<HomeOverview>) return result.value;
    } catch (_) {
      // The failure is presented locally without changing device UI state.
    }
    return null;
  }

  void _moveMonth(int delta, DateTime current) {
    setState(() {
      _month = DateTime(current.year, current.month + delta);
      _reload();
    });
  }

  String _money(AnalysisMetric? metric, String currency) {
    if (metric == null ||
        metric.availability != AnalysisDataAvailability.sufficient) {
      return '—';
    }
    final value = double.tryParse(metric.value.toString());
    if (value == null) return '—';
    return NumberFormat.simpleCurrency(
      name: metric.currency?.value ?? currency,
    ).format(value);
  }

  String _transactionCount(AnalysisMetric? metric) {
    if (metric == null ||
        metric.availability == AnalysisDataAvailability.insufficient) {
      return '—';
    }
    final count = int.tryParse(metric.value.toString());
    if (count == null) return '—';
    return NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(count);
  }

  String _periodQuery(HomeOverview data) {
    final month = data.displayMonth ?? DateTime.now();
    final from = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(month.year, month.month, 1));
    final to = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(month.year, month.month + 1, 0));
    return 'from=$from&to=$to';
  }

  void _go(String path) => context.push(path);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<HomeOverview?>(
      future: _overview,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final current = data?.displayMonth ?? _month ?? DateTime.now();
        final currency = data?.context?.baseCurrency?.value ?? 'USD';
        final query = data == null ? '' : _periodQuery(data);
        final analysis = data?.analysis;
        final unavailable =
            data == null || data.status != HomeOverviewStatus.available;
        return Column(
          children: [
            Container(
              key: const ValueKey('desktop-home-header'),
              padding: const EdgeInsets.symmetric(
                horizontal: ButlerlySize.contentGutter,
              ),
              constraints: const BoxConstraints(
                minHeight: ButlerlySize.pageToolbarHeight,
                maxHeight: ButlerlySize.pageToolbarHeight,
              ),
              decoration: BoxDecoration(
                color: context.colors.background,
                border: Border(
                  bottom: BorderSide(color: context.colors.cardDivider),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PersonalizedHomeGreeting(
                      greetingKey: greetingKeyForTime(DateTime.now()),
                      textKey: const ValueKey('desktop-home-greeting'),
                      maxLines: 1,
                      textAlign: TextAlign.start,
                      style: theme.appBarTheme.titleTextStyle,
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      minimumSize: const Size.square(
                        ButlerlyButtonTokens.iconTouchTarget,
                      ),
                    ),
                    tooltip: context.l10n.text('previousMonth'),
                    onPressed: () => _moveMonth(-1, current),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton.icon(
                    key: const ValueKey('desktop-home-month-selector'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(
                        ButlerlyButtonTokens.minimumWidth,
                        ButlerlyButtonTokens.height,
                      ),
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: () async {
                      final picked = await showButlerlyMonthPicker(
                        context,
                        selectedMonth: current,
                        currentMonth: DateTime.now(),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _month = DateTime(picked.year, picked.month);
                          _reload();
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      DateFormat.yMMMM(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(current),
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      minimumSize: const Size.square(
                        ButlerlyButtonTokens.iconTouchTarget,
                      ),
                    ),
                    tooltip: context.l10n.text('nextMonth'),
                    onPressed: () => _moveMonth(1, current),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: const Size(
                          ButlerlyButtonTokens.minimumWidth,
                          ButlerlyButtonTokens.height,
                        ),
                      ),
                      onPressed: () => _go('/search'),
                      icon: const Icon(Icons.search),
                      label: Text(
                        context.l10n.text('desktopSearchTransactions'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: const Size(
                        ButlerlyButtonTokens.minimumWidth,
                        ButlerlyButtonTokens.height,
                      ),
                    ),
                    onPressed: () => _go('/transactions/add'),
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.text('add')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(_reload);
                  await _overview;
                },
                child: ListView(
                  key: const ValueKey('desktop-home-page'),
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ButlerlySpacing.small,
                        ButlerlySpacing.small,
                        ButlerlySpacing.small,
                        ButlerlySpacing.standard,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.l10n.text('desktopFinancialOverview'),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.yMMMM(
                              Localizations.localeOf(context).toLanguageTag(),
                            ).format(current),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 10),
                          if (snapshot.connectionState != ConnectionState.done)
                            const LinearProgressIndicator(),
                          if (unavailable)
                            _DesktopPanel(
                              title: context.l10n.text('homeUnavailable'),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      context.l10n.text(
                                        'desktopLocalDataUnavailable',
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(
                                        ButlerlyButtonTokens.minimumWidth,
                                        ButlerlyButtonTokens.height,
                                      ),
                                    ),
                                    onPressed: () => setState(_reload),
                                    child: Text(
                                      context.l10n.text('desktopRetry'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (!unavailable) ...[
                            _DesktopPanel(
                              title: context.l10n.text('monthlySummary'),
                              subtitle: context.l10n.text('vsPreviousPeriod'),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DesktopMetric(
                                      key: const ValueKey(
                                        'desktop-home-summary-expenses',
                                      ),
                                      title: context.l10n.text(
                                        'desktopExpenses',
                                      ),
                                      value: _money(
                                        analysis?.spending,
                                        currency,
                                      ),
                                      icon: Icons.arrow_downward,
                                      comparison: analysis?.spendingComparison,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _DesktopMetric(
                                      key: const ValueKey(
                                        'desktop-home-summary-transactions',
                                      ),
                                      title: context.l10n.text('transactions'),
                                      value: _transactionCount(
                                        analysis?.transactionCount,
                                      ),
                                      icon: Icons.receipt_long_outlined,
                                      comparison:
                                          analysis?.transactionCountComparison,
                                      accentColor: ButlerlyHomeColorTokens
                                          .standard
                                          .transactions,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _DesktopMetric(
                                      key: const ValueKey(
                                        'desktop-home-summary-income',
                                      ),
                                      title: context.l10n.text('income'),
                                      value: _money(analysis?.income, currency),
                                      icon: Icons.arrow_upward,
                                      comparison: analysis?.incomeComparison,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _DesktopMetric(
                                      key: const ValueKey(
                                        'desktop-home-summary-net',
                                      ),
                                      title: context.l10n.text('netCashFlow'),
                                      value: _money(analysis?.net, currency),
                                      icon: Icons.show_chart,
                                      comparison: analysis?.netComparison,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, b) {
                                final left = SizedBox(
                                  height: _desktopHomeBreakdownCardHeight,
                                  child: _DesktopPanel(
                                    title: context.l10n.text('spendingTrend'),
                                    showInnerCard: true,
                                    headerHeight:
                                        _desktopHomeBreakdownHeaderHeight,
                                    trailing: DropdownButton<int>(
                                      isDense: true,
                                      value: _trendMonths,
                                      underline: const SizedBox.shrink(),
                                      items: const [3, 6, 12]
                                          .map(
                                            (n) => DropdownMenuItem(
                                              value: n,
                                              child: Text(
                                                context.l10n.text(
                                                  'desktopMonthsCount',
                                                  {'count': '$n'},
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (n) {
                                        if (n != null) {
                                          setState(() {
                                            _trendMonths = n;
                                            _reload();
                                          });
                                        }
                                      },
                                    ),
                                    child: SizedBox(
                                      height:
                                          _desktopHomeBreakdownContentHeight -
                                          ButlerlySpacing.small * 2,
                                      child: _DesktopTrend(
                                        points: data.monthlyTrend,
                                        selectedMonth: current,
                                        currency: currency,
                                        onTap: () => _go('/analysis?$query'),
                                      ),
                                    ),
                                  ),
                                );
                                final middle = SizedBox(
                                  height: _desktopHomeBreakdownCardHeight,
                                  child: _DesktopPanel(
                                    title: context.l10n.text(
                                      'desktopCategoryBreakdown',
                                    ),
                                    showInnerCard: true,
                                    headerHeight:
                                        _desktopHomeBreakdownHeaderHeight,
                                    trailing: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        minimumSize: const Size(
                                          ButlerlyButtonTokens.minimumWidth,
                                          ButlerlyButtonTokens.height,
                                        ),
                                      ),
                                      onPressed: () => _go('/analysis?$query'),
                                      child: Text(context.l10n.text('viewAll')),
                                    ),
                                    child: SizedBox(
                                      // Reserve the 12px inset within the 280px outer card.
                                      height:
                                          _desktopHomeBreakdownContentHeight -
                                          2 * ButlerlySpacing.small,
                                      child: ListView(
                                        children: [
                                          for (final metric
                                              in analysis?.categories
                                                      .where(
                                                        (category) =>
                                                            category
                                                                .availability ==
                                                            AnalysisDataAvailability
                                                                .sufficient,
                                                      )
                                                      .take(6) ??
                                                  <AnalysisMetric>[])
                                            Column(
                                              children: [
                                                _DesktopCategorySummaryRow(
                                                  metric: metric,
                                                  share:
                                                      analysis
                                                          ?.categoryShares[metric
                                                          .id],
                                                  masterData: _masterData,
                                                  amount: _money(
                                                    metric,
                                                    currency,
                                                  ),
                                                  onTap: () =>
                                                      _go('/analysis?$query'),
                                                ),
                                                const SizedBox(
                                                  height:
                                                      ButlerlySpacing.compact,
                                                ),
                                                Divider(
                                                  height: 1,
                                                  thickness: 1,
                                                  color: context
                                                      .colors
                                                      .cardDivider,
                                                ),
                                                const SizedBox(
                                                  height:
                                                      ButlerlySpacing.compact,
                                                ),
                                              ],
                                            ),
                                          if (analysis?.categories
                                                  .where(
                                                    (category) =>
                                                        category.availability ==
                                                        AnalysisDataAvailability
                                                            .sufficient,
                                                  )
                                                  .isEmpty ??
                                              true)
                                            Text(
                                              context.l10n.text(
                                                'desktopNoCategoryData',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                                final budgets = SizedBox(
                                  height: _desktopHomeBreakdownCardHeight,
                                  child: _DesktopPanel(
                                    title: context.l10n.text('myBudgets'),
                                    showInnerCard: true,
                                    headerHeight:
                                        _desktopHomeBreakdownHeaderHeight,
                                    child: SizedBox(
                                      height:
                                          _desktopHomeBreakdownContentHeight -
                                          2 * ButlerlySpacing.small,
                                      child: ListView(
                                        children: [
                                          HomeBudgetsCard(
                                            key: ValueKey(
                                              'home-budgets-${current.year}-${current.month}',
                                            ),
                                            month: current,
                                            embedded: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                                return b.maxWidth >= 960
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(child: budgets),
                                          const SizedBox(width: 8),
                                          Expanded(child: left),
                                          const SizedBox(width: 8),
                                          Expanded(child: middle),
                                        ],
                                      )
                                    : b.maxWidth >= 680
                                    ? Column(
                                        children: [
                                          budgets,
                                          const SizedBox(height: 8),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: left),
                                              const SizedBox(width: 8),
                                              Expanded(child: middle),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          budgets,
                                          const SizedBox(height: 8),
                                          left,
                                          const SizedBox(height: 8),
                                          middle,
                                        ],
                                      );
                              },
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, b) {
                                final actions = _DesktopPanel(
                                  title: context.l10n.text(
                                    'desktopActionCenter',
                                  ),
                                  child: Column(
                                    children: [
                                      _DesktopAction(
                                        label: context.l10n.text('needsReview'),
                                        count: data.reviewCount,
                                        icon: Icons.fact_check_outlined,
                                        onTap: () =>
                                            _go('/review?view=needsReview'),
                                      ),
                                      _DesktopAction(
                                        label: context.l10n.text(
                                          'uncategorized',
                                        ),
                                        count:
                                            data.uncategorizedTransactionCount,
                                        icon: Icons.category_outlined,
                                        onTap: () =>
                                            _go('/review?view=uncategorized'),
                                      ),
                                      _DesktopAction(
                                        label: context.l10n.text(
                                          'possibleDuplicates',
                                        ),
                                        count: data.possibleDuplicateCount,
                                        icon: Icons.copy_outlined,
                                        onTap: () =>
                                            _go('/review?view=duplicates'),
                                      ),
                                      _DesktopAction(
                                        label: context.l10n.text(
                                          'desktopMerchantIssues',
                                        ),
                                        count: data.merchantReviewCount,
                                        icon: Icons.store_outlined,
                                        onTap: () =>
                                            _go('/review?view=overview'),
                                      ),
                                      _DesktopAction(
                                        label: context.l10n.text(
                                          'desktopImportStatement',
                                        ),
                                        icon: Icons.upload_file_outlined,
                                        onTap: () => _go('/statements'),
                                      ),
                                      _DesktopAction(
                                        label: context.l10n.text(
                                          'paymentSettlements',
                                        ),
                                        icon: Icons.payments_outlined,
                                        onTap: () =>
                                            _go('/payment-settlements'),
                                      ),
                                    ],
                                  ),
                                );
                                final recent = ButlerlyDesktopTransactionSection(
                                  title: context.l10n.text(
                                    'recentTransactions',
                                  ),
                                  trailing: TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(
                                        ButlerlyButtonTokens.minimumWidth,
                                        ButlerlyButtonTokens.height,
                                      ),
                                    ),
                                    onPressed: () => _go('/search?$query'),
                                    child: Text(context.l10n.text('viewAll')),
                                  ),
                                  transactions: data.recentTransactions
                                      .take(7)
                                      .toList(),
                                  masterData:
                                      _masterData ??
                                      const TransactionMasterData(),
                                  onTap: (transaction) => _go(
                                    '/search?ids=${Uri.encodeQueryComponent(transaction.id)}',
                                  ),
                                  emptyMessage: context.l10n.text(
                                    'noTransactions',
                                  ),
                                );
                                final insightGroups = _desktopInsightCatalog(
                                  context,
                                  insightGroupSummaries(context, data.insights),
                                );
                                final insights = _DesktopPanel(
                                  title: context.l10n.text('insights'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final group in insightGroups)
                                        _DesktopAction(
                                          label: group.title,
                                          count: group.count,
                                          icon: _desktopInsightGroupIcon(
                                            group.group,
                                          ),
                                          tintColor: _desktopInsightGroupTint(
                                            group.group,
                                          ),
                                          onTap: () => _go('/insights?$query'),
                                        ),
                                    ],
                                  ),
                                );
                                return Column(
                                  children: [
                                    recent,
                                    const SizedBox(height: 8),
                                    if (b.maxWidth >= 680)
                                      IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(child: actions),
                                            const SizedBox(width: 8),
                                            Expanded(child: insights),
                                          ],
                                        ),
                                      )
                                    else ...[
                                      actions,
                                      const SizedBox(height: 8),
                                      insights,
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Desktop category row: right-aligned amount then percentage above the share bar.
class _DesktopCategorySummaryRow extends StatelessWidget {
  const _DesktopCategorySummaryRow({
    required this.metric,
    required this.share,
    required this.masterData,
    required this.amount,
    required this.onTap,
  });

  final AnalysisMetric metric;
  final DecimalValue? share;
  final TransactionMasterData? masterData;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final categoryId = analysisCategoryId(metric);
    final label = analysisDimension(context, metric, masterData);
    final color = ButlerlyChartColors.category(categoryId);
    final percentage = share == null
        ? null
        : analysisPercentageRatio(context, share!);
    final progress = (double.tryParse(share?.toString() ?? '') ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    final theme = Theme.of(context);
    return Semantics(
      label: '$label, $amount${percentage == null ? '' : ', $percentage'}',
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DesktopCategoryLeadingIcon(metric: metric),
            const SizedBox(width: ButlerlySpacing.small),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: ButlerlySpacing.compact),
                      SizedBox(
                        width: 100,
                        child: Text(
                          amount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: ButlerlySpacing.compact),
                      SizedBox(
                        width: 52,
                        child: Text(
                          percentage ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.colors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ButlerlySpacing.micro),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ButlerlyRadius.full),
                    child: SizedBox(
                      height: 7,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: color.withValues(alpha: 0.14)),
                          FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: progress,
                            child: ColoredBox(
                              color: color.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopCategoryLeadingIcon extends StatelessWidget {
  const _DesktopCategoryLeadingIcon({required this.metric});

  final AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    final categoryId = analysisCategoryId(metric);
    if (ButlerlyCategoryIdentity.forBuiltInId(categoryId) != null) {
      return ButlerlyCategoryIcon(
        categoryId: categoryId,
        containerSize: ButlerlySize.categoryIconContainer,
        glyphSize: ButlerlySize.categoryIconGlyph,
      );
    }

    final color = ButlerlyChartColors.category(categoryId);
    return SizedBox.square(
      dimension: ButlerlySize.categoryIconContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Icon(
          Icons.category_outlined,
          color: color,
          size: ButlerlySize.categoryIconGlyph,
        ),
      ),
    );
  }
}

// Applies to colored fills only; text and icons stay fully opaque for contrast.
const double _desktopHomeTintOpacity = 0.80;
// Match device Home: the selected month is solid, other months are muted.
const double _desktopHomeActionTintOpacity = 0.18;
const TextStyle _desktopHomeCardTitleStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
);
const double _desktopHomeCardTitleTopInset = 10;
const double _desktopHomeBreakdownHeaderHeight = 32;
const double _desktopHomeBreakdownCardHeight = 280;
// A 280px panel leaves 220px for content after header and outer padding.
const double _desktopHomeBreakdownContentHeight = 220;
const double _desktopHomeTrendMaxBarHeight = 180;

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.headerHeight,
    this.showInnerCard = false,
  });
  final String title;
  final Widget child;
  final String? subtitle;
  final Widget? trailing;
  final double? headerHeight;
  // Distinct themed inner surfaces and 12px insets apply in both modes.
  final bool showInnerCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(ButlerlyRadius.card),
      ),
      padding: const EdgeInsets.fromLTRB(
        ButlerlyDesktopInnerCard.outerGutter,
        _desktopHomeCardTitleTopInset,
        ButlerlyDesktopInnerCard.outerGutter,
        ButlerlyDesktopInnerCard.outerGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: headerHeight,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: _desktopHomeCardTitleStyle.copyWith(
                          color: context.colors.primaryText,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: ButlerlySpacing.micro),
                        Text(
                          subtitle!,
                          style: ButlerlyTypography.cardSubtitle(
                            Theme.of(context).textTheme.bodySmall ??
                                const TextStyle(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (showInnerCard) ButlerlyDesktopInnerCard(child: child) else child,
        ],
      ),
    );
  }
}

class _DesktopMetric extends StatelessWidget {
  const _DesktopMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.comparison,
    this.accentColor,
    super.key,
  });

  final String title;
  final String value;
  final IconData icon;
  final AnalysisComparison? comparison;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color =
        accentColor ??
        (icon == Icons.arrow_upward
            ? const Color(0xFF009B61)
            : icon == Icons.arrow_downward
            ? const Color(0xFFE24247)
            : const Color(0xFF1769E8));
    final fill = color.withValues(alpha: _desktopHomeTintOpacity);
    final percent = comparison?.percentageChange;
    final usable =
        comparison?.availability == AnalysisDataAvailability.sufficient &&
        comparison?.baselineValue != null &&
        percent != null;
    final percentValue = usable ? double.tryParse(percent.toString()) : null;
    final comparisonText = percentValue == null
        ? context.l10n.text('comparisonUnavailable')
        : percentValue > 0
        ? '↑ ${percentValue.abs().toStringAsFixed(1)}% ${context.l10n.text('vsPreviousPeriod')}'
        : percentValue < 0
        ? '↓ ${percentValue.abs().toStringAsFixed(1)}% ${context.l10n.text('vsPreviousPeriod')}'
        : '0.0% ${context.l10n.text('vsPreviousPeriod')}';

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _desktopHomeCardTitleTopInset,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white.withValues(alpha: .20),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _desktopHomeCardTitleStyle.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  comparisonText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: percentValue == null ? Colors.white70 : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopAction extends StatelessWidget {
  const _DesktopAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.count,
    this.tintColor,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int? count;
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final tint =
        tintColor ??
        (icon == Icons.fact_check_outlined || icon == Icons.copy_outlined
            ? const Color(0xFFE64A4F)
            : icon == Icons.upload_file_outlined
            ? const Color(0xFF216FE8)
            : icon == Icons.payments_outlined
            ? const Color(0xFF159D72)
            : const Color(0xFF8560D4));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final accent = isDark ? Colors.white : tint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: tint.withValues(alpha: _desktopHomeActionTintOpacity),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: foreground,
                    ),
                  ),
                ),
                if (count != null && count! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 17, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTrend extends StatelessWidget {
  const _DesktopTrend({
    required this.points,
    required this.selectedMonth,
    required this.currency,
    required this.onTap,
  });

  final List<MonthlySpendingTrendPoint> points;
  final DateTime selectedMonth;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final values = points
        .map(
          (point) =>
              double.tryParse(point.spending?.value.toString() ?? '') ?? 0.0,
        )
        .toList();
    final max = values.fold<double>(0, (a, b) => a > b ? a : b);
    if (points.isEmpty || max <= 0) {
      return Center(child: Text(context.l10n.text('desktopNoSpendingTrend')));
    }

    const gridInterval = 1000.0;
    final roundedMaximum = (max / gridInterval).ceil();
    final chartMaximum =
        (roundedMaximum < 4 ? 4 : roundedMaximum) * gridInterval;
    final gridLevels = (chartMaximum / gridInterval).toInt() + 1;
    final gridColor = context.colors.cardDivider;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatter = NumberFormat.compact(locale: locale);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: SizedBox(
              height: _desktopHomeTrendMaxBarHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < gridLevels; i++)
                    Text(
                      formatter.format(chartMaximum - i * gridInterval),
                      style: ButlerlyTypography.badgeLabel(
                        Theme.of(context).textTheme.bodySmall ??
                            const TextStyle(),
                      ).copyWith(color: context.colors.secondaryText),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: ButlerlySpacing.compact),
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  height: _desktopHomeTrendMaxBarHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < gridLevels; i++)
                        Container(height: 1, color: gridColor),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < points.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Tooltip(
                                message: NumberFormat.simpleCurrency(
                                  name: currency,
                                ).format(values[i]),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    widthFactor: 0.6,
                                    child: Container(
                                      height:
                                          _desktopHomeTrendMaxBarHeight *
                                          values[i] /
                                          chartMaximum,
                                      decoration: BoxDecoration(
                                        color: context.colors.interactive.withValues(
                                          alpha:
                                              points[i].month.year ==
                                                      selectedMonth.year &&
                                                  points[i].month.month ==
                                                      selectedMonth.month
                                              ? 1.0
                                              : 0.72,
                                        ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(5),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat.MMM(
                                  locale,
                                ).format(points[i].month).toUpperCase(),
                                textAlign: TextAlign.center,
                                style:
                                    ButlerlyTypography.badgeLabel(
                                      Theme.of(context).textTheme.bodySmall ??
                                          const TextStyle(),
                                    ).copyWith(
                                      color:
                                          points[i].month.year ==
                                                  selectedMonth.year &&
                                              points[i].month.month ==
                                                  selectedMonth.month
                                          ? context.colors.interactive
                                          : null,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Keep six standard Insights sections visible even with no findings.
/// Less-common sections appear when they have actual findings.
const _desktopDefaultInsightGroups = <InsightPresentationGroup>{
  InsightPresentationGroup.unusual,
  InsightPresentationGroup.largePurchase,
  InsightPresentationGroup.category,
  InsightPresentationGroup.subcategory,
  InsightPresentationGroup.merchant,
  InsightPresentationGroup.paymentSource,
};

List<InsightGroupSummary> _desktopInsightCatalog(
  BuildContext context,
  List<InsightGroupSummary> available,
) {
  final byGroup = <InsightPresentationGroup, InsightGroupSummary>{
    for (final item in available) item.group: item,
  };
  return [
    for (final group in insightPresentationGroupOrder)
      if (_desktopDefaultInsightGroups.contains(group) ||
          byGroup.containsKey(group))
        byGroup[group] ??
            InsightGroupSummary(
              group: group,
              title: _desktopEmptyInsightTitle(context, group),
              count: 0,
            ),
  ];
}

String _desktopEmptyInsightTitle(
  BuildContext context,
  InsightPresentationGroup group,
) => switch (group) {
  InsightPresentationGroup.unusual => context.l10n.text('needsAttention'),
  InsightPresentationGroup.largePurchase => context.l10n.text(
    'analysis.rule.r025.name',
  ),
  InsightPresentationGroup.category => context.l10n.text('categories'),
  InsightPresentationGroup.subcategory => context.l10n.text('subcategories'),
  InsightPresentationGroup.tag => context.l10n.text('tags'),
  InsightPresentationGroup.merchant => context.l10n.text('merchant'),
  InsightPresentationGroup.paymentSource => context.l10n.text('paymentSources'),
  InsightPresentationGroup.other => context.l10n.text('otherInsights'),
};

IconData _desktopInsightGroupIcon(InsightPresentationGroup group) =>
    switch (group) {
      InsightPresentationGroup.unusual => Icons.priority_high,
      InsightPresentationGroup.largePurchase => Icons.shopping_bag_outlined,
      InsightPresentationGroup.category => Icons.category_outlined,
      InsightPresentationGroup.subcategory => Icons.account_tree_outlined,
      InsightPresentationGroup.tag => Icons.sell_outlined,
      InsightPresentationGroup.merchant => Icons.storefront_outlined,
      InsightPresentationGroup.paymentSource => Icons.credit_card_outlined,
      InsightPresentationGroup.other => Icons.insights_outlined,
    };

Color _desktopInsightGroupTint(InsightPresentationGroup group) =>
    switch (group) {
      InsightPresentationGroup.unusual => const Color(0xFFE64A4F),
      InsightPresentationGroup.largePurchase => const Color(0xFFC65D00),
      InsightPresentationGroup.category => const Color(0xFF8560D4),
      InsightPresentationGroup.subcategory => const Color(0xFF2878B5),
      InsightPresentationGroup.tag => const Color(0xFF007C83),
      InsightPresentationGroup.merchant => const Color(0xFF8A6411),
      InsightPresentationGroup.paymentSource => const Color(0xFF216FE8),
      InsightPresentationGroup.other => const Color(0xFF8560D4),
    };
