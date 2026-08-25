import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

enum AnalysisInvalidationReason {
  transactionChanged,
  reconciliationChanged,
  exchangeRateChanged,
  baseCurrencyChanged,
  timeZoneChanged,
  ruleChanged,
  configurationChanged,
}

final class InvalidateAnalysis {
  const InvalidateAnalysis(this.findings);
  final AnalysisFindingRepository findings;

  Future<ApplicationResult<void>> call(
    AnalysisInvalidationReason reason,
    DateTime at,
  ) => runApplication('invalidate analysis', () async {
    switch (reason) {
      case AnalysisInvalidationReason.transactionChanged:
      case AnalysisInvalidationReason.reconciliationChanged:
      case AnalysisInvalidationReason.exchangeRateChanged:
      case AnalysisInvalidationReason.baseCurrencyChanged:
      case AnalysisInvalidationReason.timeZoneChanged:
      case AnalysisInvalidationReason.ruleChanged:
      case AnalysisInvalidationReason.configurationChanged:
        break;
    }
    final active = await findings.list(lifecycle: FindingLifecycle.active);
    for (final finding in active) {
      await findings.updateLifecycle(
        finding.id,
        FindingLifecycle.superseded,
        at,
      );
    }
  });
}
