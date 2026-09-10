import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../result/application_result.dart';
import '../dto/transaction_dto.dart';
import '../analysis/dataset_builder.dart';
import '../analysis/period_resolver.dart';
import '../analysis/rule_engine.dart';
import '../analysis/result_materialization.dart';

final class CalculateAnalysisOverview {
  const CalculateAnalysisOverview(
    this.rules,
    this.datasetBuilder,
    this.engine, {
    this.findings,
    this.results,
    this.periodResolver = const AnalysisPeriodResolver(),
  });
  final AnalysisRuleRepository rules;
  final AnalysisDatasetBuilder datasetBuilder;
  final AnalysisRuleEngine engine;
  final AnalysisPeriodResolver periodResolver;
  final AnalysisFindingRepository? findings;
  final AnalysisRuleResultRepository? results;

  /// Resolves a user-facing period choice into the authoritative analysis
  /// context. Presentation code may display this context, but must not derive
  /// its date boundaries.
  Future<ApplicationResult<AnalysisContext>> contextFor(
    String type, {
    DateTime? instant,
    AnalysisPeriod? customPeriod,
  }) => runApplication('resolve analysis period', () async {
    final timeZoneId = await datasetBuilder.timeZoneId();
    final baseCurrency = await datasetBuilder.baseCurrency();
    final placeholder = AnalysisContext(
      period:
          customPeriod ??
          AnalysisPeriod(
            startDate: '2000-01-01',
            endDate: '2000-01-01',
            timeZoneId: timeZoneId,
          ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: baseCurrency,
    );
    final resolution = periodResolver.resolvePrimary(
      type: type,
      context: placeholder,
      now: instant,
    );
    if (resolution is AnalysisPeriodResolutionFailure) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidState,
        field: 'period',
        message: 'Analysis period could not be resolved.',
      );
    }
    final window = (resolution as AnalysisPeriodResolved).window;
    return AnalysisContext(
      period: AnalysisPeriod(
        startDate: _date(window.start),
        endDate: _date(window.endExclusive.subtract(const Duration(days: 1))),
        timeZoneId: timeZoneId,
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: baseCurrency,
      periodType: type,
    );
  });

  /// Creates a selected-period context from date-only UI input while retaining
  /// the configured financial timezone and base currency in this layer.
  Future<ApplicationResult<AnalysisContext>> contextForDates({
    required String startDate,
    required String endDate,
  }) async {
    final timeZoneId = await datasetBuilder.timeZoneId();
    return contextFor(
      'selected_period',
      customPeriod: AnalysisPeriod(
        startDate: startDate,
        endDate: endDate,
        timeZoneId: timeZoneId,
      ),
    );
  }

  /// Resolves the default month in the application layer so presentation never
  /// invents financial windows or timezone policy.
  Future<ApplicationResult<List<RuleExecutionResult>>> currentMonth(
    DateTime instant,
  ) async {
    final context = await contextFor('current_month', instant: instant);
    return switch (context) {
      ApplicationSuccess<AnalysisContext>(:final value) => call(value),
      ApplicationFailure<AnalysisContext>() => ApplicationFailure(
        const ApplicationFailureDetail(
          code: ApplicationFailureCode.validation,
          operation: 'resolve current analysis month',
        ),
      ),
    };
  }

  Future<ApplicationResult<List<RuleExecutionResult>>> call(
    AnalysisContext context, {
    bool forceRefresh = false,
    int sourceRevision = 0,
  }) => runApplication('calculate analysis overview', () async {
    final definitions = await rules.listActive();
    final materializedRules = definitions
        .where(
          (rule) =>
              rule.resultPersistence == ResultPersistencePolicy.materialized,
        )
        .toList(growable: false);
    final available = <String, List<RuleExecutionResult>>{};
    if (!forceRefresh && results != null && materializedRules.isNotEmpty) {
      for (final rule in materializedRules) {
        final persisted = await results!.findAll(
          rule: rule,
          context: context,
          sourceRevision: sourceRevision,
        );
        if (persisted.isEmpty) continue;
        final expected = persisted.first.resultSetSize;
        final setKey = persisted.first.resultSetKey;
        final complete =
            persisted.length == expected &&
            (setKey == null ||
                persisted.every((value) => value.resultSetKey == setKey));
        if (complete) {
          available[rule.identity.value] = persisted
              .map((value) => restoreResult(value, rule))
              .toList(growable: false);
        }
      }
    }
    final allMaterializedFresh =
        materializedRules.length == definitions.length &&
        available.length == materializedRules.length;
    if (allMaterializedFresh) {
      return available.values.expand((value) => value).toList(growable: false);
    }
    final dataset = await datasetBuilder.build(context);
    if (dataset case ApplicationDatasetFailure()) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'analysis dataset unavailable',
      );
    }
    final calculatedResults = engine.execute(
      dataset: (dataset as ApplicationDatasetSuccess).dataset,
      definitions: definitions,
      availableResults: available,
    );
    final persistedLifecycles = findings == null
        ? const <String, FindingLifecycle>{}
        : {
            for (final finding in await findings!.list())
              finding.id: finding.lifecycle,
          };
    final executionResults = calculatedResults
        .map((result) {
          final finding = result.finding;
          if (finding == null) {
            return result;
          }
          final lifecycle = persistedLifecycles[finding.id];
          if (lifecycle == null || lifecycle == finding.lifecycle) {
            return result;
          }
          return RuleExecutionResult(
            rule: result.rule,
            metric: result.metric,
            finding: _withLifecycle(finding, lifecycle),
            comparison: result.comparison,
            issues: result.issues,
            failure: result.failure,
          );
        })
        .toList(growable: false);
    if (findings != null || results != null) {
      for (final result in executionResults) {
        final finding = result.finding;
        if (finding != null && findings != null) await findings!.save(finding);
      }
      if (results != null) {
        final materialized = executionResults.where(
          (result) =>
              result.rule.resultPersistence !=
              ResultPersistencePolicy.transient,
        );
        for (final result in materializeResults(
          materialized.toList(growable: false),
          context: context,
          at: DateTime.now().toUtc(),
          sourceRevision: sourceRevision,
        )) {
          await results!.save(result);
        }
      }
    }
    return executionResults;
  });
}

AnalysisFinding _withLifecycle(
  AnalysisFinding finding,
  FindingLifecycle lifecycle,
) => AnalysisFinding(
  id: finding.id,
  rule: finding.rule,
  context: finding.context,
  severity: finding.severity,
  lifecycle: lifecycle,
  currentValue: finding.currentValue,
  baselineValue: finding.baselineValue,
  absoluteChange: finding.absoluteChange,
  percentageChange: finding.percentageChange,
  dimension: finding.dimension,
  impactValue: finding.impactValue,
  supportingMetrics: finding.supportingMetrics,
  evidence: finding.evidence,
  qualityIssues: finding.qualityIssues,
  generatedAt: finding.generatedAt,
);

final class RerunAnalysis {
  const RerunAnalysis(this.calculate);
  final CalculateAnalysisOverview calculate;

  Future<ApplicationResult<List<RuleExecutionResult>>> call(
    AnalysisContext context, {
    int sourceRevision = 0,
  }) => calculate.call(
    context,
    forceRefresh: true,
    sourceRevision: sourceRevision,
  );
}

/// Produces the complete Insights surface from the shared Analysis
/// evaluation. This is the only layer that composes summary metrics with
/// findings; the Flutter presentation receives values and evidence only.
final class CalculateInsights {
  const CalculateInsights(this.analysis);
  final CalculateAnalysisOverview analysis;

  Future<ApplicationResult<AnalysisContext>> contextFor(
    String type, {
    DateTime? instant,
    AnalysisPeriod? customPeriod,
  }) => analysis.contextFor(type, instant: instant, customPeriod: customPeriod);

  Future<ApplicationResult<AnalysisContext>> contextForDates({
    required String startDate,
    required String endDate,
  }) => analysis.contextForDates(startDate: startDate, endDate: endDate);

  Future<ApplicationResult<InsightsEvaluation>> currentMonth(
    DateTime instant,
  ) => _fromContext(
    analysis.contextFor('current_month', instant: instant),
    forceRefresh: true,
  );

  Future<ApplicationResult<InsightsEvaluation>> call(
    AnalysisContext context, {
    bool forceRefresh = true,
    int sourceRevision = 0,
  }) async {
    final result = await analysis.call(
      context,
      forceRefresh: forceRefresh,
      sourceRevision: sourceRevision,
    );
    if (result is ApplicationFailure<List<RuleExecutionResult>>) {
      return ApplicationFailure<InsightsEvaluation>(result.failure);
    }
    return ApplicationSuccess(
      _build(
        context,
        (result as ApplicationSuccess<List<RuleExecutionResult>>).value,
      ),
    );
  }

  Future<ApplicationResult<InsightsEvaluation>> _fromContext(
    Future<ApplicationResult<AnalysisContext>> contextResult, {
    required bool forceRefresh,
  }) async {
    final context = await contextResult;
    if (context is ApplicationFailure<AnalysisContext>) {
      return ApplicationFailure(context.failure);
    }
    return call(
      (context as ApplicationSuccess<AnalysisContext>).value,
      forceRefresh: forceRefresh,
    );
  }

  InsightsEvaluation _build(
    AnalysisContext context,
    List<RuleExecutionResult> results,
  ) {
    AnalysisMetric? summaryMetric(String role) => results
        .where((result) => result.rule.role == role)
        .map((result) => result.metric)
        .whereType<AnalysisMetric>()
        .firstOrNull;
    final expense = summaryMetric('expenseTotal');
    final income = summaryMetric('incomeTotal');
    final net = summaryMetric('netCashFlow');
    final count = summaryMetric('eligibleTransactionCount');
    final expenseResult = _roleResult(results, 'expenseTotal');
    final incomeResult = _roleResult(results, 'incomeTotal');
    final baselineContext = _baselineContext(context);
    final summaryLimitations = _issues(results);
    final netComparison = _comparison(
      current: net?.value,
      baseline: _baselineValue(expenseResult, incomeResult),
    );
    final summary = PeriodSummary(
      context: context,
      baselineContext: baselineContext,
      expenseSpending: expense?.value,
      income: income?.value,
      netCashFlow: net?.value,
      eligibleTransactionCount: count?.transactionCount ?? 0,
      currency: context.baseCurrency,
      comparisonAvailable:
          expenseResult?.comparison?.baselineValue != null ||
          incomeResult?.comparison?.baselineValue != null,
      comparisonUnavailableReason:
          expenseResult?.comparison?.baselineValue == null &&
              incomeResult?.comparison?.baselineValue == null
          ? 'No comparable baseline was available.'
          : null,
      expenseChange: expenseResult?.comparison,
      incomeChange: incomeResult?.comparison,
      netCashFlowChange: netComparison,
      limitations: summaryLimitations,
    );
    final insightResults = results
        .where(
          (result) =>
              result.rule.surface == AnalysisSurface.insights &&
              result.rule.type == AnalysisRuleType.insight,
        )
        .map((result) => _insightResult(result, context, baselineContext))
        .toList();
    insightResults.sort(_compareInsights);
    // History sufficiency is about whether at least one insight comparison
    // has a usable baseline, not merely whether the selected period contains
    // transactions. A selected-period-only dataset must not present an
    // all-clear state when there is nothing meaningful to compare against.
    final hasSufficientHistory = results.any(
      (result) =>
          result.rule.surface == AnalysisSurface.insights &&
          result.rule.type == AnalysisRuleType.insight &&
          result.comparison?.availability ==
              AnalysisDataAvailability.sufficient,
    );
    return InsightsEvaluation(
      summary: summary,
      results: insightResults,
      limitations: summaryLimitations,
      hasSufficientHistory: hasSufficientHistory,
    );
  }

  InsightResult _insightResult(
    RuleExecutionResult result,
    AnalysisContext context,
    AnalysisContext? baselineContext,
  ) {
    final finding = result.finding;
    final comparison = result.comparison;
    final evidence = finding?.evidence ?? const <EvidenceReference>[];
    return InsightResult(
      outputType: result.rule.outputType,
      rule: result.rule,
      context: context,
      baselineContext: baselineContext,
      finding: finding,
      currentValue: finding?.currentValue ?? comparison?.currentValue,
      baselineValue: finding?.baselineValue ?? comparison?.baselineValue,
      absoluteChange: finding?.absoluteChange ?? comparison?.absoluteChange,
      percentageChange:
          finding?.percentageChange ?? comparison?.percentageChange,
      currency: context.baseCurrency,
      dimension: finding?.dimension,
      impactValue: finding?.impactValue,
      evidence: evidence,
      limitations: [...result.issues, ...?finding?.qualityIssues],
      failure: result.failure,
    );
  }

  RuleExecutionResult? _roleResult(
    List<RuleExecutionResult> results,
    String role,
  ) => results.where((result) => result.rule.role == role).firstOrNull;

  DecimalValue? _baselineValue(
    RuleExecutionResult? expense,
    RuleExecutionResult? income,
  ) {
    final expenseValue = expense?.comparison?.baselineValue;
    final incomeValue = income?.comparison?.baselineValue;
    if (expenseValue == null && incomeValue == null) return null;
    return _subtract(incomeValue ?? _zero(), expenseValue ?? _zero());
  }

  AnalysisComparison? _comparison({
    required DecimalValue? current,
    required DecimalValue? baseline,
  }) {
    if (current == null) return null;
    final absolute = baseline == null ? null : _subtract(current, baseline);
    final percentage = baseline == null
        ? null
        : calculatePercentageChange(absolute!, baseline);
    return AnalysisComparison(
      currentValue: current,
      baselineValue: baseline,
      absoluteChange: absolute,
      percentageChange: percentage,
      availability: baseline == null
          ? AnalysisDataAvailability.insufficient
          : AnalysisDataAvailability.sufficient,
    );
  }

  AnalysisContext? _baselineContext(AnalysisContext context) {
    final primary = _windowForContext(context);
    final previous = analysis.periodResolver.resolvePreviousEquivalent(
      primary: primary,
      elapsedAnchor: context.periodType == 'selected_period'
          ? null
          : DateTime.parse(context.period.endDate).add(const Duration(days: 1)),
    );
    if (previous is! AnalysisPeriodResolved) return null;
    final window = previous.window;
    return AnalysisContext(
      period: AnalysisPeriod(
        startDate: _date(window.start),
        endDate: _date(window.endExclusive.subtract(const Duration(days: 1))),
        timeZoneId: window.timeZoneId,
      ),
      datasetMode: context.datasetMode,
      currencyBasis: context.currencyBasis,
      baseCurrency: context.baseCurrency,
      periodType: context.periodType,
    );
  }

  ResolvedAnalysisWindow _windowForContext(AnalysisContext context) {
    final start = DateTime.parse(context.period.startDate);
    final end = DateTime.parse(
      context.period.endDate,
    ).add(const Duration(days: 1));
    final partial = {
      'current_month',
      'year_to_date',
      'rolling_30_days',
      'rolling_90_days',
    }.contains(context.periodType);
    final periodType = switch (context.periodType) {
      'current_month' || 'previous_month' || 'selected_month' => 'month',
      'year_to_date' || 'previous_year' => 'year',
      _ => 'custom',
    };
    return ResolvedAnalysisWindow(
      start: DateTime.utc(start.year, start.month, start.day),
      endExclusive: DateTime.utc(end.year, end.month, end.day),
      timeZoneId: context.period.timeZoneId,
      coverage: partial
          ? AnalysisCoverageState.partial
          : AnalysisCoverageState.complete,
      periodType: periodType,
    );
  }

  List<DataQualityIssue> _issues(List<RuleExecutionResult> results) => {
    for (final result in results) ...result.issues,
    for (final result in results) ...?result.metric?.qualityIssues,
    for (final result in results) ...?result.finding?.qualityIssues,
    for (final result in results)
      if (result.failure != null)
        DataQualityIssue(
          code: result.failure!.code,
          detail: result.failure!.message,
        ),
  }.toList(growable: false);

  int _compareInsights(InsightResult left, InsightResult right) {
    final outputPriority = {
      InsightOutputType.alert: 0,
      InsightOutputType.pattern: 1,
      InsightOutputType.summary: 2,
      InsightOutputType.dataQuality: 3,
      InsightOutputType.unresolved: 4,
    };
    final byOutput = outputPriority[left.outputType]!.compareTo(
      outputPriority[right.outputType]!,
    );
    if (byOutput != 0) return byOutput;

    final leftFinding = left.finding;
    final rightFinding = right.finding;
    if (leftFinding == null || rightFinding == null) {
      return leftFinding == null ? (rightFinding == null ? 0 : 1) : -1;
    }
    final severity = {
      RuleSeverity.critical: 0,
      RuleSeverity.warning: 1,
      RuleSeverity.attention: 2,
      RuleSeverity.info: 3,
    };
    final bySeverity = severity[leftFinding.severity]!.compareTo(
      severity[rightFinding.severity]!,
    );
    if (bySeverity != 0) return bySeverity;
    final byImpact = _compareMagnitude(
      right.impactValue ?? right.absoluteChange,
      left.impactValue ?? left.absoluteChange,
    );
    if (byImpact != 0) return byImpact;
    final byPercentage = _compareMagnitude(
      right.percentageChange,
      left.percentageChange,
    );
    if (byPercentage != 0) return byPercentage;
    final byGeneratedAt = right.generatedAt.compareTo(left.generatedAt);
    if (byGeneratedAt != 0) return byGeneratedAt;
    final byRule = left.rule.identity.value.compareTo(
      right.rule.identity.value,
    );
    if (byRule != 0) return byRule;
    return (left.dimension ?? '').compareTo(right.dimension ?? '');
  }

  int _compareMagnitude(DecimalValue? left, DecimalValue? right) {
    if (left == null || right == null) {
      return left == null ? (right == null ? 0 : 1) : -1;
    }
    final leftCoefficient = left.coefficient.abs();
    final rightCoefficient = right.coefficient.abs();
    final scale = left.scale > right.scale ? left.scale : right.scale;
    return (leftCoefficient * BigInt.from(10).pow(scale - left.scale))
        .compareTo(rightCoefficient * BigInt.from(10).pow(scale - right.scale));
  }
}

DecimalValue _zero() =>
    DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);

DecimalValue _subtract(DecimalValue left, DecimalValue right) {
  final scale = left.scale > right.scale ? left.scale : right.scale;
  return DecimalValue.fromParts(
    coefficient:
        left.coefficient * BigInt.from(10).pow(scale - left.scale) -
        right.coefficient * BigInt.from(10).pow(scale - right.scale),
    scale: scale,
  );
}

/// Converts an instant to the calendar date in the persisted financial zone.
/// The returned value is used only for its calendar components.
DateTime financialDateAt(DateTime instant, String timeZoneId) {
  time_zone_data.initializeTimeZones();
  final value = time_zone.TZDateTime.from(
    instant.toUtc(),
    time_zone.getLocation(timeZoneId),
  );
  return DateTime.utc(value.year, value.month, value.day);
}

final class QueryTransactionsForFinancialDate {
  const QueryTransactionsForFinancialDate(this.repository);
  final TransactionRepository repository;

  Future<ApplicationResult<List<TransactionDto>>> call(String date) =>
      runApplication('query financial date transactions', () async {
        final values = await repository.listAll();
        return values
            .where(
              (value) =>
                  value.transactionDate == date &&
                  value.status == TransactionStatus.active,
            )
            .map(TransactionDto.fromDomain)
            .toList(growable: false);
      });
}

final class AnalysisCalendarDay {
  const AnalysisCalendarDay({
    required this.financialDate,
    required this.transactionCount,
    required this.expenseTotal,
    required this.incomeTotal,
    required this.currencyBasis,
    this.qualityIssues = const [],
    this.evidence = const [],
  });

  final String financialDate;
  final int transactionCount;
  final Money? expenseTotal;
  final Money? incomeTotal;
  final CurrencyBasis currencyBasis;
  final List<DataQualityIssue> qualityIssues;
  final List<EvidenceReference> evidence;
}

final class AnalysisCalendarResult {
  const AnalysisCalendarResult({
    required this.year,
    required this.month,
    required this.timeZoneId,
    required this.days,
  });

  final int year;
  final int month;
  final String timeZoneId;
  final List<AnalysisCalendarDay> days;
}

/// Builds the backend contract for a selected financial month. It deliberately
/// consumes the canonical dataset instead of querying raw SQLite rows.
final class CalculateAnalysisCalendar {
  const CalculateAnalysisCalendar(this.datasetBuilder, this.rules, this.engine);
  final AnalysisDatasetBuilder datasetBuilder;
  final AnalysisRuleRepository rules;
  final AnalysisRuleEngine engine;

  Future<ApplicationResult<AnalysisCalendarResult>> call({
    required int year,
    required int month,
    required DatasetMode datasetMode,
    required CurrencyBasis currencyBasis,
    CurrencyCode? baseCurrency,
  }) => runApplication('calculate analysis calendar', () async {
    final first = DateTime.utc(year, month, 1);
    final last = DateTime.utc(year, month + 1, 0);
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: _date(first),
        endDate: _date(last),
        timeZoneId: await datasetBuilder.timeZoneId(),
      ),
      datasetMode: datasetMode,
      currencyBasis: currencyBasis,
      baseCurrency: baseCurrency,
    );
    final result = await datasetBuilder.build(context);
    if (result case ApplicationDatasetFailure(:final code)) {
      throw RepositoryException(RepositoryFailureCode.unavailable, code);
    }
    final dataset = (result as ApplicationDatasetSuccess).dataset;
    final definitions = (await rules.listActive())
        .where((rule) => rule.surface == AnalysisSurface.calendar)
        .toList(growable: false);
    final metrics = engine
        .execute(dataset: dataset, definitions: definitions)
        .where((result) => result.metric != null)
        .map((result) => result.metric!)
        .toList(growable: false);
    final days = <AnalysisCalendarDay>[];
    for (
      var day = first;
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    ) {
      final date = _date(day);
      AnalysisMetric? named(String key) =>
          metrics.cast<AnalysisMetric?>().firstWhere(
            (metric) => metric?.dimension == '$date:$key',
            orElse: () => null,
          );
      final countMetric = named('transactionCount');
      final expenseMetric = named('expenseTotal');
      final incomeMetric = named('incomeTotal');
      Money? money(AnalysisMetric? metric) => metric?.currency == null
          ? null
          : Money(amount: metric!.value, currency: metric.currency!);
      days.add(
        AnalysisCalendarDay(
          financialDate: date,
          transactionCount:
              int.tryParse(countMetric?.value.toString() ?? '') ?? 0,
          expenseTotal: money(expenseMetric),
          incomeTotal: money(incomeMetric),
          currencyBasis: currencyBasis,
          qualityIssues: [
            ...dataset.qualityIssues,
            ...?countMetric?.qualityIssues,
            ...?expenseMetric?.qualityIssues,
            ...?incomeMetric?.qualityIssues,
          ],
          evidence: {
            ...?countMetric?.evidence,
            ...?expenseMetric?.evidence,
            ...?incomeMetric?.evidence,
          }.toList(growable: false),
        ),
      );
    }
    return AnalysisCalendarResult(
      year: year,
      month: month,
      timeZoneId: context.period.timeZoneId,
      days: days,
    );
  });
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

final class UpdateFindingLifecycle {
  const UpdateFindingLifecycle(this.repository);
  final AnalysisFindingRepository repository;

  Future<ApplicationResult<void>> call(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) => runApplication(
    'update analysis finding lifecycle',
    () => repository.updateLifecycle(id, lifecycle, at),
  );
}
