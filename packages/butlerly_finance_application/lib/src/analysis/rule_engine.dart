import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class AnalysisRuleEngine {
  const AnalysisRuleEngine();

  List<RuleExecutionResult> execute({
    required AnalysisDataset dataset,
    required List<AnalysisRuleDefinition> definitions,
    DateTime? calculatedAt,
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
        final primaryValues =
            dataset.primaryTransactionsByPeriod[rule.period] ??
            dataset.transactions;
        final values = primaryValues
            .where(
              (value) =>
                  _eligible(value, dataset.context, rule) &&
                  _matchesQualityField(value, rule),
            )
            .toList(growable: false);
        for (final entry in _group(values, rule.grouping).entries) {
          final metric = _metric(
            rule,
            dataset,
            entry.value,
            metrics,
            entry.key,
            calculatedAt ?? DateTime.now().toUtc(),
          );
          if (metric != null) {
            metrics['${rule.identity.value}:${entry.key}'] = metric;
            metrics[rule.identity.value] = metric;
          }
          final finding =
              rule.type == AnalysisRuleType.insight &&
                  metric != null &&
                  _conditionMatches(rule.condition, metric.value)
              ? _finding(
                  rule,
                  dataset,
                  entry.key,
                  metric,
                  calculatedAt ?? DateTime.now().toUtc(),
                )
              : null;
          final result = RuleExecutionResult(
            rule: rule,
            metric:
                rule.type == AnalysisRuleType.metric ||
                    rule.type == AnalysisRuleType.dataQuality
                ? metric
                : null,
            finding: finding,
          );
          results.add(result);
          resultById[rule.identity.value] = result;
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
    final baseline =
        rule.baseline == RuleBaseline.none ||
            dataset.baselineTransactions.isEmpty
        ? null
        : _metric(
            rule,
            dataset,
            dataset.baselineTransactions
                .where(
                  (value) =>
                      _eligible(value, dataset.context, rule) &&
                      _matchesQualityField(value, rule),
                )
                .toList(growable: false),
            const <String, AnalysisMetric>{},
            dimension,
            at,
          );
    final baselineValue = baseline?.value;
    final absolute = baselineValue == null
        ? null
        : _subtract(current.value, baselineValue);
    final percentage = baselineValue == null || baselineValue.isZero
        ? null
        : DecimalValue.fromParts(
            coefficient: absolute!.coefficient * BigInt.from(100),
            scale: absolute.scale,
          ).divideBy(baselineValue.coefficient.abs().toInt());
    return AnalysisFinding(
      id: '${rule.identity.value}:${dataset.context.period.startDate}:$dimension',
      rule: rule,
      context: dataset.context,
      severity: rule.severity,
      lifecycle: FindingLifecycle.active,
      currentValue: current.value,
      baselineValue: baselineValue,
      absoluteChange: absolute,
      percentageChange: percentage,
      dimension: dimension.isEmpty ? null : dimension,
      supportingMetrics: baseline == null
          ? [current.id]
          : [current.id, baseline.id],
      evidence: current.evidence,
      qualityIssues: [
        ...dataset.qualityIssues,
        if (baseline == null)
          const DataQualityIssue(
            code: 'missingBaseline',
            detail: 'No comparable baseline was available.',
          ),
      ],
      generatedAt: at,
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

  bool _conditionMatches(RuleCondition condition, DecimalValue value) {
    if (condition.operator == 'none') return true;
    if (condition.children.isNotEmpty) {
      final matches = condition.children
          .map((child) => _conditionMatches(child, value))
          .toList(growable: false);
      return switch (condition.operator) {
        'all' => matches.every((item) => item),
        'any' => matches.any((item) => item),
        'not' => !matches.first,
        _ => false,
      };
    }
    final target = condition.value;
    if (target == null) return false;
    return switch (condition.operator) {
      'gt' => value.compareTo(target) > 0,
      'gte' => value.compareTo(target) >= 0,
      'lt' => value.compareTo(target) < 0,
      'lte' => value.compareTo(target) <= 0,
      'eq' => value == target,
      _ => false,
    };
  }

  Map<String, List<AnalysisEconomicTransaction>> _group(
    List<AnalysisEconomicTransaction> values,
    RuleGrouping grouping,
  ) {
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
    AnalysisRuleDefinition rule,
  ) {
    final date = value.transactionDate;
    if (date == null) {
      return rule.type == AnalysisRuleType.dataQuality;
    }
    if (date.compareTo(context.period.startDate) < 0 ||
        date.compareTo(context.period.endDate) > 0) {
      return false;
    }
    if (context.datasetMode == DatasetMode.verifiedOnly && !value.verified) {
      return false;
    }
    for (final filter in rule.filters) {
      if (filter.kind == AnalysisFilterKind.direction &&
          !filter.values.contains(value.direction.name)) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.currency &&
          !filter.values.contains(value.money.currency.value)) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.category &&
          !filter.values.contains(value.categoryId?.value)) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.merchant &&
          !filter.values.contains(value.merchantId?.value)) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.paymentSource &&
          !filter.values.contains(value.paymentSourceId?.value)) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.tag &&
          !value.tagIds.any((tag) => filter.values.contains(tag.value))) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.reviewState &&
          !filter.values.contains(value.verified ? 'clear' : 'needsReview')) {
        return false;
      }
      if (filter.kind == AnalysisFilterKind.status &&
          !filter.values.contains(value.status.name)) {
        return false;
      }
    }
    return true;
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
    AnalysisDataset dataset,
    List<AnalysisEconomicTransaction> values,
    Map<String, AnalysisMetric> dependencies,
    String dimension,
    DateTime at,
  ) {
    final selected = values
        .where(
          (value) => rule.measure.currencyBasis == CurrencyBasis.baseCurrency
              ? value.normalizedMoney != null
              : true,
        )
        .toList(growable: false);
    final amountValues = selected
        .map(
          (value) => rule.measure.currencyBasis == CurrencyBasis.baseCurrency
              ? value.normalizedMoney!.amount
              : value.money.amount,
        )
        .toList(growable: false);
    final result = switch (rule.measure.operation) {
      RuleOperation.count => DecimalValue.fromParts(
        coefficient: BigInt.from(_countForField(selected, rule.measure.field)),
        scale: 0,
      ),
      RuleOperation.sum => _sum(amountValues),
      RuleOperation.average => _sum(amountValues).divideBy(selected.length),
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
        coefficient: BigInt.from(_distinct(selected, rule.measure.field)),
        scale: 0,
      ),
      RuleOperation.frequency => DecimalValue.fromParts(
        coefficient: BigInt.from(selected.length),
        scale: 0,
      ),
      RuleOperation.difference => _difference(rule, dependencies),
    };
    final currency = rule.measure.currencyBasis == CurrencyBasis.baseCurrency
        ? dataset.context.baseCurrency
        : (amountValues.isEmpty ? null : selected.first.money.currency);
    return AnalysisMetric(
      id: '${rule.identity.value}:${dataset.context.period.startDate}:$dimension',
      rule: rule,
      context: dataset.context,
      value: result,
      currency: currency,
      transactionCount: selected.length,
      dimension: dimension.isEmpty ? null : dimension,
      evidence: selected
          .map((value) => EvidenceReference(transactionId: value.id))
          .toList(growable: false),
      qualityIssues: dataset.qualityIssues,
      calculatedAt: at,
    );
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
