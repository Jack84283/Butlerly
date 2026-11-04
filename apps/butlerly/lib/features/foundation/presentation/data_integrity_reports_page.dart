import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DataIntegrityReportsPage extends StatefulWidget {
  const DataIntegrityReportsPage({super.key});

  @override
  State<DataIntegrityReportsPage> createState() =>
      _DataIntegrityReportsPageState();
}

class _DataIntegrityReportsPageState extends State<DataIntegrityReportsPage> {
  DataIntegrityReport? _report;
  List<DataIntegrityReport> _history = const [];
  List<OperationDiagnostic> _operationDiagnostics = const [];
  Object? _error;
  bool _busy = true;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _busy = true);
    try {
      final service = services<DataIntegrityReportService>();
      final history = await service.reportHistory();
      final operationDiagnostics = await _recentOperationDiagnostics();
      if (!mounted) return;
      setState(() {
        _history = history;
        _operationDiagnostics = operationDiagnostics;
        _report = history.isEmpty ? null : history.first;
        _error = null;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  Future<void> _runReport() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await services<DataIntegrityReportService>().runReport();
      if (!mounted) return;
      final history = await services<DataIntegrityReportService>()
          .reportHistory();
      final operationDiagnostics = await _recentOperationDiagnostics();
      if (!mounted) return;
      setState(() {
        _report = report;
        _history = history;
        _operationDiagnostics = operationDiagnostics;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ButlerlyPage(
      title: l10n.text('dataIntegrityReports'),
      subtitle: l10n.text('dataIntegrityReportsBody'),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/settings');
          }
        },
      ),
      actions: [
        IconButton(
          tooltip: l10n.text('dataIntegrityRefresh'),
          onPressed: _busy ? null : _loadHistory,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        if (_busy && _report == null)
          const Center(child: CircularProgressIndicator())
        else if (_error != null && _report == null)
          ButlerlyEmptyState(
            icon: Icons.error_outline_rounded,
            title: l10n.text('dataIntegrityLoadFailed'),
            message: l10n.text('tryAgain'),
            actionLabel: l10n.text('tryAgain'),
            onAction: _loadHistory,
          )
        else ...[
          ButlerlyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _report?.hasFindings == true
                          ? Icons.warning_amber_rounded
                          : Icons.verified_outlined,
                      color: _report?.hasFindings == true
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: ButlerlySpacing.small),
                    Expanded(
                      child: Text(
                        _report == null
                            ? l10n.text('dataIntegrityNoReport')
                            : _report!.hasFindings
                            ? l10n
                                  .text('dataIntegrityFindingsSummary')
                                  .replaceFirst(
                                    '{count}',
                                    '${_report!.findings.length}',
                                  )
                            : l10n.text('dataIntegrityNoFindings'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (_report != null) ...[
                  const SizedBox(height: ButlerlySpacing.small),
                  Text(
                    '${l10n.text('dataIntegrityLastScan')}: ${_formatDate(context, _report!.scannedAtUtc)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: ButlerlySpacing.standard),
                FilledButton.icon(
                  onPressed: _busy ? null : _runReport,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(
                    _report == null
                        ? l10n.text('dataIntegrityRun')
                        : l10n.text('dataIntegrityRefresh'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: ButlerlySpacing.small),
              child: Text(
                l10n.text('dataIntegrityScanFailed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_report != null && _report!.findings.isNotEmpty) ...[
            const SizedBox(height: ButlerlySpacing.section),
            ButlerlySectionHeader(title: l10n.text('dataIntegrityFindings')),
            for (final group in _groupFindings(_report!.findings))
              _FindingGroup(
                findings: group.$2,
                label: _categoryLabel(context, group.$1),
                onOpenRoute: (route) => context.go(route),
                routeForRecord: _recordRoute,
              ),
          ],
          if (_operationDiagnostics.isNotEmpty) ...[
            const SizedBox(height: ButlerlySpacing.section),
            ButlerlySectionHeader(
              title: l10n.text('dataIntegrityOperationDiagnostics'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
              child: Text(
                l10n.text('dataIntegrityOperationDiagnosticsBody'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final group in _groupFindings([
              for (final diagnostic in _operationDiagnostics)
                diagnostic.finding,
            ]))
              _FindingGroup(
                findings: group.$2,
                label: _categoryLabel(context, group.$1),
                onOpenRoute: (route) => context.go(route),
                routeForRecord: _recordRoute,
              ),
          ],
          const SizedBox(height: ButlerlySpacing.section),
          ButlerlyCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: Text(l10n.text('dataIntegrityHistory')),
              initiallyExpanded: _showHistory,
              onExpansionChanged: (value) =>
                  setState(() => _showHistory = value),
              children: [
                if (_history.isEmpty)
                  ListTile(title: Text(l10n.text('dataIntegrityNoHistory')))
                else
                  for (final report in _history)
                    ListTile(
                      leading: Icon(
                        report.hasFindings
                            ? Icons.warning_amber_outlined
                            : Icons.check_circle_outline,
                      ),
                      title: Text(_formatDate(context, report.scannedAtUtc)),
                      subtitle: Text(
                        report.hasFindings
                            ? l10n
                                  .text('dataIntegrityFindingsSummary')
                                  .replaceFirst(
                                    '{count}',
                                    '${report.findings.length}',
                                  )
                            : l10n.text('dataIntegrityNoFindings'),
                      ),
                      onTap: () => setState(() => _report = report),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(BuildContext context, DateTime value) {
    return DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_jm().format(value.toLocal());
  }

  Future<List<OperationDiagnostic>> _recentOperationDiagnostics() async {
    if (!services.isRegistered<OperationDiagnosticsStore>()) {
      return const [];
    }
    try {
      return await services<OperationDiagnosticsStore>().recent();
    } on Object {
      // A diagnostic-history problem must not make the independent report
      // scanner unavailable.
      return const [];
    }
  }

  List<(DataIntegrityFindingCategory, List<DataIntegrityFinding>)>
  _groupFindings(List<DataIntegrityFinding> findings) {
    final grouped =
        <DataIntegrityFindingCategory, List<DataIntegrityFinding>>{};
    for (final finding in findings) {
      grouped.putIfAbsent(finding.category, () => []).add(finding);
    }
    return [for (final entry in grouped.entries) (entry.key, entry.value)];
  }

  String _categoryLabel(
    BuildContext context,
    DataIntegrityFindingCategory category,
  ) => context.l10n.text(switch (category) {
    DataIntegrityFindingCategory.missingReceipt =>
      'dataIntegrityCategoryMissingReceipt',
    DataIntegrityFindingCategory.missingAttachment =>
      'dataIntegrityCategoryMissingAttachment',
    DataIntegrityFindingCategory.invalidFileReference =>
      'dataIntegrityCategoryInvalidFileReference',
    DataIntegrityFindingCategory.missingReferencedRecord =>
      'dataIntegrityCategoryMissingRecord',
    DataIntegrityFindingCategory.analysisInconsistency =>
      'dataIntegrityCategoryAnalysis',
    DataIntegrityFindingCategory.invalidCustomConfiguration =>
      'dataIntegrityCategoryCustomConfiguration',
    DataIntegrityFindingCategory.relationshipInconsistency =>
      'dataIntegrityCategoryRelationship',
  });

  String? _recordRoute(
    DataIntegrityRecordReference record,
    List<DataIntegrityRecordReference> relatedRecords,
  ) => switch (record.type) {
    'transaction' => Uri(
      path: '/transactions',
      queryParameters: {'ids': record.id},
    ).toString(),
    // Evidence is reviewed and reattached from the transaction workflow.
    // An orphan record must not advertise a button that opens an unrelated
    // unfiltered transaction list.
    'evidence' ||
    'attachment' => _transactionRouteForRelatedRecords(relatedRecords),
    'budget' => '/budgets',
    'category' => Uri(
      path: '/search',
      queryParameters: {'locked': 'true', 'category': record.id},
    ).toString(),
    'merchant' => Uri(
      path: '/search',
      queryParameters: {'locked': 'true', 'merchant': record.id},
    ).toString(),
    // Analysis rules are reviewed from the analysis surface. The rule ID is
    // still shown in the report because this route does not expose a stable
    // single-rule deep link.
    'analysisRule' => '/analysis',
    _ => null,
  };

  String? _transactionRouteForRelatedRecords(
    List<DataIntegrityRecordReference> records,
  ) {
    final transactionIds = records
        .where((record) => record.type == 'transaction')
        .map((record) => record.id)
        .toSet()
        .toList(growable: false);
    if (transactionIds.isEmpty) return null;
    return Uri(
      path: '/transactions',
      queryParameters: {'ids': transactionIds.join(',')},
    ).toString();
  }
}

class _FindingGroup extends StatelessWidget {
  const _FindingGroup({
    required this.findings,
    required this.label,
    required this.onOpenRoute,
    required this.routeForRecord,
  });

  final List<DataIntegrityFinding> findings;
  final String label;
  final ValueChanged<String> onOpenRoute;
  final String? Function(
    DataIntegrityRecordReference,
    List<DataIntegrityRecordReference>,
  )
  routeForRecord;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
    child: ButlerlyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(ButlerlySpacing.standard),
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final severityGroup in _groupBySeverity(findings)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ButlerlySpacing.standard,
                0,
                ButlerlySpacing.standard,
                ButlerlySpacing.xs,
              ),
              child: Text(
                _severityLabel(context, severityGroup.$1),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final finding in severityGroup.$2)
              ExpansionTile(
                leading: Icon(
                  finding.severity == DataIntegrityFindingSeverity.error
                      ? Icons.error_outline
                      : Icons.warning_amber_outlined,
                  color: finding.severity == DataIntegrityFindingSeverity.error
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.tertiary,
                ),
                title: Text(_findingDescription(context, finding)),
                childrenPadding: const EdgeInsets.fromLTRB(
                  ButlerlySpacing.standard,
                  0,
                  ButlerlySpacing.standard,
                  ButlerlySpacing.standard,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${context.l10n.text('dataIntegrityRecommendedAction')}: ${_findingAction(context, finding)}',
                    ),
                  ),
                  if (finding.affectedRecords.isNotEmpty) ...[
                    const SizedBox(height: ButlerlySpacing.small),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.l10n.text('dataIntegrityAffectedRecords'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    for (final record in finding.affectedRecords)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed:
                              _recordCanOpen(record, finding.affectedRecords)
                              ? () =>
                                    _openRecord(record, finding.affectedRecords)
                              : null,
                          child: Text(_recordReferenceLabel(context, record)),
                        ),
                      ),
                  ],
                ],
              ),
          ],
        ],
      ),
    ),
  );

  List<(DataIntegrityFindingSeverity, List<DataIntegrityFinding>)>
  _groupBySeverity(List<DataIntegrityFinding> values) {
    final grouped =
        <DataIntegrityFindingSeverity, List<DataIntegrityFinding>>{};
    for (final finding in values) {
      grouped.putIfAbsent(finding.severity, () => []).add(finding);
    }
    const order = [
      DataIntegrityFindingSeverity.error,
      DataIntegrityFindingSeverity.warning,
      DataIntegrityFindingSeverity.info,
    ];
    return [
      for (final severity in order)
        if (grouped[severity] case final findings?) (severity, findings),
    ];
  }

  String _severityLabel(
    BuildContext context,
    DataIntegrityFindingSeverity severity,
  ) => context.l10n.text(switch (severity) {
    DataIntegrityFindingSeverity.info => 'dataIntegritySeverityInfo',
    DataIntegrityFindingSeverity.warning => 'dataIntegritySeverityWarning',
    DataIntegrityFindingSeverity.error => 'dataIntegritySeverityError',
  });

  bool _recordCanOpen(
    DataIntegrityRecordReference record,
    List<DataIntegrityRecordReference> relatedRecords,
  ) => routeForRecord(record, relatedRecords) != null;

  void _openRecord(
    DataIntegrityRecordReference record,
    List<DataIntegrityRecordReference> relatedRecords,
  ) {
    final route = routeForRecord(record, relatedRecords);
    if (route != null) onOpenRoute(route);
  }
}

String _findingDescription(
  BuildContext context,
  DataIntegrityFinding finding,
) => context.l10n.text(switch (finding.code) {
  'missing_evidence_file' =>
    finding.category == DataIntegrityFindingCategory.missingReceipt
        ? 'dataIntegrityFindingMissingReceipt'
        : 'dataIntegrityFindingMissingAttachment',
  'missing_receipt' => 'dataIntegrityFindingMissingReceipt',
  'missing_evidence' => 'dataIntegrityFindingMissingAttachment',
  'invalid_evidence_reference' =>
    finding.context['unsafe'] == 'true'
        ? 'dataIntegrityFindingUnsafeFileReference'
        : 'dataIntegrityFindingInvalidFileReference',
  'missing_referenced_record' => 'dataIntegrityFindingMissingReferencedRecord',
  'invalid_budget_scope_reference' => 'dataIntegrityFindingInvalidBudgetScope',
  'missing_budget_scope_record' => 'dataIntegrityFindingMissingBudgetRecord',
  'invalid_analysis_rule_definition' =>
    'dataIntegrityFindingInvalidRuleDefinition',
  'analysis_rule_provenance_mismatch' =>
    'dataIntegrityFindingProvenanceMismatch',
  'active_analysis_rule_missing' => 'dataIntegrityFindingActiveRuleMissing',
  'invalid_analysis_rule_configuration' =>
    'dataIntegrityFindingInvalidRuleConfiguration',
  'invalid_custom_analysis_rule' => 'dataIntegrityFindingInvalidRuleDefinition',
  'invalid_custom_configuration' =>
    'dataIntegrityFindingInvalidRuleConfiguration',
  'relationship_inconsistency' =>
    'dataIntegrityFindingRelationshipInconsistency',
  'analysis_rebuild_failed' => 'dataIntegrityFindingAnalysisRebuildFailed',
  _ => 'dataIntegrityFindingUnknown',
});

String _findingAction(
  BuildContext context,
  DataIntegrityFinding finding,
) => context.l10n.text(switch (finding.code) {
  'missing_evidence_file' => 'dataIntegrityActionAttachEvidence',
  'missing_receipt' => 'dataIntegrityActionAttachEvidence',
  'missing_evidence' => 'dataIntegrityActionAttachEvidence',
  'invalid_evidence_reference' => 'dataIntegrityActionReviewEvidence',
  'missing_referenced_record' => 'dataIntegrityActionReviewRelatedData',
  'invalid_budget_scope_reference' => 'dataIntegrityActionReviewBudgetScope',
  'missing_budget_scope_record' => 'dataIntegrityActionReviewBudgetRecord',
  'invalid_analysis_rule_definition' => 'dataIntegrityActionReviewRuleSource',
  'analysis_rule_provenance_mismatch' =>
    'dataIntegrityActionReviewRuleProvenance',
  'active_analysis_rule_missing' => 'dataIntegrityActionReviewActiveRule',
  'invalid_analysis_rule_configuration' =>
    'dataIntegrityActionReviewRuleConfiguration',
  'invalid_custom_analysis_rule' => 'dataIntegrityActionReviewRuleSource',
  'invalid_custom_configuration' =>
    'dataIntegrityActionReviewRuleConfiguration',
  'relationship_inconsistency' => 'dataIntegrityActionReviewRelationship',
  'analysis_rebuild_failed' => 'dataIntegrityActionRetryAnalysis',
  _ => 'dataIntegrityActionReviewLocalData',
});

String _recordReferenceLabel(
  BuildContext context,
  DataIntegrityRecordReference record,
) {
  final type = context.l10n.text(switch (record.type) {
    'transaction' => 'dataIntegrityRecordTypeTransaction',
    'evidence' => 'dataIntegrityRecordTypeEvidence',
    'attachment' => 'dataIntegrityRecordTypeAttachment',
    'budget' => 'dataIntegrityRecordTypeBudget',
    'category' => 'dataIntegrityRecordTypeCategory',
    'merchant' => 'dataIntegrityRecordTypeMerchant',
    'analysisRule' => 'dataIntegrityRecordTypeAnalysisRule',
    _ => 'dataIntegrityRecordTypeRelated',
  });
  return context.l10n
      .text('dataIntegrityRecordReference')
      .replaceFirst('{type}', type)
      .replaceFirst('{id}', record.id);
}
