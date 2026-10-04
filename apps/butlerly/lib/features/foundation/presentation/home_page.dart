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
        masterData: masterData,
        model: overview.analysis,
        insight: overview.insights.firstOrNull,
        trend: [
          for (final point in overview.monthlyTrend)
            _HomeTrendPoint(
              month: _monthStart(point.month),
              value: point.spending == null
                  ? 0
                  : analysisNumber(point.spending!),
              metric: point.spending,
              selected: _sameMonth(point.month, overview.displayMonth!),
            ),
        ],
        trendUnavailable: overview.monthlyTrendUnavailable,
        displayMonth: overview.displayMonth!,
        currentFinancialMonth: overview.currentFinancialMonth!,
        period: overview.context!.period,
        analysisUnavailable: overview.analysisUnavailable,
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

    final hasUsefulAnalysis = [
      data.model?.spending,
      data.model?.income,
      data.model?.net,
      data.model?.transactionCount,
    ].whereType<AnalysisMetric>().any((metric) => analysisNumber(metric) != 0);
    final hasUsefulActivity =
        data.transactions.isNotEmpty ||
        hasUsefulAnalysis ||
        data.model?.categories.isNotEmpty == true ||
        data.insight != null ||
        data.reviewCount > 0 ||
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
          selectedMonth: data.displayMonth,
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
        ] else if (data.reviewCount > 0) ...[
          const SizedBox(height: ButlerlySpacing.cardGap),
          _AttentionSection(reviewCount: data.reviewCount, period: period!),
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
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) => SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.remainingPaintExtent,
                    ),
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
                                snapshot.connectionState !=
                                    ConnectionState.done;
                            return _homeContent(context, data, loading);
                          },
                        ),
                      ),
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
  final scaledBody = scaler.scale(14);
  final stacked = scaledBody > 18 || availableWidth < 360;
  final direction = Directionality.of(context);

  final appStyle = textTheme.headlineLarge ?? const TextStyle(fontSize: 32);
  final taglineStyle = (textTheme.labelMedium ?? const TextStyle()).copyWith(
    letterSpacing: 2.2,
    fontSize: 9.5,
  );
  final greetingStyle = textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  final monthStyle = textTheme.titleMedium ?? const TextStyle(fontSize: 16);

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

  double monthButtonHeight(double width, {required bool wrap}) {
    final textWidth =
        (width - ButlerlySpacing.compact * 2 - ButlerlySpacing.micro - 20)
            .clamp(1.0, double.infinity)
            .toDouble();
    final textHeight = maxMeasured(
      monthLabels,
      monthStyle,
      textWidth,
      maxLines: wrap ? null : 1,
    );
    final contentHeight = textHeight + ButlerlySpacing.compact * 2;
    return contentHeight > kMinInteractiveDimension
        ? contentHeight
        : kMinInteractiveDimension;
  }

  final appName = context.l10n.text('appName');
  final tagline = context.l10n.text('homeTagline');
  if (stacked) {
    final brandHeight =
        measure(appName, appStyle, availableWidth) +
        ButlerlySpacing.xxs +
        measure(tagline, taglineStyle, availableWidth);
    final contextHeight =
        maxMeasured(greetingLabels, greetingStyle, availableWidth) +
        ButlerlySpacing.xxs +
        monthButtonHeight(availableWidth, wrap: true);
    return brandHeight +
        ButlerlySpacing.standard +
        contextHeight +
        ButlerlySpacing.small +
        scaler.scale(2);
  }

  final rowWidth = availableWidth - ButlerlySpacing.standard;
  final brandWidth = rowWidth * 5 / 9;
  final contextWidth = rowWidth * 4 / 9;
  final brandHeight =
      measure(appName, appStyle, brandWidth, maxLines: 1) +
      ButlerlySpacing.xxs +
      measure(tagline, taglineStyle, brandWidth, maxLines: 2);
  final contextHeight =
      maxMeasured(greetingLabels, greetingStyle, contextWidth, maxLines: 1) +
      ButlerlySpacing.xxs +
      monthButtonHeight(contextWidth, wrap: false);
  final contentHeight = brandHeight > contextHeight
      ? brandHeight
      : contextHeight;
  return contentHeight + ButlerlySpacing.small + scaler.scale(2);
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
      builder: (context, constraints) {
        final scaledBody = MediaQuery.textScalerOf(context).scale(14);
        final stacked = scaledBody > 18 || constraints.maxWidth < 360;
        final alignContextToEdge =
            ButlerlyLayout.modeForWidth(constraints.maxWidth) !=
            ButlerlyLayoutMode.compact;
        final brand = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.text('appName'),
              maxLines: stacked ? null : 1,
              overflow: stacked ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: ButlerlySpacing.xxs),
            Text(
              context.l10n.text('homeTagline'),
              maxLines: stacked ? null : 2,
              overflow: stacked ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 2.2,
                fontSize: 9.5,
              ),
            ),
          ],
        );
        final contextBlock = Column(
          key: const ValueKey('home-header-context'),
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.text(greetingKey),
              key: const ValueKey('home-greeting'),
              maxLines: stacked ? null : 1,
              overflow: stacked ? null : TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: ButlerlySpacing.xxs),
            TextButton(
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
                      maxLines: stacked ? null : 1,
                      overflow: stacked ? null : TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleMedium,
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
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              brand,
              const SizedBox(height: ButlerlySpacing.standard),
              contextBlock,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: brand),
            const SizedBox(width: ButlerlySpacing.standard),
            if (alignContextToEdge)
              Expanded(flex: 4, child: contextBlock)
            else
              Flexible(flex: 4, child: contextBlock),
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
  Widget build(BuildContext context) => ButlerlyCard(
    key: const ValueKey('home-summary-card'),
    semanticLabel: context.l10n.text('analysisSummary'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ButlerlyCardHeader(
          title: context.l10n.text('analysisSummary'),
          action: IconButton(
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
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
            final stacked = largeText || constraints.maxWidth < 320;
            final cells = [
              _HomeMetricCell(
                key: const ValueKey('home-summary-metric-spending'),
                label: context.l10n.text('totalSpending'),
                metric: model?.spending,
              ),
              _HomeMetricCell(
                key: const ValueKey('home-summary-metric-income'),
                label: context.l10n.text('income'),
                metric: model?.income,
              ),
              _HomeMetricCell(
                key: const ValueKey('home-summary-metric-net'),
                label: context.l10n.text('netCashFlow'),
                metric: model?.net,
                signed: true,
              ),
              _HomeMetricCell(
                key: const ValueKey('home-summary-metric-count'),
                label: context.l10n.text('transactionCount'),
                metric: model?.transactionCount,
                count: true,
              ),
            ];
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < cells.length; index++) ...[
                    cells[index],
                    if (index < cells.length - 1)
                      const SizedBox(height: ButlerlySpacing.section),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cells[row * 2]),
                      const SizedBox(width: ButlerlySpacing.standard),
                      Expanded(child: cells[row * 2 + 1]),
                    ],
                  ),
                  if (row == 0) const SizedBox(height: ButlerlySpacing.section),
                ],
              ],
            );
          },
        ),
        if (analysisUnavailable) ...[
          const SizedBox(height: ButlerlySpacing.standard),
          Text(
            context.l10n.text('analysisUnavailable'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
        ],
      ],
    ),
  );
}

class _HomeMetricCell extends StatelessWidget {
  const _HomeMetricCell({
    super.key,
    required this.label,
    required this.metric,
    this.count = false,
    this.signed = false,
  });

  final String label;
  final AnalysisMetric? metric;
  final bool count;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final value = metric == null
        ? '—'
        : count
        ? localizedCount(context, metric!.value.toString())
        : _homeMoney(context, metric!, signed: signed);
    return Semantics(
      label:
          '$label, ${metric == null ? context.l10n.text('notAvailable') : value}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            value,
            softWrap: true,
            style: ButlerlyTypography.financialAmount(
              Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
            ).copyWith(fontSize: 24),
          ),
        ],
      ),
    );
  }
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

class _SpendingTrend extends StatelessWidget {
  const _SpendingTrend({
    required this.points,
    required this.unavailable,
    this.comparison,
    this.selectedMonth,
  });

  final List<_HomeTrendPoint> points;
  final bool unavailable;
  final AnalysisComparison? comparison;
  final DateTime? selectedMonth;

  @override
  Widget build(BuildContext context) {
    final meaningful = points.any((point) => point.value > 0);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final selected =
        selectedMonth ??
        points
            .where((point) => point.selected)
            .map((point) => point.month)
            .firstOrNull;
    return ButlerlyCard(
      key: const ValueKey('home-trend-card'),
      semanticLabel: context.l10n.text('spendingTrend'),
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ButlerlyCardHeader(
              title: context.l10n.text('spendingTrend'),
              subtitle: selected == null
                  ? null
                  : DateFormat.yMMMM(locale).format(selected),
            ),
            if (unavailable || points.isEmpty || !meaningful) ...[
              const SizedBox(height: ButlerlySpacing.standard),
              Text(
                context.l10n.text(
                  unavailable
                      ? 'analysisUnavailableBody'
                      : 'insufficientTrendData',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              const SizedBox(height: ButlerlySpacing.standard),
              _HomeTrendPlot(points: points, locale: locale),
              if (comparison != null &&
                  analysisComparisonText(context, comparison!).isNotEmpty) ...[
                const SizedBox(height: ButlerlySpacing.standard),
                Text(
                  analysisComparisonText(context, comparison!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: comparison!.percentageChange?.isNegative == true
                        ? context.colors.success
                        : context.colors.interactive,
                  ),
                ),
              ],
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
    return SizedBox(
      height: 156,
      child: Column(
        children: [
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
                              heightFactor: maxValue <= 0 || point.value <= 0
                                  ? 0
                                  : (point.value / maxValue)
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
                                      : context.colors.secondaryText.withValues(
                                          alpha: 0.35,
                                        ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(ButlerlyRadius.small),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
        model?.categories.take(4).toList(growable: false) ??
        const <AnalysisMetric>[];
    return ButlerlyCard(
      key: const ValueKey('home-category-card'),
      semanticLabel: context.l10n.text('analysis.rule.r010.name'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(
            title: context.l10n.text('analysis.rule.r010.name'),
            action: TextButton(
              key: const Key('home-category-view-all'),
              onPressed: onViewAll,
              child: Text(context.l10n.text('viewAll')),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          if (model == null)
            Text(
              context.l10n.text('analysisUnavailableBody'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (categories.isEmpty)
            Text(
              context.l10n.text('noSpendingInPeriod'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Column(
              children: [
                for (var index = 0; index < categories.length; index++) ...[
                  _CategorySummaryItem(
                    metric: categories[index],
                    masterData: masterData,
                  ),
                  if (index < categories.length - 1)
                    Divider(
                      height: ButlerlySpacing.section,
                      color: context.colors.cardDivider,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CategorySummaryItem extends StatelessWidget {
  const _CategorySummaryItem({required this.metric, required this.masterData});

  final AnalysisMetric metric;
  final TransactionMasterData masterData;

  @override
  Widget build(BuildContext context) {
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
    return Semantics(
      label: '$label, ${analysisMoney(context, metric)}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaledBody = MediaQuery.textScalerOf(context).scale(14);
          final stacked = scaledBody > 18 || constraints.maxWidth < 300;
          final amount = Text(
            analysisMoney(context, metric),
            textAlign: TextAlign.end,
            style: ButlerlyTypography.financialAmount(
              Theme.of(context).textTheme.titleMedium ?? const TextStyle(),
            ).copyWith(fontSize: 18),
          );
          final name = Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: ButlerlySpacing.standard),
              Expanded(
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          name,
                          const SizedBox(height: ButlerlySpacing.micro),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: amount,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: name),
                          const SizedBox(width: ButlerlySpacing.small),
                          amount,
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
  const _AttentionSection({required this.reviewCount, required this.period});

  final int reviewCount;
  final AnalysisPeriod period;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    key: const ValueKey('home-attention-card'),
    color: context.colors.selection,
    onTap: () => context.push(_reviewRoute(period)),
    semanticLabel:
        '${context.l10n.text('needsAttention')}: '
        '${context.l10n.text('dataQualityNeedsAttention', {'count': localizedCount(context, reviewCount.toString())})}',
    child: Row(
      children: [
        Icon(
          _homeIcon(
            context,
            material: Icons.notifications_none_rounded,
            cupertino: CupertinoIcons.bell,
          ),
          color: context.colors.interactive,
          size: ButlerlySize.standardIcon,
        ),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.text('needsAttention'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ButlerlySpacing.micro),
              Text(
                context.l10n.text('dataQualityNeedsAttention', {
                  'count': localizedCount(context, reviewCount.toString()),
                }),
                style: Theme.of(context).textTheme.bodySmall,
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
            action: TextButton(
              key: const Key('home-recent-view-all'),
              onPressed: onViewAll,
              child: Text(context.l10n.text('viewAll')),
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
    onTap: onTap,
    semanticLabel:
        '${context.l10n.text('notable')}: '
        '${context.l10n.text(insight.rule.nameKey)}',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _homeIcon(
            context,
            material: Icons.lightbulb_outline,
            cupertino: CupertinoIcons.lightbulb,
          ),
          color: context.colors.info,
        ),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.text('notable'),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: context.colors.info),
              ),
              const SizedBox(height: ButlerlySpacing.micro),
              Text(
                context.l10n.text(insight.rule.nameKey),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ButlerlySpacing.micro),
              Text(
                context.l10n.text(insight.rule.descriptionKey),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_homeInsightValues(context, insight) case final values?) ...[
                const SizedBox(height: ButlerlySpacing.small),
                Text(
                  values,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: ButlerlySpacing.micro),
              Text(
                _homeInsightContext(context, insight),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (insight.evidence.isNotEmpty) ...[
                const SizedBox(height: ButlerlySpacing.micro),
                Text(
                  context.l10n.text('supportingTransactions', {
                    'count': localizedCount(
                      context,
                      insight.evidence.length.toString(),
                    ),
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            context.l10n.text('noTransactionsBody'),
            style: Theme.of(context).textTheme.bodyMedium,
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                context.l10n.text('noTransactionsBody'),
                style: Theme.of(context).textTheme.bodySmall,
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
        for (var index = 0; index < 4; index++)
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  Text(
                    context.l10n.text(bodyKey),
                    style: Theme.of(context).textTheme.bodyMedium,
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
    required this.masterData,
    required this.model,
    required this.insight,
    required this.trend,
    required this.trendUnavailable,
    required this.displayMonth,
    required this.currentFinancialMonth,
    required this.period,
    required this.analysisUnavailable,
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

String _reviewRoute(AnalysisPeriod period) => Uri(
  path: '/review',
  queryParameters: {
    'view': 'needsReview',
    'from': period.startDate,
    'to': period.endDate,
    'timeZoneId': period.timeZoneId,
  },
).toString();
