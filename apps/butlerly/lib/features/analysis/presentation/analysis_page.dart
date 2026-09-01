import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    this.load,
    this.loadForPeriod,
    this.loadCalendar,
    this.loadTransactionsForDate,
  });
  final Future<ApplicationResult<List<RuleExecutionResult>>> Function()? load;
  final Future<ApplicationResult<List<RuleExecutionResult>>> Function(
    String period,
  )?
  loadForPeriod;
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
  static const _defaultPeriod = 'current_month';
  late Future<ApplicationResult<List<RuleExecutionResult>>> _result;
  String _period = _defaultPeriod;
  AnalysisContext? _context;
  AnalysisPeriod? _customPeriod;
  Future<ApplicationResult<AnalysisCalendarResult>>? _calendar;
  String? _selectedDate;
  Future<ApplicationResult<List<TransactionDto>>>? _transactions;

  @override
  void initState() {
    super.initState();
    _result = _load(_period);
    transactionChanges.addListener(_reload);
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_reload);
    super.dispose();
  }

  Future<ApplicationResult<List<RuleExecutionResult>>> _load(String period) {
    if (widget.loadForPeriod != null) return widget.loadForPeriod!(period);
    if (widget.load != null && period == _defaultPeriod) return widget.load!();
    final finance = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>()
        : null;
    final useCase = finance?.calculateAnalysisOverview;
    if (useCase == null)
      return Future.value(
        const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'calculate analysis overview',
            code: ApplicationFailureCode.unavailable,
          ),
        ),
      );
    return useCase
        .contextFor(
          period,
          instant: DateTime.now(),
          customPeriod: _customPeriod,
        )
        .then((resolved) {
          if (resolved is! ApplicationSuccess<AnalysisContext>)
            return const ApplicationFailure(
              ApplicationFailureDetail(
                operation: 'resolve analysis period',
                code: ApplicationFailureCode.unavailable,
              ),
            );
          _context = resolved.value;
          return useCase.call(resolved.value);
        });
  }

  Future<ApplicationResult<AnalysisCalendarResult>>? _loadCalendar(
    AnalysisContext context,
  ) {
    if (widget.loadCalendar == null &&
        context.period.startDate.substring(0, 7) !=
            context.period.endDate.substring(0, 7))
      return null;
    final start = context.period.startDate == '2000-01-01'
        ? DateTime(DateTime.now().year, DateTime.now().month)
        : DateTime.parse(context.period.startDate);
    if (widget.loadCalendar != null)
      return widget.loadCalendar!(start.year, start.month);
    final useCase = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().calculateAnalysisCalendar
        : null;
    return useCase?.call(
      year: start.year,
      month: start.month,
      datasetMode: context.datasetMode,
      currencyBasis: context.currencyBasis,
      baseCurrency: context.baseCurrency,
    );
  }

  Future<ApplicationResult<List<TransactionDto>>>? _loadTransactions(
    String date,
  ) {
    if (widget.loadTransactionsForDate != null)
      return widget.loadTransactionsForDate!(date);
    if (!services.isRegistered<FinanceServices>()) return null;
    return services<FinanceServices>().queryTransactionsForFinancialDate(date);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _result = _load(_period);
      _calendar = null;
    });
  }

  void _selectPeriod(String period) {
    if (period == _period) return;
    if (period == 'selected_period') {
      _chooseCustomPeriod();
      return;
    }
    setState(() {
      _period = period;
      _customPeriod = null;
      _context = null;
      _selectedDate = null;
      _transactions = null;
      _calendar = null;
      _result = _load(period);
    });
  }

  Future<void> _chooseCustomPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || range == null) return;
    setState(() {
      _period = 'selected_period';
      _customPeriod = AnalysisPeriod(
        startDate: _date(range.start),
        endDate: _date(range.end),
        timeZoneId: _context?.period.timeZoneId ?? 'UTC',
      );
      _context = null;
      _selectedDate = null;
      _transactions = null;
      _calendar = null;
      _result = _load(_period);
    });
  }

  void _selectDate(String date) => setState(() {
    _selectedDate = date;
    _transactions = _loadTransactions(date);
  });
  Future<void> _refresh() async {
    final value = _load(_period);
    setState(() => _result = value);
    await value;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<ApplicationResult<List<RuleExecutionResult>>>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return ListView(
              padding: const EdgeInsets.all(ButlerlySpacing.standard),
              children: const [_AnalysisSkeleton()],
            );
          final result = snapshot.data;
          if (result is! ApplicationSuccess<List<RuleExecutionResult>>)
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
          final analysisContext =
              _context ??
              result.value
                  .map((r) => r.metric?.context ?? r.finding?.context)
                  .whereType<AnalysisContext>()
                  .firstOrNull ??
              _emptyContext;
          _calendar ??= _loadCalendar(analysisContext);
          return _AnalysisContent(
            results: result.value,
            analysisContext: analysisContext,
            period: _period,
            calendar: _calendar,
            selectedDate: _selectedDate,
            transactions: _transactions,
            onPeriodChanged: _selectPeriod,
            onSelectDate: _selectDate,
          );
        },
      ),
    ),
  );
  static final _emptyContext = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2000-01-01',
      endDate: '2000-01-01',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
  );
}

class _AnalysisContent extends StatelessWidget {
  const _AnalysisContent({
    required this.results,
    required this.analysisContext,
    required this.period,
    required this.calendar,
    required this.selectedDate,
    required this.transactions,
    required this.onPeriodChanged,
    required this.onSelectDate,
  });
  final List<RuleExecutionResult> results;
  final AnalysisContext analysisContext;
  final String period;
  final Future<ApplicationResult<AnalysisCalendarResult>>? calendar;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final ValueChanged<String> onPeriodChanged;
  final ValueChanged<String> onSelectDate;
  @override
  Widget build(BuildContext context) {
    final model = _AnalysisModel.fromResults(results);
    return ButlerlyPage(
      title: context.l10n.text('analysis'),
      subtitle: _periodDescription(context, period, analysisContext.period),
      children: [
        _AnalysisPeriodSelector(value: period, onChanged: onPeriodChanged),
        const SizedBox(height: ButlerlySpacing.standard),
        _AnalysisSummary(model: model),
        _SectionHeader(title: context.l10n.text('trends')),
        _AnalysisTrend(model: model),
        _SectionHeader(title: context.l10n.text('spending')),
        _AnalysisBreakdown(model: model),
        _SectionHeader(title: context.l10n.text('financialCalendar')),
        calendar == null
            ? _ActivitySummary(metric: model.transactionCount)
            : _AnalysisActivity(
                result: calendar!,
                selectedDate: selectedDate,
                transactions: transactions,
                onSelectDate: onSelectDate,
              ),
        if (model.insight != null) ...[
          _SectionHeader(title: context.l10n.text('insights')),
          _AnalysisInsight(finding: model.insight!),
        ] else if (model.insightUnavailable) ...[
          _SectionHeader(title: context.l10n.text('insights')),
          ButlerlyCard(child: Text(context.l10n.text('insightsUnavailable'))),
        ],
        _SectionHeader(title: context.l10n.text('dataQuality')),
        _AnalysisQuality(model: model),
      ],
    );
  }
}

class _AnalysisPeriodSelector extends StatelessWidget {
  const _AnalysisPeriodSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: const ValueKey('analysis-period-selector'),
    initialValue: value,
    decoration: InputDecoration(labelText: context.l10n.text('analysisPeriod')),
    items: [
      for (final item in const [
        ('current_month', 'thisMonth'),
        ('previous_month', 'lastMonth'),
        ('year_to_date', 'yearToDate'),
        ('rolling_30_days', 'last30Days'),
        ('rolling_90_days', 'last90Days'),
        ('selected_period', 'custom'),
      ])
        DropdownMenuItem(
          value: item.$1,
          child: Text(context.l10n.text(item.$2)),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class _AnalysisSummary extends StatelessWidget {
  const _AnalysisSummary({required this.model});
  final _AnalysisModel model;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: context.l10n.text('analysisSummary'),
    child: ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.spending == null
                ? context.l10n.text('noSpendingInPeriod')
                : _money(context, model.spending!),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          Text(context.l10n.text('totalSpending')),
          const SizedBox(height: ButlerlySpacing.standard),
          Row(
            children: [
              Expanded(
                child: _SupportingMetric(
                  metric: model.income,
                  label: context.l10n.text('income'),
                ),
              ),
              Expanded(
                child: _SupportingMetric(
                  metric: model.net,
                  label: context.l10n.text('netCashFlow'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SupportingMetric extends StatelessWidget {
  const _SupportingMetric({required this.metric, required this.label});
  final AnalysisMetric? metric;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$label, ${metric == null ? context.l10n.text('notAvailable') : _money(context, metric!)}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          metric == null ? '—' : _money(context, metric!),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    ),
  );
}

class _AnalysisTrend extends StatelessWidget {
  const _AnalysisTrend({required this.model});
  final _AnalysisModel model;
  @override
  Widget build(BuildContext context) {
    if (model.trend.isEmpty)
      return ButlerlyCard(
        child: Text(context.l10n.text('insufficientTrendData')),
      );
    final max = model.trend
        .map(_number)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return ButlerlyCard(
      semanticLabel: context.l10n.text('spendingTrend'),
      child: Semantics(
        label: model.trend
            .map((m) => '${_dimension(m)} ${_money(context, m)}')
            .join(', '),
        child: SizedBox(
          height: 150,
          child: CustomPaint(
            painter: _TrendPainter(
              values: model.trend
                  .map<double>((m) => max == 0 ? 0 : _number(m) / max)
                  .toList(),
              color: context.colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.color});
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y =
          size.height - (size.height * values[i]).clamp(8, size.height - 8);
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.color != color;
}

class _AnalysisBreakdown extends StatelessWidget {
  const _AnalysisBreakdown({required this.model});
  final _AnalysisModel model;
  @override
  Widget build(BuildContext context) {
    if (model.categories.isEmpty)
      return ButlerlyCard(child: Text(context.l10n.text('noSpendingInPeriod')));
    final max = model.categories
        .map(_number)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return ButlerlyCard(
      child: Column(
        children: [
          for (final metric in model.categories.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
              child: Semantics(
                label: '${_dimension(metric)}, ${_money(context, metric)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_dimension(metric))),
                        Text(_money(context, metric)),
                      ],
                    ),
                    const SizedBox(height: ButlerlySpacing.micro),
                    LinearProgressIndicator(
                      value: max == 0 ? 0 : _number(metric) / max,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.metric});
  final AnalysisMetric? metric;
  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Text(
      metric == null
          ? context.l10n.text('noActivityInPeriod')
          : '${_number(metric!).round()} ${context.l10n.text('transactions')}',
    ),
  );
}

class _AnalysisActivity extends StatelessWidget {
  const _AnalysisActivity({
    required this.result,
    required this.selectedDate,
    required this.transactions,
    required this.onSelectDate,
  });
  final Future<ApplicationResult<AnalysisCalendarResult>> result;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final ValueChanged<String> onSelectDate;
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<ApplicationResult<AnalysisCalendarResult>>(
    future: result,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done)
        return const ButlerlyCard(child: LinearProgressIndicator());
      if (value is! ApplicationSuccess<AnalysisCalendarResult>)
        return ButlerlyCard(
          child: Text(context.l10n.text('analysisUnavailable')),
        );
      final calendar = value.value;
      final first = DateTime(calendar.year, calendar.month);
      final leading = first.weekday - DateTime.monday;
      return ButlerlyCard(
        child: Column(
          children: [
            Text(
              MaterialLocalizations.of(context).formatMonthYear(first),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: ButlerlySpacing.small),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leading + calendar.days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                if (index < leading) return const SizedBox.shrink();
                final day = calendar.days[index - leading];
                final selected = day.financialDate == selectedDate;
                return Semantics(
                  label:
                      '${day.financialDate}, ${day.transactionCount} ${context.l10n.text('transactions')}',
                  selected: selected,
                  button: true,
                  child: InkWell(
                    key: ValueKey('analysis-calendar-${day.financialDate}'),
                    onTap: () => onSelectDate(day.financialDate),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: day.transactionCount == 0
                            ? null
                            : context.colors.selection,
                        border: selected
                            ? Border.all(
                                color: context.colors.interactive,
                                width: 2,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(
                          ButlerlyRadius.small,
                        ),
                      ),
                      child: Text(day.financialDate.substring(8)),
                    ),
                  ),
                );
              },
            ),
            if (selectedDate != null)
              _DaySummary(date: selectedDate!, result: transactions),
          ],
        ),
      );
    },
  );
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.date, required this.result});
  final String date;
  final Future<ApplicationResult<List<TransactionDto>>>? result;
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<ApplicationResult<List<TransactionDto>>>(
    future: result,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (value is! ApplicationSuccess<List<TransactionDto>>)
        return const Padding(
          padding: EdgeInsets.only(top: ButlerlySpacing.small),
          child: LinearProgressIndicator(),
        );
      return Padding(
        padding: const EdgeInsets.only(top: ButlerlySpacing.small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$date · ${localizedCount(context, value.value.length.toString())} ${context.l10n.text('transactions')}',
            ),
            if (value.value.isEmpty) Text(context.l10n.text('noTransactions')),
            for (final transaction in value.value.take(3))
              ListTile(
                key: ValueKey(
                  'analysis-calendar-transaction-${transaction.id}',
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  transaction.description?.trim().isNotEmpty == true
                      ? transaction.description!
                      : context.l10n.text('untitledTransaction'),
                ),
                subtitle: Text(
                  transactionDateLabel(
                    transaction,
                    pendingLabel: context.l10n.text('pending'),
                    locale: Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
                trailing: Text(
                  '${localizedTransactionAmount(context, transaction.amount)} ${transaction.currency}',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _AnalysisInsight extends StatelessWidget {
  const _AnalysisInsight({required this.finding});
  final AnalysisFinding finding;
  @override
  Widget build(BuildContext context) => ButlerlyCard(
    semanticLabel: context.l10n.text('notable'),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.info_outline, color: context.colors.info),
      title: Text(context.l10n.text('notable')),
      subtitle: Text(context.l10n.text(finding.rule.nameKey)),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _AnalysisQuality extends StatelessWidget {
  const _AnalysisQuality({required this.model});
  final _AnalysisModel model;
  @override
  Widget build(BuildContext context) {
    final count = model.qualityCount;
    return ButlerlyCard(
      child: Row(
        children: [
          Icon(
            count == 0
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            color: count == 0 ? context.colors.success : context.colors.warning,
          ),
          const SizedBox(width: ButlerlySpacing.small),
          Expanded(
            child: Text(
              count == 0
                  ? context.l10n.text('dataQualityGood')
                  : context.l10n.text('dataQualityNeedsAttention', {
                      'count': localizedCount(context, count.toString()),
                    }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => ButlerlySectionHeader(title: title);
}

class _AnalysisSkeleton extends StatelessWidget {
  const _AnalysisSkeleton();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 48),
      for (var i = 0; i < 4; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
          child: ButlerlyCard(
            child: SizedBox(
              height: i == 0 ? 120 : 160,
              child: const LinearProgressIndicator(),
            ),
          ),
        ),
    ],
  );
}

class _AnalysisModel {
  const _AnalysisModel({
    this.spending,
    this.income,
    this.net,
    this.transactionCount,
    this.insight,
    required this.insightUnavailable,
    required this.trend,
    required this.categories,
    required this.qualityCount,
  });
  final AnalysisMetric? spending;
  final AnalysisMetric? income;
  final AnalysisMetric? net;
  final AnalysisMetric? transactionCount;
  final AnalysisFinding? insight;
  final bool insightUnavailable;
  final List<AnalysisMetric> trend;
  final List<AnalysisMetric> categories;
  final int qualityCount;
  factory _AnalysisModel.fromResults(List<RuleExecutionResult> results) {
    AnalysisMetric? metric(String id) => results
        .where((r) => r.metric != null && r.rule.identity.value == id)
        .map((r) => r.metric!)
        .firstOrNull;
    final categories =
        results
            .where(
              (r) => r.metric != null && r.rule.identity.value == 'ANL-R010',
            )
            .map((r) => r.metric!)
            .toList()
          ..sort((a, b) => _number(b).compareTo(_number(a)));
    final trend =
        results
            .where(
              (r) => r.metric != null && r.rule.identity.value == 'ANL-R014',
            )
            .map((r) => r.metric!)
            .toList()
          ..sort((a, b) => _dimension(a).compareTo(_dimension(b)));
    final finding = results
        .where((r) => r.finding != null && r.rule.identity.value == 'ANL-R020')
        .map((r) => r.finding!)
        .firstOrNull;
    return _AnalysisModel(
      spending: metric('ANL-R001'),
      income: metric('ANL-R002'),
      net: metric('ANL-R003'),
      transactionCount: metric('ANL-R004'),
      insight: finding,
      insightUnavailable: results.any((r) => r.failure != null),
      trend: trend,
      categories: categories,
      qualityCount: results
          .where(
            (r) =>
                r.metric != null &&
                r.rule.surface == AnalysisSurface.dataQuality,
          )
          .fold(
            0,
            (sum, r) => sum + (int.tryParse(r.metric!.value.toString()) ?? 0),
          ),
    );
  }
}

String _periodDescription(
  BuildContext context,
  String period,
  AnalysisPeriod value,
) {
  final label = context.l10n.text(switch (period) {
    'current_month' => 'thisMonth',
    'previous_month' => 'lastMonth',
    'year_to_date' => 'yearToDate',
    'rolling_30_days' => 'last30Days',
    'rolling_90_days' => 'last90Days',
    _ => 'custom',
  });
  return '$label · ${value.startDate} – ${value.endDate}';
}

String _money(BuildContext context, AnalysisMetric metric) =>
    '${localizedDecimal(context, metric.value.toString())} ${metric.currency?.value ?? ''}'
        .trim();
double _number(AnalysisMetric metric) =>
    double.tryParse(metric.value.toString()) ?? 0;
String _dimension(AnalysisMetric metric) =>
    metric.dimension?.split(':').firstOrNull ?? metric.rule.nameKey;

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
