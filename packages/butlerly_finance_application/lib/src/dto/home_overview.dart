import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'analysis_overview.dart';
import 'transaction_dto.dart';
import '../use_cases/monthly_spending_trend_use_case.dart';

/// Application-owned composition of the data needed by the Home surface.
///
/// Financial metrics remain in [analysis]. This projection only adds the
/// Home-specific composition around that authoritative analysis result.
final class HomeOverview {
  const HomeOverview({
    required this.context,
    required this.currentFinancialMonth,
    required this.displayMonth,
    required this.analysis,
    required this.monthlyTrend,
    required this.monthlyTrendUnavailable,
    required this.reviewCount,
    required this.recentTransactions,
    required this.insights,
    required this.analysisUnavailable,
    required this.reviewUnavailable,
  });

  final AnalysisContext context;
  final DateTime currentFinancialMonth;
  final DateTime displayMonth;

  final AnalysisOverview? analysis;

  final List<MonthlySpendingTrendPoint> monthlyTrend;
  final bool monthlyTrendUnavailable;

  final int reviewCount;

  final List<TransactionDto> recentTransactions;

  final List<InsightResult> insights;

  final bool analysisUnavailable;
  final bool reviewUnavailable;
}
