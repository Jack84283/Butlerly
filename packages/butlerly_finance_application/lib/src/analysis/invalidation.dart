import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

enum AnalysisInvalidationReason {
  transactionChanged,
  transactionCreated,
  transactionUpdated,
  transactionDeleted,
  transactionDateChanged,
  transactionAmountChanged,
  transactionDirectionChanged,
  categoryChanged,
  merchantChanged,
  paymentSourceChanged,
  tagsChanged,
  verificationChanged,
  reconciliationChanged,
  exchangeRateChanged,
  baseCurrencyChanged,
  timeZoneChanged,
  ruleChanged,
  configurationChanged,
}

final class InvalidateAnalysis {
  const InvalidateAnalysis(this.findings, {this.results});
  final AnalysisFindingRepository findings;
  final AnalysisRuleResultRepository? results;

  Future<ApplicationResult<void>> call(
    AnalysisInvalidationReason reason,
    DateTime at, {
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) => runApplication('invalidate analysis', () async {
    switch (reason) {
      case AnalysisInvalidationReason.transactionChanged:
      case AnalysisInvalidationReason.transactionCreated:
      case AnalysisInvalidationReason.transactionUpdated:
      case AnalysisInvalidationReason.transactionDeleted:
      case AnalysisInvalidationReason.transactionDateChanged:
      case AnalysisInvalidationReason.transactionAmountChanged:
      case AnalysisInvalidationReason.transactionDirectionChanged:
      case AnalysisInvalidationReason.categoryChanged:
      case AnalysisInvalidationReason.merchantChanged:
      case AnalysisInvalidationReason.paymentSourceChanged:
      case AnalysisInvalidationReason.tagsChanged:
      case AnalysisInvalidationReason.verificationChanged:
      case AnalysisInvalidationReason.reconciliationChanged:
      case AnalysisInvalidationReason.exchangeRateChanged:
      case AnalysisInvalidationReason.baseCurrencyChanged:
      case AnalysisInvalidationReason.timeZoneChanged:
      case AnalysisInvalidationReason.ruleChanged:
      case AnalysisInvalidationReason.configurationChanged:
        break;
    }
    await results?.markStale(
      periodStart: periodStart,
      periodEnd: periodEnd,
      ruleIds: ruleIds,
    );
    final active = await findings.list(lifecycle: FindingLifecycle.active);
    for (final finding in active) {
      if (periodStart != null &&
          finding.context.period.endDate.compareTo(periodStart) < 0) {
        continue;
      }
      if (periodEnd != null &&
          finding.context.period.startDate.compareTo(periodEnd) > 0) {
        continue;
      }
      if (ruleIds != null && !ruleIds.contains(finding.rule.identity.value)) {
        continue;
      }
      await findings.updateLifecycle(
        finding.id,
        FindingLifecycle.superseded,
        at,
      );
    }
  });
}
