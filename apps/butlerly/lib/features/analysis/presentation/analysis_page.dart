import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_activity.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_data_quality.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_insight_preview.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_period_selector.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_skeleton.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_spending_breakdown.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_summary.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_trend.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    this.load,
    this.loadForPeriod,
    this.loadCalendar,
    this.loadTransactionsForDate,
    this.loadMasterData,
    this.onNavigationRequested,
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
  final Future<TransactionMasterData> Function()? loadMasterData;
  final ValueChanged<String>? onNavigationRequested;
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  static const _defaultPeriod = 'current_month';
  late Future<ApplicationResult<List<RuleExecutionResult>>> _result;
  String _period = _defaultPeriod;
  AnalysisContext? _context;
  DateTimeRange? _customRange;
  Future<ApplicationResult<AnalysisCalendarResult>>? _calendar;
  String? _selectedDate;
  Future<ApplicationResult<List<TransactionDto>>>? _transactions;
  TransactionMasterData? _masterData;
  String? _masterDataLocale;

  @override
  void initState() {
    super.initState();
    _result = _load(_period);
    transactionChanges.addListener(_reload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (_masterDataLocale == locale) return;
    _masterDataLocale = locale;
    final future = widget.loadMasterData != null
        ? widget.loadMasterData!()
        : services.isRegistered<FinanceServices>()
        ? TransactionMasterData.load(
            services<FinanceServices>(),
            languageCode: locale,
          )
        : null;
    future?.then((value) {
      if (mounted) setState(() => _masterData = value);
    });
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
    final contextFuture = period == 'selected_period' && _customRange != null
        ? useCase.contextForDates(
            startDate: analysisDate(_customRange!.start),
            endDate: analysisDate(_customRange!.end),
          )
        : useCase.contextFor(period, instant: DateTime.now());
    return contextFuture.then((resolved) {
      if (resolved is! ApplicationSuccess<AnalysisContext>) {
        return const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'resolve analysis period',
            code: ApplicationFailureCode.unavailable,
          ),
        );
      }
      _context = resolved.value;
      return useCase.call(resolved.value);
    });
  }

  Future<ApplicationResult<AnalysisCalendarResult>>? _loadCalendar(
    AnalysisContext context,
  ) {
    if (widget.loadCalendar == null &&
        context.period.startDate.substring(0, 7) !=
            context.period.endDate.substring(0, 7)) {
      return null;
    }
    final start = context.period.startDate == '2000-01-01'
        ? DateTime(DateTime.now().year, DateTime.now().month)
        : DateTime.parse(context.period.startDate);
    final end = context.period.endDate == '2000-01-01'
        ? DateTime(start.year, start.month + 1, 0)
        : DateTime.parse(context.period.endDate);
    if (widget.loadCalendar == null &&
        end.day != DateTime(start.year, start.month + 1, 0).day) {
      return null;
    }
    if (widget.loadCalendar != null) {
      return widget.loadCalendar!(start.year, start.month);
    }
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
    if (widget.loadTransactionsForDate != null) {
      return widget.loadTransactionsForDate!(date);
    }
    if (!services.isRegistered<FinanceServices>()) return null;
    return services<FinanceServices>().queryTransactionsForFinancialDate(date);
  }

  void _reload() {
    if (!mounted) return;
    final selected = _selectedDate;
    setState(() {
      _result = _load(_period);
      _calendar = null;
      _transactions = selected == null ? null : _loadTransactions(selected);
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
      _customRange = null;
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
      _customRange = range;
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
    final selected = _selectedDate;
    setState(() {
      _result = value;
      _calendar = null;
      _transactions = selected == null ? null : _loadTransactions(selected);
    });
    await value;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<ApplicationResult<List<RuleExecutionResult>>>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ButlerlyPage(
              title: context.l10n.text('analysis'),
              children: const [AnalysisSkeleton()],
            );
          }
          final result = snapshot.data;
          if (result is! ApplicationSuccess<List<RuleExecutionResult>>) {
            return ButlerlyPage(
              title: context.l10n.text('analysis'),
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
          final analysisContext =
              _context ??
              result.value
                  .map((r) => r.metric?.context ?? r.finding?.context)
                  .whereType<AnalysisContext>()
                  .firstOrNull;
          _calendar ??= analysisContext == null
              ? _loadCalendarForTestOnly()
              : _loadCalendar(analysisContext);
          return _AnalysisContent(
            results: result.value,
            analysisContext: analysisContext,
            period: _period,
            masterData: _masterData,
            onNavigationRequested: widget.onNavigationRequested,
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
  Future<ApplicationResult<AnalysisCalendarResult>>?
  _loadCalendarForTestOnly() {
    if (widget.loadCalendar == null) return null;
    final now = DateTime.now();
    return widget.loadCalendar!(now.year, now.month);
  }
}

class _AnalysisContent extends StatelessWidget {
  const _AnalysisContent({
    required this.results,
    required this.analysisContext,
    required this.period,
    required this.masterData,
    required this.onNavigationRequested,
    required this.calendar,
    required this.selectedDate,
    required this.transactions,
    required this.onPeriodChanged,
    required this.onSelectDate,
  });
  final List<RuleExecutionResult> results;
  final AnalysisContext? analysisContext;
  final String period;
  final TransactionMasterData? masterData;
  final ValueChanged<String>? onNavigationRequested;
  final Future<ApplicationResult<AnalysisCalendarResult>>? calendar;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final ValueChanged<String> onPeriodChanged;
  final ValueChanged<String> onSelectDate;
  @override
  Widget build(BuildContext context) {
    final model = AnalysisModel.fromResults(results);
    return ButlerlyPage(
      title: context.l10n.text('analysis'),
      subtitle: analysisPeriodDescription(
        context,
        period,
        analysisContext?.period,
      ),
      children: [
        AnalysisPeriodSelector(value: period, onChanged: onPeriodChanged),
        const SizedBox(height: ButlerlySpacing.standard),
        AnalysisSummary(model: model),
        _SectionHeader(title: context.l10n.text('trends')),
        AnalysisTrend(model: model, masterData: masterData),
        _SectionHeader(title: context.l10n.text('spending')),
        AnalysisSpendingBreakdown(
          model: model,
          masterData: masterData,
          onCategoryTap: analysisContext == null
              ? null
              : (metric) => _openTransactions(
                  context,
                  period: analysisContext!.period,
                  category: analysisCategoryId(metric),
                ),
          onViewAll: analysisContext != null && model.categories.length > 5
              ? () =>
                    _openTransactions(context, period: analysisContext!.period)
              : null,
        ),
        _SectionHeader(title: context.l10n.text('financialCalendar')),
        calendar == null
            ? AnalysisActivitySummary(metric: model.transactionCount)
            : AnalysisActivity(
                result: calendar!,
                selectedDate: selectedDate,
                transactions: transactions,
                onSelectDate: onSelectDate,
                onViewTransactions: () => _openTransactions(
                  context,
                  period: analysisContext?.period,
                  date: selectedDate,
                ),
              ),
        if (model.insight != null) ...[
          _SectionHeader(title: context.l10n.text('insights')),
          AnalysisInsightPreview(
            finding: model.insight!,
            onTap: () => _navigate(context, '/insights'),
          ),
        ] else if (model.insightUnavailable) ...[
          _SectionHeader(title: context.l10n.text('insights')),
          ButlerlyCard(child: Text(context.l10n.text('insightsUnavailable'))),
        ],
        _SectionHeader(title: context.l10n.text('dataQuality')),
        AnalysisDataQuality(model: model),
      ],
    );
  }

  void _navigate(BuildContext context, String path) {
    if (onNavigationRequested case final callback?) {
      callback(path);
    } else {
      context.push(path);
    }
  }

  void _openTransactions(
    BuildContext context, {
    AnalysisPeriod? period,
    String? category,
    String? date,
  }) {
    final query = <String, String>{
      'from': date ?? period!.startDate,
      'to': date ?? period!.endDate,
      'category': ?category,
    };
    _navigate(
      context,
      Uri(path: '/transactions', queryParameters: query).toString(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => ButlerlySectionHeader(title: title);
}
