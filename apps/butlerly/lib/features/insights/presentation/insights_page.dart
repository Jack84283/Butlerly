import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_custom_period_sheet.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_period_selector.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({
    super.key,
    this.loadEvaluation,
    this.dismissFinding,
    this.onNavigationRequested,
  });

  final Future<ApplicationResult<InsightsEvaluation>> Function(String)?
  loadEvaluation;
  final Future<ApplicationResult<void>> Function(String)? dismissFinding;
  final ValueChanged<String>? onNavigationRequested;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  static const _defaultPeriod = 'current_month';
  late Future<ApplicationResult<InsightsEvaluation>> _result;
  String _period = _defaultPeriod;
  AnalysisContext? _context;
  DateTimeRange? _customRange;

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

  Future<ApplicationResult<InsightsEvaluation>> _load(String period) {
    if (widget.loadEvaluation != null) {
      return widget.loadEvaluation!(period).then((value) {
        if (value is ApplicationSuccess<InsightsEvaluation>) {
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
            _context = value.value;
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
        _context = value.value;
        return useCase.call(value.value);
      });
    }
    return future.then((value) {
      if (value is ApplicationSuccess<InsightsEvaluation>) {
        _context ??= value.value.summary.context;
      }
      return value;
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
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
    final result = invalidated.then((_) => _load(_period));
    setState(() {
      _result = result;
    });
    await result;
  }

  void _selectPeriod(String period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _context = null;
      _result = _load(period);
    });
  }

  Future<void> _chooseCustomPeriod() async {
    final now = DateTime.now();
    final range = await showButlerlyBottomSheet<DateTimeRange>(
      context: context,
      builder: (_) => AnalysisCustomPeriodSheet(
        initialRange: DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0),
        ),
      ),
    );
    if (!mounted || range == null) return;
    setState(() {
      _period = 'selected_period';
      _customRange = range;
      _context = null;
      _result = _load(_period);
    });
  }

  Future<void> _dismiss(InsightResult insight) async {
    final finding = insight.finding;
    if (finding == null) return;
    Future<ApplicationResult<void>> Function(String)? dismiss =
        widget.dismissFinding;
    if (dismiss == null && services.isRegistered<FinanceServices>()) {
      final useCase =
          services<FinanceServices>().updateAnalysisFindingLifecycle;
      if (useCase != null) {
        dismiss = (id) =>
            useCase(id, FindingLifecycle.dismissed, DateTime.now().toUtc());
      }
    }
    if (dismiss == null) return;
    final result = await dismiss(finding.id);
    if (!mounted) return;
    if (result is ApplicationSuccess<void>) {
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('insightActionFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<ApplicationResult<InsightsEvaluation>>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ButlerlyPage(
            title: context.l10n.text('insights'),
            children: const [Center(child: CircularProgressIndicator())],
          );
        }
        final result = snapshot.data;
        if (result is! ApplicationSuccess<InsightsEvaluation>) {
          return ButlerlyPage(
            title: context.l10n.text('insights'),
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
          period: _period,
          onPeriodChanged: (value) => value == 'selected_period'
              ? _chooseCustomPeriod()
              : _selectPeriod(value),
          onDismiss: _dismiss,
          onViewTransactions: (insight) {
            final period = insight.context.period;
            final path = Uri(
              path: '/transactions',
              queryParameters: {
                if (insight.evidence.isEmpty) ...{
                  'from': period.startDate,
                  'to': period.endDate,
                },
                if (insight.evidence.isNotEmpty)
                  'ids': insight.evidence
                      .map((evidence) => evidence.transactionId.value)
                      .join(','),
              },
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
    required this.onDismiss,
    required this.onViewTransactions,
  });

  final InsightsEvaluation evaluation;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final Future<void> Function(InsightResult) onDismiss;
  final ValueChanged<InsightResult> onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final activeFindings = [...evaluation.activeFindings]
      ..sort(_compareInsights);
    final alerts = activeFindings
        .where((result) => result.outputType == InsightOutputType.alert)
        .toList(growable: false);
    final patterns = activeFindings
        .where((result) => result.outputType == InsightOutputType.pattern)
        .toList(growable: false);
    return ButlerlyPage(
      title: context.l10n.text('insights'),
      subtitle: analysisPeriodDescription(
        context,
        period,
        evaluation.summary.context.period,
      ),
      children: [
        AnalysisPeriodSelector(value: period, onChanged: onPeriodChanged),
        const SizedBox(height: ButlerlySpacing.standard),
        _PeriodSummaryCard(summary: evaluation.summary),
        if (evaluation.limitations.isNotEmpty) ...[
          ButlerlySectionHeader(
            title: context.l10n.text('dataQualityLimitations'),
          ),
          ButlerlyCard(
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
        if (alerts.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('needsAttention')),
          for (final insight in alerts)
            _InsightCard(
              insight: insight,
              onDismiss: () => onDismiss(insight),
              onViewTransactions: () => onViewTransactions(insight),
            ),
        ],
        if (patterns.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('otherInsights')),
          for (final insight in patterns)
            _InsightCard(
              insight: insight,
              onDismiss: () => onDismiss(insight),
              onViewTransactions: () => onViewTransactions(insight),
            ),
        ],
        if (activeFindings.isEmpty && !evaluation.hasSufficientHistory)
          ButlerlyEmptyState(
            icon: Icons.insights_outlined,
            title: context.l10n.text('insightsInsufficientHistory'),
            message: context.l10n.text('insightsInsufficientHistoryBody'),
          )
        else if (activeFindings.isEmpty)
          ButlerlyEmptyState(
            icon: Icons.check_circle_outline,
            title: context.l10n.text('insightsNothingNoteworthy'),
            message: context.l10n.text('insightsNothingNoteworthyBody'),
          ),
      ],
    );
  }

  int _compareInsights(InsightResult left, InsightResult right) {
    final severity = {
      RuleSeverity.critical: 0,
      RuleSeverity.warning: 1,
      RuleSeverity.attention: 2,
      RuleSeverity.info: 3,
    };
    final bySeverity = severity[left.finding!.severity]!.compareTo(
      severity[right.finding!.severity]!,
    );
    if (bySeverity != 0) return bySeverity;
    final byDate = right.generatedAt.compareTo(left.generatedAt);
    if (byDate != 0) return byDate;
    return left.rule.identity.value.compareTo(right.rule.identity.value);
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
      semanticLabel: context.l10n.text('periodSummary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text('periodSummary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ButlerlySpacing.small),
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

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.insight,
    required this.onDismiss,
    required this.onViewTransactions,
  });

  final InsightResult insight;
  final VoidCallback onDismiss;
  final VoidCallback onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final currency = insight.currency?.value ?? '';
    final rule = insight.rule;
    String? amount(DecimalValue? value) => value == null
        ? null
        : '${localizedDecimal(context, value.toString())} $currency'.trim();
    final severity = _severityPresentation(context, insight.finding!.severity);
    final values = <Widget>[
      _InsightValue(
        label: context.l10n.text('currentPeriod'),
        value: amount(insight.currentValue),
      ),
      _InsightValue(
        label: context.l10n.text('previousPeriod'),
        value: amount(insight.baselineValue),
      ),
      _InsightValue(
        label: context.l10n.text('difference'),
        value: amount(insight.absoluteChange),
      ),
      _InsightValue(
        label: context.l10n.text('percentageChange'),
        value: insight.percentageChange == null
            ? null
            : '${localizedDecimal(context, insight.percentageChange.toString())}%',
      ),
      _InsightValue(
        label: context.l10n.text('analysisPeriod'),
        value:
            '${insight.context.period.startDate} – ${insight.context.period.endDate}',
      ),
    ].whereType<_InsightValue>().where((value) => value.value != null).toList();
    return ButlerlyCard(
      semanticLabel: context.l10n.text(rule.nameKey),
      onTap: onViewTransactions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(severity.icon, color: severity.color),
              const SizedBox(width: ButlerlySpacing.small),
              Expanded(
                child: Text(
                  context.l10n.text(rule.nameKey),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: context.l10n.text('dismiss'),
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.small),
          Text(context.l10n.text(rule.descriptionKey)),
          const SizedBox(height: ButlerlySpacing.standard),
          ...values,
          if (insight.evidence.isNotEmpty) ...[
            const SizedBox(height: ButlerlySpacing.small),
            Text(
              context.l10n.text('supportingTransactions', {
                'count': '${insight.evidence.length}',
              }),
            ),
          ],
          const SizedBox(height: ButlerlySpacing.small),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onViewTransactions,
              child: Text(context.l10n.text('viewTransactions')),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightValue extends StatelessWidget {
  const _InsightValue({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.micro),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value!)],
    ),
  );
}

({IconData icon, Color color}) _severityPresentation(
  BuildContext context,
  RuleSeverity severity,
) => switch (severity) {
  RuleSeverity.critical => (
    icon: Icons.error_outline,
    color: context.colors.error,
  ),
  RuleSeverity.warning => (
    icon: Icons.warning_amber_outlined,
    color: context.colors.warning,
  ),
  RuleSeverity.attention => (
    icon: Icons.priority_high,
    color: context.colors.warning,
  ),
  RuleSeverity.info => (icon: Icons.info_outline, color: context.colors.info),
};

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
