import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

final class _Clock implements ApplicationClock {
  _Clock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-03-01',
      endDate: '2026-03-31',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
  );

  test('selected period resolves with an exclusive end boundary', () {
    final result =
        const AnalysisPeriodResolver().resolvePrimary(
              type: 'selected_period',
              context: context,
            )
            as AnalysisPeriodResolved;
    expect(result.window.start, DateTime.utc(2026, 3, 1));
    expect(result.window.endExclusive, DateTime.utc(2026, 4, 1));
    expect(result.window.timeZoneId, 'America/Los_Angeles');
  });

  test('previous equivalent period uses partial elapsed coverage', () {
    final primary =
        const AnalysisPeriodResolver().resolvePrimary(
              type: 'selected_month',
              context: context,
            )
            as AnalysisPeriodResolved;
    final result = AnalysisPeriodResolver(
      clock: _Clock(DateTime.utc(2026, 3, 16, 12)),
    ).resolvePreviousEquivalent(primary: primary.window);
    expect(result, isA<AnalysisPeriodResolved>());
    final window = (result as AnalysisPeriodResolved).window;
    expect(window.coverage, AnalysisCoverageState.partial);
    expect(window.limitations, contains('equivalentElapsedCoverage'));
  });

  test('supports month, year, leap-year, and rolling period boundaries', () {
    final resolver = AnalysisPeriodResolver(
      clock: _Clock(DateTime.utc(2024, 03, 01, 07)),
    );
    AnalysisContext contextFor(String start, String end) => AnalysisContext(
      period: AnalysisPeriod(startDate: start, endDate: end, timeZoneId: 'UTC'),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.original,
    );
    final leap = contextFor('2024-02-01', '2024-02-29');
    final current =
        resolver.resolvePrimary(type: 'current_month', context: leap)
            as AnalysisPeriodResolved;
    expect(current.window.start, DateTime.utc(2024, 3, 1));
    expect(current.window.endExclusive, DateTime.utc(2024, 4, 1));
    final previous =
        resolver.resolvePrimary(type: 'previous_month', context: leap)
            as AnalysisPeriodResolved;
    expect(previous.window.start, DateTime.utc(2024, 2, 1));
    expect(previous.window.endExclusive, DateTime.utc(2024, 3, 1));
    final year =
        resolver.resolvePrimary(type: 'previous_year', context: leap)
            as AnalysisPeriodResolved;
    expect(year.window.start, DateTime.utc(2023, 1, 1));
    expect(year.window.endExclusive, DateTime.utc(2024, 1, 1));
    final rolling =
        resolver.resolvePrimary(type: 'rolling_30_days', context: leap)
            as AnalysisPeriodResolved;
    expect(rolling.window.start, DateTime.utc(2024, 2, 1));
    expect(rolling.window.endExclusive, DateTime.utc(2024, 3, 2));
    final rollingLong =
        resolver.resolvePrimary(type: 'rolling_90_days', context: leap)
            as AnalysisPeriodResolved;
    expect(rollingLong.window.endExclusive, DateTime.utc(2024, 3, 2));
    expect(
      rollingLong.window.endExclusive.difference(rollingLong.window.start),
      const Duration(days: 90),
    );
  });

  test(
    'resolves timezone-sensitive current dates and custom selected months',
    () {
      final resolver = AnalysisPeriodResolver(
        clock: _Clock(DateTime.utc(2026, 4, 1, 6)),
      );
      final context = AnalysisContext(
        period: AnalysisPeriod(
          startDate: '2026-03-15',
          endDate: '2026-04-14',
          timeZoneId: 'America/Los_Angeles',
        ),
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.original,
      );
      final current =
          resolver.resolvePrimary(type: 'current_month', context: context)
              as AnalysisPeriodResolved;
      expect(current.window.start, DateTime.utc(2026, 3, 1));
      final month =
          resolver.resolvePrimary(type: 'selected_month', context: context)
              as AnalysisPeriodResolved;
      expect(month.window.start, DateTime.utc(2026, 3, 1));
      expect(month.window.endExclusive, DateTime.utc(2026, 4, 1));
    },
  );

  test(
    'previous equivalent period preserves duration and elapsed coverage',
    () {
      final resolver = AnalysisPeriodResolver(
        clock: _Clock(DateTime.utc(2026, 3, 16, 12)),
      );
      final primary =
          resolver.resolvePrimary(type: 'current_month', context: context)
              as AnalysisPeriodResolved;
      final result = resolver.resolvePreviousEquivalent(
        primary: primary.window,
      );
      final window = (result as AnalysisPeriodResolved).window;
      expect(window.start, DateTime.utc(2026, 2, 1));
      expect(window.endExclusive, DateTime.utc(2026, 2, 16));
      expect(window.coverage, AnalysisCoverageState.partial);
    },
  );

  test('previous equivalent period supports custom selected ranges', () {
    final resolver = AnalysisPeriodResolver(
      clock: _Clock(DateTime.utc(2027, 2, 1)),
    );
    final custom =
        resolver.resolvePrimary(
              type: 'selected_period',
              context: AnalysisContext(
                period: AnalysisPeriod(
                  startDate: '2026-01-10',
                  endDate: '2026-01-19',
                  timeZoneId: 'UTC',
                ),
                datasetMode: DatasetMode.allEligible,
                currencyBasis: CurrencyBasis.original,
              ),
            )
            as AnalysisPeriodResolved;
    final previous =
        resolver.resolvePreviousEquivalent(primary: custom.window)
            as AnalysisPeriodResolved;
    expect(previous.window.start, DateTime.utc(2025, 12, 31));
    expect(previous.window.endExclusive, DateTime.utc(2026, 1, 10));
  });

  test('unsupported primary period types fail instead of falling back', () {
    final result = const AnalysisPeriodResolver().resolvePrimary(
      type: 'not_a_period',
      context: context,
    );
    expect(result, isA<AnalysisPeriodResolutionFailure>());
    expect(
      (result as AnalysisPeriodResolutionFailure).code,
      'unsupportedPeriodType',
    );
  });
}
