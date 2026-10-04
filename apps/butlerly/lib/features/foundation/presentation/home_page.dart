import 'dart:math' as math;

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSliverRefreshControl;
import 'package:flutter/foundation.dart'
    show
        SynchronousFuture,
        TargetPlatform,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static DateTime? debugCurrentDate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<_HomeData> _data;
  String? _loadedLanguageCode;
  DateTime? _selectedMonth;
  int _loadGeneration = 0;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  DateTime get _now => HomePage.debugCurrentDate ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _data = Future.value(_HomeData.empty(_now));
    transactionChanges.addListener(_handleTransactionChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _loadGeneration++;
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

  Future<_HomeData> _load({
    String? languageCode,
    bool forceAnalysisRefresh = false,
  }) async {
    final finance = _finance;
    final now = _now;
    final loadHomeOverview = finance?.loadHomeOverview;
    if (finance == null || loadHomeOverview == null) {
      final fallback = ResolveHomePeriod.utcFallback(
        instant: now,
        selectedMonth: _selectedMonth,
      );
      return _HomeData.empty(now, resolution: fallback);
    }

    final activeLanguageCode =
        languageCode ??
        _loadedLanguageCode ??
        Localizations.localeOf(context).languageCode;
    final masterDataFuture = _loadMasterDataSafely(
      finance,
      languageCode: activeLanguageCode,
    );
    Future<_HomeData> unavailable() async {
      await masterDataFuture;
      return _HomeData.unavailable(now, selectedMonth: _selectedMonth);
    }

    try {
      final overviewResult = await loadHomeOverview(
        instant: now,
        selectedMonth: _selectedMonth,
        forceAnalysisRefresh: forceAnalysisRefresh,
      );
      if (overviewResult is ApplicationFailure<HomeOverview>) {
        return await unavailable();
      }
      final overview =
          (overviewResult as ApplicationSuccess<HomeOverview>).value;
      if (overview.status == HomeOverviewStatus.periodUnavailable) {
        return await unavailable();
      }
      if (overview.status == HomeOverviewStatus.transactionsUnavailable) {
        await masterDataFuture;
        return _HomeData.transactionsUnavailable(
          displayMonth: overview.displayMonth!,
          currentFinancialMonth: overview.currentFinancialMonth!,
        );
      }
      final masterData = await masterDataFuture;

      return _HomeData(
        transactions: overview.recentTransactions,
        reviewCount: overview.reviewCount,
        uncategorizedTransactionCount: overview.uncategorizedTransactionCount,
        possibleDuplicateCount: overview.possibleDuplicateCount,
        merchantReviewCount: overview.merchantReviewCount,
        masterData: masterData,
        model: overview.analysis,
        insight: overview.insights.firstOrNull,
        trend: [
          for (final point in overview.monthlyTrend)
            _HomeTrendPoint(
              month: _monthStart(point.month),
              value:
                  point.spending == null ||
                      point.spending!.availability !=
                          AnalysisDataAvailability.sufficient
                  ? 0
                  : analysisNumber(point.spending!),
              metric:
                  point.spending?.availability !=
                      AnalysisDataAvailability.sufficient
                  ? null
                  : point.spending,
              selected: _sameMonth(point.month, overview.displayMonth!),
            ),
        ],
        trendUnavailable: overview.monthlyTrendUnavailable,
        displayMonth: overview.displayMonth!,
        currentFinancialMonth: overview.currentFinancialMonth!,
        period: overview.context!.period,
        analysisUnavailable: overview.analysisUnavailable,
        duplicateUnavailable: overview.duplicateUnavailable,
        status: overview.reviewUnavailable
            ? _HomeDataStatus.reviewUnavailable
            : _HomeDataStatus.available,
      );
    } catch (_) {
      return await unavailable();
    }
  }

  Future<TransactionMasterData> _loadMasterDataSafely(
    FinanceServices finance, {
    required String languageCode,
  }) async {
    try {
      return await TransactionMasterData.load(
        finance,
        languageCode: languageCode,
      );
    } catch (_) {
      return const TransactionMasterData();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_loadGeneration;
    final refreshed = await _load(forceAnalysisRefresh: true);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _data = SynchronousFuture<_HomeData>(refreshed);
    });
  }

  Future<void> _selectMonth(_HomeData data) async {
    final selected = await showButlerlyBottomSheet<DateTime>(
      context: context,
      builder: (context) => _HomeMonthPicker(
        selectedMonth: data.displayMonth,
        currentMonth: data.currentFinancialMonth,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedMonth = _sameMonth(selected, data.currentFinancialMonth)
          ? null
          : _monthStart(selected);
      _loadGeneration++;
      _data = _load();
    });
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

  Widget _homeContent(BuildContext context, _HomeData data, bool loading) {
    final currentMonth = _sameMonth(
      data.displayMonth,
      data.currentFinancialMonth,
    );
    final period = data.period;
    if (loading) return const _HomeLoading();
    if (data.status == _HomeDataStatus.periodUnavailable) {
      return _HomePeriodUnavailable(onRetry: _refresh);
    }
    if (data.status == _HomeDataStatus.transactionsUnavailable) {
      return _HomeTransactionsUnavailable(onRetry: _refresh);
    }

    final hasUsefulAnalysis =
        [
          data.model?.spending,
          data.model?.income,
          data.model?.net,
          data.model?.transactionCount,
        ].whereType<AnalysisMetric>().any(
          (metric) =>
              metric.availability == AnalysisDataAvailability.sufficient &&
              analysisNumber(metric) != 0,
        );
    final hasUsefulActivity =
        data.transactions.isNotEmpty ||
        hasUsefulAnalysis ||
        data.model?.categories.isNotEmpty == true ||
        data.insight != null ||
        data.reviewCount > 0 ||
        data.uncategorizedTransactionCount > 0 ||
        data.possibleDuplicateCount > 0 ||
        data.merchantReviewCount > 0 ||
        data.duplicateUnavailable ||
        data.status == _HomeDataStatus.reviewUnavailable ||
        data.trend.any((point) => point.selected && point.value > 0);
    if (!data.analysisUnavailable && !hasUsefulActivity) {
      return _HomeEmptyState(
        onAdd: () => context.push('/add'),
        onViewAnalysis: period == null
            ? null
            : () => context.push(
                _periodRoute('/analysis', period, currentMonth: currentMonth),
              ),
        onViewRecent: period == null
            ? null
            : () => context.push(
                _periodRoute('/search', period, currentMonth: currentMonth),
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSummaryCard(
          model: data.model,
          analysisUnavailable: data.analysisUnavailable,
        ),
        const SizedBox(height: ButlerlySpacing.cardGap),
        _SpendingTrend(
          points: data.trend,
          unavailable: data.trendUnavailable,
          comparison: data.model?.comparison,
        ),
        const SizedBox(height: ButlerlySpacing.cardGap),
        _CategorySummary(
          model: data.model,
          masterData: data.masterData,
          onViewAll: period == null
              ? null
              : () => context.push(
                  _periodRoute('/analysis', period, currentMonth: currentMonth),
                ),
        ),
        if (data.status == _HomeDataStatus.reviewUnavailable) ...[
          const SizedBox(height: ButlerlySpacing.cardGap),
          _HomeReviewUnavailable(onRetry: _refresh),
        ] else if (data.uncategorizedTransactionCount > 0 ||
            data.possibleDuplicateCount > 0 ||
            data.merchantReviewCount > 0 ||
            data.reviewCount > 0 ||
            data.duplicateUnavailable) ...[
          const SizedBox(height: ButlerlySpacing.cardGap),
          _AttentionSection(
            uncategorizedTransactionCount: data.uncategorizedTransactionCount,
            possibleDuplicateCount: data.possibleDuplicateCount,
            merchantReviewCount: data.merchantReviewCount,
            reviewCount: data.reviewCount,
            duplicateUnavailable: data.duplicateUnavailable,
            period: period!,
          ),
        ],
        const SizedBox(height: ButlerlySpacing.cardGap),
        _HomeRecentActivity(
          transactions: data.transactions,
          masterData: data.masterData,
          onTap: _open,
          onViewAll: period == null
              ? null
              : () => context.push(
                  _periodRoute('/search', period, currentMonth: currentMonth),
                ),
        ),
        if (data.insight != null) ...[
          const SizedBox(height: ButlerlySpacing.cardGap),
          _HomeInsightCard(
            insight: data.insight!,
            onTap: period == null
                ? null
                : () => context.push(
                    _periodRoute(
                      '/insights',
                      period,
                      currentMonth: currentMonth,
                    ),
                  ),
          ),
        ],
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _data;
    final useCupertinoRefresh =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    final content = ButlerlyContentCanvas(
      canvasKey: const ValueKey('home-page-canvas'),
      child: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          physics: useCupertinoRefresh
              ? const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                )
              : const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HomePinnedHeaderDelegate(
                extent: _homeHeaderExtent(
                  context,
                  crossAxisExtent: constraints.maxWidth,
                ),
                child: FutureBuilder<_HomeData>(
                  future: future,
                  builder: (context, snapshot) {
                    final data = snapshot.hasError
                        ? _HomeData.unavailable(
                            _now,
                            selectedMonth: _selectedMonth,
                          )
                        : snapshot.data ??
                              _HomeData.empty(
                                _now,
                                selectedMonth: _selectedMonth,
                              );
                    final loading =
                        !snapshot.hasError &&
                        snapshot.connectionState != ConnectionState.done;
                    return _HomeHeader(
                      month: data.displayMonth,
                      greetingKey: homeGreetingKey(_now),
                      onMonthTap: loading || data.period == null
                          ? null
                          : () => _selectMonth(data),
                    );
                  },
                ),
              ),
            ),
            if (useCupertinoRefresh)
              CupertinoSliverRefreshControl(
                key: const ValueKey('home-cupertino-refresh-control'),
                onRefresh: _refresh,
              ),
            ButlerlySliverContentSurface(
              surfaceKey: const ValueKey('home-page-content-surface'),
              surfaceHorizontalPadding: ButlerlySize.contentGutter * 2,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  key: const ValueKey('home-page-content-padding'),
                  padding: const EdgeInsets.fromLTRB(
                    ButlerlySize.contentGutter,
                    ButlerlySpacing.small,
                    ButlerlySize.contentGutter,
                    ButlerlySpacing.large,
                  ),
                  child: SizedBox(
                    key: const ValueKey('home-page-content'),
                    width: double.infinity,
                    child: FutureBuilder<_HomeData>(
                      key: const ValueKey('home-body-data'),
                      future: future,
                      builder: (context, snapshot) {
                        final data = snapshot.hasError
                            ? _HomeData.unavailable(
                                _now,
                                selectedMonth: _selectedMonth,
                              )
                            : snapshot.data ??
                                  _HomeData.empty(
                                    _now,
                                    selectedMonth: _selectedMonth,
                                  );
                        final loading =
                            !snapshot.hasError &&
                            snapshot.connectionState != ConnectionState.done;
                        return _homeContent(context, data, loading);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (useCupertinoRefresh) return content;

    return RefreshIndicator(
      key: const ValueKey('home-refresh-indicator'),
      onRefresh: _refresh,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      child: content,
    );
  }
}

String homeGreetingKey(DateTime localTime) {
  if (localTime.hour < 12) return 'greetingMorning';
  if (localTime.hour < 18) return 'greetingAfternoon';
  return 'greetingEvening';
}

double _homeHeaderExtent(
  BuildContext context, {
  required double crossAxisExtent,
}) {
  final textTheme = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  final locale = Localizations.localeOf(context);
  final localeTag = locale.toLanguageTag();
  final availableWidth = (crossAxisExtent - ButlerlySize.contentGutter * 2)
      .clamp(1.0, double.infinity)
      .toDouble();
  final direction = Directionality.of(context);

  final appStyle = ButlerlyTypography.brandTitle(
    textTheme.headlineLarge ?? const TextStyle(),
  );
  final introStyle = ButlerlyTypography.pageIntro(
    textTheme.bodyLarge ?? const TextStyle(),
  );
  final greetingStyle = ButlerlyTypography.pageHeroTitle(
    textTheme.headlineLarge ?? const TextStyle(),
  );
  final monthStyle = ButlerlyTypography.cardAction(
    textTheme.titleMedium ?? const TextStyle(),
  );

  double measure(
    String text,
    TextStyle style,
    double maxWidth, {
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth.clamp(1.0, double.infinity).toDouble());
    return painter.height;
  }

  double maxMeasured(
    Iterable<String> values,
    TextStyle style,
    double maxWidth, {
    int? maxLines,
  }) => values.fold<double>(
    0,
    (height, value) =>
        height > measure(value, style, maxWidth, maxLines: maxLines)
        ? height
        : measure(value, style, maxWidth, maxLines: maxLines),
  );

  final greetingLabels = <String>[
    context.l10n.text('greetingMorning'),
    context.l10n.text('greetingAfternoon'),
    context.l10n.text('greetingEvening'),
  ];
  final monthLabels = <String>[
    for (var month = 1; month <= 12; month++)
      DateFormat.yMMMM(localeTag).format(DateTime(2026, month)),
  ];
  final introLabels = <String>[
    for (var month = 1; month <= 12; month++)
      context.l10n.text('homeSubtitle', {
        'period': DateFormat.yMMMM(localeTag).format(DateTime(2026, month)),
      }),
  ];

  double monthButtonHeight(double width) {
    final textWidth =
        (width - ButlerlySpacing.compact * 2 - ButlerlySpacing.micro - 20)
            .clamp(1.0, double.infinity)
            .toDouble();
    final textHeight = maxMeasured(
      monthLabels,
      monthStyle,
      textWidth,
      maxLines: null,
    );
    final contentHeight = textHeight + ButlerlySpacing.compact * 2;
    return contentHeight > kMinInteractiveDimension
        ? contentHeight
        : kMinInteractiveDimension;
  }

  final appName = context.l10n.text('appName');
  final rowWidth = availableWidth - ButlerlySpacing.standard;
  final brandWidth = rowWidth * 5 / 9;
  final monthWidth = rowWidth * 4 / 9;
  final brandHeight = measure(appName, appStyle, brandWidth);
  final monthHeight = monthButtonHeight(monthWidth);
  final largeText = scaler.scale(14) > 18;
  final stackedTopRow = largeText || availableWidth < 360;
  final topRowHeight = stackedTopRow
      ? brandHeight + ButlerlySpacing.small + monthHeight
      : brandHeight > monthHeight
      ? brandHeight
      : monthHeight;
  final greetingHeight = maxMeasured(
    greetingLabels,
    greetingStyle,
    availableWidth,
  );
  final introHeight = maxMeasured(introLabels, introStyle, availableWidth);
  return topRowHeight +
      ButlerlySpacing.small +
      greetingHeight +
      ButlerlySpacing.small +
      introHeight +
      ButlerlySpacing.small;
}

class _HomePinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HomePinnedHeaderDelegate({required this.extent, required this.child});

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    key: const ValueKey('home-header-surface'),
    color: context.colors.background,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ButlerlySize.contentGutter,
          ButlerlySpacing.small,
          ButlerlySize.contentGutter,
          0,
        ),
        child: SizedBox(
          key: const ValueKey('home-header-content'),
          width: double.infinity,
          child: child,
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant _HomePinnedHeaderDelegate oldDelegate) =>
      oldDelegate.extent != extent || oldDelegate.child != child;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.month,
    required this.greetingKey,
    required this.onMonthTap,
  });

  final DateTime month;
  final String greetingKey;
  final VoidCallback? onMonthTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final monthLabel = DateFormat.yMMMM(locale).format(month);
    return LayoutBuilder(
      builder: (context, _) {
        final brand = Text(
          context.l10n.text('appName'),
          style: ButlerlyTypography.brandTitle(
            Theme.of(context).textTheme.headlineLarge ?? const TextStyle(),
          ),
        );
        final monthButton = TextButton(
          key: const Key('home-month-selector'),
          onPressed: onMonthTap,
          style: TextButton.styleFrom(
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySpacing.compact,
              vertical: ButlerlySpacing.compact,
            ),
            minimumSize: const Size(0, kMinInteractiveDimension),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  monthLabel,
                  softWrap: true,
                  textAlign: TextAlign.end,
                  style: ButlerlyTypography.cardAction(
                    Theme.of(context).textTheme.titleMedium ??
                        const TextStyle(),
                  ),
                ),
              ),
              const SizedBox(width: ButlerlySpacing.micro),
              Icon(
                _homeIcon(
                  context,
                  material: Icons.keyboard_arrow_down_rounded,
                  cupertino: CupertinoIcons.chevron_down,
                ),
                size: 20,
              ),
            ],
          ),
        );
        final availableWidth =
            MediaQuery.sizeOf(context).width - ButlerlySize.contentGutter * 2;
        final stackedTopRow =
            MediaQuery.textScalerOf(context).scale(14) > 18 ||
            availableWidth < 360;
        final topRow = stackedTopRow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  brand,
                  const SizedBox(height: ButlerlySpacing.small),
                  monthButton,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: brand),
                  const SizedBox(width: ButlerlySpacing.standard),
                  Flexible(
                    flex: 4,
                    child: Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: monthButton,
                    ),
                  ),
                ],
              );
        return Column(
          key: const ValueKey('home-header-context'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            topRow,
            const SizedBox(height: ButlerlySpacing.small),
            Text(
              context.l10n.text(greetingKey),
              key: const ValueKey('home-greeting'),
              style: ButlerlyTypography.pageHeroTitle(
                Theme.of(context).textTheme.headlineLarge ?? const TextStyle(),
              ),
            ),
            const SizedBox(height: ButlerlySpacing.small),
            Text(
              context.l10n.text('homeSubtitle', {'period': monthLabel}),
              key: const ValueKey('home-intro'),
              style: ButlerlyTypography.pageIntro(
                Theme.of(context).textTheme.bodyLarge ?? const TextStyle(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomeSummaryCard extends StatelessWidget {
  const _HomeSummaryCard({
    required this.model,
    required this.analysisUnavailable,
  });

  final AnalysisModel? model;
  final bool analysisUnavailable;

  @override
  Widget build(BuildContext context) {
    final headerAction = Text(
      context.l10n.text('vsLastMonth'),
      style: ButlerlyTypography.cardAction(
        Theme.of(context).textTheme.labelLarge ?? const TextStyle(),
      ),
    );
    return ButlerlyCard(
      key: const ValueKey('home-summary-card'),
      variant: ButlerlyCardVariant.dashboard,
      semanticLabel: context.l10n.text('monthlySummary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(
            title: context.l10n.text('monthlySummary'),
            titleStyle: ButlerlyTypography.cardTitle(
              Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
            ),
            action: headerAction,
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
              final stacked = largeText || constraints.maxWidth < 300;
              final cells = [
                _HomeMetricCell(
                  key: const ValueKey('home-summary-metric-spending'),
                  label: context.l10n.text('spending'),
                  metric: model?.spending,
                  comparison: model?.spendingComparison,
                  icon: Icons.arrow_downward_rounded,
                  color: context.colors.error,
                  supportingColor: context.colors.error,
                ),
                _HomeMetricCell(
                  key: const ValueKey('home-summary-metric-income'),
                  label: context.l10n.text('income'),
                  metric: model?.income,
                  comparison: model?.incomeComparison,
                  icon: Icons.arrow_upward_rounded,
                  color: context.colors.success,
                  supportingColor: context.colors.success,
                ),
                _HomeMetricCell(
                  key: const ValueKey('home-summary-metric-savings'),
                  label: context.l10n.text('savings'),
                  value: model?.savings,
                  supportingText: model?.savingsRate == null
                      ? null
                      : '${analysisPercentageRatio(context, model!.savingsRate!)} '
                            '${context.l10n.text('savingsRateOfIncome')}',
                  icon: Icons.savings_outlined,
                  color: context.colors.info,
                  supportingColor: context.colors.info,
                ),
                _HomeMetricCell(
                  key: const ValueKey('home-summary-metric-net-position'),
                  label: context.l10n.text('netPosition'),
                  metric: model?.net,
                  supportingText: model?.netComparison == null
                      ? null
                      : analysisAbsoluteChange(
                          context,
                          model!.netComparison!,
                          model?.net?.currency,
                        ),
                  signed: true,
                  icon: Icons.account_balance_wallet_outlined,
                  color: context.colors.warning,
                  supportingColor: _homeNetChangeColor(
                    context,
                    model?.netComparison,
                  ),
                ),
              ];
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < cells.length; index++) ...[
                      cells[index],
                      if (index < cells.length - 1)
                        const SizedBox(height: ButlerlySpacing.standard),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < cells.length; index++) ...[
                    if (index > 0)
                      const SizedBox(
                        height: 92,
                        child: VerticalDivider(width: ButlerlySpacing.standard),
                      ),
                    Expanded(child: cells[index]),
                  ],
                ],
              );
            },
          ),
          if (analysisUnavailable) ...[
            const SizedBox(height: ButlerlySpacing.standard),
            Text(
              context.l10n.text('analysisUnavailable'),
              style: ButlerlyTypography.cardSubtitle(
                Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
              ).copyWith(color: context.colors.secondaryText),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeMetricCell extends StatelessWidget {
  const _HomeMetricCell({
    super.key,
    required this.label,
    this.metric,
    this.value,
    this.comparison,
    this.supportingText,
    this.supportingColor,
    required this.icon,
    required this.color,
    this.signed = false,
  });

  final String label;
  final AnalysisMetric? metric;
  final AnalysisValue? value;
  final AnalysisComparison? comparison;
  final String? supportingText;
  final Color? supportingColor;
  final IconData icon;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final metricUnavailable =
        metric?.availability != null &&
        metric!.availability != AnalysisDataAvailability.sufficient;
    final valueUnavailable =
        value?.availability != null &&
        value!.availability != AnalysisDataAvailability.sufficient;
    final displayUnavailable =
        metric == null && (value == null || valueUnavailable) ||
        metricUnavailable;
    final displayValue = displayUnavailable
        ? '—'
        : value == null
        ? _homeMoney(context, metric!, signed: signed)
        : analysisValueMoney(context, value!);
    final comparisonText = comparison == null
        ? null
        : analysisComparisonChangeText(context, comparison!);
    final support = supportingText ?? comparisonText;
    return Semantics(
      label:
          '$label, ${displayUnavailable ? context.l10n.text('notAvailable') : displayValue}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: ButlerlySpacing.compact),
          Text(
            label,
            style: ButlerlyTypography.metricLabel(
              Theme.of(context).textTheme.labelLarge ?? const TextStyle(),
            ).copyWith(color: context.colors.secondaryText),
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            displayValue,
            softWrap: true,
            style: ButlerlyTypography.metricValue(
              Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
            ),
          ),
          if (!valueUnavailable &&
              !metricUnavailable &&
              support != null &&
              support.isNotEmpty) ...[
            const SizedBox(height: ButlerlySpacing.micro),
            Text(
              support,
              softWrap: true,
              style:
                  ButlerlyTypography.metricChange(
                    Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                  ).copyWith(
                    color: supportingColor ?? context.colors.secondaryText,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _homeNetChangeColor(
  BuildContext context,
  AnalysisComparison? comparison,
) {
  final change = comparison?.absoluteChange;
  if (comparison == null || !isUsableComparison(comparison) || change == null) {
    return context.colors.secondaryText;
  }
  if (change.isZero) return context.colors.secondaryText;
  return change.isNegative ? context.colors.error : context.colors.success;
}

@visibleForTesting
Widget homeSpendingTrendForTest(
  List<({DateTime month, double value, bool selected})> points, {
  bool unavailable = false,
}) => _SpendingTrend(
  unavailable: unavailable,
  points: [
    for (final point in points)
      _HomeTrendPoint(
        month: point.month,
        value: point.value,
        metric: null,
        selected: point.selected,
      ),
  ],
);

@visibleForTesting
Widget homeCategorySummaryItemForTest({
  required AnalysisMetric metric,
  TransactionMasterData masterData = const TransactionMasterData(),
}) => _CategorySummaryItem(metric: metric, masterData: masterData);

@visibleForTesting
Widget homeSummaryForTest(AnalysisModel model) =>
    _HomeSummaryCard(model: model, analysisUnavailable: false);

class _SpendingTrend extends StatelessWidget {
  const _SpendingTrend({
    required this.points,
    required this.unavailable,
    this.comparison,
  });

  final List<_HomeTrendPoint> points;
  final bool unavailable;
  final AnalysisComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final meaningful = points.any((point) => point.value > 0);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final selectedPoint = points.where((point) => point.selected).firstOrNull;
    final comparisonText = comparison == null
        ? ''
        : analysisComparisonText(context, comparison!);
    final trendAction = Semantics(
      container: true,
      label: context.l10n.text('lastSixMonths'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.subtleSurface,
          borderRadius: BorderRadius.circular(ButlerlyRadius.full),
          border: Border.all(color: context.colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlySpacing.compact,
            vertical: ButlerlySpacing.micro,
          ),
          child: SizedBox(
            width: 150,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.text('lastSixMonths'),
                    softWrap: true,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.micro),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
    return ButlerlyCard(
      key: const ValueKey('home-trend-card'),
      variant: ButlerlyCardVariant.dashboard,
      semanticLabel: context.l10n.text('spendingTrend'),
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ButlerlyCardHeader(
              title: context.l10n.text('spendingTrend'),
              titleStyle: ButlerlyTypography.cardTitle(
                Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
              ),
              action: trendAction,
            ),
            if (unavailable || points.isEmpty || !meaningful) ...[
              const SizedBox(height: ButlerlySpacing.standard),
              Text(
                context.l10n.text(
                  unavailable
                      ? 'analysisUnavailableBody'
                      : 'insufficientTrendData',
                ),
                style: ButlerlyTypography.cardSubtitle(
                  Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                ),
              ),
            ] else ...[
              if (selectedPoint?.metric case final metric?) ...[
                const SizedBox(height: ButlerlySpacing.small),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ButlerlySpacing.small,
                  runSpacing: ButlerlySpacing.micro,
                  children: [
                    Text(
                      analysisMoney(context, metric),
                      style: ButlerlyTypography.metricValue(
                        Theme.of(context).textTheme.titleLarge ??
                            const TextStyle(),
                      ).copyWith(fontSize: 30, height: 1.08),
                    ),
                    if (comparisonText.isNotEmpty)
                      Text(
                        comparisonText,
                        style:
                            ButlerlyTypography.metricChange(
                              Theme.of(context).textTheme.bodySmall ??
                                  const TextStyle(),
                            ).copyWith(
                              color:
                                  comparison!.percentageChange?.isNegative ==
                                      true
                                  ? context.colors.success
                                  : context.colors.interactive,
                            ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: ButlerlySpacing.standard),
              _HomeTrendPlot(points: points, locale: locale),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeTrendPlot extends StatelessWidget {
  const _HomeTrendPlot({required this.points, required this.locale});

  final List<_HomeTrendPoint> points;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final maxValue = points
        .map((point) => point.value)
        .fold<double>(0, (left, right) => left > right ? left : right);
    final scaleMax = _trendScaleMax(maxValue);
    final chartHeight = math
        .max(
          156.0,
          MediaQuery.textScalerOf(context).scale(18) * 5 +
              ButlerlySpacing.section * 4,
        )
        .toDouble();
    return SizedBox(
      height: chartHeight,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var index = 0; index < 5; index++)
                        Text(
                          _trendScaleLabel(locale, scaleMax * (4 - index) / 4),
                          key: ValueKey(
                            'home-spending-trend-axis-label-$index',
                          ),
                          maxLines: 1,
                          style: ButlerlyTypography.badgeLabel(
                            Theme.of(context).textTheme.bodySmall ??
                                const TextStyle(),
                          ).copyWith(color: context.colors.secondaryText),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.compact),
                Expanded(
                  child: Stack(
                    key: const ValueKey('home-spending-trend-plot'),
                    children: [
                      const Positioned.fill(
                        child: _SpendingTrendGrid(
                          key: ValueKey('home-spending-trend-grid'),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final point in points)
                            Expanded(
                              child: Semantics(
                                label:
                                    '${DateFormat.yMMMM(locale).format(point.month)}, ${point.metric == null ? context.l10n.text('noSpendingInPeriod') : analysisMoney(context, point.metric!)}',
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        scaleMax <= 0 || point.value <= 0
                                        ? 0
                                        : (point.value / scaleMax)
                                              .clamp(0.04, 1.0)
                                              .toDouble(),
                                    widthFactor: 0.42,
                                    child: DecoratedBox(
                                      key: ValueKey(
                                        'home-spending-trend-bar-${point.month.year}-${point.month.month}',
                                      ),
                                      decoration: BoxDecoration(
                                        color: point.selected
                                            ? context.colors.interactive
                                            : context.colors.secondaryText
                                                  .withValues(alpha: 0.35),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(
                                                ButlerlyRadius.small,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
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
          const SizedBox(height: ButlerlySpacing.compact),
          Row(
            children: [
              for (final point in points)
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      DateFormat.MMM(locale).format(point.month).toUpperCase(),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style:
                          ButlerlyTypography.badgeLabel(
                            Theme.of(context).textTheme.bodySmall ??
                                const TextStyle(),
                          ).copyWith(
                            color: point.selected
                                ? context.colors.interactive
                                : null,
                            fontWeight: point.selected ? FontWeight.w600 : null,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategorySummary extends StatelessWidget {
  const _CategorySummary({
    required this.model,
    required this.masterData,
    required this.onViewAll,
  });

  final AnalysisModel? model;
  final TransactionMasterData masterData;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final categories =
        model?.categories.take(5).toList(growable: false) ??
        const <AnalysisMetric>[];
    return ButlerlyCard(
      key: const ValueKey('home-category-card'),
      variant: ButlerlyCardVariant.dashboard,
      semanticLabel: context.l10n.text('topCategories'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(
            title: context.l10n.text('topCategories'),
            titleStyle: ButlerlyTypography.cardTitle(
              Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
            ),
            action: TextButton(
              key: const Key('home-category-view-all'),
              onPressed: onViewAll,
              child: Text(
                context.l10n.text('viewAll'),
                style: ButlerlyTypography.cardAction(
                  Theme.of(context).textTheme.labelLarge ?? const TextStyle(),
                ),
              ),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          if (model == null)
            Text(
              context.l10n.text('analysisUnavailableBody'),
              style: ButlerlyTypography.cardSubtitle(
                Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
              ),
            )
          else if (categories.isEmpty)
            Text(
              context.l10n.text('noSpendingInPeriod'),
              style: ButlerlyTypography.cardSubtitle(
                Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < categories.length; index++) ...[
                  _CategorySummaryItem(
                    metric: categories[index],
                    masterData: masterData,
                    share: model?.categoryShares[categories[index].id],
                  ),
                  if (index < categories.length - 1)
                    const SizedBox(height: ButlerlySpacing.small),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CategorySummaryItem extends StatelessWidget {
  const _CategorySummaryItem({
    required this.metric,
    required this.masterData,
    this.share,
  });

  final AnalysisMetric metric;
  final TransactionMasterData masterData;
  final DecimalValue? share;

  @override
  Widget build(BuildContext context) {
    final metricUnavailable =
        metric.availability != AnalysisDataAvailability.sufficient;
    final categoryId = analysisCategoryId(metric);
    final label = analysisDimension(context, metric, masterData);
    final identity = ButlerlyCategoryIdentity.forBuiltInId(categoryId);
    final color = ButlerlyChartColors.category(categoryId);
    final icon = identity == null
        ? Container(
            width: ButlerlySize.categoryIconContainer,
            height: ButlerlySize.categoryIconContainer,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Icon(
              _homeIcon(
                context,
                material: Icons.category_outlined,
                cupertino: CupertinoIcons.square_grid_2x2,
              ),
              size: 22,
              color: color,
            ),
          )
        : ButlerlyCategoryIcon(categoryId: categoryId, semanticLabel: label);
    final percentage = metricUnavailable || share == null
        ? null
        : analysisPercentageRatio(context, share!);
    final progress = metricUnavailable || share == null
        ? 0.0
        : (double.tryParse(share.toString()) ?? 0).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label:
          '$label, ${metricUnavailable ? context.l10n.text('notAvailable') : analysisMoney(context, metric)}${percentage == null ? '' : ', $percentage'}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaledBody = MediaQuery.textScalerOf(context).scale(14);
          final stacked = scaledBody > 18 || constraints.maxWidth < 300;
          final amount = Text(
            metricUnavailable ? '—' : analysisMoney(context, metric),
            textAlign: TextAlign.end,
            softWrap: true,
            style: ButlerlyTypography.rowAmount(
              Theme.of(context).textTheme.titleMedium ?? const TextStyle(),
            ),
          );
          final name = Text(
            label,
            softWrap: true,
            style: ButlerlyTypography.rowTitle(
              Theme.of(context).textTheme.bodyLarge ?? const TextStyle(),
            ),
          );
          final details = stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    name,
                    const SizedBox(height: ButlerlySpacing.micro),
                    Row(
                      children: [
                        Expanded(child: amount),
                        if (percentage != null) ...[
                          const SizedBox(width: ButlerlySpacing.compact),
                          Text(
                            percentage,
                            style: ButlerlyTypography.metricChange(
                              Theme.of(context).textTheme.bodySmall ??
                                  const TextStyle(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: ButlerlySpacing.small),
                    amount,
                    if (percentage != null) ...[
                      const SizedBox(width: ButlerlySpacing.compact),
                      Text(
                        percentage,
                        style: ButlerlyTypography.metricChange(
                          Theme.of(context).textTheme.bodySmall ??
                              const TextStyle(),
                        ),
                      ),
                    ],
                  ],
                );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: ButlerlySpacing.small),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
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
          );
        },
      ),
    );
  }
}

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.uncategorizedTransactionCount,
    required this.possibleDuplicateCount,
    required this.merchantReviewCount,
    required this.reviewCount,
    required this.duplicateUnavailable,
    required this.period,
  });

  final int uncategorizedTransactionCount;
  final int possibleDuplicateCount;
  final int merchantReviewCount;
  final int reviewCount;
  final bool duplicateUnavailable;
  final AnalysisPeriod period;

  @override
  Widget build(BuildContext context) {
    return ButlerlyCard(
      key: const ValueKey('home-attention-card'),
      variant: ButlerlyCardVariant.dashboard,
      color: context.colors.warning.withValues(alpha: 0.08),
      semanticLabel:
          '${context.l10n.text('needsAttention')}: '
          '${context.l10n.text('attentionNeedsReview')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: const ValueKey('home-attention-icon'),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.warning.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: context.colors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: ButlerlySpacing.standard),
              Expanded(
                child: ButlerlyCardHeader(
                  title: context.l10n.text('needsAttention'),
                  subtitle: context.l10n.text('attentionNeedsReview'),
                  titleStyle: ButlerlyTypography.cardTitle(
                    Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
                  ),
                  action: TextButton(
                    key: const Key('home-attention-view-all'),
                    onPressed: () => context.push(_reviewRoute(period)),
                    child: Text(context.l10n.text('viewAll')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.small),
          if (uncategorizedTransactionCount > 0)
            _AttentionRow(
              icon: Icons.category_outlined,
              title: context.l10n.text('manyTransactions', {
                'count': localizedCount(
                  context,
                  uncategorizedTransactionCount.toString(),
                ),
              }),
              subtitle: context.l10n.text('uncategorizedTransactions'),
              onTap: () =>
                  context.push(_reviewRoute(period, view: 'uncategorized')),
            ),
          if (possibleDuplicateCount > 0)
            _AttentionRow(
              icon: Icons.copy_all_outlined,
              title: context.l10n.text('possibleDuplicatesCount', {
                'count': localizedCount(
                  context,
                  possibleDuplicateCount.toString(),
                ),
              }),
              subtitle: context.l10n.text('reviewSimilarTransactions'),
              onTap: () =>
                  context.push(_reviewRoute(period, view: 'duplicates')),
            ),
          if (duplicateUnavailable)
            _AttentionRow(
              icon: Icons.copy_all_outlined,
              title: context.l10n.text('possibleDuplicatesUnavailable'),
              subtitle: context.l10n.text('possibleDuplicatesUnavailableBody'),
              onTap: () =>
                  context.push(_reviewRoute(period, view: 'duplicates')),
            ),
          if (merchantReviewCount > 0)
            _AttentionRow(
              icon: Icons.storefront_outlined,
              title: context.l10n.text(
                merchantReviewCount == 1
                    ? 'oneMerchantToReview'
                    : 'manyMerchantsToReview',
                {
                  'count': localizedCount(
                    context,
                    merchantReviewCount.toString(),
                  ),
                },
              ),
              subtitle: context.l10n.text(
                merchantReviewCount == 1
                    ? 'newMerchantNeedsCategorization'
                    : 'newMerchantsNeedCategorization',
              ),
              onTap: () => context.push(
                _reviewRoute(
                  period,
                  reason: ReviewIssueReason.merchantNeedsReview,
                ),
              ),
            ),
          if (reviewCount > 0 &&
              uncategorizedTransactionCount == 0 &&
              possibleDuplicateCount == 0 &&
              merchantReviewCount == 0)
            _AttentionRow(
              icon: Icons.rate_review_outlined,
              title: context.l10n.text(
                reviewCount == 1 ? 'oneReviewItem' : 'manyReviewItems',
                {'count': localizedCount(context, reviewCount.toString())},
              ),
              subtitle: context.l10n.text('needsReview'),
              onTap: () => context.push(_reviewRoute(period)),
            ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ButlerlySpacing.compact),
    child: Material(
      color: context.colors.subtleSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        side: BorderSide(color: context.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.interactive.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: context.colors.interactive, size: 20),
              ),
              const SizedBox(width: ButlerlySpacing.standard),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ButlerlyTypography.rowTitle(
                        Theme.of(context).textTheme.titleMedium ??
                            const TextStyle(),
                      ),
                    ),
                    const SizedBox(height: ButlerlySpacing.micro),
                    Text(
                      subtitle,
                      style: ButlerlyTypography.rowMetadata(
                        Theme.of(context).textTheme.bodySmall ??
                            const TextStyle(),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _homeIcon(
                  context,
                  material: Icons.chevron_right_rounded,
                  cupertino: CupertinoIcons.chevron_right,
                ),
                color: context.colors.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomeRecentActivity extends StatelessWidget {
  const _HomeRecentActivity({
    required this.transactions,
    required this.masterData,
    required this.onTap,
    required this.onViewAll,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final ValueChanged<TransactionDto> onTap;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    key: const ValueKey('home-recent-card'),
    variant: ButlerlyCardVariant.dashboard,
    padding: EdgeInsets.zero,
    semanticLabel: context.l10n.text('recentTransactions'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ButlerlySpacing.standard,
            ButlerlySpacing.standard,
            ButlerlySpacing.standard,
            ButlerlySpacing.small,
          ),
          child: ButlerlyCardHeader(
            title: context.l10n.text('recentTransactions'),
            titleStyle: ButlerlyTypography.cardTitle(
              Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
            ),
            action: TextButton(
              key: const Key('home-recent-view-all'),
              onPressed: onViewAll,
              child: Text(
                context.l10n.text('viewAll'),
                style: ButlerlyTypography.cardAction(
                  Theme.of(context).textTheme.labelLarge ?? const TextStyle(),
                ),
              ),
            ),
          ),
        ),
        if (transactions.isEmpty)
          const _HomeEmptyTransactions()
        else
          ButlerlyTransactionList(
            children: [
              for (final transaction in transactions)
                TransactionRow(
                  transaction: transaction,
                  masterData: masterData,
                  showDate: true,
                  showCategoryPill: true,
                  showNavigationIndicator: true,
                  variant: ButlerlyTransactionRowVariant.dashboard,
                  onTap: () => onTap(transaction),
                ),
            ],
          ),
      ],
    ),
  );
}

class _HomeInsightCard extends StatelessWidget {
  const _HomeInsightCard({required this.insight, required this.onTap});

  final InsightResult insight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    key: const ValueKey('home-insight-card'),
    variant: ButlerlyCardVariant.dashboard,
    semanticLabel:
        '${context.l10n.text('insights')}: '
        '${context.l10n.text(insight.rule.nameKey)}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ButlerlyCardHeader(
          title: context.l10n.text('insights'),
          titleStyle: ButlerlyTypography.cardTitle(
            Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
          ),
          action: TextButton(
            onPressed: onTap,
            child: Text(context.l10n.text('viewAll')),
          ),
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Material(
          color: context.colors.selection,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(ButlerlySpacing.standard),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    key: const ValueKey('home-insight-icon'),
                    decoration: BoxDecoration(
                      color: context.colors.info.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(ButlerlySpacing.small),
                      child: Icon(
                        _homeIcon(
                          context,
                          material: Icons.lightbulb_outline,
                          cupertino: CupertinoIcons.lightbulb,
                        ),
                        size: 20,
                        color: context.colors.info,
                      ),
                    ),
                  ),
                  const SizedBox(width: ButlerlySpacing.standard),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.text(insight.rule.nameKey),
                          style: ButlerlyTypography.rowTitle(
                            Theme.of(context).textTheme.titleMedium ??
                                const TextStyle(),
                          ),
                        ),
                        const SizedBox(height: ButlerlySpacing.micro),
                        Text(
                          context.l10n.text(insight.rule.descriptionKey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ButlerlyTypography.rowMetadata(
                            Theme.of(context).textTheme.bodySmall ??
                                const TextStyle(),
                          ),
                        ),
                        if (_homeInsightValues(context, insight)
                            case final values?) ...[
                          const SizedBox(height: ButlerlySpacing.small),
                          Text(
                            values,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ButlerlyTypography.metricChange(
                              Theme.of(context).textTheme.bodyMedium ??
                                  const TextStyle(),
                            ),
                          ),
                        ],
                        const SizedBox(height: ButlerlySpacing.micro),
                        Text(
                          _homeInsightContext(context, insight),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ButlerlyTypography.badgeLabel(
                            Theme.of(context).textTheme.bodySmall ??
                                const TextStyle(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      _homeIcon(
                        context,
                        material: Icons.chevron_right_rounded,
                        cupertino: CupertinoIcons.chevron_right,
                      ),
                      color: context.colors.tertiaryText,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.onAdd,
    required this.onViewAnalysis,
    required this.onViewRecent,
  });

  final VoidCallback onAdd;
  final VoidCallback? onViewAnalysis;
  final VoidCallback? onViewRecent;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('home-empty-transactions-card'),
    container: true,
    explicitChildNodes: true,
    child: ButlerlyCard(
      variant: ButlerlyCardVariant.dashboard,
      semanticLabel: context.l10n.text('noActivityInPeriod'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Icon(
                  _homeIcon(
                    context,
                    material: Icons.receipt_long_outlined,
                    cupertino: CupertinoIcons.doc_text,
                  ),
                  color: context.colors.secondaryText,
                  size: ButlerlySize.standardIcon,
                ),
              ),
              IconButton(
                key: const Key('home-notification-action'),
                tooltip: context.l10n.text('notifications'),
                onPressed: () => context.push('/notifications'),
                icon: Icon(
                  _homeIcon(
                    context,
                    material: Icons.notifications_none_rounded,
                    cupertino: CupertinoIcons.bell,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          Text(
            context.l10n.text('noActivityInPeriod'),
            style: ButlerlyTypography.cardTitle(
              Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            context.l10n.text('noTransactionsBody'),
            style: ButlerlyTypography.cardSubtitle(
              Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: Icon(
              _homeIcon(
                context,
                material: Icons.add,
                cupertino: CupertinoIcons.add,
              ),
            ),
            label: Text(context.l10n.text('addFirstTransaction')),
          ),
          if (onViewAnalysis != null || onViewRecent != null) ...[
            const SizedBox(height: ButlerlySpacing.compact),
            Wrap(
              spacing: ButlerlySpacing.compact,
              runSpacing: ButlerlySpacing.compact,
              children: [
                if (onViewAnalysis != null)
                  TextButton(
                    key: const Key('home-category-view-all'),
                    onPressed: onViewAnalysis,
                    child: Text(context.l10n.text('viewAllAnalysis')),
                  ),
                if (onViewRecent != null)
                  TextButton(
                    key: const Key('home-recent-view-all'),
                    onPressed: onViewRecent,
                    child: Text(context.l10n.text('viewAllRecentTransactions')),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

String? _homeInsightValues(BuildContext context, InsightResult insight) {
  String? value(DecimalValue? input) {
    if (input == null) return null;
    final formatted = localizedDecimal(context, input.toString());
    if (insight.rule.measure.operation == RuleOperation.share) {
      return '$formatted%';
    }
    final currency = insight.currency?.value;
    return currency == null || currency.isEmpty
        ? formatted
        : '$formatted $currency';
  }

  final current = value(insight.currentValue);
  final baseline = value(insight.baselineValue);
  final difference = value(insight.absoluteChange);
  final percent = insight.percentageChange == null
      ? null
      : '${localizedDecimal(context, insight.percentageChange.toString())}%';
  final values = <String>[
    ?baseline,
    if (baseline != null && current != null) '→',
    ?current,
    ?difference,
    ?percent,
  ];
  return values.isEmpty ? null : values.join(' · ');
}

String _homeInsightContext(BuildContext context, InsightResult insight) {
  final periods = <String>[
    '${context.l10n.text('currentPeriod')}: '
        '${localizedPeriodRange(context, startDate: insight.context.period.startDate, endDate: insight.context.period.endDate)}',
    if (insight.baselineContext case final baseline?)
      '${context.l10n.text('previousPeriod')}: '
          '${localizedPeriodRange(context, startDate: baseline.period.startDate, endDate: baseline.period.endDate)}',
  ];
  return periods.join(' · ');
}

class _HomeEmptyTransactions extends StatelessWidget {
  const _HomeEmptyTransactions();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('home-empty-transactions-row'),
    padding: const EdgeInsets.all(ButlerlySpacing.standard),
    child: Row(
      children: [
        Icon(
          _homeIcon(
            context,
            material: Icons.receipt_long_outlined,
            cupertino: CupertinoIcons.doc_text,
          ),
          color: context.colors.secondaryText,
        ),
        const SizedBox(width: ButlerlySpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.text('noTransactions'),
                style: ButlerlyTypography.rowTitle(
                  Theme.of(context).textTheme.titleMedium ?? const TextStyle(),
                ),
              ),
              Text(
                context.l10n.text('noTransactionsBody'),
                style: ButlerlyTypography.rowMetadata(
                  Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SpendingTrendGrid extends StatelessWidget {
  const _SpendingTrendGrid({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var index = 0; index < 5; index++)
          Divider(
            key: ValueKey('home-spending-trend-grid-line-$index'),
            height: 1,
            thickness: 1,
            color: context.colors.cardDivider.withValues(alpha: 0.7),
          ),
      ],
    ),
  );
}

double _trendScaleMax(double maxValue) {
  if (maxValue <= 0) return 1;
  var magnitude = 1.0;
  while (magnitude * 10 <= maxValue) {
    magnitude *= 10;
  }
  final normalized = maxValue / magnitude;
  final step = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 5
      ? 5
      : 10;
  return step * magnitude;
}

String _trendScaleLabel(String locale, double value) =>
    NumberFormat.compact(locale: locale).format(value);

class _HomePeriodUnavailable extends StatelessWidget {
  const _HomePeriodUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _HomeUnavailableCard(
    cardKey: const ValueKey('home-period-unavailable-card'),
    retryKey: const ValueKey('home-period-unavailable-retry'),
    titleKey: 'homeUnavailable',
    bodyKey: 'homeUnavailableBody',
    onRetry: onRetry,
  );
}

class _HomeTransactionsUnavailable extends StatelessWidget {
  const _HomeTransactionsUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _HomeUnavailableCard(
    cardKey: const ValueKey('home-transactions-unavailable-card'),
    retryKey: const ValueKey('home-transactions-unavailable-retry'),
    titleKey: 'homeTransactionsUnavailable',
    bodyKey: 'homeTransactionsUnavailableBody',
    onRetry: onRetry,
  );
}

class _HomeReviewUnavailable extends StatelessWidget {
  const _HomeReviewUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _HomeUnavailableCard(
    cardKey: const ValueKey('home-review-unavailable-card'),
    retryKey: const ValueKey('home-review-unavailable-retry'),
    titleKey: 'homeReviewUnavailable',
    bodyKey: 'homeReviewUnavailableBody',
    onRetry: onRetry,
  );
}

class _HomeUnavailableCard extends StatelessWidget {
  const _HomeUnavailableCard({
    required this.cardKey,
    required this.retryKey,
    required this.titleKey,
    required this.bodyKey,
    required this.onRetry,
  });

  final Key cardKey;
  final Key retryKey;
  final String titleKey;
  final String bodyKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    key: cardKey,
    container: true,
    liveRegion: true,
    child: Material(
      color: context.colors.subtleSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        side: BorderSide(color: context.colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ButlerlySpacing.standard),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _homeIcon(
                context,
                material: Icons.error_outline,
                cupertino: CupertinoIcons.exclamationmark_circle,
              ),
              color: context.colors.secondaryText,
            ),
            const SizedBox(width: ButlerlySpacing.small),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text(titleKey),
                    style: ButlerlyTypography.rowTitle(
                      Theme.of(context).textTheme.titleMedium ??
                          const TextStyle(),
                    ),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  Text(
                    context.l10n.text(bodyKey),
                    style: ButlerlyTypography.cardSubtitle(
                      Theme.of(context).textTheme.bodyMedium ??
                          const TextStyle(),
                    ),
                  ),
                  const SizedBox(height: ButlerlySpacing.small),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: retryKey,
                      onPressed: onRetry,
                      child: Text(context.l10n.text('tryAgain')),
                    ),
                  ),
                ],
              ),
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
    height: 320,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _HomeMonthPicker extends StatefulWidget {
  const _HomeMonthPicker({
    required this.selectedMonth,
    required this.currentMonth,
  });

  final DateTime selectedMonth;
  final DateTime currentMonth;

  @override
  State<_HomeMonthPicker> createState() => _HomeMonthPickerState();
}

class _HomeMonthPickerState extends State<_HomeMonthPicker> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.selectedMonth.year;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ButlerlySheet(
      title: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _year--),
            icon: Icon(
              _homeIcon(
                context,
                material: Icons.chevron_left_rounded,
                cupertino: CupertinoIcons.chevron_left,
              ),
            ),
          ),
          Expanded(child: Text('$_year', textAlign: TextAlign.center)),
          IconButton(
            onPressed: _year < widget.currentMonth.year
                ? () => setState(() => _year++)
                : null,
            icon: Icon(
              _homeIcon(
                context,
                material: Icons.chevron_right_rounded,
                cupertino: CupertinoIcons.chevron_right,
              ),
            ),
          ),
        ],
      ),
      content: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.4,
          crossAxisSpacing: ButlerlySpacing.compact,
          mainAxisSpacing: ButlerlySpacing.compact,
        ),
        itemBuilder: (context, index) {
          final candidate = DateTime(_year, index + 1, 1);
          final future = _monthStart(
            candidate,
          ).isAfter(_monthStart(widget.currentMonth));
          final selected = _sameMonth(candidate, widget.selectedMonth);
          final label = DateFormat.MMM(locale).format(candidate);
          return selected
              ? FilledButton(
                  key: Key('home-month-${candidate.year}-${candidate.month}'),
                  onPressed: future
                      ? null
                      : () => Navigator.of(context).pop(candidate),
                  child: Text(label),
                )
              : OutlinedButton(
                  key: Key('home-month-${candidate.year}-${candidate.month}'),
                  onPressed: future
                      ? null
                      : () => Navigator.of(context).pop(candidate),
                  child: Text(label),
                );
        },
      ),
    );
  }
}

enum _HomeDataStatus {
  available,
  periodUnavailable,
  transactionsUnavailable,
  reviewUnavailable,
}

class _HomeData {
  const _HomeData({
    required this.transactions,
    required this.reviewCount,
    required this.uncategorizedTransactionCount,
    required this.possibleDuplicateCount,
    required this.merchantReviewCount,
    required this.masterData,
    required this.model,
    required this.insight,
    required this.trend,
    required this.trendUnavailable,
    required this.displayMonth,
    required this.currentFinancialMonth,
    required this.period,
    required this.analysisUnavailable,
    required this.duplicateUnavailable,
    required this.status,
  });

  factory _HomeData.empty(
    DateTime now, {
    DateTime? selectedMonth,
    HomePeriodResolution? resolution,
  }) {
    final currentMonth = resolution?.currentFinancialMonth ?? _monthStart(now);
    final displayMonth =
        resolution?.displayMonth ?? _monthStart(selectedMonth ?? currentMonth);
    return _HomeData(
      transactions: const [],
      reviewCount: 0,
      uncategorizedTransactionCount: 0,
      possibleDuplicateCount: 0,
      merchantReviewCount: 0,
      duplicateUnavailable: false,
      masterData: const TransactionMasterData(),
      model: null,
      insight: null,
      trend: const [],
      trendUnavailable: true,
      displayMonth: displayMonth,
      currentFinancialMonth: currentMonth,
      period: resolution?.period,
      analysisUnavailable: false,
      status: _HomeDataStatus.available,
    );
  }

  factory _HomeData.unavailable(DateTime now, {DateTime? selectedMonth}) {
    final currentMonth = _monthStart(now);
    return _HomeData(
      transactions: const [],
      reviewCount: 0,
      uncategorizedTransactionCount: 0,
      possibleDuplicateCount: 0,
      merchantReviewCount: 0,
      duplicateUnavailable: false,
      masterData: const TransactionMasterData(),
      model: null,
      insight: null,
      trend: const [],
      trendUnavailable: true,
      displayMonth: _monthStart(selectedMonth ?? currentMonth),
      currentFinancialMonth: currentMonth,
      period: null,
      analysisUnavailable: false,
      status: _HomeDataStatus.periodUnavailable,
    );
  }

  factory _HomeData.transactionsUnavailable({
    required DateTime displayMonth,
    required DateTime currentFinancialMonth,
  }) => _HomeData(
    transactions: const [],
    reviewCount: 0,
    uncategorizedTransactionCount: 0,
    possibleDuplicateCount: 0,
    merchantReviewCount: 0,
    duplicateUnavailable: false,
    masterData: const TransactionMasterData(),
    model: null,
    insight: null,
    trend: const [],
    trendUnavailable: true,
    displayMonth: displayMonth,
    currentFinancialMonth: currentFinancialMonth,
    period: null,
    analysisUnavailable: false,
    status: _HomeDataStatus.transactionsUnavailable,
  );

  final List<TransactionDto> transactions;
  final int reviewCount;
  final int uncategorizedTransactionCount;
  final int possibleDuplicateCount;
  final int merchantReviewCount;
  final bool duplicateUnavailable;
  final TransactionMasterData masterData;
  final AnalysisModel? model;
  final InsightResult? insight;
  final List<_HomeTrendPoint> trend;
  final bool trendUnavailable;
  final DateTime displayMonth;
  final DateTime currentFinancialMonth;
  final AnalysisPeriod? period;
  final bool analysisUnavailable;
  final _HomeDataStatus status;
}

class _HomeTrendPoint {
  const _HomeTrendPoint({
    required this.month,
    required this.value,
    required this.metric,
    required this.selected,
  });

  final DateTime month;
  final double value;
  final AnalysisMetric? metric;
  final bool selected;
}

DateTime _monthStart(DateTime value) => DateTime(value.year, value.month, 1);

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;

String _homeMoney(
  BuildContext context,
  AnalysisMetric metric, {
  bool signed = false,
}) {
  final formatted = analysisMoney(context, metric);
  if (!signed || analysisNumber(metric) <= 0 || formatted.startsWith('+')) {
    return formatted;
  }
  return '+$formatted';
}

IconData _homeIcon(
  BuildContext context, {
  required IconData material,
  required IconData cupertino,
}) => !kIsWeb && Theme.of(context).platform == TargetPlatform.iOS
    ? cupertino
    : material;

String _periodRoute(
  String path,
  AnalysisPeriod period, {
  required bool currentMonth,
  bool includeUndated = false,
}) {
  if (path == '/analysis' || path == '/insights') {
    if (currentMonth) return path;
    final start = DateTime.parse(period.startDate);
    final month =
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}';
    return Uri(path: path, queryParameters: {'month': month}).toString();
  }
  final queryParameters = <String, String>{
    'from': period.startDate,
    'to': period.endDate,
  };
  if (includeUndated) queryParameters['includeUndated'] = 'true';
  return Uri(path: path, queryParameters: queryParameters).toString();
}

String _reviewRoute(
  AnalysisPeriod period, {
  String view = 'needsReview',
  ReviewIssueReason? reason,
}) => Uri(
  path: '/review',
  queryParameters: {
    'view': view,
    'from': period.startDate,
    'to': period.endDate,
    'timeZoneId': period.timeZoneId,
    if (reason != null) 'reason': reason.name,
  },
).toString();
