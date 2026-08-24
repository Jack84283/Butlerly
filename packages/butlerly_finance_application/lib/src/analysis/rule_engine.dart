import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class AnalysisRuleEngine {
  const AnalysisRuleEngine();

  List<RuleExecutionResult> execute({
    required AnalysisDataset dataset,
    required List<AnalysisRuleDefinition> definitions,
    DateTime? calculatedAt,
  }) {
    final ordered = _order(definitions);
    final results = <RuleExecutionResult>[];
    final metrics = <String, AnalysisMetric>{};
    for (final rule in ordered) {
      if (!rule.enabled || rule.status != AnalysisRuleStatus.active) continue;
      try {
        final values = dataset.transactions
            .where((value) => _eligible(value, dataset.context, rule))
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
          results.add(
            RuleExecutionResult(
              rule: rule,
              metric:
                  rule.type == AnalysisRuleType.metric ||
                      rule.type == AnalysisRuleType.dataQuality
                  ? metric
                  : null,
            ),
          );
        }
      } on Object catch (error) {
        results.add(
          RuleExecutionResult(
            rule: rule,
            failure: AnalysisFailure(
              code: 'execution',
              message: error.toString(),
              ruleId: rule.identity,
            ),
          ),
        );
      }
    }
    return results;
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
      RuleGrouping.week ||
      RuleGrouping.month => value.transactionDate?.substring(0, 7) ?? 'unknown',
      RuleGrouping.none => '',
    };
    final grouped = <String, List<AnalysisEconomicTransaction>>{};
    for (final value in values) {
      grouped.putIfAbsent(key(value), () => []).add(value);
    }
    return grouped;
  }

  List<AnalysisRuleDefinition> _order(
    List<AnalysisRuleDefinition> definitions,
  ) {
    final byId = {for (final value in definitions) value.identity.value: value};
    final ordered = <AnalysisRuleDefinition>[];
    final visiting = <String>{};
    final visited = <String>{};
    void visit(AnalysisRuleDefinition value) {
      if (visited.contains(value.identity.value)) return;
      if (!visiting.add(value.identity.value)) {
        throw StateError('Analysis rule dependency cycle.');
      }
      for (final dependency in value.dependencies) {
        final target = byId[dependency.ruleId.value];
        if (target != null) visit(target);
      }
      visiting.remove(value.identity.value);
      visited.add(value.identity.value);
      ordered.add(value);
    }

    for (final definition in [
      ...definitions,
    ]..sort((a, b) => a.identity.value.compareTo(b.identity.value))) {
      visit(definition);
    }
    return ordered;
  }

  bool _eligible(
    AnalysisEconomicTransaction value,
    AnalysisContext context,
    AnalysisRuleDefinition rule,
  ) {
    final date = value.transactionDate;
    if (date == null) return false;
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
    }
    return true;
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
        coefficient: BigInt.from(selected.length),
        scale: 0,
      ),
      RuleOperation.sum => _sum(amountValues),
      RuleOperation.average => _sum(amountValues).divideBy(selected.length),
      RuleOperation.difference => _difference(rule, dependencies),
      _ => throw StateError(
        'Unsupported operation for this engine slice: ${rule.measure.operation.name}',
      ),
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
