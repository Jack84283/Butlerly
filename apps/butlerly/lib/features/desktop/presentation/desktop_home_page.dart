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
            padding: const EdgeInsets.all(24),
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
                    width: 270,
                    child: OutlinedButton.icon(
                      onPressed: () => _go('/search'),
                      icon: const Icon(Icons.search),
                      label: const Text('Search transactions'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _go('/transactions/add'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Financial overview', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                DateFormat.yMMMM().format(current),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
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
                          tint: Colors.green,
                          onTap: () => _go('/search?$query&direction=income'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _DesktopMetric(
                          title: 'Expenses',
                          value: _money(analysis?.spending, currency),
                          icon: Icons.arrow_downward,
                          tint: Colors.red,
                          onTap: () => _go('/search?$query&direction=expense'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _DesktopMetric(
                          title: 'Net cash flow',
                          value: _money(analysis?.net, currency),
                          icon: Icons.show_chart,
                          tint: Colors.blue,
                          onTap: () => _go('/analysis?$query'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, b) {
                    final left = _DesktopPanel(
                      title: 'Spending trend',
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
                        height: 190,
                        child: _DesktopTrend(
                          points: data.monthlyTrend,
                          currency: currency,
                          onTap: () => _go('/analysis?$query'),
                        ),
                      ),
                    );
                    final middle = _DesktopPanel(
                      title: 'Spending by category',
                      trailing: TextButton(
                        onPressed: () => _go('/analysis?$query'),
                        child: const Text('View all →'),
                      ),
                      child: SizedBox(
                        height: 190,
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
                    return b.maxWidth >= 1050
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: left),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: middle),
                            ],
                          )
                        : Column(
                            children: [
                              left,
                              const SizedBox(height: 16),
                              middle,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, b) {
                    final actions = _DesktopPanel(
                      title: 'Action center',
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
                      title: 'Recent transactions',
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
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _go('/insights?$query'),
                            icon: const Icon(Icons.insights),
                            label: const Text('Explore insights'),
                          ),
                        ],
                      ),
                    );
                    if (b.maxWidth >= 1160) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: actions),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: recent),
                          const SizedBox(width: 16),
                          Expanded(flex: 3, child: insights),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        actions,
                        const SizedBox(height: 16),
                        recent,
                        const SizedBox(height: 16),
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _DesktopMetric extends StatelessWidget {
  const _DesktopMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: tint.withValues(alpha: .12),
              child: Icon(icon, color: tint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('$count'),
          ),
        const Icon(Icons.chevron_right, size: 16),
      ],
    ),
    onTap: onTap,
  );
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
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: NumberFormat.simpleCurrency(
                        name: currency,
                      ).format(values[i]),
                      child: Container(
                        height: 135 * values[i] / max,
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
                    const SizedBox(height: 8),
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
