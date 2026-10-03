import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/period_resolver.dart';
import '../result/application_result.dart';

final class HomePeriodResolution {
  const HomePeriodResolution({
    required this.period,
    required this.currentFinancialMonth,
    required this.displayMonth,
  });

  final AnalysisPeriod period;
  final DateTime currentFinancialMonth;
  final DateTime displayMonth;
}

/// Resolves the period used by Home, including the persisted financial
/// timezone, before presentation requests transactions or analysis data.
final class ResolveHomePeriod {
  const ResolveHomePeriod(this.preferences);

  final UserPreferenceRepository preferences;

  /// Provides the same safe startup fallback Home historically used when the
  /// finance services are not available yet. The fallback stays in the
  /// application layer so presentation code never constructs a financial
  /// period directly.
  static HomePeriodResolution utcFallback({
    required DateTime instant,
    DateTime? selectedMonth,
  }) => _resolveHomePeriod(
    instant: instant,
    selectedMonth: selectedMonth,
    timeZoneId: 'UTC',
  );

  Future<ApplicationResult<HomePeriodResolution>> call({
    required DateTime instant,
    DateTime? selectedMonth,
  }) => runApplication('resolve Home period', () async {
    UserPreference? preference;
    try {
      preference = await preferences.load();
    } catch (_) {
      // Home previously continued with UTC when preferences were unavailable.
      // Keep period reads usable while still honoring the persisted zone when
      // it can be loaded.
    }
    final timeZoneId = preference?.timeZoneId ?? 'UTC';
    return _resolveHomePeriod(
      instant: instant,
      selectedMonth: selectedMonth,
      timeZoneId: timeZoneId,
    );
  });
}

HomePeriodResolution _resolveHomePeriod({
  required DateTime instant,
  DateTime? selectedMonth,
  required String timeZoneId,
}) {
  final currentFinancialDate = financialDateAt(instant, timeZoneId);
  final currentFinancialMonth = _monthStart(currentFinancialDate);
  final displayMonth = _monthStart(selectedMonth ?? currentFinancialMonth);
  final period = _sameMonth(displayMonth, currentFinancialMonth)
      ? _resolveMonth(
          month: currentFinancialMonth,
          type: 'current_month',
          instant: instant,
          timeZoneId: timeZoneId,
        )
      : _resolveMonth(
          month: displayMonth,
          type: 'selected_month',
          instant: instant,
          timeZoneId: timeZoneId,
        );
  return HomePeriodResolution(
    period: period,
    currentFinancialMonth: currentFinancialMonth,
    displayMonth: displayMonth,
  );
}

AnalysisPeriod _resolveMonth({
  required DateTime month,
  required String type,
  required DateTime instant,
  required String timeZoneId,
}) {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: _date(month),
      endDate: _date(month),
      timeZoneId: timeZoneId,
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    periodType: type,
  );
  final resolution = const AnalysisPeriodResolver().resolvePrimary(
    type: type,
    context: context,
    now: instant,
  );
  if (resolution case AnalysisPeriodResolved(:final window)) {
    return AnalysisPeriod(
      startDate: _date(window.start),
      endDate: _date(window.endExclusive.subtract(const Duration(days: 1))),
      timeZoneId: window.timeZoneId,
    );
  }
  throw const DomainValidationException(
    code: DomainErrorCode.invalidState,
    field: 'period',
    message: 'Home period could not be resolved.',
  );
}

DateTime _monthStart(DateTime value) => DateTime(value.year, value.month, 1);

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
