import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_statement_ocr_support.dart';
import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly/core/evidence/statement_source_matcher.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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
      services<FinanceServices>().listPaymentSources(),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0] case ApplicationSuccess<List<FinancialStatement>>(
        value: final v,
      )) {
        _statements = v;
      }
      if (results[1] case ApplicationSuccess<List<PaymentSource>>(
        value: final v,
      )) {
        _sources = v;
      }
    });
  }

  Future<void> _capture() async {
    const types = XTypeGroup(
      label: 'Statements',
      extensions: ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [types]);
    if (file == null || !mounted) return;
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
        : _extractedRows(id, extraction.rows, now);
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
          description: value.description,
          amount: value.amount,
          currency: value.currency,
          direction: value.direction,
          confidence: value.confidence,
          sourceContext: 'On-device OCR, line ${position + 1}',
          status: complete
              ? StatementRowStatus.pending
              : StatementRowStatus.unresolved,
          createdAt: now,
          updatedAt: now,
        );
      })
      .toList(growable: false);

  Future<void> _open(FinancialStatement item) async {
    final rowsResult = await statement.rows(item.id);
    if (!mounted || rowsResult is! ApplicationSuccess<List<StatementRow>>) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StatementReviewPage(
          statement: item,
          rows: rowsResult.value,
          sources: _sources,
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
    appBar: AppBar(title: const Text('Statements')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy ? null : _capture,
      icon: const Icon(Icons.document_scanner_outlined),
      label: const Text('Add statement'),
    ),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : _statements.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Add a bank or card statement. The original stays on this device and every row waits for your review.',
              ),
            ),
          )
        : ListView.builder(
            itemCount: _statements.length,
            itemBuilder: (_, index) {
              final item = _statements[index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(item.institution ?? 'Statement'),
                subtitle: Text(
                  item.paymentSourceId == null
                      ? 'Choose a payment source to continue'
                      : 'Review in progress',
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
    required this.service,
  });
  final FinancialStatement statement;
  final List<StatementRow> rows;
  final List<PaymentSource> sources;
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
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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

  Future<void> _addRows() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                TextField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                TextField(
                  controller: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  decoration: const InputDecoration(
                    labelText: 'Direction (required)',
                  ),
                  items: TransactionDirection.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.name,
                          child: Text(v.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => direction = v),
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
      final matches = await widget.service.likelyMatches(row, _sourceId!);
      if (!mounted) return;
      if (matches case ApplicationSuccess<List<TransactionDto>>(
        value: final values,
      ) when values.isNotEmpty) {
        final link = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Likely existing transaction'),
            content: Text(
              '${values.first.transactionDate} · ${values.first.direction} · ${values.first.currency} ${values.first.amount}\n${values.first.description ?? values.first.rawCounterparty ?? ''}\n\nLink this statement row instead of creating a duplicate?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Create separately'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Link existing'),
              ),
            ],
          ),
        );
        if (link == true) {
          await widget.service.link(row, values.first.id);
          status = StatementRowStatus.linked;
        } else {
          await widget.service.save(row, _sourceId!);
        }
      } else {
        await widget.service.save(row, _sourceId!);
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
    appBar: AppBar(title: const Text('Review statement')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _sourceId,
          decoration: const InputDecoration(
            labelText: 'Payment source (required)',
          ),
          items: _sources
              .where(
                (s) =>
                    s.status == PaymentSourceStatus.active ||
                    s.id.value == _sourceId,
              )
              .map(
                (s) => DropdownMenuItem(
                  value: s.id.value,
                  enabled:
                      s.status == PaymentSourceStatus.active ||
                      s.id.value == _sourceId,
                  child: Text(
                    '${s.displayIdentity ?? s.name}${s.status == PaymentSourceStatus.archived ? ' (archived)' : ''}',
                  ),
                ),
              )
              .toList(),
          onChanged: (value) async {
            if (value == null) return;
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
