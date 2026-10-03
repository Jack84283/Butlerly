import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/analysis_overview.dart';
import '../dto/home_overview.dart';
import '../dto/review_item_dto.dart';
import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'analysis_use_cases.dart';
import '../commands/transaction_commands.dart';
import 'home_period_use_case.dart';
import 'monthly_spending_trend_use_case.dart';
import 'transaction_use_cases.dart';

/// Coordinates the application data needed by Home for one selected month.
///
/// This use case owns financial period and query orchestration while keeping
/// presentation-specific label and formatting work outside the application
/// package.
final class GetHomeOverview {
  const GetHomeOverview({
    required this.resolveHomePeriod,
    required this.calculateAnalysis,
    required this.calculateInsights,
    required this.listTransactions,
    required this.listReviewItems,
  });

  final ResolveHomePeriod resolveHomePeriod;
  final CalculateAnalysisOverview? calculateAnalysis;
  final CalculateInsights? calculateInsights;
  final ListTransactions listTransactions;
  final ListReviewItems listReviewItems;

  Future<ApplicationResult<HomeOverview>> call({
    required DateTime instant,
    DateTime? selectedMonth,
    bool forceAnalysisRefresh = false,
  }) async {
    final CalculateAnalysisOverview? analysisUseCase = calculateAnalysis;
    final _HomeContextResolution homeResolution;
    if (analysisUseCase == null) {
      // Transactions and review remain useful while analysis is not installed
      // yet. ResolveHomePeriod supplies the period in that configuration; no
      // financial metric is synthesized here.
      final fallbackResult = await _fallbackHomeContext(
        instant: instant,
        selectedMonth: selectedMonth,
      );
      if (fallbackResult case ApplicationFailure<_HomeContextResolution>()) {
        return const ApplicationSuccess(HomeOverview.periodUnavailable());
      }
      homeResolution =
          (fallbackResult as ApplicationSuccess<_HomeContextResolution>).value;
    } else {
      final analysisResolution = await _resolveWithAnalysis(
        analysisUseCase,
        instant: instant,
        selectedMonth: selectedMonth,
      );
      if (analysisResolution
          case ApplicationFailure<_HomeContextResolution>()) {
        return const ApplicationSuccess(HomeOverview.periodUnavailable());
      }
      homeResolution =
          (analysisResolution as ApplicationSuccess<_HomeContextResolution>)
              .value;
    }
    final homePeriod = homeResolution.homePeriod;
    final context = homeResolution.context;
    final analysisContextUnavailable =
        homeResolution.analysisContextUnavailable;

    // Review is independent of the selected-period transaction read. Start it
    // before awaiting the transaction query so the existing Home loading
    // behavior remains responsive without moving review filtering here.
    final reviewResultFuture = listReviewItems();
    final transactionResult = await listTransactions(
      ListTransactionsQuery(
        from: DateTime.parse(context.period.startDate),
        to: DateTime.parse(context.period.endDate),
        status: TransactionStatus.active,
        timeZoneId: context.period.timeZoneId,
      ),
    );
    if (transactionResult is ApplicationFailure<List<TransactionDto>>) {
      await reviewResultFuture;
      return ApplicationSuccess(
        HomeOverview.transactionsUnavailable(
          context: context,
          currentFinancialMonth: homePeriod.currentFinancialMonth,
          displayMonth: homePeriod.displayMonth,
        ),
      );
    }
    final transactions =
        (transactionResult as ApplicationSuccess<List<TransactionDto>>).value;
    final reviewResult = await reviewResultFuture;

    final AnalysisOverview? analysis;
    final List<InsightResult> insights;
    final bool analysisUnavailable;
    if (analysisUseCase == null || analysisContextUnavailable) {
      analysis = null;
      insights = const [];
      analysisUnavailable = true;
    } else {
      final analysisResult = await analysisUseCase(
        context,
        forceRefresh: forceAnalysisRefresh,
      );
      if (analysisResult case ApplicationSuccess<List<RuleExecutionResult>>(
        :final value,
      )) {
        analysis = AnalysisOverview.fromResults(value);
        insights = calculateInsights == null
            ? const []
            : calculateInsights!.fromResults(context, value).activeFindings;
        analysisUnavailable = false;
      } else {
        analysis = null;
        insights = const [];
        analysisUnavailable = true;
      }
    }

    final List<MonthlySpendingTrendPoint> monthlyTrend;
    final bool monthlyTrendUnavailable;
    if (analysisUseCase == null || analysisContextUnavailable) {
      monthlyTrend = const [];
      monthlyTrendUnavailable = true;
    } else {
      final trendResult = await CalculateMonthlySpendingTrend(analysisUseCase)(
        endingMonth: homePeriod.displayMonth,
        instant: instant,
      );
      if (trendResult case ApplicationSuccess<List<MonthlySpendingTrendPoint>>(
        :final value,
      )) {
        monthlyTrend = value;
        monthlyTrendUnavailable = false;
      } else {
        monthlyTrend = const [];
        monthlyTrendUnavailable = true;
      }
    }

    final periodTransactionIds = transactions.map((value) => value.id).toSet();
    final reviewItems = switch (reviewResult) {
      ApplicationSuccess<List<ReviewItemDto>>(:final value) => value,
      _ => const <ReviewItemDto>[],
    };
    final reviewCount = reviewItems
        .where((item) => periodTransactionIds.contains(item.transactionId))
        .length;

    return ApplicationSuccess(
      HomeOverview.available(
        context: context,
        currentFinancialMonth: homePeriod.currentFinancialMonth,
        displayMonth: homePeriod.displayMonth,
        analysis: analysis,
        monthlyTrend: monthlyTrend,
        monthlyTrendUnavailable: monthlyTrendUnavailable,
        reviewCount: reviewCount,
        recentTransactions: transactions.take(4).toList(growable: false),
        insights: insights,
        analysisUnavailable: analysisUnavailable,
        reviewUnavailable: reviewResult is! ApplicationSuccess,
      ),
    );
  }

  Future<ApplicationResult<_HomeContextResolution>> _resolveWithAnalysis(
    CalculateAnalysisOverview analysis, {
    required DateTime instant,
    DateTime? selectedMonth,
  }) async {
    final currentContextResult = await analysis.contextFor(
      'current_month',
      instant: instant,
    );
    if (currentContextResult case ApplicationFailure<AnalysisContext>()) {
      return _fallbackHomeContext(
        instant: instant,
        selectedMonth: selectedMonth,
      );
    }
    final currentContext =
        (currentContextResult as ApplicationSuccess<AnalysisContext>).value;
    final currentFinancialMonth = _monthStart(
      DateTime.parse(currentContext.period.startDate),
    );
    final displayMonth = _monthStart(selectedMonth ?? currentFinancialMonth);
    if (_sameMonth(displayMonth, currentFinancialMonth)) {
      return ApplicationSuccess(
        _HomeContextResolution(
          homePeriod: HomePeriodResolution(
            period: currentContext.period,
            currentFinancialMonth: currentFinancialMonth,
            displayMonth: displayMonth,
          ),
          context: currentContext,
          analysisContextUnavailable: false,
        ),
      );
    }

    final selectedContextResult = await analysis.contextFor(
      'selected_month',
      instant: instant,
      customPeriod: AnalysisPeriod(
        startDate: _date(displayMonth),
        endDate: _date(displayMonth),
        timeZoneId: currentContext.period.timeZoneId,
      ),
    );
    if (selectedContextResult case ApplicationFailure<AnalysisContext>()) {
      return _fallbackHomeContext(
        instant: instant,
        selectedMonth: selectedMonth,
      );
    }
    final selectedContext =
        (selectedContextResult as ApplicationSuccess<AnalysisContext>).value;
    return ApplicationSuccess(
      _HomeContextResolution(
        homePeriod: HomePeriodResolution(
          period: selectedContext.period,
          currentFinancialMonth: currentFinancialMonth,
          displayMonth: displayMonth,
        ),
        context: selectedContext,
        analysisContextUnavailable: false,
      ),
    );
  }

  Future<ApplicationResult<_HomeContextResolution>> _fallbackHomeContext({
    required DateTime instant,
    DateTime? selectedMonth,
  }) async {
    final homePeriodResult = await resolveHomePeriod(
      instant: instant,
      selectedMonth: selectedMonth,
    );
    if (homePeriodResult case ApplicationFailure<HomePeriodResolution>(
      :final failure,
    )) {
      return ApplicationFailure(failure);
    }
    final homePeriod =
        (homePeriodResult as ApplicationSuccess<HomePeriodResolution>).value;
    return ApplicationSuccess(
      _HomeContextResolution(
        homePeriod: homePeriod,
        context: AnalysisContext(
          period: homePeriod.period,
          datasetMode: DatasetMode.allEligible,
          currencyBasis: CurrencyBasis.baseCurrency,
          periodType:
              _sameMonth(
                homePeriod.displayMonth,
                homePeriod.currentFinancialMonth,
              )
              ? 'current_month'
              : 'selected_month',
        ),
        analysisContextUnavailable: true,
      ),
    );
  }
}

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;

DateTime _monthStart(DateTime value) => DateTime(value.year, value.month, 1);

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

final class _HomeContextResolution {
  const _HomeContextResolution({
    required this.homePeriod,
    required this.context,
    required this.analysisContextUnavailable,
  });

  final HomePeriodResolution homePeriod;
  final AnalysisContext context;
  final bool analysisContextUnavailable;
}
