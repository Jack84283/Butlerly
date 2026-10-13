import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_category_icon.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
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
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _overview;
          },
          child: ListView(
            key: const ValueKey('desktop-home-page'),
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                ),
                child: Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        minimumSize: const Size(34, 32),
                      ),
                      tooltip: 'Previous month',
                      onPressed: () => _moveMonth(-1, current),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: () async {
                        final picked = await _selectDesktopMonth(
                          context,
                          current,
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _month = DateTime(picked.year, picked.month);
                            _reload();
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(DateFormat.yMMMM().format(current)),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        minimumSize: const Size(34, 32),
                      ),
                      tooltip: 'Next month',
                      onPressed: () => _moveMonth(1, current),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const Spacer(),
                    Text(
                      _desktopGreeting(DateTime.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
                          minimumSize: const Size(0, 32),
                        ),
                        onPressed: () => _go('/search'),
                        icon: const Icon(Icons.search),
                        label: const Text('Search transactions'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _go('/transactions/add'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ),
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
                      'Financial overview',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.yMMMM().format(current),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    if (snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator(),
                    if (unavailable)
                      _DesktopPanel(
                        title: 'Overview unavailable',
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Local financial data is currently unavailable. Your records are preserved.',
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(0, 32),
                              ),
                              onPressed: () => setState(_reload),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    if (!unavailable) ...[
                      LayoutBuilder(
                        builder: (context, bounds) => Row(
                          children: [
                            Expanded(
                              child: _DesktopMetric(
                                title: 'Income',
                                value: _money(analysis?.income, currency),
                                icon: Icons.arrow_upward,
                                comparison: analysis?.incomeComparison,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DesktopMetric(
                                title: 'Expenses',
                                value: _money(analysis?.spending, currency),
                                icon: Icons.arrow_downward,
                                comparison: analysis?.spendingComparison,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DesktopMetric(
                                title: 'Net cash flow',
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
                              title: 'Spending Trend',
                              headerHeight: _desktopHomeBreakdownHeaderHeight,
                              trailing: DropdownButton<int>(
                                isDense: true,
                                value: _trendMonths,
                                underline: const SizedBox.shrink(),
                                items: const [3, 6, 12]
                                    .map(
                                      (n) => DropdownMenuItem(
                                        value: n,
                                        child: Text('$n months'),
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
                                height: 160,
                                child: _DesktopTrend(
                                  points: data.monthlyTrend,
                                  currency: currency,
                                  onTap: () => _go('/analysis?$query'),
                                ),
                              ),
                            ),
                          );
                          final middle = SizedBox(
                            height: _desktopHomeBreakdownCardHeight,
                            child: _DesktopPanel(
                              title: 'Category Breakdown',
                              headerHeight: _desktopHomeBreakdownHeaderHeight,
                              trailing: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 32),
                                ),
                                onPressed: () => _go('/analysis?$query'),
                                child: const Text('View all →'),
                              ),
                              child: SizedBox(
                                height: 160,
                                child: ListView(
                                  children: [
                                    for (final metric
                                        in analysis?.categories
                                                .where(
                                                  (category) =>
                                                      category.availability ==
                                                      AnalysisDataAvailability
                                                          .sufficient,
                                                )
                                                .take(6) ??
                                            <AnalysisMetric>[])
                                      Column(
                                        children: [
                                          ListTile(
                                            leading:
                                                _DesktopCategoryLeadingIcon(
                                                  metric: metric,
                                                ),
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              analysisDimension(
                                                context,
                                                metric,
                                                _masterData,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: Text(
                                              _money(metric, currency),
                                            ),
                                            onTap: () =>
                                                _go('/analysis?$query'),
                                          ),
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? const Color(0xFF555B63)
                                                : const Color(0xFFD8DDE6),
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
                                      const Text(
                                        'No category data for this period',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          return b.maxWidth >= 680
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: left),
                                    const SizedBox(width: 8),
                                    Expanded(child: middle),
                                  ],
                                )
                              : Column(
                                  children: [
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
                            title: 'Action Center',
                            child: Column(
                              children: [
                                _DesktopAction(
                                  label: 'Needs review',
                                  count: data.reviewCount,
                                  icon: Icons.fact_check_outlined,
                                  onTap: () => _go('/review?view=needsReview'),
                                ),
                                _DesktopAction(
                                  label: 'Uncategorized',
                                  count: data.uncategorizedTransactionCount,
                                  icon: Icons.category_outlined,
                                  onTap: () =>
                                      _go('/review?view=uncategorized'),
                                ),
                                _DesktopAction(
                                  label: 'Possible duplicates',
                                  count: data.possibleDuplicateCount,
                                  icon: Icons.copy_outlined,
                                  onTap: () => _go('/review?view=duplicates'),
                                ),
                                _DesktopAction(
                                  label: 'Merchant issues',
                                  count: data.merchantReviewCount,
                                  icon: Icons.store_outlined,
                                  onTap: () => _go('/review?view=overview'),
                                ),
                                _DesktopAction(
                                  label: 'Import statement',
                                  icon: Icons.upload_file_outlined,
                                  onTap: () => _go('/statements'),
                                ),
                                _DesktopAction(
                                  label: 'Payment settlements',
                                  icon: Icons.payments_outlined,
                                  onTap: () => _go('/payment-settlements'),
                                ),
                              ],
                            ),
                          );
                          final recent = _DesktopPanel(
                            title: 'Recent Transactions',
                            trailing: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(0, 32),
                              ),
                              onPressed: () => _go('/search?$query'),
                              child: const Text('View all →'),
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        'Date',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Merchant',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Category',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Subcategory',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Payment source',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 112,
                                      child: Text(
                                        'Amount',
                                        textAlign: TextAlign.right,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 12),
                                for (final transaction
                                    in data.recentTransactions.take(7))
                                  Column(
                                    children: [
                                      InkWell(
                                        onTap: () => _go(
                                          '/search?ids=${Uri.encodeQueryComponent(transaction.id)}',
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 100,
                                                child: Text(
                                                  _desktopTransactionDate(
                                                    context,
                                                    transaction,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  _masterData?.merchantName(
                                                        transaction.merchantId,
                                                      ) ??
                                                      transaction
                                                          .rawCounterparty ??
                                                      transaction.description ??
                                                      'Transaction',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _desktopCategoryBadgeColor(
                                                            transaction
                                                                .categoryId,
                                                            context,
                                                          ).withValues(
                                                            alpha:
                                                                _desktopHomeTintOpacity,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            100,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      _masterData?.categoryName(
                                                            transaction
                                                                .categoryId,
                                                          ) ??
                                                          (transaction.categoryId ==
                                                                  null
                                                              ? 'Uncategorized'
                                                              : 'Category unavailable'),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _masterData?.subcategoryName(
                                                        transaction
                                                            .subcategoryId,
                                                      ) ??
                                                      '—',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _masterData?.paymentSourceName(
                                                        transaction
                                                            .paymentSourceId,
                                                      ) ??
                                                      '—',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 112,
                                                child: Text(
                                                  _desktopTransactionAmount(
                                                    context,
                                                    transaction,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Divider(
                                        height: 1,
                                        thickness: 1,
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF555B63)
                                            : const Color(0xFFD8DDE6),
                                      ),
                                    ],
                                  ),
                                if (data.recentTransactions.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Text('No recent transactions'),
                                  ),
                              ],
                            ),
                          );
                          final insightGroups = insightGroupSummaries(
                            context,
                            data.insights,
                          );
                          final insights = _DesktopPanel(
                            title: 'Insights',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final group in insightGroups)
                                  _DesktopAction(
                                    label: group.title,
                                    count: group.count,
                                    icon: _desktopInsightGroupIcon(group.group),
                                    tintColor: _desktopInsightGroupTint(
                                      group.group,
                                    ),
                                    onTap: () => _go('/insights?$query'),
                                  ),
                                if (insightGroups.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      data.analysisUnavailable
                                          ? 'Insights unavailable for this period'
                                          : 'No insights for this period',
                                    ),
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
        );
      },
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

    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: ButlerlySize.categoryIconContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.category_outlined,
          color: scheme.onSurfaceVariant,
          size: ButlerlySize.categoryIconGlyph,
        ),
      ),
    );
  }
}

const double _desktopHomeTintOpacity = 0.80;
const double _desktopHomeCardTitleTopInset = 10;
const double _desktopHomeBreakdownHeaderHeight = 32;
const double _desktopHomeBreakdownCardHeight = 220;

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    required this.title,
    required this.child,
    this.trailing,
    this.headerHeight,
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  final double? headerHeight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF6F8FB) : const Color(0xFF14213E);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF292D33) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(
        10,
        _desktopHomeCardTitleTopInset,
        10,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: headerHeight,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: 8),
          child,
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
  });

  final String title;
  final String value;
  final IconData icon;
  final AnalysisComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final color = title == 'Income'
        ? const Color(0xFF009B61)
        : title == 'Expenses'
        ? const Color(0xFFE24247)
        : const Color(0xFF1769E8);
    final fill = color.withValues(alpha: _desktopHomeTintOpacity);
    final percent = comparison?.percentageChange;
    final usable =
        comparison?.availability == AnalysisDataAvailability.sufficient &&
        comparison?.baselineValue != null &&
        percent != null;
    final percentValue = usable ? double.tryParse(percent.toString()) : null;
    final comparisonText = percentValue == null
        ? 'Change unavailable'
        : percentValue > 0
        ? '↑ ${percentValue.abs().toStringAsFixed(1)}% vs previous period'
        : percentValue < 0
        ? '↓ ${percentValue.abs().toStringAsFixed(1)}% vs previous period'
        : '0.0% vs previous period';

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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
        (label == 'Needs review' || label == 'Possible duplicates'
            ? const Color(0xFFE64A4F)
            : label == 'Import statement'
            ? const Color(0xFF216FE8)
            : label == 'Payment settlements'
            ? const Color(0xFF159D72)
            : const Color(0xFF8560D4));
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: tint.withValues(alpha: _desktopHomeTintOpacity),
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
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.white,
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
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 17, color: Colors.white),
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
    required this.currency,
    required this.onTap,
  });
  final List<MonthlySpendingTrendPoint> points;
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
      return const Center(child: Text('No spending trend available'));
    }
    return InkWell(
      onTap: onTap,
      child: Row(
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
                      child: Container(
                        height: 120 * values[i] / max,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: _desktopHomeTintOpacity),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.MMM().format(points[i].month),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<DateTime?> _selectDesktopMonth(BuildContext context, DateTime selected) {
  var year = selected.year;
  var month = selected.month;
  return showButlerlyBottomSheet<DateTime>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, update) => ButlerlySheet(
        title: Row(
          children: [
            const Expanded(child: Text('Select month')),
            IconButton(
              style: IconButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(34, 32),
              ),
              tooltip: 'Previous year',
              icon: const Icon(Icons.chevron_left),
              onPressed: year > 2000 ? () => update(() => year--) : null,
            ),
            Text('$year'),
            IconButton(
              style: IconButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(34, 32),
              ),
              tooltip: 'Next year',
              icon: const Icon(Icons.chevron_right),
              onPressed: year < 2100 ? () => update(() => year++) : null,
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final candidate = index + 1;
              return OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  minimumSize: const Size(0, 30),
                  backgroundColor: candidate == month
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.transparent,
                ),
                onPressed: () => update(() => month = candidate),
                child: Text(DateFormat.MMM().format(DateTime(year, candidate))),
              );
            },
          ),
        ),
        actions: [
          ButlerlyCancelButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () => Navigator.pop(sheetContext, DateTime(year, month)),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  );
}

String _desktopTransactionDate(
  BuildContext context,
  TransactionDto transaction,
) {
  final date =
      transaction.financialDate ??
      DateTime.tryParse(transaction.transactionDate ?? '') ??
      transaction.occurredAt;
  if (date == null) return '—';
  return DateFormat.yMd(
    Localizations.localeOf(context).toString(),
  ).format(date);
}

String _desktopTransactionAmount(
  BuildContext context,
  TransactionDto transaction,
) {
  final amount = double.tryParse(transaction.amount);
  if (amount == null) return '—';
  final formatted = NumberFormat.simpleCurrency(
    name: transaction.currency,
    locale: Localizations.localeOf(context).toString(),
  ).format(amount.abs());
  return '${transaction.direction == 'income' ? '+' : '−'}$formatted';
}

Color _desktopCategoryBadgeColor(String? categoryId, BuildContext context) {
  final identity = categoryId == null
      ? null
      : ButlerlyCategoryIdentity.forBuiltInId(categoryId);
  if (identity != null) {
    return ButlerlyCategoryColors.color(identity.categoryColorId);
  }
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

String _desktopGreeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

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
