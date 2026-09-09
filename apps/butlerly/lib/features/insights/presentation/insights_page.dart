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
    this.load,
    this.dismissFinding,
    this.onNavigationRequested,
  });

  final Future<ApplicationResult<List<RuleExecutionResult>>> Function(String)?
  load;
  final Future<ApplicationResult<void>> Function(String)? dismissFinding;
  final ValueChanged<String>? onNavigationRequested;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  static const _defaultPeriod = 'current_month';
  late Future<ApplicationResult<List<RuleExecutionResult>>> _result;
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

  Future<ApplicationResult<List<RuleExecutionResult>>> _load(String period) {
    if (widget.load != null) {
      return widget.load!(period).then((value) {
        if (value is ApplicationSuccess<List<RuleExecutionResult>>) {
          _context ??= value.value
              .map(
                (result) => result.metric?.context ?? result.finding?.context,
              )
              .whereType<AnalysisContext>()
              .firstOrNull;
        }
        return value;
      });
    }
    final useCase = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().calculateAnalysisOverview
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
    late final Future<ApplicationResult<List<RuleExecutionResult>>> future;
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
              return const ApplicationFailure<List<RuleExecutionResult>>(
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
          return const ApplicationFailure<List<RuleExecutionResult>>(
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
      if (value is ApplicationSuccess<List<RuleExecutionResult>>) {
        _context ??= value.value
            .map((result) => result.metric?.context ?? result.finding?.context)
            .whereType<AnalysisContext>()
            .firstOrNull;
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

  Future<void> _dismiss(AnalysisFinding finding) async {
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
    body: FutureBuilder<ApplicationResult<List<RuleExecutionResult>>>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ButlerlyPage(
            title: context.l10n.text('insights'),
            children: const [Center(child: CircularProgressIndicator())],
          );
        }
        final result = snapshot.data;
        if (result is! ApplicationSuccess<List<RuleExecutionResult>>) {
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
          results: result.value,
          context: _context,
          period: _period,
          onPeriodChanged: (value) => value == 'selected_period'
              ? _chooseCustomPeriod()
              : _selectPeriod(value),
          onDismiss: _dismiss,
          onViewTransactions: (finding) {
            final period = _context?.period;
            if (period == null) return;
            final path = Uri(
              path: '/transactions',
              queryParameters: {
                if (finding.evidence.isEmpty) ...{
                  'from': period.startDate,
                  'to': period.endDate,
                },
                if (finding.evidence.isNotEmpty)
                  'ids': finding.evidence
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
    required this.results,
    required this.context,
    required this.period,
    required this.onPeriodChanged,
    required this.onDismiss,
    required this.onViewTransactions,
  });

  final List<RuleExecutionResult> results;
  final AnalysisContext? context;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final Future<void> Function(AnalysisFinding) onDismiss;
  final ValueChanged<AnalysisFinding> onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final insightResults = results
        .where(
          (result) =>
              result.rule.surface == AnalysisSurface.insights &&
              result.rule.type == AnalysisRuleType.insight,
        )
        .toList(growable: false);
    final activeFindings =
        insightResults
            .map((result) => result.finding)
            .whereType<AnalysisFinding>()
            .where((finding) => finding.lifecycle == FindingLifecycle.active)
            .toList()
          ..sort(_compareFindings);
    final evaluated = insightResults.any(
      (result) =>
          result.failure == null &&
          (result.finding != null ||
              result.metric != null ||
              result.comparison?.availability ==
                  AnalysisDataAvailability.sufficient ||
              result.comparison?.availability ==
                  AnalysisDataAvailability.empty),
    );
    return ButlerlyPage(
      title: context.l10n.text('insights'),
      subtitle: analysisPeriodDescription(
        context,
        period,
        this.context?.period,
      ),
      children: [
        AnalysisPeriodSelector(value: period, onChanged: onPeriodChanged),
        const SizedBox(height: ButlerlySpacing.standard),
        if (activeFindings.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('needsAttention')),
          for (final finding in activeFindings)
            _InsightCard(
              finding: finding,
              rule: finding.rule,
              analysisContext: this.context ?? finding.context,
              onDismiss: () => onDismiss(finding),
              onViewTransactions: () => onViewTransactions(finding),
            ),
        ] else if (!evaluated)
          ButlerlyEmptyState(
            icon: Icons.insights_outlined,
            title: context.l10n.text('insightsInsufficientHistory'),
            message: context.l10n.text('insightsInsufficientHistoryBody'),
          )
        else
          ButlerlyEmptyState(
            icon: Icons.check_circle_outline,
            title: context.l10n.text('insightsNothingNoteworthy'),
            message: context.l10n.text('insightsNothingNoteworthyBody'),
          ),
      ],
    );
  }

  int _compareFindings(AnalysisFinding left, AnalysisFinding right) {
    final severity = {
      RuleSeverity.critical: 0,
      RuleSeverity.warning: 1,
      RuleSeverity.attention: 2,
      RuleSeverity.info: 3,
    };
    final bySeverity = severity[left.severity]!.compareTo(
      severity[right.severity]!,
    );
    if (bySeverity != 0) return bySeverity;
    final byDate = right.generatedAt.compareTo(left.generatedAt);
    if (byDate != 0) return byDate;
    return left.rule.identity.value.compareTo(right.rule.identity.value);
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.finding,
    required this.rule,
    required this.analysisContext,
    required this.onDismiss,
    required this.onViewTransactions,
  });

  final AnalysisFinding finding;
  final AnalysisRuleDefinition rule;
  final AnalysisContext analysisContext;
  final VoidCallback onDismiss;
  final VoidCallback onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final currency = analysisContext.baseCurrency?.value ?? '';
    String? amount(DecimalValue? value) => value == null
        ? null
        : '${localizedDecimal(context, value.toString())} $currency'.trim();
    final severity = _severityPresentation(context, finding.severity);
    final values = <Widget>[
      _InsightValue(
        label: context.l10n.text('currentPeriod'),
        value: amount(finding.currentValue),
      ),
      _InsightValue(
        label: context.l10n.text('previousPeriod'),
        value: amount(finding.baselineValue),
      ),
      _InsightValue(
        label: context.l10n.text('difference'),
        value: amount(finding.absoluteChange),
      ),
      _InsightValue(
        label: context.l10n.text('percentageChange'),
        value: finding.percentageChange == null
            ? null
            : '${localizedDecimal(context, finding.percentageChange.toString())}%',
      ),
      _InsightValue(
        label: context.l10n.text('analysisPeriod'),
        value:
            '${analysisContext.period.startDate} – ${analysisContext.period.endDate}',
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
          if (finding.evidence.isNotEmpty) ...[
            const SizedBox(height: ButlerlySpacing.small),
            Text(
              context.l10n.text('supportingTransactions', {
                'count': '${finding.evidence.length}',
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
