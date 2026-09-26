import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_custom_period_sheet.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_period_selector.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_group_visualization.dart';
import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _selectiveConditionEvidenceMarker = 'conditionEvidence:selective';

class InsightsPage extends StatefulWidget {
  const InsightsPage({
    super.key,
    this.initialMonth,
    this.initialRange,
    this.loadEvaluation,
    this.onNavigationRequested,
    this.masterData,
  });

  final DateTime? initialMonth;
  final DateTimeRange? initialRange;
  final Future<ApplicationResult<InsightsEvaluation>> Function(String)?
  loadEvaluation;
  final ValueChanged<String>? onNavigationRequested;
  final TransactionMasterData? masterData;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  static const _defaultPeriod = 'current_month';
  late Future<ApplicationResult<InsightsEvaluation>> _result;
  String _period = _defaultPeriod;
  AnalysisContext? _context;
  DateTimeRange? _customRange;
  TransactionMasterData _presentation = const TransactionMasterData();
  String? _loadedLanguageCode;
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
    transactionChanges.addListener(_reload);
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_reload);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.masterData != null) {
      _presentation = widget.masterData!;
      return;
    }
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    final finance = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>()
        : null;
    if (finance == null) return;
    TransactionMasterDataProvider(
      finance,
    ).load(languageCode: languageCode).then((snapshot) {
      if (!mounted || _loadedLanguageCode != languageCode) return;
      setState(() => _presentation = snapshot.presentation);
    });
  }

  Future<ApplicationResult<InsightsEvaluation>> _load(
    String period, {
    required int generation,
  }) {
    if (widget.loadEvaluation != null) {
      return widget.loadEvaluation!(period).then((value) {
        if (value is ApplicationSuccess<InsightsEvaluation> &&
            generation == _loadGeneration) {
          _context = value.value.summary.context;
        }
        return value;
      });
    }
    final useCase = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().calculateInsights
        : null;
    if (useCase == null) {
      return Future.value(
        const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'calculate insights',
            code: ApplicationFailureCode.unavailable,
          ),
        ),
      );
    }
    late final Future<ApplicationResult<InsightsEvaluation>> future;
    if (period == _defaultPeriod) {
      future = useCase.currentMonth(DateTime.now());
    } else if (period == 'selected_month' && widget.initialMonth != null) {
      final month = widget.initialMonth!;
      final anchor = analysisDate(DateTime(month.year, month.month, 1));
      future = useCase
          .contextFor(
            'selected_month',
            instant: DateTime.now(),
            customPeriod: AnalysisPeriod(
              startDate: anchor,
              endDate: anchor,
              timeZoneId: 'UTC',
            ),
          )
          .then((value) {
            if (value is! ApplicationSuccess<AnalysisContext>) {
              return const ApplicationFailure<InsightsEvaluation>(
                ApplicationFailureDetail(
                  operation: 'resolve insights month',
                  code: ApplicationFailureCode.unavailable,
                ),
              );
            }
            if (generation == _loadGeneration) {
              _context = value.value;
            }
            return useCase.call(value.value);
          });
    } else if (period == 'selected_period' && _customRange != null) {
      future = useCase
          .contextForDates(
            startDate: analysisDate(_customRange!.start),
            endDate: analysisDate(_customRange!.end),
          )
          .then((value) {
            if (value is! ApplicationSuccess<AnalysisContext>) {
              return const ApplicationFailure<InsightsEvaluation>(
                ApplicationFailureDetail(
                  operation: 'resolve insights period',
                  code: ApplicationFailureCode.unavailable,
                ),
              );
            }
            if (generation == _loadGeneration) {
              _context = value.value;
            }
            return useCase.call(value.value);
          });
    } else {
      future = useCase.contextFor(period, instant: DateTime.now()).then((
        value,
      ) {
        if (value is! ApplicationSuccess<AnalysisContext>) {
          return const ApplicationFailure<InsightsEvaluation>(
            ApplicationFailureDetail(
              operation: 'resolve insights period',
              code: ApplicationFailureCode.unavailable,
            ),
          );
        }
        if (generation == _loadGeneration) {
          _context = value.value;
        }
        return useCase.call(value.value);
      });
    }
    return future.then((value) {
      if (value is ApplicationSuccess<InsightsEvaluation> &&
          generation == _loadGeneration) {
        _context ??= value.value.summary.context;
      }
      return value;
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final period = _period;
    final finance = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>()
        : null;
    final invalidation = finance?.invalidateAnalysis;
    final invalidated = invalidation == null
        ? Future<ApplicationResult<void>>.value(const ApplicationSuccess(null))
        : invalidation.call(
            AnalysisInvalidationReason.transactionChanged,
            DateTime.now().toUtc(),
          );
    final result = await invalidated.then(
      (_) => _load(period, generation: generation),
    );
    if (!mounted || generation != _loadGeneration) return;
    if (result is ApplicationFailure<InsightsEvaluation>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
    setState(() {
      _result = Future.value(result);
    });
  }

  void _selectPeriod(String period) {
    if (period == _period) return;
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
    });

    final result = await _load(period, generation: generation);
    if (!mounted || generation != _loadGeneration) return;

    if (result is ApplicationFailure<InsightsEvaluation>) {
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
      builder: (_) => AnalysisCustomPeriodSheet(initialRange: initialRange),
    );
    if (!mounted || range == null) return;
    await _changePeriod('selected_period', customRange: range);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<ApplicationResult<InsightsEvaluation>>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ButlerlyPage(
            title: context.l10n.text('insights'),
            onRefresh: _reload,
            refreshKey: const ValueKey('insights-pull-to-refresh'),
            children: const [Center(child: CircularProgressIndicator())],
          );
        }
        final result = snapshot.data;
        if (result is! ApplicationSuccess<InsightsEvaluation>) {
          return ButlerlyPage(
            title: context.l10n.text('insights'),
            onRefresh: _reload,
            refreshKey: const ValueKey('insights-pull-to-refresh'),
            children: [
              ButlerlyErrorState(
                title: context.l10n.text('insightsUnavailable'),
                message: context.l10n.text('insightsUnavailableBody'),
                preserved: context.l10n.text('dataPreserved'),
                actionLabel: context.l10n.text('tryAgain'),
                onAction: _reload,
              ),
            ],
          );
        }
        return _InsightsContent(
          evaluation: result.value,
          masterData: _presentation,
          period: _period,
          onPeriodChanged: (value) => value == 'selected_period'
              ? _chooseCustomPeriod()
              : _selectPeriod(value),
          onRefresh: _reload,
          onViewTransactions: (insight) {
            if (!_hasPreciseDrillDown(insight)) return;
            final path = Uri(
              path: '/search',
              queryParameters: _drillDownQueryParameters(insight),
            ).toString();
            if (widget.onNavigationRequested case final callback?) {
              callback(path);
            } else {
              context.push(path);
            }
          },
        );
      },
    ),
  );
}

class _InsightsContent extends StatelessWidget {
  const _InsightsContent({
    required this.evaluation,
    required this.period,
    required this.onPeriodChanged,
    required this.onRefresh,
    required this.onViewTransactions,
    required this.masterData,
  });

  final InsightsEvaluation evaluation;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final RefreshCallback onRefresh;
  final ValueChanged<InsightResult> onViewTransactions;
  final TransactionMasterData masterData;

  @override
  Widget build(BuildContext context) {
    final activeFindings = evaluation.activeFindings
        .where(
          (result) =>
              result.outputType != InsightOutputType.dataQuality &&
              result.presentation.visualizationType !=
                  InsightVisualizationType.pie,
        )
        .toList(growable: false);
    final summaryPieResults = evaluation.results
        .where(
          (result) =>
              result.presentation.visualizationType ==
              InsightVisualizationType.pie,
        )
        .toList(growable: false);

    final subtitle = analysisPeriodDescription(
      context,
      period,
      evaluation.summary.context.period,
    );
    return ButlerlyPage(
      title: context.l10n.text('insights'),
      onRefresh: onRefresh,
      refreshKey: const ValueKey('insights-pull-to-refresh'),
      pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
      pinnedHeaderExtent: AnalysisPeriodPinnedHeader.extent(context, subtitle),
      pinnedHeader: AnalysisPeriodPinnedHeader(
        subtitle: subtitle,
        value: period,
        onChanged: onPeriodChanged,
      ),
      children: [
        ButlerlySectionHeader(title: context.l10n.text('periodSummary')),
        _PeriodSummaryCard(summary: evaluation.summary),
        if (summaryPieResults.isNotEmpty)
          InsightGroupVisualizations(
            results: summaryPieResults,
            masterData: masterData,
            externalTitle: true,
            pieDensity: ButlerlyVisualizationDensity.regular,
            pieLegendBelow: true,
            pieValueLabel: (result) {
              final shareText = result.currentValue?.toString();
              final amount = result.impactValue;
              if (amount == null) {
                return shareText == null
                    ? '—'
                    : '${localizedDecimal(context, shareText)}%';
              }
              final currency = evaluation.summary.currency?.value ?? '';
              return '${localizedDecimal(context, amount.toString())}${currency.isEmpty ? '' : ' $currency'}';
            },
          ),
        ],
        if (evaluation.limitations.isNotEmpty) ...[
          ButlerlySectionHeader(
            title: context.l10n.text('dataQualityLimitations'),
          ),
          ButlerlyCard(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: evaluation.limitations
                  .fold<Map<String, DataQualityIssue>>(
                    {},
                    (issues, issue) =>
                        issues..putIfAbsent(issue.code, () => issue),
                  )
                  .values
                  .map(
                    (issue) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: ButlerlySpacing.micro,
                      ),
                      child: Text(_qualityIssueText(context, issue.code)),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        if (activeFindings.isNotEmpty)
          InsightGroupedList(
            results: activeFindings,
            visualizationResults: evaluation.results,
            masterData: masterData,
            canViewTransactions: _hasPreciseDrillDown,
            onViewTransactions: onViewTransactions,
          )
        else if (!evaluation.hasSufficientHistory)
          ButlerlyEmptyState(
            icon: Icons.insights_outlined,
            title: context.l10n.text('insightsInsufficientHistory'),
            message: context.l10n.text('insightsInsufficientHistoryBody'),
          )
        else if (summaryPieResults.isEmpty)
          ButlerlyEmptyState(
            icon: Icons.check_circle_outline,
            title: context.l10n.text('insightsNothingNoteworthy'),
            message: context.l10n.text('insightsNothingNoteworthyBody'),
          ),
      ],
    );
  }
}

class _PeriodSummaryCard extends StatelessWidget {
  const _PeriodSummaryCard({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    String? amount(DecimalValue? value) => value == null
        ? null
        : '${localizedDecimal(context, value.toString())} ${summary.currency?.value ?? ''}'
              .trim();
    final values = <_InsightValue>[
      _InsightValue(
        label: context.l10n.text('currentPeriod'),
        value:
            '${summary.context.period.startDate} – ${summary.context.period.endDate}',
      ),
      if (summary.baselineContext != null)
        _InsightValue(
          label: context.l10n.text('previousPeriod'),
          value:
              '${summary.baselineContext!.period.startDate} – ${summary.baselineContext!.period.endDate}',
        ),
      _InsightValue(
        label: context.l10n.text('totalSpending'),
        value: amount(summary.expenseSpending),
      ),
      _InsightValue(
        label: context.l10n.text('income'),
        value: amount(summary.income),
      ),
      _InsightValue(
        label: context.l10n.text('netCashFlow'),
        value: amount(summary.netCashFlow),
      ),
      _InsightValue(
        label: context.l10n.text('eligibleTransactions'),
        value: '${summary.eligibleTransactionCount}',
      ),
      if (summary.expenseChange?.absoluteChange != null)
        _InsightValue(
          label: context.l10n.text('difference'),
          value: amount(summary.expenseChange!.absoluteChange),
        ),
      if (summary.expenseChange?.percentageChange != null)
        _InsightValue(
          label: context.l10n.text('percentageChange'),
          value:
              '${localizedDecimal(context, summary.expenseChange!.percentageChange.toString())}%',
        ),
    ];

    return ButlerlyCard(
      color: Theme.of(context).scaffoldBackgroundColor,
      semanticLabel: context.l10n.text('periodSummary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...values.where((value) => value.value != null),
          if (!summary.comparisonAvailable)
            Text(
              '${context.l10n.text('comparisonUnavailable')}: '
              '${context.l10n.text('comparisonUnavailableBody')}',
            ),
        ],
      ),
    );
  }
}

bool _hasPreciseDrillDown(InsightResult insight) {
  if (_canUseCriteriaDrillDown(insight)) return true;
  return insight.evidence.isNotEmpty;
}

bool _usesSelectiveConditionEvidence(InsightResult insight) =>
    insight.finding?.supportingMetrics.contains(
      _selectiveConditionEvidenceMarker,
    ) ??
    false;

bool _canUseCriteriaDrillDown(InsightResult insight) {
  if (_usesSelectiveConditionEvidence(insight)) return false;
  final dimension = insight.dimension;
  final groupingSupported = switch (insight.rule.grouping) {
    RuleGrouping.none => true,
    RuleGrouping.category => dimension != null,
    RuleGrouping.paymentSource => dimension != null,
    _ => false,
  };
  if (!groupingSupported) return false;
  return insight.rule.filters.every(
    (filter) =>
        filter.values.length == 1 &&
        const {
          AnalysisFilterKind.direction,
          AnalysisFilterKind.category,
          AnalysisFilterKind.paymentSource,
          AnalysisFilterKind.currency,
        }.contains(filter.kind),
  );
}

Map<String, String> _drillDownQueryParameters(InsightResult insight) {
  final period = insight.context.period;
  final parameters = <String, String>{
    'locked': 'true',
    'from': period.startDate,
    'to': period.endDate,
  };

  String? singleFilter(AnalysisFilterKind kind) {
    for (final filter in insight.rule.filters) {
      if (filter.kind == kind && filter.values.length == 1) {
        return filter.values.single;
      }
    }
    return null;
  }

  final direction = singleFilter(AnalysisFilterKind.direction);
  final currency = singleFilter(AnalysisFilterKind.currency);
  if (direction != null) parameters['direction'] = direction;
  if (currency != null) parameters['currency'] = currency;

  if (!_canUseCriteriaDrillDown(insight)) {
    if (insight.evidence.isNotEmpty) {
      parameters['ids'] = insight.evidence
          .map((evidence) => evidence.transactionId.value)
          .join(',');
    }
    if (_usesSelectiveConditionEvidence(insight)) {
      parameters['insightRule'] = insight.rule.identity.value;
      if (insight.dimension != null) {
        parameters['insightDimension'] = insight.dimension!;
      }
    }
    return parameters;
  }

  final dimension = insight.dimension;
  final isUncategorized =
      insight.rule.grouping == RuleGrouping.category &&
      dimension == 'uncategorized';
  final category = insight.rule.grouping == RuleGrouping.category
      ? dimension
      : singleFilter(AnalysisFilterKind.category);
  final paymentSource = insight.rule.grouping == RuleGrouping.paymentSource
      ? dimension
      : singleFilter(AnalysisFilterKind.paymentSource);

  if (isUncategorized) {
    parameters['uncategorized'] = 'true';
  } else if (category != null) {
    parameters['category'] = category;
  }
  if (paymentSource != null) parameters['paymentSource'] = paymentSource;
  return parameters;
}

class _InsightValue extends StatelessWidget {
  const _InsightValue({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) =>
      ButlerlyKeyValueRow(label: label, value: value!);
}

String _qualityIssueText(BuildContext context, String code) => switch (code) {
  'missingFx' => context.l10n.text('analysisDataQualityIssueMissingFx'),
  'insufficientData' => context.l10n.text(
    'analysisDataQualityIssueInsufficient',
  ),
  'missingBaseline' => context.l10n.text('analysisDataQualityIssueBaseline'),
  'equivalentElapsedCoverage' ||
  'currentMonthToDate' ||
  'currentYearInProgress' ||
  'rollingWindowIncludesCurrentDate' => context.l10n.text(
    'analysisDataQualityIssueCoverage',
  ),
  'reconciliationUncertainty' => context.l10n.text(
    'analysisDataQualityIssueReconciliation',
  ),
  'execution' || 'dependencyFailure' || 'missingDependency' =>
    context.l10n.text('analysisDataQualityIssueRuleFailure'),
  _ => context.l10n.text('analysisDataQualityIssueGeneric'),
};
