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
    final previousStart = switch (primary.periodType) {
      'month' => DateTime.utc(primary.start.year, primary.start.month - 1, 1),
      'year' => DateTime.utc(primary.start.year - 1, 1, 1),
      _ => end.subtract(duration),
    };
    final previousEnd = switch (primary.periodType) {
      'month' => DateTime.utc(previousStart.year, previousStart.month + 1, 1),
      'year' => DateTime.utc(previousStart.year + 1, 1, 1),
      _ => end,
    };
    final previousDuration = previousEnd.difference(previousStart);
    final comparableElapsed = elapsed > previousDuration
        ? previousDuration
        : elapsed;
    return AnalysisPeriodResolved(
      ResolvedAnalysisWindow(
        start: previousStart,
        endExclusive: coverage == AnalysisCoverageState.partial
            ? previousStart.add(comparableElapsed)
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

  DateTime _financialDate(DateTime instant, String timeZoneId) {
    time_zone_data.initializeTimeZones();
    final value = time_zone.TZDateTime.from(
      instant.toUtc(),
      time_zone.getLocation(timeZoneId),
    );
    return DateTime.utc(value.year, value.month, value.day);
  }

  DateTime _parseDate(String value) {
    final parsed = DateTime.parse(value);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
