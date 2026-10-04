import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/period_resolver.dart';

enum ReviewPeriodScopeStatus { unscoped, scoped, invalid }

/// Semantic scope for the Review application capability.
///
/// Route parsing belongs to presentation, but the resulting period values are
/// validated here so every Review caller shares the same financial-date and
/// timezone rules.
final class ReviewPeriodScope {
  const ReviewPeriodScope.unscoped()
    : status = ReviewPeriodScopeStatus.unscoped,
      period = null;

  const ReviewPeriodScope.invalid()
    : status = ReviewPeriodScopeStatus.invalid,
      period = null;

  const ReviewPeriodScope._scoped(this.period)
    : status = ReviewPeriodScopeStatus.scoped,
      assert(period != null);

  factory ReviewPeriodScope.scoped({required AnalysisPeriod period}) =>
      ReviewPeriodScope._scoped(period);

  factory ReviewPeriodScope.fromDateValues({
    required String startDate,
    required String endDate,
    required String timeZoneId,
  }) {
    try {
      final start = parseFinancialDateOnly(startDate);
      final end = parseFinancialDateOnly(endDate);
      resolveFinancialTimeZone(timeZoneId);
      if (start.isAfter(end)) return const ReviewPeriodScope.invalid();
      return ReviewPeriodScope.scoped(
        period: AnalysisPeriod(
          startDate: _date(start),
          endDate: _date(end),
          timeZoneId: timeZoneId,
        ),
      );
    } on Object {
      return const ReviewPeriodScope.invalid();
    }
  }

  final ReviewPeriodScopeStatus status;
  final AnalysisPeriod? period;

  bool get isScoped => status == ReviewPeriodScopeStatus.scoped;
  bool get isInvalid => status == ReviewPeriodScopeStatus.invalid;

  @override
  bool operator ==(Object other) =>
      other is ReviewPeriodScope &&
      other.status == status &&
      other.period?.startDate == period?.startDate &&
      other.period?.endDate == period?.endDate &&
      other.period?.timeZoneId == period?.timeZoneId;

  @override
  int get hashCode => Object.hash(
    status,
    period?.startDate,
    period?.endDate,
    period?.timeZoneId,
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
