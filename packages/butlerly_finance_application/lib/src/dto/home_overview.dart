import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'analysis_overview.dart';
import 'monthly_spending_trend_point.dart';
import 'transaction_dto.dart';

/// Application-owned composition of the data needed by the Home surface.
///
/// Financial metrics remain in [analysis]. This projection only adds the
/// Home-specific composition around that authoritative analysis result.
enum HomeOverviewStatus {
  available,
  transactionsUnavailable,
  periodUnavailable,
}

final class HomeOverview {
  const HomeOverview.available({
    required AnalysisContext context,
    required DateTime currentFinancialMonth,
    required DateTime displayMonth,
    required AnalysisOverview? analysis,
    required List<MonthlySpendingTrendPoint> monthlyTrend,
    required bool monthlyTrendUnavailable,
    required int reviewCount,
    required int uncategorizedTransactionCount,
    required int possibleDuplicateCount,
    required int merchantReviewCount,
    required List<TransactionDto> recentTransactions,
    required List<InsightResult> insights,
    required bool analysisUnavailable,
    required bool reviewUnavailable,
    required bool duplicateUnavailable,
  }) : this._(
         status: HomeOverviewStatus.available,
         context: context,
         currentFinancialMonth: currentFinancialMonth,
         displayMonth: displayMonth,
         analysis: analysis,
         monthlyTrend: monthlyTrend,
         monthlyTrendUnavailable: monthlyTrendUnavailable,
         reviewCount: reviewCount,
         uncategorizedTransactionCount: uncategorizedTransactionCount,
         possibleDuplicateCount: possibleDuplicateCount,
         merchantReviewCount: merchantReviewCount,
         recentTransactions: recentTransactions,
         insights: insights,
         analysisUnavailable: analysisUnavailable,
         reviewUnavailable: reviewUnavailable,
         duplicateUnavailable: duplicateUnavailable,
       );

  const HomeOverview.transactionsUnavailable({
    required AnalysisContext context,
    required DateTime currentFinancialMonth,
    required DateTime displayMonth,
  }) : this._(
         status: HomeOverviewStatus.transactionsUnavailable,
         context: context,
         currentFinancialMonth: currentFinancialMonth,
         displayMonth: displayMonth,
       );

  const HomeOverview.periodUnavailable()
    : this._(status: HomeOverviewStatus.periodUnavailable);

  const HomeOverview._({
    required this.status,
    this.context,
    this.currentFinancialMonth,
    this.displayMonth,
    this.analysis,
    this.monthlyTrend = const [],
    this.monthlyTrendUnavailable = true,
    this.reviewCount = 0,
    this.uncategorizedTransactionCount = 0,
    this.possibleDuplicateCount = 0,
    this.merchantReviewCount = 0,
    this.recentTransactions = const [],
    this.insights = const [],
    this.analysisUnavailable = false,
    this.reviewUnavailable = false,
    this.duplicateUnavailable = false,
  });

  final HomeOverviewStatus status;

  /// Null only when [status] is [HomeOverviewStatus.periodUnavailable].
  final AnalysisContext? context;

  /// Null only when [status] is [HomeOverviewStatus.periodUnavailable].
  final DateTime? currentFinancialMonth;

  /// Null only when [status] is [HomeOverviewStatus.periodUnavailable].
  final DateTime? displayMonth;

  final AnalysisOverview? analysis;

  final List<MonthlySpendingTrendPoint> monthlyTrend;
  final bool monthlyTrendUnavailable;

  final int reviewCount;
  final int uncategorizedTransactionCount;
  final int possibleDuplicateCount;
  final int merchantReviewCount;

  final List<TransactionDto> recentTransactions;

  final List<InsightResult> insights;

  final bool analysisUnavailable;
  final bool reviewUnavailable;
  final bool duplicateUnavailable;
}
