import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    this.load,
    this.loadCalendar,
    this.loadTransactionsForDate,
  });

  final Future<ApplicationResult<List<RuleExecutionResult>>> Function()? load;
  final Future<ApplicationResult<AnalysisCalendarResult>> Function(
    int year,
    int month,
  )?
  loadCalendar;
  final Future<ApplicationResult<List<TransactionDto>>> Function(String date)?
  loadTransactionsForDate;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late Future<ApplicationResult<List<RuleExecutionResult>>> _result;
  late DateTime _calendarMonth;
  Future<ApplicationResult<AnalysisCalendarResult>>? _calendarResult;
  String? _selectedDate;
  Future<ApplicationResult<List<TransactionDto>>>? _transactions;

  @override
  void initState() {
    super.initState();
    _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _result = _load();
    _calendarResult = _loadCalendar();
  }

  Future<ApplicationResult<List<RuleExecutionResult>>> _load() {
    if (widget.load != null) return widget.load!();
    if (!services.isRegistered<FinanceServices>()) {
      return Future.value(
        const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'calculate analysis overview',
            code: ApplicationFailureCode.unavailable,
          ),
        ),
      );
    }
    final useCase = services<FinanceServices>().calculateAnalysisOverview;
    if (useCase == null) {
      return Future.value(
        const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'calculate analysis overview',
            code: ApplicationFailureCode.unavailable,
          ),
        ),
      );
    }
    return useCase.currentMonth(DateTime.now());
  }

  Future<ApplicationResult<AnalysisCalendarResult>>? _loadCalendar() {
    if (widget.loadCalendar != null) {
      return widget.loadCalendar!(_calendarMonth.year, _calendarMonth.month);
    }
    if (!services.isRegistered<FinanceServices>()) return null;
    final finance = services<FinanceServices>();
    final useCase = finance.calculateAnalysisCalendar;
    if (useCase == null) return null;
    return finance.loadUserPreference().then((preferenceResult) {
      final preference = preferenceResult is ApplicationSuccess<UserPreference?>
          ? preferenceResult.value
          : null;
      return useCase(
        year: _calendarMonth.year,
        month: _calendarMonth.month,
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.baseCurrency,
        baseCurrency: preference?.baseCurrency,
      );
    });
  }

  void _moveMonth(int delta) {
    setState(() {
      _calendarMonth = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + delta,
      );
      _selectedDate = null;
      _transactions = null;
      _calendarResult = _loadCalendar();
    });
  }

  void _selectDate(String date) {
    Future<ApplicationResult<List<TransactionDto>>>? transactions;
    if (widget.loadTransactionsForDate != null) {
      transactions = widget.loadTransactionsForDate!(date);
    } else if (services.isRegistered<FinanceServices>()) {
      transactions = services<FinanceServices>()
          .queryTransactionsForFinancialDate(date);
    }
    setState(() {
      _selectedDate = date;
      _transactions = transactions;
    });
  }

  Future<void> _refresh() async {
    final value = _load();
    final calendar = _loadCalendar();
    setState(() {
      _result = value;
      _calendarResult = calendar;
    });
    await Future.wait([
      value,
      ...?calendar == null ? null : [calendar],
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('analysis'))),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<ApplicationResult<List<RuleExecutionResult>>>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data;
          if (result is! ApplicationSuccess<List<RuleExecutionResult>>) {
            return ListView(
              children: [
                ButlerlyErrorState(
                  title: context.l10n.text('analysisUnavailable'),
                  message: context.l10n.text('analysisUnavailableBody'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _refresh,
                ),
              ],
            );
          }
          return _AnalysisResults(
            results: result.value,
            calendarResult: _calendarResult,
            selectedDate: _selectedDate,
            transactions: _transactions,
            onPreviousMonth: () => _moveMonth(-1),
            onNextMonth: () => _moveMonth(1),
            onSelectDate: _selectDate,
          );
        },
      ),
    ),
  );
}

class _AnalysisResults extends StatelessWidget {
  const _AnalysisResults({
    required this.results,
    required this.calendarResult,
    required this.selectedDate,
    required this.transactions,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDate,
  });

  final List<RuleExecutionResult> results;
  final Future<ApplicationResult<AnalysisCalendarResult>>? calendarResult;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<String> onSelectDate;

  @override
  Widget build(BuildContext context) {
    List<RuleExecutionResult> surface(AnalysisSurface surface) => results
        .where((value) => value.metric != null && value.rule.surface == surface)
        .toList(growable: false);
    final overview = surface(AnalysisSurface.overview);
    final spending = surface(AnalysisSurface.spending);
    final dataQuality = surface(AnalysisSurface.dataQuality);
    final trends = results
        .where(
          (value) =>
              value.finding != null &&
              value.rule.surface == AnalysisSurface.trends,
        )
        .toList(growable: false);
    final findings = results
        .where(
          (value) =>
              value.finding != null &&
              value.rule.surface == AnalysisSurface.insights,
        )
        .toList(growable: false);
    final limitations = results
        .expand(
          (value) => [
            ...value.issues,
            ...?value.metric?.qualityIssues,
            ...?value.finding?.qualityIssues,
          ],
        )
        .toList(growable: false)
        .fold<List<DataQualityIssue>>(
          [],
          (unique, issue) => unique.any((item) => item.detail == issue.detail)
              ? unique
              : [...unique, issue],
        );
    final failures = results.where((value) => value.failure != null).toList();
    return ListView(
      padding: const EdgeInsets.all(ButlerlySpacing.standard),
      children: [
        Semantics(
          label: context.l10n.text('offlineAnalysisStatus'),
          child: ButlerlyCard(
            child: Row(
              children: [
                Icon(
                  Icons.offline_bolt_outlined,
                  color: context.colors.success,
                ),
                const SizedBox(width: ButlerlySpacing.small),
                Expanded(
                  child: Text(context.l10n.text('offlineAnalysisStatus')),
                ),
              ],
            ),
          ),
        ),
        ButlerlySectionHeader(title: context.l10n.text('overview')),
        if (overview.isEmpty)
          ButlerlyEmptyState(
            icon: Icons.insights_outlined,
            title: context.l10n.text('notEnoughInsightData'),
            message: context.l10n.text('notEnoughInsightDataBody'),
          )
        else
          ...overview.map(
            (result) =>
                _MetricCard(metric: result.metric!, showDimension: false),
          ),
        if (spending.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('spending')),
          ...spending.map((result) => _MetricCard(metric: result.metric!)),
        ],
        if (trends.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('trends')),
          ...trends.map((result) => _FindingCard(finding: result.finding!)),
        ],
        if (calendarResult != null) ...[
          ButlerlySectionHeader(title: context.l10n.text('financialCalendar')),
          _FinancialCalendar(
            result: calendarResult!,
            selectedDate: selectedDate,
            transactions: transactions,
            onPreviousMonth: onPreviousMonth,
            onNextMonth: onNextMonth,
            onSelectDate: onSelectDate,
          ),
        ],
        ButlerlySectionHeader(title: context.l10n.text('insights')),
        if (findings.isEmpty && failures.isEmpty)
          ButlerlyCard(
            child: ListTile(
              leading: Icon(
                Icons.check_circle_outline,
                color: context.colors.success,
              ),
              title: Text(context.l10n.text('allClear')),
              subtitle: Text(context.l10n.text('allClearBody')),
            ),
          )
        else if (findings.isNotEmpty)
          ...findings.map((result) => _FindingCard(finding: result.finding!)),
        if (findings.isEmpty && failures.isNotEmpty)
          ButlerlyEmptyState(
            icon: Icons.error_outline,
            title: context.l10n.text('insightsUnavailable'),
            message: context.l10n.text('insightsUnavailableBody'),
          ),
        if (dataQuality.isNotEmpty ||
            limitations.isNotEmpty ||
            failures.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('dataQuality')),
          ...dataQuality.map(
            (result) => Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.compact),
              child: _DataQualityCard(metric: result.metric!),
            ),
          ),
          if (limitations.isNotEmpty || failures.isNotEmpty)
            ButlerlyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...limitations.map(
                    (issue) => Text('• ${_localizedIssue(context, issue)}'),
                  ),
                  ...failures.map(
                    (result) => Text('• ${result.failure!.message}'),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _FinancialCalendar extends StatelessWidget {
  const _FinancialCalendar({
    required this.result,
    required this.selectedDate,
    required this.transactions,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDate,
  });

  final Future<ApplicationResult<AnalysisCalendarResult>> result;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<String> onSelectDate;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<ApplicationResult<AnalysisCalendarResult>>(
    future: result,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done) {
        return const ButlerlyCard(
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (value is! ApplicationSuccess<AnalysisCalendarResult>) {
        return ButlerlyCard(
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(context.l10n.text('analysisUnavailable')),
            subtitle: Text(context.l10n.text('dataPreserved')),
          ),
        );
      }
      final calendar = value.value;
      final first = DateTime(calendar.year, calendar.month);
      final leading = first.weekday - DateTime.monday;
      final today = financialDateAt(DateTime.now(), calendar.timeZoneId);
      final todayDate =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      return ButlerlyCard(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('analysis-calendar-previous'),
                  tooltip: 'Previous month',
                  onPressed: onPreviousMonth,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(context).formatMonthYear(first),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('analysis-calendar-next'),
                  tooltip: 'Next month',
                  onPressed: onNextMonth,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leading + calendar.days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemBuilder: (context, index) {
                if (index < leading) return const SizedBox.shrink();
                final day = calendar.days[index - leading];
                final selected = selectedDate == day.financialDate;
                final isToday = todayDate == day.financialDate;
                final hasTransactions = day.transactionCount > 0;
                final number = int.parse(day.financialDate.substring(8));
                return Semantics(
                  label:
                      '${day.financialDate}${isToday ? ', today' : ''}, ${day.transactionCount} transactions',
                  selected: selected,
                  button: true,
                  child: InkWell(
                    key: ValueKey('analysis-calendar-${day.financialDate}'),
                    onTap: () => onSelectDate(day.financialDate),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : isToday
                              ? Theme.of(context).colorScheme.secondary
                              : Colors.transparent,
                          width: selected ? 2 : 1,
                        ),
                        color: hasTransactions
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$number'),
                          Text(
                            '${day.transactionCount}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: context.colors.secondaryText),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (selectedDate != null) ...[
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  selectedDate!,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              _CalendarTransactions(result: transactions),
            ],
          ],
        ),
      );
    },
  );
}

class _CalendarTransactions extends StatelessWidget {
  const _CalendarTransactions({required this.result});
  final Future<ApplicationResult<List<TransactionDto>>>? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) return const SizedBox.shrink();
    return FutureBuilder<ApplicationResult<List<TransactionDto>>>(
      future: result,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value is! ApplicationSuccess<List<TransactionDto>>) {
          return const LinearProgressIndicator();
        }
        if (value.value.isEmpty) {
          return Text(context.l10n.text('noTransactions'));
        }
        final finance = services.isRegistered<FinanceServices>()
            ? services<FinanceServices>()
            : null;
        final masterData = finance == null
            ? Future.value(TransactionMasterData())
            : TransactionMasterData.load(
                finance,
                languageCode: Localizations.localeOf(context).languageCode,
              );
        return FutureBuilder<TransactionMasterData>(
          future: masterData,
          builder: (context, masterSnapshot) {
            final data = masterSnapshot.data ?? const TransactionMasterData();
            return ButlerlyTransactionList(
              children: value.value
                  .map(
                    (transaction) => ButlerlyTransactionListItem(
                      key: ValueKey(
                        'analysis-calendar-transaction-${transaction.id}',
                      ),
                      title: transaction.description?.trim().isNotEmpty == true
                          ? transaction.description!
                          : context.l10n.text('untitledTransaction'),
                      subtitle: data.summary(transaction),
                      meta: transactionDateLabel(
                        transaction,
                        pendingLabel: context.l10n.text('pending'),
                        locale: Localizations.localeOf(context).toLanguageTag(),
                      ),
                      amount: localizedTransactionAmount(
                        context,
                        transaction.amount,
                      ),
                      currency: transaction.currency,
                      isIncome:
                          transaction.direction ==
                          TransactionDirection.income.name,
                      needsReview: transaction.reviewState == 'needsReview',
                      onTap: finance == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TransactionDetailPage(
                                  finance: finance,
                                  transaction: transaction,
                                ),
                              ),
                            ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        );
      },
    );
  }
}

class _DataQualityCard extends StatelessWidget {
  const _DataQualityCard({required this.metric});
  final AnalysisMetric metric;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: ExpansionTile(
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(context.l10n.text(metric.rule.nameKey)),
      subtitle: Text(
        context.l10n.text('supportingTransactions', {
          'count': localizedCount(context, metric.evidence.length.toString()),
        }),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Text(
        localizedDecimal(context, metric.value.toString()),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      children: metric.evidence
          .map(
            (evidence) => ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(evidence.transactionId.value),
            ),
          )
          .toList(growable: false),
    ),
  );
}

String _localizedIssue(BuildContext context, DataQualityIssue issue) {
  if (issue.detail == 'No comparable baseline was available.') {
    return context.l10n.text('baselineUnavailable');
  }
  return issue.detail;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, this.showDimension = true});
  final AnalysisMetric metric;
  final bool showDimension;

  @override
  Widget build(BuildContext context) {
    final value = metric.rule.measure.operation == RuleOperation.count
        ? localizedCount(context, metric.value.toString())
        : localizedDecimal(context, metric.value.toString());
    final label = _withoutValueLabel(context.l10n.text(metric.rule.nameKey));
    return Padding(
      padding: const EdgeInsets.only(bottom: ButlerlySpacing.compact),
      child: Semantics(
        label:
            '$label, $value${metric.currency == null ? '' : ' ${metric.currency!.value}'}',
        child: ButlerlyCard(
          child: ListTile(
            title: Text(label),
            subtitle: showDimension && metric.dimension != null
                ? Text(
                    _withoutValueLabel(metric.dimension!),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            trailing: Text(
              '$value${metric.currency == null ? '' : ' ${metric.currency!.value}'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
}

String _withoutValueLabel(String label) => label
    .replaceAll(RegExp(r'\s*:\s*value\b', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});
  final AnalysisFinding finding;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(context.l10n.text(finding.rule.nameKey)),
      subtitle: Text(
        finding.baselineValue == null
            ? context.l10n.text('baselineUnavailable')
            : context.l10n.text('baselineAvailable'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}
