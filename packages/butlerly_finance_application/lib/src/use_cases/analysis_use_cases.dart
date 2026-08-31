import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../result/application_result.dart';
import '../dto/transaction_dto.dart';
import '../analysis/dataset_builder.dart';
import '../analysis/rule_engine.dart';
import '../analysis/result_materialization.dart';

final class CalculateAnalysisOverview {
  const CalculateAnalysisOverview(
    this.rules,
    this.datasetBuilder,
    this.engine, {
    this.findings,
    this.results,
  });
  final AnalysisRuleRepository rules;
  final AnalysisDatasetBuilder datasetBuilder;
  final AnalysisRuleEngine engine;
  final AnalysisFindingRepository? findings;
  final AnalysisRuleResultRepository? results;

  /// Resolves the default month in the application layer so presentation never
  /// invents financial windows or timezone policy.
  Future<ApplicationResult<List<RuleExecutionResult>>> currentMonth(
    DateTime instant,
  ) async {
    final timeZoneId = await datasetBuilder.timeZoneId();
    final baseCurrency = await datasetBuilder.baseCurrency();
    final financialDate = financialDateAt(instant, timeZoneId);
    final first = DateTime.utc(financialDate.year, financialDate.month, 1);
    final last = DateTime.utc(financialDate.year, financialDate.month + 1, 0);
    return call(
      AnalysisContext(
        period: AnalysisPeriod(
          startDate: _date(first),
          endDate: _date(last),
          timeZoneId: timeZoneId,
        ),
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.baseCurrency,
        baseCurrency: baseCurrency,
      ),
    );
  }

  Future<ApplicationResult<List<RuleExecutionResult>>> call(
    AnalysisContext context, {
    bool forceRefresh = false,
    int sourceRevision = 0,
  }) => runApplication('calculate analysis overview', () async {
    final dataset = await datasetBuilder.build(context);
    if (dataset case ApplicationDatasetFailure()) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'analysis dataset unavailable',
      );
    }
    final definitions = await rules.listActive();
    final materializedRules = definitions
        .where(
          (rule) => rule.resultPersistence != ResultPersistencePolicy.transient,
        )
        .toList(growable: false);
    if (!forceRefresh && results != null && materializedRules.isNotEmpty) {
      final cached = <RuleExecutionResult>[];
      for (final rule in materializedRules) {
        final persisted = await results!.find(
          rule: rule,
          context: context,
          sourceRevision: sourceRevision,
        );
        if (persisted == null) {
          cached.clear();
          break;
        }
        cached.add(restoreResult(persisted, rule));
      }
      if (cached.length == materializedRules.length) {
        final transientDefinitions = definitions
            .where(
              (rule) =>
                  rule.resultPersistence == ResultPersistencePolicy.transient,
            )
            .toList(growable: false);
        if (transientDefinitions.isEmpty) return cached;
        return [
          ...cached,
          ...engine.execute(
            dataset: (dataset as ApplicationDatasetSuccess).dataset,
            definitions: transientDefinitions,
          ),
        ];
      }
    }
    final executionResults = engine.execute(
      dataset: (dataset as ApplicationDatasetSuccess).dataset,
      definitions: definitions,
    );
    if (findings != null || results != null) {
      for (final result in executionResults) {
        final finding = result.finding;
        if (finding != null && findings != null) await findings!.save(finding);
        if (results != null &&
            result.rule.resultPersistence !=
                ResultPersistencePolicy.transient &&
            (result.metric != null || result.finding != null)) {
          await results!.save(
            materializeResult(
              result,
              context: context,
              at: DateTime.now().toUtc(),
              sourceRevision: sourceRevision,
            ),
          );
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
