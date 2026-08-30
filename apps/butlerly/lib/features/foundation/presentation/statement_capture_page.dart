import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_statement_ocr_support.dart';
import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly/core/evidence/statement_source_matcher.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/statement_labels.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

sealed class StatementReconciliationDecision {
  const StatementReconciliationDecision();
}

final class LinkStatementReconciliation
    extends StatementReconciliationDecision {
  const LinkStatementReconciliation(this.transactionId);
  final String transactionId;
}

final class CreateStatementSeparately extends StatementReconciliationDecision {
  const CreateStatementSeparately();
}

final class CancelStatementReconciliation
    extends StatementReconciliationDecision {
  const CancelStatementReconciliation();
}

class StatementCapturePage extends StatefulWidget {
  const StatementCapturePage({this.pickImage, super.key});

  final Future<XFile?> Function(ImageSource source)? pickImage;
  @override
  State<StatementCapturePage> createState() => _StatementCapturePageState();
}

class _StatementCapturePageState extends State<StatementCapturePage> {
  final _rowsText = TextEditingController();
  List<FinancialStatement> _statements = const [];
  List<PaymentSource> _sources = const [];
  bool _busy = false;
  final _imagePicker = ImagePicker();
  final _debugDiagnostics = <String, String>{};
  StatementServices get statement =>
      services<FinanceServices>().statementServices!;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _rowsText.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final results = await Future.wait([
      statement.list(),
      TransactionMasterDataProvider(services<FinanceServices>()).load(),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0] case ApplicationSuccess<List<FinancialStatement>>(
        value: final v,
      )) {
        _statements = v;
      }
      if (results[1] case final TransactionMasterDataSnapshot v) {
        _sources = v.paymentSources;
      }
    });
  }

  Future<void> _captureImage(ImageSource source) async {
    final file =
        await (widget.pickImage?.call(source) ??
            _imagePicker.pickImage(
              source: source,
              imageQuality: 100,
              requestFullMetadata: false,
            ));
    if (file == null || !mounted) return;
    await _ingest(file);
  }

  Future<void> _ingest(XFile file) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final store = services<LocalEvidenceStore>();
    final preserved = await store.preserve(file);
    StatementExtraction? extraction;
    try {
      final localFile = await store.fileForPreserved(preserved);
      if (localFile != null && supportsLocalStatementOcr()) {
        extraction = await const LocalStatementExtractor().extract(
          localFile.path,
        );
      }
    } on Object {
      // The original is still retained so unreadable statements can be fixed.
      if (kDebugMode) {
        debugPrint(
          'Butlerly statement OCR: Outcome: technicalOcrFailure; '
          'Failure stage: capturePipeline',
        );
      }
    }
    final evidence = await store.storePreservedStatement(preserved);
    if (evidence == null) {
      await store.discardPreserved(preserved);
      _message('The statement could not be stored.');
      return;
    }
    final now = DateTime.now().toUtc();
    final id = 'statement-${now.microsecondsSinceEpoch}';
    if (kDebugMode) {
      final summary =
          extraction?.debugSummary ??
          'Outcome: technicalOcrFailure\nFailure stage: capturePipeline';
      _debugDiagnostics[id] = summary;
      debugPrint('Butlerly statement OCR\n$summary');
    }
    String? rawTextReference;
    if (extraction != null && extraction.rawText.isNotEmpty) {
      final storedText = await services<FinanceServices>().saveExtraction(
        Extraction(
          id: ExtractionId('$id-ocr'),
          evidenceId: evidence.id,
          values: {'rawText': extraction.rawText},
          provenance: Provenance(
            id: ProvenanceId('$id-ocr-provenance'),
            sourceType: ProvenanceSourceType.scan,
            capturedAt: now,
            sourceId: evidence.id.value,
            originalRepresentation: 'On-device statement OCR',
          ),
          createdAt: now,
        ),
      );
      if (storedText is ApplicationSuccess<Extraction>) {
        rawTextReference = evidence.id.value;
      }
    }
    final matchedSource = extraction == null
        ? null
        : confidentlyMatchStatementSource(
            maskedAccountIdentifier: extraction.maskedAccountIdentifier,
            institution: extraction.institution,
            sources: _sources,
          );
    final rows = extraction == null
        ? <StatementRow>[]
        : _extractedRows(id, extraction.rows, now, matchedSource?.id.value);
    final result = await statement.create(
      FinancialStatement(
        id: id,
        evidenceId: evidence.id.value,
        paymentSourceId: matchedSource?.id.value,
        status: matchedSource == null
            ? StatementStatus.needsSource
            : StatementStatus.ready,
        institution: extraction?.institution,
        maskedAccountIdentifier: extraction?.maskedAccountIdentifier,
        periodStart: extraction?.context.periodStart,
        periodEnd: extraction?.context.periodEnd,
        currency: extraction?.context.defaultCurrency,
        originalFilename: file.name,
        rawTextReference: rawTextReference,
        createdAt: now,
        updatedAt: now,
        extractionMessage: rows.isNotEmpty
            ? extraction!.rows.any((row) => row.isUnresolved)
                  ? l10n.text('statementUnresolvedEvidence')
                  : null
            : extraction == null
            ? l10n.text('statementProcessingFailed')
            : switch (extraction.outcome) {
                StatementExtractionOutcome.noText => l10n.text(
                  'statementNoText',
                ),
                StatementExtractionOutcome.textWithoutCandidates => l10n.text(
                  'statementNoRows',
                ),
                StatementExtractionOutcome.unresolvedEvidence => l10n.text(
                  'statementUnresolvedEvidence',
                ),
                StatementExtractionOutcome.reconstructedCandidates => l10n.text(
                  'statementNoRows',
                ),
                StatementExtractionOutcome.technicalOcrFailure => l10n.text(
                  'statementProcessingFailed',
                ),
              },
      ),
      rows,
    );
    if (result is! ApplicationSuccess<void>) {
      await store.remove(evidence);
      if (kDebugMode && result is ApplicationFailure<void>) {
        debugPrint(
          'Butlerly statement create failed: operation='
          '${result.failure.operation}; code=${result.failure.code}; '
          'detail=${result.failure.detail ?? 'none'}; rows=${rows.length}',
        );
      }
      _message('The statement could not be created.');
      return;
    }
    _rowsText.clear();
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  List<StatementRow> _extractedRows(
    String statementId,
    List<StatementExtractedRow> extracted,
    DateTime now,
    String? paymentSourceId,
  ) => extracted.indexed
      .map((entry) {
        final (position, value) = entry;
        final complete =
            !value.isUnresolved &&
            value.date != null &&
            value.amount != null &&
            value.currency != null &&
            value.direction != null;
        return StatementRow(
          id: '$statementId-row-$position',
          statementId: statementId,
          position: position,
          originalText: value.originalText,
          transactionDate: value.date,
          postingDate: value.postingDate,
          description: value.description,
          amount: value.amount,
          currency: value.currency,
          direction: value.direction,
          confidence: value.confidence,
          sourceContext:
              'On-device OCR observations ${value.sourceObservationIndexes.join(', ')}',
          reviewReason: value.unresolvedReason?.name,
          paymentSourceId: paymentSourceId,
          status: complete
              ? StatementRowStatus.pending
              : StatementRowStatus.unresolved,
          createdAt: now,
          updatedAt: now,
        );
      })
      .toList(growable: false);

  Future<void> _open(FinancialStatement item) async {
    final results = await Future.wait([
      statement.rows(item.id),
      TransactionMasterDataProvider(services<FinanceServices>()).load(),
    ]);
    if (!mounted ||
        results[0] is! ApplicationSuccess<List<StatementRow>> ||
        results[1] is! TransactionMasterDataSnapshot) {
      return;
    }
    final rowsResult = results[0] as ApplicationSuccess<List<StatementRow>>;
    final masterData = results[1] as TransactionMasterDataSnapshot;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StatementReviewPage(
          statement: item,
          rows: rowsResult.value,
          sources: _sources,
          masterData: masterData,
          service: statement,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _deleteUnprocessed(FinancialStatement item) async {
    final l10n = context.l10n;
    final eligibility = await statement.canDeleteStatement(item.id);
    if (!mounted) return;
    if (eligibility is! ApplicationSuccess<bool> || !eligibility.value) {
      _message(context.l10n.text('statementDeletionProtected'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.text('deleteStatementTitle')),
        content: Text(l10n.text('deleteStatementBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.text('deleteStatement')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await services<LocalEvidenceStore>()
        .removeUnprocessedStatement(item.id);
    if (!mounted) return;
    if (success) {
      await _reload();
      _message(l10n.text('statementDeleted'));
    } else {
      _message(l10n.text('statementDeleteFailed'));
    }
  }

  void _message(String value) {
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _showDiagnostics(String id) async {
    if (!kDebugMode) return;
    final summary = _debugDiagnostics[id];
    if (summary == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Statement extraction diagnostics'),
        content: SingleChildScrollView(child: SelectableText(summary)),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: summary)),
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('done')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text('statements')),
      actions: [
        IconButton(
          onPressed: _busy ? null : () => _captureImage(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          tooltip: context.l10n.text('scanReceipt'),
        ),
        IconButton(
          onPressed: _busy ? null : () => _captureImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          tooltip: context.l10n.text('importData'),
        ),
      ],
    ),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : _statements.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(ButlerlySpacing.large),
              child: Text(context.l10n.text('statementsEmptyBody')),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),
            itemCount: _statements.length,
            itemBuilder: (_, index) {
              final item = _statements[index];
              return Card(
                margin: const EdgeInsets.only(bottom: ButlerlySpacing.cardGap),
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(statementDisplayTitle(context, item, _sources)),
                  subtitle: Text(
                    item.extractionMessage ??
                        (item.paymentSourceId == null
                            ? context.l10n.text('choosePaymentSourceToContinue')
                            : context.l10n.text('reviewInProgress')),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') _deleteUnprocessed(item);
                      if (value == 'diagnostics') _showDiagnostics(item.id);
                    },
                    itemBuilder: (_) => [
                      if (kDebugMode && _debugDiagnostics.containsKey(item.id))
                        const PopupMenuItem(
                          value: 'diagnostics',
                          child: Text('Extraction diagnostics'),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.l10n.text('deleteStatement')),
                      ),
                    ],
                  ),
                  onTap: () => _open(item),
                ),
              );
            },
          ),
  );
}

class _StatementReviewPage extends StatefulWidget {
  const _StatementReviewPage({
    required this.statement,
    required this.rows,
    required this.sources,
    required this.masterData,
    required this.service,
  });
  final FinancialStatement statement;
  final List<StatementRow> rows;
  final List<PaymentSource> sources;
  final TransactionMasterDataSnapshot masterData;
  final StatementServices service;
  @override
  State<_StatementReviewPage> createState() => _StatementReviewPageState();
}

class _StatementReviewPageState extends State<_StatementReviewPage> {
  String? _sourceId;
  late List<StatementRow> _rows;
  late List<PaymentSource> _sources;
  @override
  void initState() {
    super.initState();
    _sourceId = widget.statement.paymentSourceId;
    _rows = [...widget.rows];
    _sources = [...widget.sources];
  }

  Future<void> _createSource() async {
    final name = TextEditingController(text: widget.statement.institution);
    final lastFour = TextEditingController(
      text: RegExp(
        r'(\d{4})$',
      ).firstMatch(widget.statement.maskedAccountIdentifier ?? '')?.group(1),
    );
    var type = PaymentSourceType.account;
    final create = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ButlerlySheet(
          title: const Text('Create payment source'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                DropdownButtonFormField<PaymentSourceType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: PaymentSourceType.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
                TextField(
                  controller: lastFour,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Last four digits (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create and use'),
            ),
          ],
        ),
      ),
    );
    if (create != true || name.text.trim().isEmpty) {
      name.dispose();
      lastFour.dispose();
      return;
    }
    final digits = lastFour.text.trim();
    if (digits.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(digits)) {
      _message('Enter exactly four digits, or leave the field empty.');
      name.dispose();
      lastFour.dispose();
      return;
    }
    final source = PaymentSource(
      id: PaymentSourceId('source-${DateTime.now().microsecondsSinceEpoch}'),
      name: name.text.trim(),
      type: type,
      displayIdentity: name.text.trim(),
      lastFour: digits.isEmpty ? null : digits,
      issuer: widget.statement.institution,
    );
    name.dispose();
    lastFour.dispose();
    final saved = await services<FinanceServices>().savePaymentSource(source);
    if (saved is! ApplicationSuccess<PaymentSource>) {
      _message('The payment source could not be created.');
      return;
    }
    final assigned = await widget.service.assignSource(
      widget.statement.id,
      source.id.value,
    );
    if (!mounted) return;
    setState(() => _sources.add(source));
    if (assigned is ApplicationSuccess<void>) {
      setState(() {
        _sourceId = source.id.value;
      });
    } else {
      _message(
        'The source was created, but could not be linked. Select it to retry.',
      );
    }
  }

  Future<void> _abandonImport() async {
    final l10n = context.l10n;
    final confirmed = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(l10n.text('abandonStatementImportTitle')),
        content: Text(l10n.text('abandonStatementImportBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.text('abandonStatementImport')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await services<LocalEvidenceStore>().abandonStatementImport(
      widget.statement.id,
    );
    if (!mounted) return;
    if (removed) {
      Navigator.pop(context);
    } else {
      _message(l10n.text('statementDeleteFailed'));
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _importBatch() async {
    final sourceId = _sourceId;
    if (sourceId == null) {
      _message(context.l10n.text('choosePaymentSourceToContinue'));
      return;
    }
    final candidates = _rows
        .where(
          (row) =>
              row.status == StatementRowStatus.pending ||
              row.status == StatementRowStatus.unresolved,
        )
        .toList(growable: false);
    final assessmentResult = await widget.service.assessBatch(
      widget.statement,
      candidates,
      sourceId,
    );
    if (!mounted) return;
    if (assessmentResult is! ApplicationSuccess<StatementImportAssessment>) {
      _message(context.l10n.text('statementAssessmentFailed'));
      return;
    }
    final assessment = assessmentResult.value;
    final confirmed = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(context.l10n.text('reviewStatementImport')),
        content: Text(
          [
            '${context.l10n.text('candidateTransactions')}: ${assessment.candidateCount}',
            if (assessment.aggregateAmount != null)
              '${context.l10n.text('aggregateAmount')}: ${assessment.currency} ${assessment.aggregateAmount}',
            '${context.l10n.text('statementNeedsReview')}: ${assessment.lowConfidenceCount}',
            '${context.l10n.text('possibleDuplicates')}: ${assessment.possibleDuplicateCount}',
            '${context.l10n.text('unresolvedRows')}: ${assessment.invalidCount}',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('importData')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await widget.service.importBatch(
      widget.statement,
      candidates,
      sourceId,
    );
    if (!mounted) return;
    if (result case ApplicationSuccess<StatementImportSummary>(
      value: final summary,
    )) {
      notifyTransactionChanged();
      await showButlerlyBottomSheet<void>(
        context: context,
        builder: (context) => ButlerlySheet(
          title: Text(context.l10n.text('importSummary')),
          content: Text(
            '${summary.imported} ${context.l10n.text('statementSaved')} · '
            '${summary.needsReview} ${context.l10n.text('statementNeedsReview')} · '
            '${summary.possibleDuplicates} ${context.l10n.text('possibleDuplicates')} · '
            '${summary.failed} ${context.l10n.text('statementFailed')}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (summary.failed > 0) {
                  Navigator.pop(context);
                } else {
                  context.go('/review');
                }
              },
              child: Text(
                context.l10n.text(summary.failed > 0 ? 'done' : 'review'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('done')),
            ),
          ],
        ),
      );
      if (mounted) context.pop();
    }
  }

  // Retained for future recovery tooling; intentionally hidden from V1 review UI.
  // ignore: unused_element
  Future<void> _addRows() async {
    final controller = TextEditingController();
    final text = await showButlerlyBottomSheet<String>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: const Text('Add rows from statement'),
        content: TextField(
          controller: controller,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            helperText:
                'One per line: YYYY-MM-DD | description | signed amount | currency',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add for review'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    final now = DateTime.now().toUtc();
    final rows = <StatementRow>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final parts = line.split('|').map((value) => value.trim()).toList();
      if (parts.length < 4 || line.trim().isEmpty) continue;
      String? amount;
      String? direction;
      try {
        final amountText = parts[2].trim();
        final signed = DecimalValue.parse(amountText);
        amount = DecimalValue.fromParts(
          coefficient: signed.coefficient.abs(),
          scale: signed.scale,
        ).toString();
        direction = amountText.startsWith('-')
            ? TransactionDirection.expense.name
            : amountText.startsWith('+')
            ? TransactionDirection.income.name
            : null;
      } on DomainValidationException {
        /* Keep the row unresolved. */
      }
      final position = _rows.length + rows.length;
      final date = LocalStatementExtractor.parseDate(parts[0]);
      final currency = RegExp(r'^[A-Za-z]{3}$').hasMatch(parts[3])
          ? parts[3].toUpperCase()
          : null;
      rows.add(
        StatementRow(
          id: '${widget.statement.id}-row-$position',
          statementId: widget.statement.id,
          position: position,
          originalText: line,
          transactionDate: date,
          description: parts[1],
          amount: amount,
          currency: currency,
          direction: direction,
          sourceContext: 'User correction after local extraction',
          paymentSourceId: _sourceId,
          status:
              date != null &&
                  amount != null &&
                  currency != null &&
                  direction != null
              ? StatementRowStatus.pending
              : StatementRowStatus.unresolved,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (rows.isEmpty) return;
    await widget.service.addRows(rows);
    final refreshed = await widget.service.rows(widget.statement.id);
    if (mounted) {
      if (refreshed case ApplicationSuccess<List<StatementRow>>(
        value: final values,
      )) {
        setState(() => _rows = values);
      }
    }
  }

  Future<void> _edit(StatementRow row) async {
    final date = TextEditingController(
      text: row.transactionDate?.toIso8601String().substring(0, 10),
    );
    final postingDate = TextEditingController(
      text: row.postingDate?.toIso8601String().substring(0, 10),
    );
    final description = TextEditingController(text: row.description);
    final amount = TextEditingController(text: row.amount);
    final currency = TextEditingController(text: row.currency);
    var direction = row.direction;
    var subcategoryId =
        row.categoryId != null &&
            widget.masterData.presentation.categoryParentId(row.categoryId) !=
                null
        ? row.categoryId
        : null;
    var categoryId =
        widget.masterData.presentation.categoryParentId(row.categoryId) ??
        row.categoryId;
    var merchantId = row.merchantId;
    var tagIds = row.tagIds.toSet();
    final accepted = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ButlerlySheet(
          title: const Text('Correct extracted row'),
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ButlerlySpacing.small,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    [
                          Text(row.originalText),
                          TextField(
                            controller: date,
                            decoration: const InputDecoration(
                              labelText: 'Date (YYYY-MM-DD)',
                            ),
                          ),
                          TextField(
                            controller: postingDate,
                            decoration: const InputDecoration(
                              labelText: 'Posting date (YYYY-MM-DD)',
                            ),
                          ),
                          TextField(
                            controller: description,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                            ),
                          ),
                          ButlerlyMerchantSelector(
                            merchants: widget.masterData.merchants,
                            value: merchantId,
                            label: context.l10n.text('merchant'),
                            clearLabel: context.l10n.text('clear'),
                            createTooltip: context.l10n.text('create'),
                            onChanged: (value) =>
                                setDialogState(() => merchantId = value),
                          ),
                          ButlerlyCategorySelector(
                            categories: widget.masterData.categories,
                            masterData: widget.masterData.presentation,
                            value: categoryId,
                            label: context.l10n.text('category'),
                            clearLabel: context.l10n.text('clear'),
                            onChanged: (value) => setDialogState(() {
                              categoryId = value;
                              subcategoryId = null;
                            }),
                          ),
                          ButlerlySubcategorySelector(
                            categories: widget.masterData.categories,
                            masterData: widget.masterData.presentation,
                            parentId: categoryId,
                            value: subcategoryId,
                            label: context.l10n.text('subcategory'),
                            clearLabel: context.l10n.text('clear'),
                            onChanged: (value) =>
                                setDialogState(() => subcategoryId = value),
                          ),
                          ButlerlyTagPicker(
                            tags: widget.masterData.tags,
                            masterData: widget.masterData.presentation,
                            selected: tagIds,
                            searchLabel: context.l10n.text('search'),
                            createLabel: context.l10n.text('create'),
                            onChanged: (value) =>
                                setDialogState(() => tagIds = value),
                          ),
                          TextField(
                            controller: amount,
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                            ),
                          ),
                          TextField(
                            controller: currency,
                            decoration: const InputDecoration(
                              labelText: 'Currency',
                            ),
                          ),
                          ButlerlyDirectionFilter(
                            value: direction == null
                                ? null
                                : TransactionDirection.values.byName(
                                    direction!,
                                  ),
                            label: context.l10n.text('direction'),
                            anyLabel: context.l10n.text('clear'),
                            onChanged: (v) =>
                                setDialogState(() => direction = v?.name),
                          ),
                        ]
                        .expand((child) sync* {
                          yield child;
                          yield const SizedBox(height: ButlerlySpacing.small);
                        })
                        .toList(growable: false),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: direction == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Save corrections'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    String? normalizedAmount;
    try {
      final parsedAmount = DecimalValue.parse(amount.text.trim());
      normalizedAmount = DecimalValue.fromParts(
        coefficient: parsedAmount.coefficient.abs(),
        scale: parsedAmount.scale,
      ).toString();
    } on DomainValidationException {
      normalizedAmount = null;
    }
    final correctedDate = LocalStatementExtractor.parseDate(date.text.trim());
    final correctedPostingDate = LocalStatementExtractor.parseDate(
      postingDate.text.trim(),
    );
    final correctedCurrency =
        RegExp(r'^[A-Za-z]{3}$').hasMatch(currency.text.trim())
        ? currency.text.trim().toUpperCase()
        : null;
    final corrected = StatementRow(
      id: row.id,
      statementId: row.statementId,
      position: row.position,
      originalText: row.originalText,
      transactionDate: correctedDate,
      postingDate: correctedPostingDate,
      description: description.text.trim(),
      amount: normalizedAmount,
      currency: correctedCurrency,
      direction: direction,
      kind: row.kind,
      confidence: row.confidence,
      sourceContext:
          '${row.sourceContext ?? 'Local extraction'}; user corrected',
      status:
          correctedDate != null &&
              normalizedAmount != null &&
              correctedCurrency != null &&
              direction != null
          ? StatementRowStatus.pending
          : StatementRowStatus.unresolved,
      categoryId: subcategoryId ?? categoryId,
      merchantId: merchantId,
      tagIds: tagIds.toList(growable: false),
      paymentSourceId: row.paymentSourceId,
      sourceReferenceId: row.sourceReferenceId,
      reviewReason: row.reviewReason,
      dispositionReason: row.dispositionReason,
      createdAt: row.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await widget.service.correct(corrected);
    final refreshed = await widget.service.rows(widget.statement.id);
    if (mounted) {
      if (refreshed case ApplicationSuccess<List<StatementRow>>(
        value: final values,
      )) {
        setState(() => _rows = values);
      }
    }
  }

  Future<void> _act(StatementRow row, StatementRowStatus status) async {
    if (_sourceId == null) return;
    if (status == StatementRowStatus.saved) {
      final strict = await widget.service.duplicates(row);
      if (!mounted) return;
      if (strict case ApplicationSuccess<DuplicateTransactionCheckResult>(
        value: final duplicate,
      ) when duplicate.requiresConfirmation) {
        final proposed = TransactionDto(
          id: '__statement-proposed__',
          amount: row.amount!,
          currency: row.currency!,
          direction: row.direction!,
          status: TransactionStatus.active.name,
          reviewState: TransactionReviewState.clear.name,
          transactionDate: row.transactionDate!.toIso8601String().substring(
            0,
            10,
          ),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          description: row.description,
          rawCounterparty: row.originalText,
          paymentSourceId: row.paymentSourceId ?? _sourceId,
          merchantId: row.merchantId,
          categoryId: row.categoryId,
          tagIds: row.tagIds,
        );
        final decision =
            await showButlerlyBottomSheet<ButlerlyDuplicateConfirmationResult>(
              context: context,
              builder: (_) => ButlerlyDuplicateTransactionConfirmation(
                proposed: proposed,
                candidates: duplicate.candidates,
                paymentSourceLabels: {
                  for (final source in _sources)
                    source.id.value: source.lastFour == null
                        ? (source.displayIdentity ?? source.name)
                        : '${source.displayIdentity ?? source.name} ••••${source.lastFour}',
                },
                onDecision: (value) => Navigator.pop(context, value),
              ),
            );
        if (!mounted || decision == null) return;
        if (decision.decision == ButlerlyDuplicateDecision.useExisting &&
            decision.selectedTransactionId != null) {
          await widget.service.link(row, decision.selectedTransactionId!);
        } else if (decision.decision ==
            ButlerlyDuplicateDecision.continueAnyway) {
          await widget.service.save(row, _sourceId!, allowCreateNew: true);
        }
        return;
      }
      final matches = await widget.service.likelyMatches(row, _sourceId!);
      if (!mounted) return;
      if (matches case ApplicationSuccess<List<ReconciliationMatchCandidate>>(
        value: final values,
      ) when values.isNotEmpty) {
        final decision = await showButlerlyBottomSheet<StatementReconciliationDecision>(
          context: context,
          builder: (_) => ButlerlySheet(
            title: Text(context.l10n.text('statementReconciliationTitle')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.text('statementReconciliationPrompt')),
                for (final candidate in values)
                  ListTile(
                    title: Text(
                      '${candidate.transaction.currency} ${localizedTransactionAmount(context, candidate.transaction.amount)} · ${candidate.transaction.transactionDate}',
                    ),
                    subtitle: Text(
                      '${context.l10n.text('reconciliationScore', {'score': candidate.assessment.score.toStringAsFixed(2)})}\n${candidate.assessment.reasons.join('; ')}${candidate.assessment.conflicts.isEmpty ? '' : '\n${candidate.assessment.conflicts.join('; ')}'}',
                    ),
                    onTap: () => Navigator.pop(
                      context,
                      LinkStatementReconciliation(candidate.transaction.id),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const CreateStatementSeparately()),
                child: Text(context.l10n.text('createSeparately')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  const CancelStatementReconciliation(),
                ),
                child: Text(context.l10n.text('cancel')),
              ),
            ],
          ),
        );
        if (decision is LinkStatementReconciliation) {
          await widget.service.link(row, decision.transactionId);
        } else if (decision is CreateStatementSeparately) {
          await widget.service.save(row, _sourceId!, allowCreateNew: true);
        }
      } else {
        await widget.service.save(row, _sourceId!, allowCreateNew: true);
      }
    } else {
      await widget.service.setDisposition(row, status);
    }
    final refreshed = await widget.service.rows(widget.statement.id);
    if (!mounted) return;
    if (refreshed case ApplicationSuccess<List<StatementRow>>(
      value: final values,
    )) {
      setState(() => _rows = values);
    }
  }

  Future<void> _toggleSkipRestore(StatementRow row) async {
    await widget.service.toggleSkipRestore(row);
    final refreshed = await widget.service.rows(widget.statement.id);
    if (!mounted) return;
    if (refreshed case ApplicationSuccess<List<StatementRow>>(:final value)) {
      setState(() => _rows = value);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text('reviewStatementImport')),
      actions: [
        IconButton(
          onPressed: _abandonImport,
          tooltip: context.l10n.text('abandonStatementImport'),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),
      children: [
        if (widget.statement.institution != null ||
            widget.statement.maskedAccountIdentifier != null ||
            widget.statement.periodStart != null)
          Card(
            child: ListTile(
              title: Text(
                statementDisplayTitle(context, widget.statement, _sources),
              ),
              subtitle: Text(
                [
                  if (widget.statement.maskedAccountIdentifier != null)
                    widget.statement.maskedAccountIdentifier!,
                  if (widget.statement.periodStart != null &&
                      widget.statement.periodEnd != null)
                    '${widget.statement.periodStart!.toIso8601String().substring(0, 10)} – '
                        '${widget.statement.periodEnd!.toIso8601String().substring(0, 10)}',
                ].join(' · '),
              ),
            ),
          ),
        const SizedBox(height: ButlerlySpacing.compact),
        _ProgressSummary(rows: _rows),
        const SizedBox(height: ButlerlySpacing.sectionSpacing),
        ButlerlyPaymentSourceSelector(
          value: _sourceId,
          label: '${context.l10n.text('paymentSource')} *',
          clearLabel: context.l10n.text('clear'),
          sources: _sources,
          onChanged: (value) async {
            if (value == null) {
              setState(() => _sourceId = null);
              return;
            }
            await widget.service.assignSource(widget.statement.id, value);
            setState(() => _sourceId = value);
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _createSource,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Create new payment source'),
          ),
        ),
        const SizedBox(height: ButlerlySpacing.compact),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ButlerlySpacing.sectionSpacing,
            ),
            child: Text(
              widget.statement.extractionMessage ??
                  context.l10n.text('statementNoRows'),
              textAlign: TextAlign.center,
            ),
          ),
        for (final row in _rows)
          Card(
            margin: const EdgeInsets.only(bottom: ButlerlySpacing.cardGap),
            child: Padding(
              padding: const EdgeInsets.all(ButlerlySpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.description ?? row.originalText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    [
                      row.transactionDate?.toIso8601String().substring(0, 10) ??
                          'Date needs review',
                      row.currency ?? 'Currency needs review',
                      row.amount ?? 'Amount needs review',
                      row.direction ?? 'Direction needs review',
                      row.status.name,
                    ].join(' · '),
                  ),
                  if (row.status == StatementRowStatus.pending ||
                      row.status == StatementRowStatus.unresolved ||
                      row.status == StatementRowStatus.deferred ||
                      row.status == StatementRowStatus.skipped)
                    Wrap(
                      spacing: ButlerlySpacing.compactActionSpacing,
                      children: [
                        if (row.status != StatementRowStatus.skipped)
                          ButlerlyCompactActionButton(
                            onPressed: () => _edit(row),
                            icon: Icons.edit_outlined,
                            child: Text(context.l10n.text('edit')),
                          ),
                        if (row.status != StatementRowStatus.skipped)
                          ButlerlyCompactActionButton(
                            onPressed:
                                _sourceId != null &&
                                    row.transactionDate != null &&
                                    row.amount != null &&
                                    row.currency != null &&
                                    row.direction != null
                                ? () => _act(row, StatementRowStatus.saved)
                                : null,
                            icon: Icons.save_outlined,
                            child: Text(context.l10n.text('save')),
                          ),
                        if (row.status != StatementRowStatus.skipped)
                          ButlerlyCompactActionButton(
                            onPressed: () =>
                                _act(row, StatementRowStatus.deferred),
                            icon: Icons.schedule_outlined,
                            child: Text(context.l10n.text('later')),
                          ),
                        ButlerlyCompactActionButton(
                          onPressed: () => _toggleSkipRestore(row),
                          icon: row.status == StatementRowStatus.skipped
                              ? Icons.restore_outlined
                              : Icons.skip_next_outlined,
                          child: Text(
                            row.status == StatementRowStatus.skipped
                                ? context.l10n.text('restore')
                                : context.l10n.text('skip'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(
            top: ButlerlySpacing.micro,
            bottom: ButlerlySpacing.bottomActionSpacing,
          ),
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              onPressed: _sourceId == null || _rows.isEmpty
                  ? null
                  : _importBatch,
              icon: const Icon(Icons.download_done_outlined),
              label: Text(context.l10n.text('importData')),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.rows});
  final List<StatementRow> rows;

  @override
  Widget build(BuildContext context) {
    int count(StatementRowStatus status) =>
        rows.where((row) => row.status == status).length;
    return Text(
      '${context.l10n.text('statementRows')}: ${rows.length}  '
      '${context.l10n.text('statementSaved')}: ${count(StatementRowStatus.saved)}  '
      '${context.l10n.text('statementLinked')}: ${count(StatementRowStatus.linked)}  '
      '${context.l10n.text('statementNeedsReview')}: '
      '${count(StatementRowStatus.pending) + count(StatementRowStatus.unresolved)}  '
      '${context.l10n.text('statementSkipped')}: ${count(StatementRowStatus.skipped)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
