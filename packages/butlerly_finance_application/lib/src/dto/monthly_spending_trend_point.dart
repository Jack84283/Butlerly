import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// One authoritative monthly spending value for presentation trends.
///
/// [month] is a calendar anchor only. Financial boundaries and timezone
/// semantics remain owned by the analysis period resolver.
final class MonthlySpendingTrendPoint {
  const MonthlySpendingTrendPoint({
    required this.month,
    required this.spending,
  });

  final DateTime month;
  final AnalysisMetric? spending;
}
