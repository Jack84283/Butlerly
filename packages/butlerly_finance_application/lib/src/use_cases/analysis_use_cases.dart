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
    final executionResults = engine.execute(
      dataset: (dataset as ApplicationDatasetSuccess).dataset,
      definitions: definitions,
      availableResults: available,
    );
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
