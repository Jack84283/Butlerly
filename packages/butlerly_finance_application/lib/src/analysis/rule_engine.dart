import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'period_resolver.dart';

final class AnalysisRuleEngine {
  const AnalysisRuleEngine({
    this.periodResolver = const AnalysisPeriodResolver(),
  });

  final AnalysisPeriodResolver periodResolver;

  List<RuleExecutionResult> execute({
    required AnalysisDataset dataset,
    required List<AnalysisRuleDefinition> definitions,
    DateTime? calculatedAt,
    Map<String, List<RuleExecutionResult>> availableResults = const {},
  }) {
    final ordering = _order(definitions);
    final ordered = ordering.ordered;
    final results = <RuleExecutionResult>[];
    final metrics = <String, AnalysisMetric>{};
    final resultById = <String, RuleExecutionResult>{};
    final knownIds = definitions.map((value) => value.identity.value).toSet();
    for (final rule in ordered) {
      if (!rule.enabled || rule.status != AnalysisRuleStatus.active) continue;
      try {
        final cached = availableResults[rule.identity.value];
        if (cached != null && cached.isNotEmpty) {
          results.addAll(cached);
          final first = cached.first;
          resultById[rule.identity.value] = first;
          for (final cachedResult in cached) {
            final metric = cachedResult.metric;
            if (metric != null) {
              metrics[rule.identity.value] ??= metric;
              metrics['${rule.identity.value}:${metric.dimension ?? ''}'] =
                  metric;
            }
          }
          continue;
        }
        if (ordering.cyclicIds.contains(rule.identity.value)) {
          final result = RuleExecutionResult(
            rule: rule,
            failure: AnalysisFailure(
              code: 'dependencyCycle',
              message: 'Rule belongs to a dependency cycle.',
              ruleId: rule.identity,
            ),
          );
          results.add(result);
          resultById[rule.identity.value] = result;
          continue;
        }
        final missing = rule.dependencies.where(
          (value) => !knownIds.contains(value.ruleId.value),
        );
        if (missing.isNotEmpty) {
          final result = RuleExecutionResult(
            rule: rule,
            failure: AnalysisFailure(
              code: 'missingDependency',
              message:
                  'Dependency is unavailable: ${missing.first.ruleId.value}.',
              ruleId: rule.identity,
            ),
          );
          results.add(result);
          resultById[rule.identity.value] = result;
          continue;
        }
        final hasFailedDependency = rule.dependencies.any(
          (value) => resultById[value.ruleId.value]?.failure != null,
        );
        if (hasFailedDependency) {
          final result = RuleExecutionResult(
            rule: rule,
            failure: AnalysisFailure(
              code: 'dependencyFailure',
              message: 'A dependency failed.',
              ruleId: rule.identity,
            ),
          );
          results.add(result);
          resultById[rule.identity.value] = result;
          continue;
        }
        final incompatibleDependency = rule.dependencies.where((value) {
          if (value.minimumVersion == null) return false;
          final dependency = definitions.firstWhere(
            (candidate) => candidate.identity == value.ruleId,
          );
          return _compareVersions(dependency.version, value.minimumVersion!) <
              0;
        });
        if (incompatibleDependency.isNotEmpty) {
          final dependency = incompatibleDependency.first;
          final result = RuleExecutionResult(
            rule: rule,
            failure: AnalysisFailure(
              code: 'dependencyVersion',
              message:
                  'Dependency ${dependency.ruleId.value} does not meet its minimum version.',
              ruleId: rule.identity,
            ),
          );
          results.add(result);
          resultById[rule.identity.value] = result;
          continue;
        }
        final primaryResolution = periodResolver.resolvePrimary(
          type: rule.period,
          context: dataset.context,
        );
        if (primaryResolution case AnalysisPeriodResolutionFailure(
          :final code,
        )) {
          throw StateError('Unable to resolve ${rule.period}: $code.');
        }
        final primaryWindow =
            (primaryResolution as AnalysisPeriodResolved).window;
        final primaryValues = rule.type == AnalysisRuleType.dataQuality
            ? dataset.transactions
            : dataset.primaryTransactionsByPeriod[rule.period] ??
                  dataset.transactions;
        final values = primaryValues
            .where(
              (value) =>
                  _eligible(
                    value,
                    dataset.context,
                    rule,
                    window: rule.type == AnalysisRuleType.dataQuality
                        ? null
                        : primaryWindow,
                  ) &&
                  _matchesQualityField(value, rule),
            )
            .toList(growable: false);
        final grouped = _group(
          values,
          rule.grouping,
          completeDailyAxis:
              rule.surface == AnalysisSurface.trends &&
              rule.grouping == RuleGrouping.day,
          completeMonthlyAxis:
              rule.surface == AnalysisSurface.trends &&
              rule.grouping == RuleGrouping.month,
          window: primaryWindow,
        );
        for (final entry in grouped.entries) {
          for (final measure
              in rule.measures.isEmpty ? [rule.measure] : rule.measures) {
            final metric = _metric(
              rule,
              measure,
              dataset,
              entry.value,
              metrics,
              entry.key,
              calculatedAt ?? DateTime.now().toUtc(),
            );
            if (metric != null) {
              metrics['${rule.identity.value}:${entry.key}:${measure.key}'] =
                  metric;
              metrics[rule.identity.value] = metric;
            }
            AnalysisFinding? finding;
            final comparison =
                metric == null || rule.baseline == RuleBaseline.none
                ? null
                : _comparison(
                    rule,
                    dataset,
                    entry.key,
                    metric,
                    calculatedAt ?? DateTime.now().toUtc(),
                  );
            var resultIssues =
                metric?.qualityIssues ?? const <DataQualityIssue>[];
            if (rule.type == AnalysisRuleType.insight &&
                metric != null &&
                metric.availability == AnalysisDataAvailability.sufficient &&
                rule.condition.operator != 'none') {
              final candidate = _finding(
                rule,
                dataset,
                entry.key,
                metric,
                calculatedAt ?? DateTime.now().toUtc(),
              );
              resultIssues = candidate.qualityIssues;
              final baselineIsUsable =
                  rule.baseline == RuleBaseline.none ||
                  candidate.baselineValue != null;
              if (baselineIsUsable &&
                  _conditionMatches(
                    rule.condition,
                    metric.value,
                    candidate.percentageChange,
                  )) {
                finding = candidate;
              }
            }
            final result = RuleExecutionResult(
              rule: rule,
              metric:
                  rule.type == AnalysisRuleType.metric ||
                      rule.type == AnalysisRuleType.dataQuality
                  ? metric
                  : null,
              finding: finding,
              comparison: comparison,
              issues: resultIssues,
            );
            results.add(result);
            resultById[rule.identity.value] = result;
          }
        }
      } on Object catch (error) {
        final result = RuleExecutionResult(
          rule: rule,
          failure: AnalysisFailure(
            code: 'execution',
            message: error.toString(),
            ruleId: rule.identity,
          ),
        );
        results.add(result);
        resultById[rule.identity.value] = result;
      }
    }
    return results;
  }

  AnalysisFinding _finding(
    AnalysisRuleDefinition rule,
    AnalysisDataset dataset,
    String dimension,
    AnalysisMetric current,
    DateTime at,
  ) {
    final comparison = _comparison(rule, dataset, dimension, current, at);
    return AnalysisFinding(
      id: AnalysisResultIdentity.forRule(
        rule: rule,
        context: dataset.context,
        dimension: dimension,
      ).value,
      rule: rule,
      context: dataset.context,
      severity: rule.severity,
      lifecycle: FindingLifecycle.active,
      currentValue: comparison.currentValue,
      baselineValue: comparison.baselineValue,
      absoluteChange: comparison.absoluteChange,
      percentageChange: comparison.percentageChange,
      dimension: dimension.isEmpty ? null : dimension,
      supportingMetrics: [current.id, ?comparison.baselineMetricId],
      evidence: current.evidence,
      qualityIssues: [
        ...dataset.qualityIssues,
        if (comparison.baselineValue == null)
          const DataQualityIssue(
            code: 'missingBaseline',
            detail: 'No comparable baseline was available.',
          ),
      ],
      generatedAt: at,
    );
  }

  AnalysisComparison _comparison(
    AnalysisRuleDefinition rule,
    AnalysisDataset dataset,
    String dimension,
    AnalysisMetric current,
    DateTime at,
  ) {
    final baselineValues =
        dataset.baselineTransactionsByPeriod[rule.period] ??
        dataset.baselineTransactions;
    final baselineResolution = periodResolver.resolvePrimary(
      type: rule.period,
      context: dataset.context,
    );
    final baselineWindow = baselineResolution is AnalysisPeriodResolved
        ? periodResolver.resolvePreviousEquivalent(
            primary: baselineResolution.window,
          )
        : null;
    final baselineContext = baselineWindow is AnalysisPeriodResolved
        ? _contextForWindow(dataset.context, baselineWindow.window)
        : null;
    final baselineEligible = baselineValues
        .where(
          (value) =>
              _eligible(value, dataset.context, rule) &&
              _matchesQualityField(value, rule),
        )
        .toList(growable: false);
    final baselineGroup = rule.grouping == RuleGrouping.none
        ? baselineEligible
        : _group(baselineEligible, rule.grouping)[dimension] ??
              const <AnalysisEconomicTransaction>[];
    final baseline = rule.baseline == RuleBaseline.none || baselineGroup.isEmpty
        ? null
        : _metric(
            rule,
            rule.measure,
            dataset,
            baselineGroup,
            const <String, AnalysisMetric>{},
            dimension,
            at,
            contextOverride: baselineContext,
          );
    final usableBaseline =
        baseline?.availability == AnalysisDataAvailability.sufficient
        ? baseline
        : null;
    final baselineValue = usableBaseline?.value;
    final absolute = baselineValue == null
        ? null
        : _subtract(current.value, baselineValue);
    final percentage = baselineValue == null || baselineValue.isZero
        ? null
        : DecimalValue.fromParts(
            coefficient: absolute!.coefficient * BigInt.from(100),
            scale: absolute.scale,
          ).divideBy(baselineValue.coefficient.abs().toInt());
    return AnalysisComparison(
      currentValue: current.value,
      baselineValue: baselineValue,
      absoluteChange: absolute,
      percentageChange: percentage,
      baselineMetricId: usableBaseline?.id,
      availability: usableBaseline == null
          ? AnalysisDataAvailability.insufficient
          : AnalysisDataAvailability.sufficient,
    );
  }

  DecimalValue _subtract(DecimalValue left, DecimalValue right) {
    final scale = left.scale > right.scale ? left.scale : right.scale;
    return DecimalValue.fromParts(
      coefficient:
          left.coefficient * BigInt.from(10).pow(scale - left.scale) -
          right.coefficient * BigInt.from(10).pow(scale - right.scale),
      scale: scale,
    );
  }

  bool _conditionMatches(
    RuleCondition condition,
    DecimalValue value, [
    DecimalValue? percentageChange,
  ]) {
    if (condition.operator == 'none') return true;
    if (condition.children.isNotEmpty) {
      final matches = condition.children
          .map((child) => _conditionMatches(child, value, percentageChange))
          .toList(growable: false);
      return switch (condition.operator) {
        'all' => matches.every((item) => item),
        'any' => matches.any((item) => item),
        'not' => !matches.first,
        _ => false,
      };
    }
    final targetValue = condition.left == 'percentageChange'
        ? percentageChange
        : value;
    final target = condition.value;
    if (target == null || targetValue == null) return false;
    return switch (condition.operator) {
      'gt' => targetValue.compareTo(target) > 0,
      'gte' => targetValue.compareTo(target) >= 0,
      'lt' => targetValue.compareTo(target) < 0,
      'lte' => targetValue.compareTo(target) <= 0,
      'eq' => targetValue == target,
      _ => false,
    };
  }

  int _compareVersions(RuleVersion left, RuleVersion right) {
    final a = left.value.split('.').map(int.parse).toList(growable: false);
    final b = right.value.split('.').map(int.parse).toList(growable: false);
    for (var i = 0; i < 3; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  Map<String, List<AnalysisEconomicTransaction>> _group(
    List<AnalysisEconomicTransaction> values,
    RuleGrouping grouping, {
    bool completeDailyAxis = false,
    bool completeMonthlyAxis = false,
    ResolvedAnalysisWindow? window,
  }) {
    if (grouping == RuleGrouping.none) return {'': values};
    String key(AnalysisEconomicTransaction value) => switch (grouping) {
      RuleGrouping.category => value.categoryId?.value ?? 'uncategorized',
      RuleGrouping.merchant => value.merchantId?.value ?? 'unresolved',
      RuleGrouping.paymentSource => value.paymentSourceId?.value ?? 'unknown',
      RuleGrouping.tag =>
        value.tagIds.isEmpty ? 'untagged' : value.tagIds.first.value,
      RuleGrouping.day => value.transactionDate ?? 'unknown',
      RuleGrouping.week => _weekKey(value.transactionDate),
      RuleGrouping.month => value.transactionDate?.substring(0, 7) ?? 'unknown',
      RuleGrouping.none => '',
    };
    final grouped = <String, List<AnalysisEconomicTransaction>>{};
    if (completeDailyAxis && window != null) {
      for (
        var date = window.start;
        date.isBefore(window.endExclusive);
        date = date.add(const Duration(days: 1))
      ) {
        grouped[_formatDate(date)] = <AnalysisEconomicTransaction>[];
      }
    }
    if (completeMonthlyAxis && window != null) {
      for (
        var month = DateTime.utc(window.start.year, window.start.month);
        month.isBefore(window.endExclusive);
        month = DateTime.utc(month.year, month.month + 1)
      ) {
        grouped[_formatMonth(month)] = <AnalysisEconomicTransaction>[];
      }
    }
    for (final value in values) {
      if (grouping == RuleGrouping.tag && value.tagIds.length > 1) {
        for (final tag in value.tagIds) {
          grouped.putIfAbsent(tag.value, () => []).add(value);
        }
      } else {
        grouped.putIfAbsent(key(value), () => []).add(value);
      }
    }
    return grouped;
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _formatMonth(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

  String _weekKey(String? value) {
    if (value == null) return 'unknown';
    final date = DateTime.tryParse(value);
    if (date == null) return 'unknown';
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  _RuleOrdering _order(List<AnalysisRuleDefinition> definitions) {
    final byId = {for (final value in definitions) value.identity.value: value};
    final ordered = <AnalysisRuleDefinition>[];
    final visiting = <String>{};
    final visited = <String>{};
    final cyclicIds = <String>{};
    final stack = <String>[];
    void visit(AnalysisRuleDefinition value) {
      if (visited.contains(value.identity.value)) return;
      if (visiting.contains(value.identity.value)) {
        final cycleStart = stack.indexOf(value.identity.value);
        cyclicIds.addAll(stack.skip(cycleStart));
        return;
      }
      visiting.add(value.identity.value);
      stack.add(value.identity.value);
      for (final dependency in value.dependencies) {
        final target = byId[dependency.ruleId.value];
        if (target != null) visit(target);
      }
      visiting.remove(value.identity.value);
      stack.removeLast();
      visited.add(value.identity.value);
      ordered.add(value);
    }

    for (final definition in [
      ...definitions,
    ]..sort((a, b) => a.identity.value.compareTo(b.identity.value))) {
      visit(definition);
    }
    return _RuleOrdering(ordered, cyclicIds);
  }

  bool _eligible(
    AnalysisEconomicTransaction value,
    AnalysisContext context,
    AnalysisRuleDefinition rule, {
    ResolvedAnalysisWindow? window,
  }) {
    final date = value.transactionDate;
    if (date == null) {
      return rule.type == AnalysisRuleType.dataQuality;
    }
    if (window != null) {
      final parsed = DateTime.tryParse(date);
      if (parsed == null ||
          parsed.isBefore(window.start) ||
          !parsed.isBefore(window.endExclusive)) {
        return false;
      }
    }
    if (context.datasetMode == DatasetMode.verifiedOnly && !value.verified) {
      return false;
    }
    return _matchesFilters(value, rule.filters);
  }

  bool _matchesQualityField(
    AnalysisEconomicTransaction value,
    AnalysisRuleDefinition rule,
  ) {
    if (rule.type != AnalysisRuleType.dataQuality) return true;
    final field = rule.measure.field;
    if (field == 'dataQuality') return value.transactionDate == null;
    return value.dataQuality.any((issue) => issue.code == field);
  }

  AnalysisMetric? _metric(
    AnalysisRuleDefinition rule,
    RuleMeasure measure,
    AnalysisDataset dataset,
    List<AnalysisEconomicTransaction> values,
    Map<String, AnalysisMetric> dependencies,
    String dimension,
    DateTime at, {
    AnalysisContext? contextOverride,
  }) {
    final metricContext = contextOverride ?? dataset.context;
    final selected = values
        .where((value) => _matchesFilters(value, measure.filters))
        .where(
          (value) => measure.currencyBasis == CurrencyBasis.baseCurrency
              ? value.normalizedMoney != null ||
                    value.money.currency == metricContext.baseCurrency
              : true,
        )
        .toList(growable: false);
    final amountValues = selected
        .map(
          (value) => measure.currencyBasis == CurrencyBasis.baseCurrency
              ? (value.normalizedMoney ?? value.money).amount
              : value.money.amount,
        )
        .toList(growable: false);
    final result = switch (measure.operation) {
      RuleOperation.count => DecimalValue.fromParts(
        coefficient: BigInt.from(_countForField(selected, measure.field)),
        scale: 0,
      ),
      RuleOperation.sum => _sum(amountValues),
      RuleOperation.average =>
        selected.isEmpty
            ? DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0)
            : _sum(amountValues).divideBy(selected.length),
      RuleOperation.median => _median(amountValues),
      RuleOperation.minimum =>
        amountValues.isEmpty
            ? DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0)
            : amountValues.reduce((a, b) => a.compareTo(b) <= 0 ? a : b),
      RuleOperation.maximum =>
        amountValues.isEmpty
            ? DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0)
            : amountValues.reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
      RuleOperation.distinctCount => DecimalValue.fromParts(
        coefficient: BigInt.from(_distinct(selected, measure.field)),
        scale: 0,
      ),
      RuleOperation.frequency => DecimalValue.fromParts(
        coefficient: BigInt.from(selected.length),
        scale: 0,
      ),
      RuleOperation.difference => _difference(rule, dependencies),
    };
    final monetary = {
      RuleOperation.sum,
      RuleOperation.average,
      RuleOperation.median,
      RuleOperation.minimum,
      RuleOperation.maximum,
      RuleOperation.difference,
    }.contains(measure.operation);
    final currency = !monetary
        ? null
        : measure.currencyBasis == CurrencyBasis.baseCurrency
        ? metricContext.baseCurrency
        : (amountValues.isEmpty ? null : selected.first.money.currency);
    final availability = selected.isNotEmpty
        ? AnalysisDataAvailability.sufficient
        : values.isEmpty
        ? AnalysisDataAvailability.empty
        : measure.currencyBasis == CurrencyBasis.baseCurrency
        ? AnalysisDataAvailability.insufficient
        : AnalysisDataAvailability.empty;
    final qualityIssues = [
      ...dataset.qualityIssues,
      if (availability != AnalysisDataAvailability.sufficient)
        DataQualityIssue(
          code: 'insufficientData',
          detail: availability == AnalysisDataAvailability.empty
              ? 'No eligible data was available for ${measure.operation.name}.'
              : 'Required currency normalization was unavailable for ${measure.operation.name}.',
        ),
    ];
    return AnalysisMetric(
      id: AnalysisResultIdentity.forRule(
        rule: rule,
        context: metricContext,
        dimension: dimension.isEmpty
            ? measure.key
            : '$dimension:${measure.key}',
      ).value,
      rule: rule,
      context: metricContext,
      value: result,
      currency: currency,
      transactionCount: selected.length,
      availability: availability,
      dimension: dimension.isEmpty ? measure.key : '$dimension:${measure.key}',
      evidence: selected
          .map((value) => EvidenceReference(transactionId: value.id))
          .toList(growable: false),
      qualityIssues: qualityIssues,
      calculatedAt: at,
    );
  }

  bool _matchesFilters(
    AnalysisEconomicTransaction value,
    List<AnalysisFilter> filters,
  ) {
    for (final filter in filters) {
      final matches = switch (filter.kind) {
        AnalysisFilterKind.direction => filter.values.contains(
          value.direction.name,
        ),
        AnalysisFilterKind.currency => filter.values.contains(
          value.money.currency.value,
        ),
        AnalysisFilterKind.category => filter.values.contains(
          value.categoryId?.value,
        ),
        AnalysisFilterKind.merchant => filter.values.contains(
          value.merchantId?.value,
        ),
        AnalysisFilterKind.paymentSource => filter.values.contains(
          value.paymentSourceId?.value,
        ),
        AnalysisFilterKind.tag => value.tagIds.any(
          (tag) => filter.values.contains(tag.value),
        ),
        AnalysisFilterKind.reviewState => filter.values.contains(
          value.verified ? 'clear' : 'needsReview',
        ),
        AnalysisFilterKind.status => filter.values.contains(value.status.name),
      };
      if (!matches) return false;
    }
    return true;
  }

  int _countForField(List<AnalysisEconomicTransaction> values, String field) {
    if (field == 'transaction') return values.length;
    final code = switch (field) {
      'unresolvedNormalization' => 'missingFx',
      'reconciliationUncertainty' => 'reconciliationUncertainty',
      'dataQuality' => null,
      _ => null,
    };
    if (code == null) {
      return field == 'dataQuality'
          ? values.fold(0, (sum, value) => sum + value.dataQuality.length)
          : values.length;
    }
    return values
        .where((value) => value.dataQuality.any((issue) => issue.code == code))
        .length;
  }

  int _distinct(List<AnalysisEconomicTransaction> values, String field) =>
      values
          .map(
            (value) => switch (field) {
              'category' => value.categoryId?.value ?? 'uncategorized',
              'merchant' => value.merchantId?.value ?? 'unresolved',
              'paymentSource' => value.paymentSourceId?.value ?? 'unknown',
              'tag' => value.tagIds.map((tag) => tag.value).join(','),
              'currency' => value.money.currency.value,
              _ => value.id.value,
            },
          )
          .toSet()
          .length;

  DecimalValue _median(List<DecimalValue> values) {
    if (values.isEmpty) {
      return DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);
    }
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return _sum([sorted[middle - 1], sorted[middle]]).divideBy(2);
  }

  DecimalValue _difference(
    AnalysisRuleDefinition rule,
    Map<String, AnalysisMetric> dependencies,
  ) {
    if (rule.dependencies.length < 2) {
      throw StateError('Difference requires two metric dependencies.');
    }
    final income = dependencies[rule.dependencies[1].ruleId.value];
    final expense = dependencies[rule.dependencies[0].ruleId.value];
    if (income == null || expense == null) {
      throw StateError('Metric dependency result is unavailable.');
    }
    final scale = income.value.scale > expense.value.scale
        ? income.value.scale
        : expense.value.scale;
    return DecimalValue.fromParts(
      coefficient:
          income.value.coefficient *
              BigInt.from(10).pow(scale - income.value.scale) -
          expense.value.coefficient *
              BigInt.from(10).pow(scale - expense.value.scale),
      scale: scale,
    );
  }

  DecimalValue _sum(List<DecimalValue> values) {
    if (values.isEmpty) {
      return DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);
    }
    final scale = values
        .map((value) => value.scale)
        .reduce((a, b) => a > b ? a : b);
    final coefficient = values.fold<BigInt>(
      BigInt.zero,
      (sum, value) =>
          sum + value.coefficient * BigInt.from(10).pow(scale - value.scale),
    );
    return DecimalValue.fromParts(coefficient: coefficient, scale: scale);
  }
}

AnalysisContext _contextForWindow(
  AnalysisContext context,
  ResolvedAnalysisWindow window,
) => AnalysisContext(
  period: AnalysisPeriod(
    startDate: _dateOnly(window.start),
    endDate: _dateOnly(window.endExclusive.subtract(const Duration(days: 1))),
    timeZoneId: window.timeZoneId,
  ),
  datasetMode: context.datasetMode,
  currencyBasis: context.currencyBasis,
  baseCurrency: context.baseCurrency,
);

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

final class _RuleOrdering {
  const _RuleOrdering(this.ordered, this.cyclicIds);
  final List<AnalysisRuleDefinition> ordered;
  final Set<String> cyclicIds;
}

extension on DecimalValue {
  DecimalValue divideBy(int divisor) {
    if (divisor <= 0) {
      return DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);
    }
    return DecimalValue.fromParts(
      coefficient: coefficient,
      scale: scale + 6,
    ).divideInteger(divisor);
  }

  DecimalValue divideInteger(int divisor) {
    final quotient = coefficient ~/ BigInt.from(divisor);
    return DecimalValue.fromParts(coefficient: quotient, scale: scale);
  }
}
