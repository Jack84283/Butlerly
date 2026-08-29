import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_statement_ocr_support.dart';
import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly/core/evidence/statement_source_matcher.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
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
  const StatementCapturePage({super.key});
  @override
  State<StatementCapturePage> createState() => _StatementCapturePageState();
}

class _StatementCapturePageState extends State<StatementCapturePage> {
  final _rowsText = TextEditingController();
  List<FinancialStatement> _statements = const [];
  List<PaymentSource> _sources = const [];
  bool _busy = false;
  final _imagePicker = ImagePicker();
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
    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 100,
      requestFullMetadata: false,
    );
    if (file == null || !mounted) return;
    await _ingest(file);
  }

  Future<void> _ingest(XFile file) async {
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
    }
    final evidence = await store.storePreservedStatement(preserved);
    if (evidence == null) {
      await store.discardPreserved(preserved);
      _message('The statement could not be stored.');
      return;
    }
    final now = DateTime.now().toUtc();
    final id = 'statement-${now.microsecondsSinceEpoch}';
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
        rawTextReference: extraction == null ? null : evidence.id.value,
        createdAt: now,
        updatedAt: now,
        extractionMessage: rows.isEmpty
            ? supportsLocalStatementOcr()
                  ? 'No supported rows were found. Add rows manually.'
                  : 'Automatic text recognition is not available on this platform. Add rows manually.'
            : null,
      ),
      rows,
    );
    if (result is! ApplicationSuccess<void>) {
      await store.remove(evidence);
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
          reviewReason: value.unresolvedReason,
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

  void _message(String value) {
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
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
              padding: EdgeInsets.all(32),
              child: Text(context.l10n.text('statementsEmptyBody')),
            ),
          )
        : ListView.builder(
            itemCount: _statements.length,
            itemBuilder: (_, index) {
              final item = _statements[index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(item.institution ?? context.l10n.text('statement')),
                subtitle: Text(
                  item.paymentSourceId == null
                      ? context.l10n.text('choosePaymentSourceToContinue')
                      : context.l10n.text('reviewInProgress'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(item),
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
            '${summary.possibleDuplicates} ${context.l10n.text('possibleDuplicates')}',
          ),
          actions: [
            TextButton(
              onPressed: () => context.go('/review'),
              child: Text(context.l10n.text('review')),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.originalText),
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Date (YYYY-MM-DD)',
                  ),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
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
                  onChanged: (value) => setDialogState(() => tagIds = value),
                ),
                TextField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                TextField(
                  controller: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                ),
                ButlerlyDirectionFilter(
                  value: direction == null
                      ? null
                      : TransactionDirection.values.byName(direction!),
                  label: context.l10n.text('direction'),
                  anyLabel: context.l10n.text('clear'),
                  onChanged: (v) => setDialogState(() => direction = v?.name),
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
      postingDate: row.postingDate,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('reviewStatementImport'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.statement.institution != null ||
            widget.statement.maskedAccountIdentifier != null ||
            widget.statement.periodStart != null)
          Card(
            child: ListTile(
              title: Text(
                widget.statement.institution ?? context.l10n.text('statement'),
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
        const SizedBox(height: 8),
        _ProgressSummary(rows: _rows),
        const SizedBox(height: 16),
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
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _sourceId == null || _rows.isEmpty ? null : _importBatch,
          icon: const Icon(Icons.download_done_outlined),
          label: Text(context.l10n.text('importData')),
        ),
        const SizedBox(height: 16),
        if (_rows.isEmpty)
          Column(
            children: [
              const Text(
                'No readable rows were found. The original remains on this device.',
              ),
              FilledButton.icon(
                onPressed: _addRows,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Add or correct rows'),
              ),
            ],
          ),
        if (_rows.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addRows,
              icon: const Icon(Icons.add),
              label: const Text('Add missing row'),
            ),
          ),
        for (final row in _rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
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
                      row.status == StatementRowStatus.deferred)
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _edit(row),
                          child: const Text('Edit'),
                        ),
                        FilledButton(
                          onPressed:
                              _sourceId != null &&
                                  row.transactionDate != null &&
                                  row.amount != null &&
                                  row.currency != null &&
                                  row.direction != null
                              ? () => _act(row, StatementRowStatus.saved)
                              : null,
                          child: const Text('Save'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _act(row, StatementRowStatus.deferred),
                          child: const Text('Later'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _act(row, StatementRowStatus.skipped),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                ],
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
