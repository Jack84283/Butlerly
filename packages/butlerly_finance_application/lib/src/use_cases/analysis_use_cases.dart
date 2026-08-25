import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import '../dto/transaction_dto.dart';
import '../analysis/dataset_builder.dart';
import '../analysis/rule_engine.dart';

final class CalculateAnalysisOverview {
  const CalculateAnalysisOverview(
    this.rules,
    this.datasetBuilder,
    this.engine, {
    this.findings,
  });
  final AnalysisRuleRepository rules;
  final AnalysisDatasetBuilder datasetBuilder;
  final AnalysisRuleEngine engine;
  final AnalysisFindingRepository? findings;

  Future<ApplicationResult<List<RuleExecutionResult>>> call(
    AnalysisContext context,
  ) => runApplication('calculate analysis overview', () async {
    final dataset = await datasetBuilder.build(context);
    if (dataset case ApplicationDatasetFailure()) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'analysis dataset unavailable',
      );
    }
    final definitions = await rules.listActive();
    final results = engine.execute(
      dataset: (dataset as ApplicationDatasetSuccess).dataset,
      definitions: definitions,
    );
    if (findings != null) {
      for (final result in results) {
        final finding = result.finding;
        if (finding != null) await findings!.save(finding);
      }
    }
    return results;
  });
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
  });

  final String financialDate;
  final int transactionCount;
  final Money? expenseTotal;
  final Money? incomeTotal;
  final CurrencyBasis currencyBasis;
  final List<DataQualityIssue> qualityIssues;
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
  const CalculateAnalysisCalendar(this.datasetBuilder);
  final AnalysisDatasetBuilder datasetBuilder;

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
    final days = <AnalysisCalendarDay>[];
    for (
      var day = first;
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    ) {
      final date = _date(day);
      final values = dataset.transactions.where(
        (value) => value.transactionDate == date,
      );
      var count = 0;
      Money? expense;
      Money? income;
      var mixedCurrencies = false;
      CurrencyCode? dayCurrency;
      for (final value in values) {
        count++;
        final money = currencyBasis == CurrencyBasis.baseCurrency
            ? value.normalizedMoney
            : value.money;
        if (money == null) continue;
        if (dayCurrency != null && dayCurrency != money.currency) {
          mixedCurrencies = true;
        }
        dayCurrency ??= money.currency;
        if (value.direction == TransactionDirection.expense) {
          expense = _add(expense, money);
        } else if (value.direction == TransactionDirection.income) {
          income = _add(income, money);
        }
      }
      if (mixedCurrencies && currencyBasis == CurrencyBasis.original) {
        expense = null;
        income = null;
      }
      days.add(
        AnalysisCalendarDay(
          financialDate: date,
          transactionCount: count,
          expenseTotal: expense,
          incomeTotal: income,
          currencyBasis: currencyBasis,
          qualityIssues: [
            ...dataset.qualityIssues,
            if (mixedCurrencies && currencyBasis == CurrencyBasis.original)
              const DataQualityIssue(
                code: 'mixedCurrencyCalendarDay',
                detail:
                    'Original-currency totals are not aggregatable for this day.',
              ),
          ],
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

Money _add(Money? left, Money right) {
  if (left == null) return right;
  if (left.currency != right.currency) return left;
  final scale = left.amount.scale > right.amount.scale
      ? left.amount.scale
      : right.amount.scale;
  final coefficient =
      left.amount.coefficient * BigInt.from(10).pow(scale - left.amount.scale) +
      right.amount.coefficient *
          BigInt.from(10).pow(scale - right.amount.scale);
  return Money(
    amount: DecimalValue.fromParts(coefficient: coefficient, scale: scale),
    currency: left.currency,
  );
}

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
