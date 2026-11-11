import 'package:butlerly_finance_application/src/use_cases/home_overview_use_case.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

AnalysisContext _context(String type, String start, String end) =>
    AnalysisContext(
      period: AnalysisPeriod(startDate: start, endDate: end, timeZoneId: 'UTC'),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      periodType: type,
    );

void main() {
  test('current month uses equal month-to-date coverage', () {
    final baseline = resolveHomeComparisonPeriod(
      _context('current_month', '2026-11-01', '2026-11-11'),
      DateTime.utc(2026, 11, 11, 12),
    );
    expect(baseline?.startDate, '2026-10-01');
    expect(baseline?.endDate, '2026-10-11');
  });

  test('first day of month compares against first previous-month day', () {
    final baseline = resolveHomeComparisonPeriod(
      _context('current_month', '2024-03-01', '2024-03-01'),
      DateTime.utc(2024, 3, 1, 23, 59),
    );
    expect(baseline?.startDate, '2024-02-01');
    expect(baseline?.endDate, '2024-02-01');
  });

  test('complete month compares to leap-year February without truncation', () {
    final baseline = resolveHomeComparisonPeriod(
      _context('selected_month', '2024-03-01', '2024-03-31'),
      DateTime.utc(2024, 11, 11),
    );
    expect(baseline?.startDate, '2024-02-01');
    expect(baseline?.endDate, '2024-02-29');
  });

  test('selected complete month uses a complete previous month', () {
    final baseline = resolveHomeComparisonPeriod(
      _context('selected_month', '2026-10-01', '2026-10-31'),
      DateTime.utc(2026, 11, 11),
    );
    expect(baseline?.startDate, '2026-09-01');
    expect(baseline?.endDate, '2026-09-30');
  });

  test('month-length differences do not leak dates into current window', () {
    final baseline = resolveHomeComparisonPeriod(
      _context('current_month', '2026-03-01', '2026-03-31'),
      DateTime.utc(2026, 3, 31),
    );
    expect(baseline?.startDate, '2026-02-01');
    expect(baseline?.endDate, '2026-02-28');
  });
}
