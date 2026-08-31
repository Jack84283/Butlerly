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
  const InvalidateAnalysis(this.findings, {this.results, this.rules});
  final AnalysisFindingRepository findings;
  final AnalysisRuleResultRepository? results;
  final AnalysisRuleRepository? rules;

  Future<ApplicationResult<void>> call(
    AnalysisInvalidationReason reason,
    DateTime at, {
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) => runApplication('invalidate analysis', () async {
    final definitions = rules == null
        ? const <AnalysisRuleDefinition>[]
        : await rules!.listActive();
    final scoped = rules != null;
    final directlyAffected = _affectedRules(reason, definitions, ruleIds);
    final affected = _dependentsOf(directlyAffected, definitions);
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
      ruleIds: scoped ? affected : null,
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
      if (scoped && !affected.contains(finding.rule.identity.value)) {
        continue;
      }
      await findings.updateLifecycle(
        finding.id,
        FindingLifecycle.superseded,
        at,
      );
    }
  });

  Set<String> _affectedRules(
    AnalysisInvalidationReason reason,
    List<AnalysisRuleDefinition> definitions,
    Set<String>? requested,
  ) {
    if (requested != null && requested.isNotEmpty) return requested;
    bool uses(AnalysisRuleDefinition rule, Set<String> fields) =>
        rule.grouping.name != 'none' && fields.contains(rule.grouping.name) ||
        rule.filters.any((filter) => fields.contains(filter.kind.name)) ||
        rule.measures.any((measure) => fields.contains(measure.field)) ||
        (fields.contains('baseCurrency') &&
            rule.measures.any(
              (measure) => measure.currencyBasis == CurrencyBasis.baseCurrency,
            )) ||
        fields.contains('all');
    final fields = switch (reason) {
      AnalysisInvalidationReason.categoryChanged => {'category'},
      AnalysisInvalidationReason.merchantChanged => {'merchant'},
      AnalysisInvalidationReason.paymentSourceChanged => {'paymentSource'},
      AnalysisInvalidationReason.tagsChanged => {'tag'},
      AnalysisInvalidationReason.transactionDirectionChanged => {'direction'},
      AnalysisInvalidationReason.transactionAmountChanged => {'amount'},
      AnalysisInvalidationReason.exchangeRateChanged ||
      AnalysisInvalidationReason.baseCurrencyChanged => {'baseCurrency'},
      AnalysisInvalidationReason.timeZoneChanged => {'all'},
      AnalysisInvalidationReason.ruleChanged => {'all'},
      _ => {'all'},
    };
    return {
      for (final rule in definitions)
        if (uses(rule, fields) || fields.contains('all')) rule.identity.value,
    };
  }

  Set<String> _dependentsOf(
    Set<String> roots,
    List<AnalysisRuleDefinition> definitions,
  ) {
    final affected = {...roots};
    var changed = true;
    while (changed) {
      changed = false;
      for (final rule in definitions) {
        if (!affected.contains(rule.identity.value) &&
            rule.dependencies.any(
              (dependency) => affected.contains(dependency.ruleId.value),
            )) {
          changed = affected.add(rule.identity.value) || changed;
        }
      }
    }
    return affected;
  }
}
