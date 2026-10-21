import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/analysis/presentation/analysis_search_selection.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_activity.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_category_breakdown.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_custom_period_sheet.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_data_quality.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_insight_preview.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_merchant_breakdown.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_period_selector.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_recurring_patterns.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_skeleton.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_spending_breakdown.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_subcategory_breakdown.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_summary.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    this.initialMonth,
    this.initialRange,
    this.load,
    this.loadForPeriod,
    this.loadCalendar,
    this.loadTransactionsForDate,
    this.loadRecurringPatterns,
    this.loadMasterData,
    this.onNavigationRequested,
    this.onTransactionRequested,
  });
  final DateTime? initialMonth;
  final DateTimeRange? initialRange;
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
  final Future<ApplicationResult<List<RecurringPattern>>> Function()?
  loadRecurringPatterns;
  final Future<TransactionMasterData> Function()? loadMasterData;
  final ValueChanged<String>? onNavigationRequested;
  final ValueChanged<TransactionDto>? onTransactionRequested;
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  static const _defaultPeriod = 'current_month';
  // Hide this experimental card until its relationship to the selected
  // Analysis period is defined. Leave detection and saved decisions intact.
  static const _recurringPatternsEnabled = false;
  late Future<ApplicationResult<List<RuleExecutionResult>>> _result;
  String _period = _defaultPeriod;
  AnalysisContext? _context;
  DateTimeRange? _customRange;
  Future<ApplicationResult<AnalysisCalendarResult>>? _calendar;
  DateTime? _calendarMonth;
  String? _selectedDate;
  Future<ApplicationResult<List<TransactionDto>>>? _transactions;
  Future<ApplicationResult<List<RecurringPattern>>>? _recurringPatterns;
  TransactionMasterData? _masterData;
  String? _masterDataLocale;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _customRange = widget.initialRange;
    if (widget.initialMonth != null) {
      _period = 'selected_month';
    } else if (_customRange != null) {
      _period = 'selected_period';
    }
    _result = _load(_period, generation: ++_loadGeneration);
    _recurringPatterns =
        _recurringPatternsEnabled && widget.loadRecurringPatterns != null
        ? _loadRecurringPatterns()
        : null;
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

  Future<ApplicationResult<List<RuleExecutionResult>>> _load(
    String period, {
    required int generation,
  }) {
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
    if (period == _defaultPeriod) {
      return useCase.contextFor('current_month', instant: DateTime.now()).then((
        resolved,
      ) {
        if (resolved is! ApplicationSuccess<AnalysisContext>) {
          return const ApplicationFailure(
            ApplicationFailureDetail(
              operation: 'resolve analysis period',
              code: ApplicationFailureCode.unavailable,
            ),
          );
        }
        if (generation == _loadGeneration) _context = resolved.value;
        return _calculatePeriod(resolved.value, generation);
      });
    }
    final initialMonth = widget.initialMonth;
    final contextFuture = period == 'selected_month' && initialMonth != null
        ? useCase.contextFor(
            'selected_month',
            instant: DateTime.now(),
            customPeriod: AnalysisPeriod(
              startDate: analysisDate(
                DateTime(initialMonth.year, initialMonth.month, 1),
              ),
              endDate: analysisDate(
                DateTime(initialMonth.year, initialMonth.month, 1),
              ),
              timeZoneId: 'UTC',
            ),
          )
        : period == 'selected_period' && _customRange != null
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
      if (generation == _loadGeneration) {
        _context = resolved.value;
      }
      return _calculatePeriod(resolved.value, generation);
    });
  }

  Future<ApplicationResult<List<RuleExecutionResult>>> _calculatePeriod(
    AnalysisContext context,
    int generation,
  ) async {
    final finance = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>()
        : null;
    // Do not calculate hidden recurring candidates during Analysis loads.
    final report = _recurringPatternsEnabled
        ? finance?.calculatePeriodicFinancialReport
        : null;
    if (report != null && widget.load == null && widget.loadForPeriod == null) {
      final result = await report(context);
      if (result case ApplicationSuccess<PeriodicFinancialReport>(
        value: final value,
      )) {
        if (generation == _loadGeneration) {
          _recurringPatterns = Future.value(value.recurringPatternsResult);
        }
        return ApplicationSuccess(value.results);
      }
      if (result case ApplicationFailure<PeriodicFinancialReport>(
        failure: final failure,
      )) {
        return ApplicationFailure(failure);
      }
    }
    return finance?.calculateAnalysisOverview?.call(context) ??
        const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'calculate analysis overview',
            code: ApplicationFailureCode.unavailable,
          ),
        );
  }

  Future<ApplicationResult<AnalysisCalendarResult>>? _loadCalendar(
    AnalysisContext context, {
    DateTime? month,
  }) {
    final end = context.period.endDate == '2000-01-01'
        ? DateTime(DateTime.now().year, DateTime.now().month)
        : DateTime.parse(context.period.endDate);
    final displayedMonth = month ?? _calendarMonth ?? end;
    _calendarMonth ??= DateTime(displayedMonth.year, displayedMonth.month);
    if (widget.loadCalendar != null) {
      return widget.loadCalendar!(displayedMonth.year, displayedMonth.month);
    }
    final useCase = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().calculateAnalysisCalendar
        : null;
    return useCase?.call(
      year: displayedMonth.year,
      month: displayedMonth.month,
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

  Future<void> _reload() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final period = _period;
    final selected = _selectedDate;
    final finance = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>()
        : null;
    final invalidation = finance?.invalidateAnalysis;
    final reload = invalidation == null
        ? Future<ApplicationResult<void>>.value(const ApplicationSuccess(null))
        : invalidation.call(
            AnalysisInvalidationReason.transactionChanged,
            DateTime.now().toUtc(),
          );
    final result = await reload.then(
      (_) => _load(period, generation: generation),
    );
    if (!mounted || generation != _loadGeneration) return;
    if (result is ApplicationFailure<List<RuleExecutionResult>>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
    setState(() {
      _result = Future.value(result);
      if (_recurringPatternsEnabled && widget.loadRecurringPatterns != null) {
        _recurringPatterns = _loadRecurringPatterns();
      }
      _calendar = null;
      if (selected == _selectedDate) {
        _transactions = selected == null ? null : _loadTransactions(selected);
      }
    });
  }

  void _selectPeriod(String period) {
    if (period == _period && period != 'selected_period') return;
    if (period == 'selected_period') {
      _chooseCustomPeriod();
      return;
    }
    _changePeriod(period);
  }

  Future<void> _changePeriod(
    String period, {
    DateTimeRange? customRange,
  }) async {
    if (!mounted) return;
    final previousPeriod = _period;
    final previousRange = _customRange;
    final previousContext = _context;
    final generation = ++_loadGeneration;

    setState(() {
      _period = period;
      _customRange = customRange;
      _selectedDate = null;
      _transactions = null;
      _calendar = null;
      _calendarMonth = null;
    });

    final result = await _load(period, generation: generation);
    if (!mounted || generation != _loadGeneration) return;

    if (result is ApplicationFailure<List<RuleExecutionResult>>) {
      setState(() {
        _period = previousPeriod;
        _customRange = previousRange;
        _context = previousContext;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }

    setState(() {
      _result = Future.value(result);
    });
  }

  Future<void> _chooseCustomPeriod() async {
    final now = DateTime.now();
    final initialRange =
        _customRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0),
        );
    final range = await showButlerlyBottomSheet<DateTimeRange>(
      context: context,
      builder: (context) =>
          AnalysisCustomPeriodSheet(initialRange: initialRange),
    );
    if (!mounted || range == null) return;
    await _changePeriod('selected_period', customRange: range);
  }

  void _selectDate(String date) => setState(() {
    _selectedDate = date;
    _transactions = _loadTransactions(date);
  });

  void _selectCalendarMonth(int year, int month) {
    final context = _context;
    if (context == null) return;
    final target = DateTime(year, month);
    final start = DateTime.parse(context.period.startDate);
    final end = DateTime.parse(context.period.endDate);
    final firstMonth = DateTime(start.year, start.month);
    final lastMonth = DateTime(end.year, end.month);
    if (target.isBefore(firstMonth) || target.isAfter(lastMonth)) return;
    setState(() {
      _calendarMonth = target;
      _selectedDate = null;
      _transactions = null;
      _calendar = _loadCalendar(context, month: target);
    });
  }

  bool _canChangeCalendarMonth(
    AnalysisContext context, {
    required bool previous,
  }) {
    final displayed = _calendarMonth;
    if (displayed == null) return false;
    final target = DateTime(
      displayed.year,
      displayed.month + (previous ? -1 : 1),
    );
    final start = DateTime.parse(context.period.startDate);
    final end = DateTime.parse(context.period.endDate);
    final firstMonth = DateTime(start.year, start.month);
    final lastMonth = DateTime(end.year, end.month);
    return !target.isBefore(firstMonth) && !target.isAfter(lastMonth);
  }

  Future<void> _openTransactionDetail(TransactionDto transaction) async {
    if (widget.onTransactionRequested case final callback?) {
      callback(transaction);
      return;
    }
    if (!services.isRegistered<FinanceServices>()) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionDetailPage(
          finance: services<FinanceServices>(),
          transaction: transaction,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _refresh() async {
    await _reload();
  }

  Future<void> _confirmRecurringPattern(RecurringPattern pattern) async {
    final action = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().saveRecurringPatternDecision
        : null;
    if (action == null) return;
    final result = await action.confirm(pattern);
    await _finishRecurringDecision(result);
  }

  Future<void> _rejectRecurringPattern(RecurringPattern pattern) async {
    final action = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().saveRecurringPatternDecision
        : null;
    if (action == null) return;
    final result = await action.reject(pattern);
    await _finishRecurringDecision(result);
  }

  Future<void> _correctRecurringPattern(
    RecurringPattern pattern,
    DecimalValue amount,
  ) async {
    final action = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().saveRecurringPatternDecision
        : null;
    if (action == null) return;
    final result = await action.correct(pattern, expectedAmount: amount);
    await _finishRecurringDecision(result);
  }

  Future<void> _finishRecurringDecision(
    ApplicationResult<RecurringPattern> result,
  ) async {
    if (!mounted) return;
    if (result is ApplicationFailure<RecurringPattern>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
    setState(() {
      _recurringPatterns = _loadRecurringPatterns();
    });
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    return Scaffold(
      body: FutureBuilder<ApplicationResult<List<RuleExecutionResult>>>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ButlerlyPage(
              title: context.l10n.text('analysis'),
              fullWidth: desktop,
              onRefresh: _refresh,
              refreshKey: const ValueKey('analysis-pull-to-refresh'),
              children: const [AnalysisSkeleton()],
            );
          }
          final result = snapshot.data;
          if (result is! ApplicationSuccess<List<RuleExecutionResult>>) {
            return ButlerlyPage(
              title: context.l10n.text('analysis'),
              fullWidth: desktop,
              onRefresh: _refresh,
              refreshKey: const ValueKey('analysis-pull-to-refresh'),
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
            recurringPatterns: _recurringPatternsEnabled
                ? _recurringPatterns
                : null,
            onConfirmRecurringPattern: _confirmRecurringPattern,
            onRejectRecurringPattern: _rejectRecurringPattern,
            onCorrectRecurringPattern: _correctRecurringPattern,
            canPreviousMonth: analysisContext == null
                ? false
                : _canChangeCalendarMonth(analysisContext, previous: true),
            canNextMonth: analysisContext == null
                ? false
                : _canChangeCalendarMonth(analysisContext, previous: false),
            onMonthChanged: _selectCalendarMonth,
            onTransactionRequested:
                widget.onTransactionRequested ?? _openTransactionDetail,
            onPeriodChanged: _selectPeriod,
            onRefresh: _refresh,
            onSelectDate: _selectDate,
          );
        },
      ),
    );
  }

  Future<ApplicationResult<AnalysisCalendarResult>>?
  _loadCalendarForTestOnly() {
    if (widget.loadCalendar == null) return null;
    final now = DateTime.now();
    return widget.loadCalendar!(now.year, now.month);
  }

  Future<ApplicationResult<List<RecurringPattern>>>? _loadRecurringPatterns() {
    if (widget.loadRecurringPatterns != null) {
      return widget.loadRecurringPatterns!();
    }
    if (!services.isRegistered<FinanceServices>()) return null;
    return services<FinanceServices>().detectRecurringPatterns();
  }
}

class _AnalysisContent extends StatelessWidget {
  const _AnalysisContent({
    required this.results,
    required this.analysisContext,
    required this.period,
    required this.masterData,
    required this.onNavigationRequested,
    required this.onTransactionRequested,
    required this.calendar,
    required this.selectedDate,
    required this.transactions,
    required this.recurringPatterns,
    required this.onConfirmRecurringPattern,
    required this.onRejectRecurringPattern,
    required this.onCorrectRecurringPattern,
    required this.onPeriodChanged,
    required this.onRefresh,
    required this.onSelectDate,
    required this.canPreviousMonth,
    required this.canNextMonth,
    required this.onMonthChanged,
  });
  final List<RuleExecutionResult> results;
  final AnalysisContext? analysisContext;
  final String period;
  final TransactionMasterData? masterData;
  final ValueChanged<String>? onNavigationRequested;
  final ValueChanged<TransactionDto> onTransactionRequested;
  final Future<ApplicationResult<AnalysisCalendarResult>>? calendar;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final Future<ApplicationResult<List<RecurringPattern>>>? recurringPatterns;
  final Future<void> Function(RecurringPattern pattern)
  onConfirmRecurringPattern;
  final Future<void> Function(RecurringPattern pattern)
  onRejectRecurringPattern;
  final Future<void> Function(RecurringPattern pattern, DecimalValue amount)
  onCorrectRecurringPattern;
  final ValueChanged<String> onPeriodChanged;
  final RefreshCallback onRefresh;
  final ValueChanged<String> onSelectDate;
  final bool canPreviousMonth;
  final bool canNextMonth;
  final void Function(int year, int month) onMonthChanged;
  @override
  Widget build(BuildContext context) {
    final model = AnalysisModel.fromResults(results);
    final subtitle = analysisPeriodDescription(
      context,
      period,
      analysisContext?.period,
    );
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    final spendingCard = AnalysisSpendingBreakdown(
      desktopLayout: desktop,
      model: model,
      masterData: masterData,
      onCategoryTap: analysisContext == null
          ? null
          : (metric) => _openAnalysisSearch(
              context,
              metric: metric,
              transactionIds: _metricTransactionIds(metric),
            ),
      onViewAll: analysisContext != null && model.categories.length > 5
          ? () => _openAnalysisSearch(
              context,
              selectionContext: analysisContext!,
              ruleId: model.categories.first.rule.identity.value,
              transactionIds: _evidenceTransactionIds(
                model.categories.expand((metric) => metric.evidence),
              ),
            )
          : null,
    );

    final categoryCard = AnalysisCategoryBreakdown(
      desktopFourRows: desktop,
      model: model,
      masterData: masterData,
      onMetricTap: (metric) {
        _openAnalysisSearch(
          context,
          metric: metric,
          transactionIds: _metricTransactionIds(metric),
        );
      },
    );

    final merchantCard = desktop || model.merchants.isNotEmpty
        ? AnalysisMerchantBreakdown(
            desktopFourRows: desktop,
            model: model,
            masterData: masterData,
            onMetricTap: (metric) {
              _openAnalysisSearch(
                context,
                metric: metric,
                transactionIds: _metricTransactionIds(metric),
              );
            },
          )
        : null;

    final subcategoryCard = desktop || model.subcategories.isNotEmpty
        ? AnalysisSubcategoryBreakdown(
            desktopFourRows: desktop,
            model: model,
            masterData: masterData,
            onMetricTap: (metric) {
              _openAnalysisSearch(
                context,
                metric: metric,
                transactionIds: _metricTransactionIds(metric),
              );
            },
          )
        : null;

    final unavailableCategoryCount = model.categories
        .where(
          (metric) =>
              metric.availability != AnalysisDataAvailability.sufficient,
        )
        .length;
    // A 264 px baseline fits the chart, header and the standard legend;
    // partial data and the View All action expand the paired cards together.
    final desktopSpendingHeight =
        264.0 +
        unavailableCategoryCount * 28.0 +
        (analysisContext != null && model.categories.length > 5 ? 48.0 : 0.0);

    return ButlerlyPage(
      title: context.l10n.text('analysis'),
      onRefresh: onRefresh,
      refreshKey: const ValueKey('analysis-pull-to-refresh'),
      pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
      pinnedHeaderExtent: AnalysisPeriodPinnedHeader.extent(context, subtitle),
      pinnedHeader: AnalysisPeriodPinnedHeader(
        subtitle: subtitle,
        value: period,
        onChanged: onPeriodChanged,
      ),
      fullWidth: desktop,
      children: _withAnalysisCardSpacing([
        if (desktop) ...[
          _AnalysisDesktopCardPair(
            first: AnalysisSummary(model: model),
            second: spendingCard,
            // Keep unavailable notes and View All clear of the donut legend.
            matchedHeight: desktopSpendingHeight,
          ),
          _AnalysisDesktopBreakdownRow(
            category: categoryCard,
            subcategory: subcategoryCard!,
            merchant: merchantCard!,
          ),
        ] else ...[
          AnalysisSummary(model: model),
          spendingCard,
          ?merchantCard,
          ?subcategoryCard,
        ],
        if (recurringPatterns != null)
          AnalysisRecurringPatterns(
            patterns: recurringPatterns!,
            masterData: masterData,
            onConfirm: onConfirmRecurringPattern,
            onReject: onRejectRecurringPattern,
            onCorrect: onCorrectRecurringPattern,
          ),
        calendar == null
            ? AnalysisActivitySummary(metric: model.transactionCount)
            : AnalysisActivity(
                result: calendar!,
                selectedDate: selectedDate,
                transactions: transactions,
                onSelectDate: onSelectDate,
                canPreviousMonth: canPreviousMonth,
                canNextMonth: canNextMonth,
                onMonthChanged: onMonthChanged,
                onTransactionTap: onTransactionRequested,
                masterData: masterData,
              ),
        if (model.insight != null) ...[
          AnalysisInsightPreview(
            finding: model.insight!,
            onTap: () => _openInsights(context),
          ),
        ] else if (model.insightUnavailable) ...[
          ButlerlyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ButlerlyCardHeader(title: context.l10n.text('insights')),
                Text(context.l10n.text('insightsUnavailable')),
              ],
            ),
          ),
        ],
        AnalysisDataQuality(model: model),
      ]),
    );
  }

  void _navigate(BuildContext context, String path) {
    if (onNavigationRequested case final callback?) {
      callback(path);
    } else {
      context.push(path);
    }
  }

  void _openInsights(BuildContext context) {
    final selected = analysisContext;
    final path = switch (selected?.periodType) {
      'selected_month' => Uri(
        path: '/insights',
        queryParameters: {'month': selected!.period.startDate.substring(0, 7)},
      ).toString(),
      'selected_period' => Uri(
        path: '/insights',
        queryParameters: {
          'from': selected!.period.startDate,
          'to': selected.period.endDate,
        },
      ).toString(),
      _ => '/insights',
    };
    _navigate(context, path);
  }

  static const _maximumUrlEvidenceIds = 24;
  static const _maximumUrlEvidenceLength = 800;

  void _openAnalysisSearch(
    BuildContext context, {
    AnalysisMetric? metric,
    AnalysisContext? selectionContext,
    String? ruleId,
    List<String>? transactionIds,
  }) {
    final selected = metric?.context ?? selectionContext;
    final sourceRule = metric?.rule.identity.value ?? ruleId;
    if (selected == null || sourceRule == null) return;

    final dimension = metric == null ? null : analysisRawDimension(metric);
    final ids =
        transactionIds?.toSet().toList(growable: false) ?? const <String>[];
    final selection = AnalysisSearchSelection(
      context: selected,
      ruleId: sourceRule,
      dimension: dimension,
      evidenceIds: ids,
    );
    // Keep long evidence sets out of the URL. The rule/dimension/period are
    // sufficient to recompute canonical evidence if a link is reopened.
    final includeShortIds =
        ids.length <= _maximumUrlEvidenceIds &&
        ids.join(',').length <= _maximumUrlEvidenceLength;
    final query = <String, String>{
      'locked': 'true',
      'analysisRule': sourceRule,
      'from': selected.period.startDate,
      'to': selected.period.endDate,
      if (metric?.rule.grouping == RuleGrouping.category && dimension != null)
        'category': dimension,
      if (metric?.rule.grouping == RuleGrouping.merchant && dimension != null)
        'merchant': dimension,
      if (metric?.rule.grouping == RuleGrouping.subcategory &&
          dimension != null)
        'subcategory': dimension,
      if (includeShortIds && ids.isNotEmpty) 'ids': ids.join(','),
    };
    final path = Uri(path: '/search', queryParameters: query).toString();
    if (onNavigationRequested case final callback?) {
      callback(path);
    } else {
      context.push(path, extra: selection);
    }
  }

  List<String> _metricTransactionIds(AnalysisMetric metric) =>
      _evidenceTransactionIds(metric.evidence);

  List<String> _evidenceTransactionIds(Iterable<EvidenceReference> evidence) =>
      evidence.map((value) => value.transactionId.value).toSet().toList();
}

/// Give Summary and Spending matching heights at ordinary desktop sizes.
/// IntrinsicHeight cannot be used with the donut's LayoutBuilder, so use a
/// bounded row and fall back to natural heights for compact/large-text layouts.
class _AnalysisDesktopCardPair extends StatelessWidget {
  const _AnalysisDesktopCardPair({
    required this.first,
    required this.second,
    required this.matchedHeight,
  });

  final Widget first;
  final Widget second;
  final double matchedHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1050 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            const SizedBox(height: ButlerlySpacing.cardGap),
            second,
          ],
        );
      }
      return SizedBox(
        height: matchedHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: first),
            const SizedBox(width: ButlerlySpacing.cardGap),
            Expanded(child: second),
          ],
        ),
      );
    },
  );
}

/// Three desktop breakdowns share a single row and display four 44px items.
/// When space or accessible text size makes three columns cramped, stack the
/// same cards rather than squeeze or clip their values and category icons.
class _AnalysisDesktopBreakdownRow extends StatelessWidget {
  const _AnalysisDesktopBreakdownRow({
    required this.category,
    required this.subcategory,
    required this.merchant,
  });

  final Widget category;
  final Widget subcategory;
  final Widget merchant;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1050 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            category,
            const SizedBox(height: ButlerlySpacing.cardGap),
            subcategory,
            const SizedBox(height: ButlerlySpacing.cardGap),
            merchant,
          ],
        );
      }
      return SizedBox(
        height: 320,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: category),
            const SizedBox(width: ButlerlySpacing.cardGap),
            Expanded(child: subcategory),
            const SizedBox(width: ButlerlySpacing.cardGap),
            Expanded(child: merchant),
          ],
        ),
      );
    },
  );
}

/// Match the consistent card-to-card separation used on the Home page.
List<Widget> _withAnalysisCardSpacing(List<Widget> cards) => [
  for (var index = 0; index < cards.length; index++) ...[
    if (index > 0) const SizedBox(height: ButlerlySpacing.cardGap),
    cards[index],
  ],
];
