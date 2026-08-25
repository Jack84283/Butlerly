import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../use_cases/transaction_use_cases.dart';

enum AnalysisCoverageState { complete, partial, unresolved }

final class ResolvedAnalysisWindow {
  const ResolvedAnalysisWindow({
    required this.start,
    required this.endExclusive,
    required this.timeZoneId,
    required this.coverage,
    this.limitations = const [],
  });

  final DateTime start;
  final DateTime endExclusive;
  final String timeZoneId;
  final AnalysisCoverageState coverage;
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

  AnalysisPeriodResolution resolvePrimary({
    required String type,
    required AnalysisContext context,
  }) {
    if (type != 'selected_period' && type != 'selected_month') {
      return const AnalysisPeriodResolutionFailure('unsupportedPeriodType');
    }
    final start = DateTime.parse(context.period.startDate);
    final end = DateTime.parse(
      context.period.endDate,
    ).add(const Duration(days: 1));
    return AnalysisPeriodResolved(
      ResolvedAnalysisWindow(
        start: start,
        endExclusive: end,
        timeZoneId: context.period.timeZoneId,
        coverage: AnalysisCoverageState.complete,
      ),
    );
  }

  AnalysisPeriodResolution resolvePreviousEquivalent({
    required ResolvedAnalysisWindow primary,
    DateTime? elapsedAnchor,
  }) {
    final duration = primary.endExclusive.difference(primary.start);
    final end = primary.start;
    final start = end.subtract(duration);
    final anchor = elapsedAnchor ?? clock.now();
    final elapsed = anchor.isBefore(primary.endExclusive)
        ? anchor.difference(primary.start)
        : duration;
    final coverage = elapsed < duration
        ? AnalysisCoverageState.partial
        : AnalysisCoverageState.complete;
    return AnalysisPeriodResolved(
      ResolvedAnalysisWindow(
        start: start,
        endExclusive: coverage == AnalysisCoverageState.partial
            ? start.add(elapsed)
            : end,
        timeZoneId: primary.timeZoneId,
        coverage: coverage,
        limitations: coverage == AnalysisCoverageState.partial
            ? const ['equivalentElapsedCoverage']
            : const [],
      ),
    );
  }
}
