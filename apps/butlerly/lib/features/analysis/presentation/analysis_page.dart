import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key, this.load});

  final Future<ApplicationResult<List<RuleExecutionResult>>> Function()? load;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late Future<ApplicationResult<List<RuleExecutionResult>>> _result;

  @override
  void initState() {
    super.initState();
    _result = _load();
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

  Future<void> _refresh() async {
    final value = _load();
    setState(() => _result = value);
    await value;
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
          return _AnalysisResults(results: result.value);
        },
      ),
    ),
  );
}

class _AnalysisResults extends StatelessWidget {
  const _AnalysisResults({required this.results});
  final List<RuleExecutionResult> results;

  @override
  Widget build(BuildContext context) {
    final metrics = results.where((value) => value.metric != null).toList();
    final findings = results.where((value) => value.finding != null).toList();
    final limitations = results
        .expand(
          (value) => [
            ...value.issues,
            ...?value.metric?.qualityIssues,
            ...?value.finding?.qualityIssues,
          ],
        )
        .toList();
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
        if (metrics.isEmpty)
          ButlerlyEmptyState(
            icon: Icons.insights_outlined,
            title: context.l10n.text('notEnoughInsightData'),
            message: context.l10n.text('notEnoughInsightDataBody'),
          )
        else
          ...metrics.map((result) => _MetricCard(metric: result.metric!)),
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
        if (limitations.isNotEmpty || failures.isNotEmpty) ...[
          ButlerlySectionHeader(title: context.l10n.text('dataQuality')),
          ButlerlyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...limitations.map((issue) => Text('• ${issue.detail}')),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    final value = localizedDecimal(context, metric.value.toString());
    final label = context.l10n.text(metric.rule.nameKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: ButlerlySpacing.compact),
      child: Semantics(
        label:
            '$label, $value${metric.currency == null ? '' : ' ${metric.currency!.value}'}',
        child: ButlerlyCard(
          child: ListTile(
            title: Text(label),
            subtitle: metric.dimension == null ? null : Text(metric.dimension!),
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
      ),
    ),
  );
}
