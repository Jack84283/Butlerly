import 'dart:math' as math;

import 'package:butlerly/app/locale/home_greeting.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
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
import 'package:butlerly/l10n/finance_formatters.dart';
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

  void _reload({bool forceAnalysisRefresh = false}) {
    _overview = _load(forceAnalysisRefresh: forceAnalysisRefresh);
  }

  void _retry() {
    if (!mounted) return;
    setState(() => _reload(forceAnalysisRefresh: true));
  }

  Future<HomeOverview?> _load({bool forceAnalysisRefresh = false}) async {
    final load = _finance?.loadHomeOverview;
    if (load == null) return null;
    try {
      final result = await load(
        instant: DateTime.now(),
        selectedMonth: _month,
        forceAnalysisRefresh: forceAnalysisRefresh,
        trendMonthCount: _trendMonths,
      );
      if (result is ApplicationSuccess<HomeOverview>) return result.value;
    } catch (_) {
      // The failure is presented locally without changing device UI state.
    }
    return null;
  }

  void _moveMonth(int delta, DateTime current, DateTime currentFinancialMonth) {
    final next = DateTime(current.year, current.month + delta);
    if (delta > 0 && _isAfterMonth(next, currentFinancialMonth)) return;
    setState(() {
      _month = next;
      _reload();
    });
  }

  Future<void> _selectMonth(
    DateTime current,
    DateTime currentFinancialMonth,
  ) async {
    final picked = await showButlerlyMonthPicker(
      context,
      selectedMonth: current,
      currentMonth: currentFinancialMonth,
    );
    if (picked != null && mounted) {
      setState(() {
        _month = DateTime(picked.year, picked.month);
        _reload();
      });
    }
  }

  String _money(AnalysisMetric? metric, String currency) {
    if (metric == null) {
      return '—';
    }
    final value = metric.availability == AnalysisDataAvailability.empty
        ? 0
        : metric.availability == AnalysisDataAvailability.sufficient
        ? double.tryParse(metric.value.toString())
        : null;
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

  String _analysisRoute(HomeOverview data, {required String path}) {
    final period = data.context?.period;
    final displayMonth = data.displayMonth;
    final currentFinancialMonth = data.currentFinancialMonth;
    if (period == null ||
        displayMonth == null ||
        currentFinancialMonth == null ||
        _sameMonth(displayMonth, currentFinancialMonth)) {
      return path;
    }
    final start = DateTime.parse(period.startDate);
    return Uri(
      path: path,
      queryParameters: {
        'month':
            '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}',
      },
    ).toString();
  }

  String _searchRoute(HomeOverview data) {
    final period = data.context?.period;
    if (period == null) return '/search';
    return Uri(
      path: '/search',
      queryParameters: {
        'from': period.startDate,
        'to': period.endDate,
        'timeZoneId': period.timeZoneId,
      },
    ).toString();
  }

  String _reviewRoute(HomeOverview data, {required String view}) {
    final period = data.context?.period;
    if (period == null) {
      return Uri(path: '/review', queryParameters: {'view': view}).toString();
    }
    return Uri(
      path: '/review',
      queryParameters: {
        'view': view,
        'from': period.startDate,
        'to': period.endDate,
        'timeZoneId': period.timeZoneId,
      },
    ).toString();
  }

  void _go(String path) => context.push(path);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<HomeOverview?>(
      future: _overview,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        final displayData = data ?? const HomeOverview.periodUnavailable();
        final current = data?.displayMonth ?? _month ?? DateTime.now();
        final currentFinancialMonth = _monthStart(
          data?.currentFinancialMonth ?? DateTime.now(),
        );
        final currency = data?.context?.baseCurrency?.value ?? 'USD';
        final analysis = displayData.analysis;
        final overviewUnavailable =
            !loading &&
            (data == null || data.status != HomeOverviewStatus.available);
        final analysisUnavailable =
            !loading && data?.analysisUnavailable == true;
        final cardUnavailable =
            !loading && (overviewUnavailable || analysisUnavailable);
        final trendUnavailable =
            !loading &&
            (cardUnavailable || data?.monthlyTrendUnavailable == true);
        final duplicateUnavailable =
            !loading && data?.duplicateUnavailable == true;
        final reviewUnavailable = !loading && data?.reviewUnavailable == true;
        final analysisUnavailableBody = context.l10n.text(
          'analysisUnavailableBody',
        );
        final unavailableTitleKey =
            data?.status == HomeOverviewStatus.transactionsUnavailable
            ? 'homeTransactionsUnavailable'
            : 'homeUnavailable';
        final unavailableBodyKey =
            data?.status == HomeOverviewStatus.transactionsUnavailable
            ? 'homeTransactionsUnavailableBody'
            : 'homeUnavailableBody';
        final unavailableBody = data == null
            ? context.l10n.text('desktopLocalDataUnavailable')
            : context.l10n.text(unavailableBodyKey);
        final cardUnavailableBody = overviewUnavailable
            ? unavailableBody
            : analysisUnavailableBody;
        final canUsePeriodControls =
            !loading &&
            data?.context?.period != null &&
            data?.displayMonth != null &&
            data?.currentFinancialMonth != null;
        final canOpenPeriod = canUsePeriodControls && !overviewUnavailable;
        final analysisRoute = _analysisRoute(displayData, path: '/analysis');
        final insightsRoute = _analysisRoute(displayData, path: '/insights');
        final searchRoute = _searchRoute(displayData);
        final canOpenAnalysis = canOpenPeriod && !analysisUnavailable;
        final monthLabel = DateFormat.yMMMM(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(current);
        final canMoveNext =
            canUsePeriodControls &&
            !_isAfterMonth(
              DateTime(current.year, current.month + 1),
              currentFinancialMonth,
            );
        final largeTextToolbar =
            MediaQuery.textScalerOf(context).scale(14) >= 21;
        return Column(
          children: [
            Container(
              key: const ValueKey('desktop-home-header'),
              padding: const EdgeInsets.symmetric(
                horizontal: ButlerlySize.contentGutter,
              ),
              constraints: largeTextToolbar
                  ? const BoxConstraints(
                      minHeight: ButlerlySize.pageToolbarHeight,
                    )
                  : const BoxConstraints(
                      minHeight: ButlerlySize.pageToolbarHeight,
                      maxHeight: ButlerlySize.pageToolbarHeight,
                    ),
              decoration: BoxDecoration(
                color: context.colors.background,
                border: Border(
                  bottom: BorderSide(color: context.colors.cardDivider),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // At the narrow end of the wide shell, or with large text,
                  // icon-only actions preserve the toolbar's touch targets.
                  final compactToolbar =
                      constraints.maxWidth < 760 || largeTextToolbar;
                  return Row(
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
                        onPressed: canUsePeriodControls
                            ? () =>
                                  _moveMonth(-1, current, currentFinancialMonth)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      if (compactToolbar)
                        IconButton(
                          key: const ValueKey('desktop-home-month-selector'),
                          tooltip: monthLabel,
                          onPressed: canUsePeriodControls
                              ? () =>
                                    _selectMonth(current, currentFinancialMonth)
                              : null,
                          icon: const Icon(Icons.calendar_month_outlined),
                        )
                      else
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
                          onPressed: canUsePeriodControls
                              ? () =>
                                    _selectMonth(current, currentFinancialMonth)
                              : null,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(monthLabel),
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
                        onPressed: canMoveNext
                            ? () =>
                                  _moveMonth(1, current, currentFinancialMonth)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      const SizedBox(width: 8),
                      if (compactToolbar)
                        IconButton(
                          tooltip: context.l10n.text(
                            'desktopSearchTransactions',
                          ),
                          onPressed: () => _go('/search'),
                          icon: const Icon(Icons.search),
                        )
                      else
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
                      if (!compactToolbar) const SizedBox(width: 8),
                      if (compactToolbar)
                        IconButton(
                          tooltip: context.l10n.text('add'),
                          onPressed: () => _go('/transactions/add'),
                          icon: const Icon(Icons.add),
                        )
                      else
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
                  );
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _retry();
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
                          if (loading) const LinearProgressIndicator(),
                          if (overviewUnavailable)
                            _DesktopPanel(
                              key: const ValueKey(
                                'desktop-home-unavailable-card',
                              ),
                              title: context.l10n.text(unavailableTitleKey),
                              child: _DesktopUnavailableContent(
                                body: unavailableBody,
                                semanticsKey: const ValueKey(
                                  'desktop-home-unavailable-content',
                                ),
                                onRetry: _retry,
                              ),
                            ),
                          _DesktopPanel(
                            key: const ValueKey('desktop-home-summary-card'),
                            title: context.l10n.text('monthlySummary'),
                            subtitle: context.l10n.text('vsPreviousPeriod'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
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
                                        comparison:
                                            analysis?.spendingComparison,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _DesktopMetric(
                                        key: const ValueKey(
                                          'desktop-home-summary-transactions',
                                        ),
                                        title: context.l10n.text(
                                          'transactions',
                                        ),
                                        value: _transactionCount(
                                          analysis?.transactionCount,
                                        ),
                                        icon: Icons.receipt_long_outlined,
                                        comparison: analysis
                                            ?.transactionCountComparison,
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
                                        value: _money(
                                          analysis?.income,
                                          currency,
                                        ),
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
                                if (loading) ...[
                                  const SizedBox(height: 8),
                                  const _DesktopLoadingContent(),
                                ] else if (cardUnavailable) ...[
                                  const SizedBox(height: 8),
                                  _DesktopUnavailableContent(
                                    body: cardUnavailableBody,
                                    onRetry: analysisUnavailable
                                        ? _retry
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, b) {
                              final availableCategories =
                                  analysis?.categories
                                      .where(
                                        (category) =>
                                            category.availability ==
                                            AnalysisDataAvailability.sufficient,
                                      )
                                      .take(6)
                                      .toList(growable: false) ??
                                  const <AnalysisMetric>[];
                              final unavailableCategories =
                                  analysis?.categories
                                      .where(
                                        (category) =>
                                            category.availability !=
                                            AnalysisDataAvailability.sufficient,
                                      )
                                      .take(6)
                                      .toList(growable: false) ??
                                  const <AnalysisMetric>[];
                              final left = ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: _desktopHomeBreakdownCardHeight,
                                ),
                                child: _DesktopPanel(
                                  key: const ValueKey(
                                    'desktop-home-trend-card',
                                  ),
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
                                    onChanged: loading || trendUnavailable
                                        ? null
                                        : (n) {
                                            if (n != null) {
                                              setState(() {
                                                _trendMonths = n;
                                                _reload();
                                              });
                                            }
                                          },
                                  ),
                                  child: loading
                                      ? const _DesktopLoadingContent()
                                      : trendUnavailable
                                      ? _DesktopUnavailableContent(
                                          body: cardUnavailableBody,
                                          onRetry:
                                              data?.monthlyTrendUnavailable ==
                                                      true &&
                                                  !overviewUnavailable &&
                                                  !analysisUnavailable
                                              ? _retry
                                              : null,
                                        )
                                      : _DesktopTrend(
                                          points: displayData.monthlyTrend,
                                          selectedMonth: current,
                                          currency: currency,
                                          onTap: canOpenAnalysis
                                              ? () => _go(analysisRoute)
                                              : null,
                                        ),
                                ),
                              );
                              final middle = ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: _desktopHomeBreakdownCardHeight,
                                ),
                                child: _DesktopPanel(
                                  key: const ValueKey(
                                    'desktop-home-category-card',
                                  ),
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
                                    onPressed: canOpenAnalysis
                                        ? () => _go(analysisRoute)
                                        : null,
                                    child: Text(context.l10n.text('viewAll')),
                                  ),
                                  child: loading
                                      ? const _DesktopLoadingContent()
                                      : cardUnavailable
                                      ? _DesktopUnavailableContent(
                                          body: cardUnavailableBody,
                                        )
                                      : SizedBox(
                                          // Reserve the 12px inset within the 280px outer card.
                                          height:
                                              _desktopHomeBreakdownContentHeight -
                                              2 * ButlerlySpacing.small,
                                          child:
                                              availableCategories.isEmpty &&
                                                  unavailableCategories.isEmpty
                                              ? Center(
                                                  child: Text(
                                                    context.l10n.text(
                                                      'desktopNoCategoryData',
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                )
                                              : ListView(
                                                  children: [
                                                    for (final metric
                                                        in availableCategories)
                                                      Column(
                                                        children: [
                                                          _DesktopCategorySummaryRow(
                                                            metric: metric,
                                                            share:
                                                                analysis
                                                                    ?.categoryShares[metric
                                                                    .id],
                                                            masterData:
                                                                _masterData,
                                                            amount: _money(
                                                              metric,
                                                              currency,
                                                            ),
                                                            onTap: () => _go(
                                                              analysisRoute,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height:
                                                                ButlerlySpacing
                                                                    .compact,
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
                                                                ButlerlySpacing
                                                                    .compact,
                                                          ),
                                                        ],
                                                      ),
                                                    if (unavailableCategories
                                                        .isNotEmpty)
                                                      _DesktopUnavailableCategoryList(
                                                        categories:
                                                            unavailableCategories,
                                                        masterData: _masterData,
                                                      ),
                                                  ],
                                                ),
                                        ),
                                ),
                              );
                              final budgets = ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: _desktopHomeBreakdownCardHeight,
                                ),
                                child: _DesktopPanel(
                                  key: const ValueKey(
                                    'desktop-home-budgets-card',
                                  ),
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
                                key: const ValueKey(
                                  'desktop-home-action-center-card',
                                ),
                                title: context.l10n.text('desktopActionCenter'),
                                child: loading
                                    ? const _DesktopLoadingContent()
                                    : Column(
                                        children: [
                                          if (overviewUnavailable)
                                            _DesktopUnavailableContent(
                                              body: unavailableBody,
                                            )
                                          else ...[
                                            if (reviewUnavailable)
                                              _DesktopUnavailableContent(
                                                title: context.l10n.text(
                                                  'homeReviewUnavailable',
                                                ),
                                                body: context.l10n.text(
                                                  'homeReviewUnavailableBody',
                                                ),
                                                onRetry: _retry,
                                              ),
                                            if (reviewUnavailable &&
                                                duplicateUnavailable)
                                              const SizedBox(height: 8),
                                            if (duplicateUnavailable)
                                              _DesktopUnavailableContent(
                                                title: context.l10n.text(
                                                  'possibleDuplicatesUnavailable',
                                                ),
                                                body: context.l10n.text(
                                                  'possibleDuplicatesUnavailableBody',
                                                ),
                                                onRetry: reviewUnavailable
                                                    ? null
                                                    : _retry,
                                              ),
                                            if (!reviewUnavailable) ...[
                                              _DesktopAction(
                                                label: context.l10n.text(
                                                  'needsReview',
                                                ),
                                                count: displayData.reviewCount,
                                                icon: Icons.fact_check_outlined,
                                                onTap: () => _go(
                                                  _reviewRoute(
                                                    displayData,
                                                    view: 'needsReview',
                                                  ),
                                                ),
                                              ),
                                              _DesktopAction(
                                                label: context.l10n.text(
                                                  'uncategorized',
                                                ),
                                                count: displayData
                                                    .uncategorizedTransactionCount,
                                                icon: Icons.category_outlined,
                                                onTap: () => _go(
                                                  _reviewRoute(
                                                    displayData,
                                                    view: 'uncategorized',
                                                  ),
                                                ),
                                              ),
                                              if (!duplicateUnavailable)
                                                _DesktopAction(
                                                  label: context.l10n.text(
                                                    'possibleDuplicates',
                                                  ),
                                                  count: displayData
                                                      .possibleDuplicateCount,
                                                  icon: Icons.copy_outlined,
                                                  onTap: () => _go(
                                                    _reviewRoute(
                                                      displayData,
                                                      view: 'duplicates',
                                                    ),
                                                  ),
                                                ),
                                              _DesktopAction(
                                                label: context.l10n.text(
                                                  'desktopMerchantIssues',
                                                ),
                                                count: displayData
                                                    .merchantReviewCount,
                                                icon: Icons.store_outlined,
                                                onTap: () => _go(
                                                  _reviewRoute(
                                                    displayData,
                                                    view: 'overview',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
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
                                key: const ValueKey('desktop-home-recent-card'),
                                title: context.l10n.text('recentTransactions'),
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
                                  onPressed: canOpenPeriod
                                      ? () => _go(searchRoute)
                                      : null,
                                  child: Text(context.l10n.text('viewAll')),
                                ),
                                transactions: displayData.recentTransactions
                                    .take(7)
                                    .toList(),
                                masterData:
                                    _masterData ??
                                    const TransactionMasterData(),
                                onTap: (transaction) => _go(
                                  '/search?ids=${Uri.encodeQueryComponent(transaction.id)}',
                                ),
                                emptyMessage: loading
                                    ? context.l10n.text('homeLoading')
                                    : overviewUnavailable
                                    ? unavailableBody
                                    : context.l10n.text('noTransactions'),
                              );
                              final insightGroups = _desktopInsightCatalog(
                                context,
                                insightGroupSummaries(
                                  context,
                                  displayData.insights,
                                ),
                              );
                              final insights = _DesktopPanel(
                                key: const ValueKey(
                                  'desktop-home-insights-card',
                                ),
                                title: context.l10n.text('insights'),
                                child: loading
                                    ? const _DesktopLoadingContent()
                                    : cardUnavailable
                                    ? _DesktopUnavailableContent(
                                        title: analysisUnavailable
                                            ? context.l10n.text(
                                                'insightsUnavailable',
                                              )
                                            : null,
                                        body: overviewUnavailable
                                            ? unavailableBody
                                            : context.l10n.text(
                                                'insightsUnavailableBody',
                                              ),
                                      )
                                    : Column(
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
                                              tintColor:
                                                  _desktopInsightGroupTint(
                                                    group.group,
                                                  ),
                                              onTap: canOpenAnalysis
                                                  ? () => _go(insightsRoute)
                                                  : null,
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

class _DesktopUnavailableCategoryList extends StatelessWidget {
  const _DesktopUnavailableCategoryList({
    required this.categories,
    required this.masterData,
  });

  final List<AnalysisMetric> categories;
  final TransactionMasterData? masterData;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ButlerlySpacing.compact),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text('spendingDistributionPartial'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final metric in categories)
          Padding(
            padding: const EdgeInsets.only(top: ButlerlySpacing.micro),
            child: Row(
              key: ValueKey('desktop-unavailable-category-${metric.id}'),
              children: [
                Expanded(
                  child: Text(
                    analysisDimension(context, metric, masterData),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.compact),
                Text(context.l10n.text('notAvailable')),
              ],
            ),
          ),
      ],
    ),
  );
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
const double _desktopHomeTintOpacity = 0.50;
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
const double _desktopHomeTrendMaxAccessibleHeight = 320;
const double _desktopHomeTrendAxisLabelWidth = 72;

double _desktopTrendChartHeight(BuildContext context, int gridLevels) {
  final bodySmall = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
  final labelStyle = ButlerlyTypography.badgeLabel(bodySmall);
  final fontSize = labelStyle.fontSize ?? 12;
  final lineHeight = labelStyle.height ?? 1.2;
  final textScale = MediaQuery.textScalerOf(context).scale(1);
  final labelHeight = textScale * fontSize * lineHeight;
  final requiredHeight =
      gridLevels * labelHeight + (gridLevels - 1) * ButlerlySpacing.micro;
  // Keep ordinary charts bounded while allowing accessibility text to reserve
  // the space its labels actually need. This prevents a capped label column
  // from overflowing at extreme text scales.
  if (requiredHeight > _desktopHomeTrendMaxAccessibleHeight) {
    return requiredHeight;
  }
  return requiredHeight
      .clamp(
        _desktopHomeTrendMaxBarHeight,
        _desktopHomeTrendMaxAccessibleHeight,
      )
      .toDouble();
}

final class _DesktopTrendScale {
  const _DesktopTrendScale({
    required this.interval,
    required this.maximum,
    required this.tickCount,
  });

  final double interval;
  final double maximum;
  final int tickCount;
}

_DesktopTrendScale _desktopTrendScale(double maximum) {
  if (!maximum.isFinite || maximum <= 0) {
    return const _DesktopTrendScale(interval: 1, maximum: 4, tickCount: 5);
  }

  var interval = _niceCeiling(maximum / 5);
  for (var attempt = 0; attempt < 12; attempt++) {
    final tickCount = (maximum / interval).ceil() + 1;
    if (tickCount > 6) {
      interval = _niceCeiling(interval * 2);
      continue;
    }
    if (tickCount < 4) {
      interval /= 2;
      continue;
    }
    break;
  }

  var chartMaximum = (maximum / interval).ceil() * interval;
  var tickCount = (chartMaximum / interval).round() + 1;
  while (tickCount < 4) {
    interval /= 2;
    chartMaximum = (maximum / interval).ceil() * interval;
    tickCount = (chartMaximum / interval).round() + 1;
  }
  while (tickCount > 6) {
    interval = _niceCeiling(interval * 2);
    chartMaximum = (maximum / interval).ceil() * interval;
    tickCount = (chartMaximum / interval).round() + 1;
  }
  return _DesktopTrendScale(
    interval: interval,
    maximum: chartMaximum,
    tickCount: tickCount,
  );
}

double _niceCeiling(double value) {
  if (!value.isFinite || value <= 0) return 1;
  final exponent = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final normalized = value / exponent;
  final factor = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 5
      ? 5
      : 10;
  return factor * exponent;
}

class _DesktopUnavailableContent extends StatelessWidget {
  const _DesktopUnavailableContent({
    required this.body,
    this.title,
    this.onRetry,
    this.semanticsKey,
  });

  final String body;
  final String? title;
  final VoidCallback? onRetry;
  final Key? semanticsKey;

  @override
  Widget build(BuildContext context) => Semantics(
    key: semanticsKey,
    container: true,
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: _desktopHomeCardTitleStyle.copyWith(
                    color: context.colors.primaryText,
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.compact),
              ],
              Text(body),
            ],
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: ButlerlySpacing.small),
          TextButton(
            onPressed: onRetry,
            child: Text(context.l10n.text('desktopRetry')),
          ),
        ],
      ],
    ),
  );
}

class _DesktopLoadingContent extends StatelessWidget {
  const _DesktopLoadingContent();

  @override
  Widget build(BuildContext context) =>
      ButlerlyLoadingState(message: context.l10n.text('homeLoading'));
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    super.key,
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
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: headerHeight ?? 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                if (trailing != null)
                  Flexible(
                    fit: FlexFit.loose,
                    child: FittedBox(
                      alignment: AlignmentDirectional.centerEnd,
                      fit: BoxFit.scaleDown,
                      child: trailing!,
                    ),
                  ),
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
    final foreground = context.colors.primaryText;
    final mutedForeground = context.colors.secondaryText;
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
            backgroundColor: foreground.withValues(alpha: .20),
            child: Icon(icon, color: foreground, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: _desktopHomeCardTitleStyle.copyWith(
                      color: foreground,
                    ),
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
                      color: foreground,
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
                    color: percentValue == null ? mutedForeground : foreground,
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
  final VoidCallback? onTap;
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final values = points.map((point) {
      if (point.spending?.availability != AnalysisDataAvailability.sufficient) {
        return 0.0;
      }
      final value = double.tryParse(point.spending!.value.toString());
      if (value == null || !value.isFinite) return 0.0;
      return value;
    }).toList();
    final max = values.fold<double>(0, (a, b) => a > b ? a : b);
    final hasUnavailablePoint = points.any(
      (point) => _desktopTrendPointUnavailable(point.spending),
    );
    final hasUsablePoint = values.any((value) => value > 0);
    if (points.isEmpty || (!hasUsablePoint && !hasUnavailablePoint)) {
      return Center(child: Text(context.l10n.text('desktopNoSpendingTrend')));
    }
    if (!hasUsablePoint) {
      return Center(child: Text(context.l10n.text('spendingTrendPartial')));
    }

    final scale = _desktopTrendScale(max);
    final gridLevels = scale.tickCount;
    final chartMaximum = scale.maximum;
    final gridInterval = scale.interval;
    final gridColor = context.colors.cardDivider;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final chartHeight = _desktopTrendChartHeight(context, gridLevels);
    final axisStyle = ButlerlyTypography.badgeLabel(
      Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
    ).copyWith(color: context.colors.secondaryText);
    final monthStyle = ButlerlyTypography.badgeLabel(
      Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasUnavailablePoint) ...[
          Text(
            context.l10n.text('spendingTrendPartial'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: ButlerlySpacing.small),
        ],
        InkWell(
          key: const ValueKey('desktop-home-trend-chart'),
          onTap: onTap,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: SizedBox(
                  width: _desktopHomeTrendAxisLabelWidth,
                  height: chartHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < gridLevels; i++)
                        SizedBox(
                          width: _desktopHomeTrendAxisLabelWidth,
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _desktopTrendAxisLabel(
                                context,
                                chartMaximum - i * gridInterval,
                                currency,
                                interval: gridInterval,
                              ),
                              key: ValueKey('desktop-home-trend-axis-label-$i'),
                              style: axisStyle,
                            ),
                          ),
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
                      height: chartHeight,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Semantics(
                                    label:
                                        '${DateFormat.yMMMM(locale).format(points[i].month)}, ${_desktopTrendPointLabel(context, points[i].spending, currency)}',
                                    child: Tooltip(
                                      message: _desktopTrendPointTooltip(
                                        context,
                                        points[i],
                                        currency,
                                        locale,
                                      ),
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child:
                                            _desktopTrendPointUnavailable(
                                              points[i].spending,
                                            )
                                            ? SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: DecoratedBox(
                                                  key: ValueKey(
                                                    'desktop-home-trend-bar-${points[i].month.year}-${points[i].month.month}',
                                                  ),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: context
                                                          .colors
                                                          .secondaryText,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.remove,
                                                    size: 16,
                                                    color: context
                                                        .colors
                                                        .secondaryText,
                                                  ),
                                                ),
                                              )
                                            : FractionallySizedBox(
                                                widthFactor: 0.6,
                                                child: Container(
                                                  key: ValueKey(
                                                    'desktop-home-trend-bar-${points[i].month.year}-${points[i].month.month}',
                                                  ),
                                                  height:
                                                      chartHeight *
                                                      values[i] /
                                                      chartMaximum,
                                                  decoration: BoxDecoration(
                                                    color: context
                                                        .colors
                                                        .interactive
                                                        .withValues(
                                                          alpha:
                                                              points[i]
                                                                          .month
                                                                          .year ==
                                                                      selectedMonth
                                                                          .year &&
                                                                  points[i]
                                                                          .month
                                                                          .month ==
                                                                      selectedMonth
                                                                          .month
                                                              ? 1.0
                                                              : 0.72,
                                                        ),
                                                    borderRadius:
                                                        const BorderRadius.vertical(
                                                          top: Radius.circular(
                                                            5,
                                                          ),
                                                        ),
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
                                    style: monthStyle.copyWith(
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
        ),
      ],
    );
  }
}

String _desktopTrendAxisLabel(
  BuildContext context,
  double value,
  String currency, {
  required double interval,
}) {
  final code = currency.trim().toUpperCase();
  if (code.isEmpty) {
    return localizedCompactDecimal(context, value.toString());
  }
  final locale = Localizations.localeOf(context).toLanguageTag();
  return NumberFormat.compactCurrency(
    locale: locale,
    name: code,
    decimalDigits: _desktopTrendAxisDecimalDigits(interval),
  ).format(value);
}

int _desktopTrendAxisDecimalDigits(double interval) {
  if (!interval.isFinite || interval >= 1) return 0;
  final digits = (-math.log(interval) / math.ln10).ceil();
  return digits.clamp(1, 2);
}

String _desktopTrendPointLabel(
  BuildContext context,
  AnalysisMetric? metric,
  String currency,
) {
  if (metric == null ||
      metric.availability == AnalysisDataAvailability.insufficient) {
    return context.l10n.text('notAvailable');
  }
  if (metric.availability == AnalysisDataAvailability.empty) {
    return context.l10n.text('noSpendingInPeriod');
  }
  final metricCurrency = metric.currency?.value ?? currency;
  return localizedCompactMoney(
    context,
    metric.value.toString(),
    metricCurrency,
  );
}

bool _desktopTrendPointUnavailable(AnalysisMetric? metric) =>
    metric == null ||
    metric.availability == AnalysisDataAvailability.insufficient;

String _desktopTrendPointTooltip(
  BuildContext context,
  MonthlySpendingTrendPoint point,
  String currency,
  String locale,
) {
  final label = _desktopTrendPointLabel(context, point.spending, currency);
  if (!_desktopTrendPointUnavailable(point.spending)) return label;
  return '${DateFormat.yMMMM(locale).format(point.month)}, $label';
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

DateTime _monthStart(DateTime value) => DateTime(value.year, value.month);

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;

bool _isAfterMonth(DateTime value, DateTime boundary) =>
    value.year > boundary.year ||
    (value.year == boundary.year && value.month > boundary.month);
