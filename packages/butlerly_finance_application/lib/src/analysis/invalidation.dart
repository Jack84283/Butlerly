import 'dart:async';
import 'dart:collection';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

/// Serializes source mutations with financial analysis reads and materialized
/// result publication. Invalidation alone is not sufficient: a calculation
/// can otherwise observe the pre-mutation source after stale results are
/// marked, then publish that old calculation as fresh after the mutation.
final class AnalysisConsistencyGate {
  static final Object _ownerKey = Object();
  final Queue<void Function()> _queue = Queue<void Function()>();
  bool _locked = false;

  Future<T> runExclusive<T>(Future<T> Function() operation) {
    if (Zone.current[_ownerKey] == this) {
      return operation();
    }
    final completer = Completer<T>();
    void start() => _start(operation, completer);
    if (!_locked) {
      _locked = true;
      start();
    } else {
      _queue.add(start);
    }
    return completer.future;
  }

  Future<void> _start<T>(
    Future<T> Function() operation,
    Completer<T> completer,
  ) async {
    try {
      final result = await runZoned(
        operation,
        zoneValues: <Object, Object>{_ownerKey: this},
      );
      completer.complete(result);
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      scheduleMicrotask(_releaseNext);
    }
  }

  void _releaseNext() {
    if (_queue.isEmpty) {
      _locked = false;
      return;
    }
    _queue.removeFirst()();
  }
}

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
  duplicateDecisionChanged,
  exchangeRateChanged,
  baseCurrencyChanged,
  timeZoneChanged,
  ruleChanged,
  configurationChanged,
}

final class InvalidateAnalysis {
  const InvalidateAnalysis(
    this.findings, {
    this.results,
    this.rules,
    this.consistencyGate,
  });
  final AnalysisFindingRepository findings;
  final AnalysisRuleResultRepository? results;
  final AnalysisRuleRepository? rules;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<void>> call(
    AnalysisInvalidationReason reason,
    DateTime at, {
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) => _runExclusive(
    () => runApplication('invalidate analysis', () async {
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
        case AnalysisInvalidationReason.duplicateDecisionChanged:
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
    }),
  );

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }

  Set<String> _affectedRules(
    AnalysisInvalidationReason reason,
    List<AnalysisRuleDefinition> definitions,
    Set<String>? requested,
  ) {
    if (requested != null && requested.isNotEmpty) return requested;
    bool uses(AnalysisRuleDefinition rule, Set<String> fields) =>
        rule.grouping.name != 'none' && fields.contains(rule.grouping.name) ||
        rule.filters.any((filter) => fields.contains(filter.kind.name)) ||
        _effectiveMeasures(
          rule,
        ).any((measure) => fields.contains(measure.field)) ||
        (fields.contains('baseCurrency') &&
            _effectiveMeasures(rule).any(
              (measure) =>
                  measure.currencyBasis == CurrencyBasis.baseCurrency ||
                  measure.field == 'missingFx',
            )) ||
        fields.contains('all');
    final fields = switch (reason) {
      // A hierarchy edit can change both the effective category and the
      // subcategory dimension used by legacy and current rules.
      AnalysisInvalidationReason.categoryChanged => {'category', 'subcategory'},
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

  Iterable<RuleMeasure> _effectiveMeasures(AnalysisRuleDefinition rule) =>
      rule.measures.isEmpty ? [rule.measure] : rule.measures;

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
