import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _moveMonth(-1, current),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showButlerlyDatePicker(
                        context: context,
                        title: 'Select month',
                        cancelLabel: 'Cancel',
                        doneLabel: 'Apply',
                        initialDate: current,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
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
                    tooltip: 'Next month',
                    onPressed: () => _moveMonth(1, current),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      onPressed: () => _go('/search'),
                      icon: const Icon(Icons.search),
                      label: const Text('Search transactions'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _go('/transactions/add'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                    final left = _DesktopPanel(
                      title: 'Spending Trend',
                      trailing: DropdownButton<int>(
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
                    );
                    final middle = _DesktopPanel(
                      title: 'Category Breakdown',
                      trailing: TextButton(
                        onPressed: () => _go('/analysis?$query'),
                        child: const Text('View all →'),
                      ),
                      child: SizedBox(
                        height: 160,
                        child: ListView(
                          children: [
                            for (final metric
                                in analysis?.categories.take(6) ??
                                    <AnalysisMetric>[])
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  metric.rule.nameKey,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(_money(metric, currency)),
                                onTap: () => _go('/analysis?$query'),
                              ),
                            if (analysis?.categories.isEmpty ?? true)
                              const Text('No category data for this period'),
                          ],
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
                            children: [left, const SizedBox(height: 8), middle],
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
                            onTap: () => _go('/review?view=uncategorized'),
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
                        onPressed: () => _go('/search?$query'),
                        child: const Text('View all →'),
                      ),
                      child: Column(
                        children: [
                          for (final transaction
                              in data.recentTransactions.take(7))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                transaction.description ??
                                    transaction.rawCounterparty ??
                                    'Transaction',
                              ),
                              subtitle: Text(
                                transaction.transactionDate ??
                                    transaction.currency,
                              ),
                              trailing: Text(
                                '${transaction.direction == 'income' ? '+' : '−'}${transaction.amount} ${transaction.currency}',
                              ),
                              onTap: () => _go(
                                '/search?ids=${Uri.encodeQueryComponent(transaction.id)}',
                              ),
                            ),
                          if (data.recentTransactions.isEmpty)
                            const Text('No recent transactions'),
                        ],
                      ),
                    );
                    final insights = _DesktopPanel(
                      title: 'Insights',
                      trailing: TextButton(
                        onPressed: () => _go('/insights?$query'),
                        child: const Text('View all →'),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.insights.isEmpty
                                ? 'No insights for this period'
                                : 'You have ${data.insights.length} insight${data.insights.length == 1 ? '' : 's'} to explore.',
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _go('/insights?$query'),
                            icon: const Icon(Icons.insights),
                            label: const Text('Explore insights'),
                          ),
                        ],
                      ),
                    );
                    return Column(
                      children: [
                        if (b.maxWidth >= 680)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: recent),
                              const SizedBox(width: 8),
                              Expanded(child: actions),
                            ],
                          )
                        else ...[
                          recent,
                          const SizedBox(height: 8),
                          actions,
                        ],
                        const SizedBox(height: 8),
                        insights,
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF6F8FB) : const Color(0xFF14213E);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF171B21) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? const Color(0xFF2A3039) : const Color(0xFFE4EAF4),
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0B17325C),
                  blurRadius: 20,
                  offset: Offset(0, 5),
                ),
              ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = title == 'Income'
        ? const Color(0xFF009B61)
        : title == 'Expenses'
        ? const Color(0xFFE24247)
        : const Color(0xFF1769E8);
    final fill = dark
        ? color.withValues(alpha: .12)
        : color.withValues(alpha: .055);
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
        border: Border.all(color: color.withValues(alpha: dark ? .40 : .17)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color, size: 22),
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
                      color: dark ? color.withValues(alpha: .9) : color,
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
                    color: percentValue == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : color,
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
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = label == 'Needs review' || label == 'Possible duplicates'
        ? const Color(0xFFE64A4F)
        : label == 'Import statement'
        ? const Color(0xFF216FE8)
        : label == 'Payment settlements'
        ? const Color(0xFF159D72)
        : const Color(0xFF8560D4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: tint.withValues(alpha: dark ? .10 : .06),
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
                    color: tint.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: tint),
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
                      color: tint.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: tint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 17, color: tint),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .75),
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
