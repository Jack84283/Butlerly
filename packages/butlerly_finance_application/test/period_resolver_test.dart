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
    expect(result.window.start, DateTime(2026, 3, 1));
    expect(result.window.endExclusive, DateTime(2026, 4, 1));
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
      clock: _Clock(DateTime.utc(2026, 3, 16)),
    ).resolvePreviousEquivalent(primary: primary.window);
    expect(result, isA<AnalysisPeriodResolved>());
    final window = (result as AnalysisPeriodResolved).window;
    expect(window.coverage, AnalysisCoverageState.partial);
    expect(window.limitations, contains('equivalentElapsedCoverage'));
  });

  test('unsupported primary period types fail instead of falling back', () {
    final result = const AnalysisPeriodResolver().resolvePrimary(
      type: 'current_month',
      context: context,
    );
    expect(result, isA<AnalysisPeriodResolutionFailure>());
    expect(
      (result as AnalysisPeriodResolutionFailure).code,
      'unsupportedPeriodType',
    );
  });
}
