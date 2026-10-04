import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../use_cases/transaction_use_cases.dart';

enum AnalysisCoverageState { complete, partial, unresolved }

final class ResolvedAnalysisWindow {
  const ResolvedAnalysisWindow({
    required this.start,
    required this.endExclusive,
    required this.timeZoneId,
    required this.coverage,
    this.periodType = 'custom',
    this.limitations = const [],
  });

  final DateTime start;
  final DateTime endExclusive;
  final String timeZoneId;
  final AnalysisCoverageState coverage;
  final String periodType;
  final List<String> limitations;
}

sealed class AnalysisPeriodResolution {
  const AnalysisPeriodResolution();
}

final class AnalysisPeriodResolved extends AnalysisPeriodResolution {
  const AnalysisPeriodResolved(this.window);
  final ResolvedAnalysisWindow window;
}

final class AnalysisPeriodResolutionFailure extends AnalysisPeriodResolution {
  const AnalysisPeriodResolutionFailure(this.code);
  final String code;
}

/// UTC instants corresponding to the inclusive calendar-date range used by a
/// financial period.
final class FinancialInstantRange {
  const FinancialInstantRange({this.start, this.endExclusive});

  final DateTime? start;
  final DateTime? endExclusive;
}

/// Parses a date-only financial boundary without allowing DateTime's
/// overflow normalization to turn malformed input into another date.
DateTime parseFinancialDateOnly(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const DomainValidationException(
      code: DomainErrorCode.invalidState,
      field: 'period',
      message: 'Financial period dates must use YYYY-MM-DD.',
    );
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const DomainValidationException(
      code: DomainErrorCode.invalidState,
      field: 'period',
      message: 'Financial period contains an invalid calendar date.',
    );
  }
  return parsed;
}

/// A validated financial timezone resolved by the application boundary.
///
/// Missing preferences and preference-store failures deliberately use UTC at
/// the caller boundary. A persisted but invalid IANA identifier is different:
/// it is a validation failure and is converted into an ApplicationFailure by
/// the surrounding use case. Keeping that policy here prevents callers from
/// applying different timezone validation or fallback behavior.
final class ResolvedFinancialTimeZone {
  const ResolvedFinancialTimeZone({required this.id, required this.location});

  final String id;
  final time_zone.Location location;
}

bool _financialTimeZonesInitialized = false;
final _financialTimeZones = <String, ResolvedFinancialTimeZone>{};

ResolvedFinancialTimeZone resolveFinancialTimeZone(String timeZoneId) {
  final normalized = timeZoneId.trim();
  if (normalized.isEmpty) {
    throw const DomainValidationException(
      code: DomainErrorCode.invalidState,
      field: 'timeZoneId',
      message: 'Financial timezone must be a valid IANA timezone.',
    );
  }
  if (!_financialTimeZonesInitialized) {
    time_zone_data.initializeTimeZones();
    _financialTimeZonesInitialized = true;
  }
  try {
    return _financialTimeZones.putIfAbsent(
      normalized,
      () => ResolvedFinancialTimeZone(
        id: normalized,
        location: time_zone.getLocation(normalized),
      ),
    );
  } on Object {
    throw const DomainValidationException(
      code: DomainErrorCode.invalidState,
      field: 'timeZoneId',
      message: 'Financial timezone must be a valid IANA timezone.',
    );
  }
}

/// Loads and validates the configured financial timezone using one policy.
///
/// A missing preference, missing timezone value, or preference read failure
/// uses the explicit UTC fallback. An invalid persisted identifier returns a
/// structured validation failure to the caller instead of falling through to
/// a raw timezone-library exception.
Future<ResolvedFinancialTimeZone> configuredFinancialTimeZone(
  UserPreferenceRepository? preferences,
) async {
  if (preferences == null) return resolveFinancialTimeZone('UTC');
  UserPreference? preference;
  try {
    preference = await preferences.load();
  } on Object {
    return resolveFinancialTimeZone('UTC');
  }
  return resolveFinancialTimeZone(preference?.timeZoneId ?? 'UTC');
}

/// Resolves the authoritative transaction date, then the occurrence date in
/// the financial timezone. Truly undated records remain unknown.
DateTime? transactionFinancialDate(Transaction value, String timeZoneId) {
  final businessDate = value.transactionDate?.trim();
  if (businessDate != null && businessDate.isNotEmpty) {
    final parsed = DateTime.tryParse(businessDate);
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
  final timing = value.timing;
  return timing is KnownTransactionTime
      ? financialDateAt(timing.occurredAt, timeZoneId)
      : null;
}

/// Returns financial calendar components in a UTC container so device timezone
/// conversion cannot shift a date-only value.
DateTime financialDateAt(DateTime instant, String timeZoneId) {
  final financialTimeZone = resolveFinancialTimeZone(timeZoneId);
  final value = time_zone.TZDateTime.from(
    instant.toUtc(),
    financialTimeZone.location,
  );
  return DateTime.utc(value.year, value.month, value.day);
}

/// Converts date-only period bounds into UTC instants in [timeZoneId].
///
/// The conversion belongs at the application boundary: repositories can then
/// apply an indexed timestamp predicate without needing to interpret IANA
/// timezone rules themselves.
FinancialInstantRange financialInstantRangeForCalendarDates({
  DateTime? from,
  DateTime? to,
  required String timeZoneId,
}) {
  final location = resolveFinancialTimeZone(timeZoneId).location;
  DateTime? start;
  DateTime? endExclusive;
  if (from != null) {
    start = time_zone.TZDateTime(
      location,
      from.year,
      from.month,
      from.day,
    ).toUtc();
  }
  if (to != null) {
    endExclusive = time_zone.TZDateTime(
      location,
      to.year,
      to.month,
      to.day + 1,
    ).toUtc();
  }
  return FinancialInstantRange(start: start, endExclusive: endExclusive);
}

/// Resolves financial windows in one application boundary. Callers provide
/// anchors; they never calculate financial calendar boundaries themselves.
final class AnalysisPeriodResolver {
  const AnalysisPeriodResolver({this.clock = const SystemApplicationClock()});
  final ApplicationClock clock;

  static const supportedTypes = {
    'selected_period',
    'selected_month',
    'current_month',
    'previous_month',
    'year_to_date',
    'previous_year',
    'rolling_30_days',
    'rolling_90_days',
  };

  AnalysisPeriodResolution resolvePrimary({
    required String type,
    required AnalysisContext context,
    DateTime? now,
  }) {
    try {
      final today = _financialDate(
        now ?? clock.now(),
        context.period.timeZoneId,
      );
      final window = switch (type) {
        'selected_period' => _selected(context.period),
        // Compatibility for in-memory callers from the pre-resolver API.
        'currentPeriod' => _selected(context.period),
        'selected_month' => _selectedMonth(context.period),
        'current_month' => _currentMonth(today, context.period.timeZoneId),
        'previous_month' => _previousMonth(today, context.period.timeZoneId),
        'year_to_date' => _yearToDate(today, context.period.timeZoneId),
        'previous_year' => _previousYear(today, context.period.timeZoneId),
        'rolling_30_days' => _rolling(today, 30, context.period.timeZoneId),
        'rolling_90_days' => _rolling(today, 90, context.period.timeZoneId),
        _ => null,
      };
      return window == null
          ? const AnalysisPeriodResolutionFailure('unsupportedPeriodType')
          : AnalysisPeriodResolved(window);
    } on Object {
      return const AnalysisPeriodResolutionFailure('invalidPeriod');
    }
  }

  /// Resolves a primary period with a domain-neutral name for future callers.
  AnalysisPeriodResolution resolve({
    required String type,
    required AnalysisContext context,
    DateTime? now,
  }) => resolvePrimary(type: type, context: context, now: now);

  AnalysisPeriodResolution resolvePreviousEquivalent({
    required ResolvedAnalysisWindow primary,
    DateTime? elapsedAnchor,
  }) {
    final duration = primary.endExclusive.difference(primary.start);
    final end = primary.start;
    final anchorDate = _financialDate(
      elapsedAnchor ?? clock.now(),
      primary.timeZoneId,
    );
    final primaryStart = _dateOnly(primary.start);
    final primaryEnd = _dateOnly(primary.endExclusive);
    final elapsed = anchorDate.isBefore(primaryEnd)
        ? (anchorDate.isBefore(primaryStart)
              ? Duration.zero
              : anchorDate.difference(primaryStart))
        : duration;
    final coverage = elapsed < duration
        ? AnalysisCoverageState.partial
        : AnalysisCoverageState.complete;
    final calendarDuration = switch (primary.periodType) {
      'month' => DateTime.utc(
        primary.start.year,
        primary.start.month + 1,
        1,
      ).difference(DateTime.utc(primary.start.year, primary.start.month, 1)),
      'year' => DateTime.utc(
        primary.start.year + 1,
        1,
        1,
      ).difference(DateTime.utc(primary.start.year, 1, 1)),
      _ => duration,
    };
    final partialCalendar =
        primary.coverage == AnalysisCoverageState.partial ||
        duration < calendarDuration;
    final elapsedCalendar = primary.limitations.any(
      (value) =>
          value == 'currentMonthToDate' || value == 'currentYearInProgress',
    );
    final comparableCalendarDuration = elapsedCalendar ? elapsed : duration;
    final previousStart = switch (primary.periodType) {
      'month' => DateTime.utc(primary.start.year, primary.start.month - 1, 1),
      'year' => DateTime.utc(primary.start.year - 1, 1, 1),
      _ => end.subtract(duration),
    };
    final fullPreviousEnd = switch (primary.periodType) {
      'month' => DateTime.utc(previousStart.year, previousStart.month + 1, 1),
      'year' => DateTime.utc(previousStart.year + 1, 1, 1),
      _ => end,
    };
    final previousDuration = fullPreviousEnd.difference(previousStart);
    final previousEnd = partialCalendar
        ? previousStart.add(
            comparableCalendarDuration > previousDuration
                ? previousDuration
                : comparableCalendarDuration,
          )
        : fullPreviousEnd;
    final comparableElapsed = elapsed > previousDuration
        ? previousDuration
        : elapsed;
    return AnalysisPeriodResolved(
      ResolvedAnalysisWindow(
        start: previousStart,
        endExclusive:
            partialCalendar || coverage == AnalysisCoverageState.partial
            ? previousStart.add(
                partialCalendar
                    ? previousEnd.difference(previousStart)
                    : comparableElapsed,
              )
            : previousEnd,
        timeZoneId: primary.timeZoneId,
        coverage: coverage,
        limitations: coverage == AnalysisCoverageState.partial
            ? const ['equivalentElapsedCoverage']
            : const [],
      ),
    );
  }

  ResolvedAnalysisWindow _selected(AnalysisPeriod period) =>
      ResolvedAnalysisWindow(
        start: _parseDate(period.startDate),
        endExclusive: _parseDate(period.endDate).add(const Duration(days: 1)),
        timeZoneId: period.timeZoneId,
        coverage: AnalysisCoverageState.complete,
      );

  ResolvedAnalysisWindow _selectedMonth(AnalysisPeriod period) {
    final selected = _parseDate(period.startDate);
    return _month(selected.year, selected.month, period.timeZoneId);
  }

  ResolvedAnalysisWindow _month(int year, int month, String timeZoneId) =>
      ResolvedAnalysisWindow(
        start: DateTime.utc(year, month, 1),
        endExclusive: DateTime.utc(year, month + 1, 1),
        timeZoneId: timeZoneId,
        coverage: AnalysisCoverageState.complete,
        periodType: 'month',
      );

  ResolvedAnalysisWindow _currentMonth(DateTime today, String timeZoneId) {
    final start = DateTime.utc(today.year, today.month, 1);
    return ResolvedAnalysisWindow(
      start: start,
      endExclusive: DateTime.utc(today.year, today.month, today.day + 1),
      timeZoneId: timeZoneId,
      coverage: AnalysisCoverageState.partial,
      periodType: 'month',
      limitations: const ['currentMonthToDate'],
    );
  }

  ResolvedAnalysisWindow _previousMonth(DateTime today, String timeZoneId) {
    final current = DateTime.utc(today.year, today.month, 1);
    return ResolvedAnalysisWindow(
      start: DateTime.utc(current.year, current.month - 1, 1),
      endExclusive: current,
      timeZoneId: timeZoneId,
      coverage: AnalysisCoverageState.complete,
      periodType: 'month',
    );
  }

  ResolvedAnalysisWindow _yearToDate(DateTime today, String timeZoneId) =>
      ResolvedAnalysisWindow(
        start: DateTime.utc(today.year, 1, 1),
        endExclusive: today.add(const Duration(days: 1)),
        timeZoneId: timeZoneId,
        coverage: AnalysisCoverageState.partial,
        periodType: 'year',
        limitations: const ['currentYearInProgress'],
      );

  ResolvedAnalysisWindow _previousYear(DateTime today, String timeZoneId) =>
      ResolvedAnalysisWindow(
        start: DateTime.utc(today.year - 1, 1, 1),
        endExclusive: DateTime.utc(today.year, 1, 1),
        timeZoneId: timeZoneId,
        coverage: AnalysisCoverageState.complete,
        periodType: 'year',
      );

  ResolvedAnalysisWindow _rolling(
    DateTime today,
    int days,
    String timeZoneId,
  ) => ResolvedAnalysisWindow(
    start: today.subtract(Duration(days: days - 1)),
    endExclusive: today.add(const Duration(days: 1)),
    timeZoneId: timeZoneId,
    coverage: AnalysisCoverageState.partial,
    limitations: const ['rollingWindowIncludesCurrentDate'],
  );

  DateTime _financialDate(DateTime instant, String timeZoneId) =>
      financialDateAt(instant, timeZoneId);

  DateTime _parseDate(String value) {
    return parseFinancialDateOnly(value);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
