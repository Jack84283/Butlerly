import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
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
        _sources = v
            .where((s) => s.status == PaymentSourceStatus.active)
            .toList();
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
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review extracted rows'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: _rowsText,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: 'One row per line',
              helperText:
                  'Date | description | signed amount | currency\nExample: 2026-08-12 | Grocery | -42.10 | USD',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _rowsText.text),
            child: const Text('Preserve statement'),
          ),
        ],
      ),
    );
    if (text == null) return;
    setState(() => _busy = true);
    final store = services<LocalEvidenceStore>();
    final preserved = await store.preserve(file);
    final evidence = await store.storePreservedStatement(preserved);
    if (evidence == null) {
      await store.discardPreserved(preserved);
      _message('The statement could not be stored.');
      return;
    }
    final now = DateTime.now().toUtc();
    final id = 'statement-${now.microsecondsSinceEpoch}';
    final rows = _parseRows(id, text, now);
    final result = await statement.create(
      FinancialStatement(
        id: id,
        evidenceId: evidence.id.value,
        status: StatementStatus.needsSource,
        createdAt: now,
        updatedAt: now,
        extractionMessage: rows.isEmpty
            ? 'No supported rows were found. Add or correct rows manually.'
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

  List<StatementRow> _parseRows(
    String statementId,
    String input,
    DateTime now,
  ) {
    final rows = <StatementRow>[];
    for (final line in input.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('|').map((e) => e.trim()).toList();
      DateTime? date;
      String? amount;
      String? currency;
      String? direction;
      String? description;
      if (parts.length >= 4) {
        date = DateTime.tryParse(parts[0]);
        description = parts[1];
        try {
          final signed = DecimalValue.parse(parts[2]);
          amount = DecimalValue.fromParts(
            coefficient: signed.coefficient.abs(),
            scale: signed.scale,
          ).toString();
          direction = parts[2].startsWith('-')
              ? TransactionDirection.expense.name
              : TransactionDirection.income.name;
        } on DomainValidationException {
          amount = null;
        }
        currency = RegExp(r'^[A-Za-z]{3}$').hasMatch(parts[3])
            ? parts[3].toUpperCase()
            : null;
      }
      final position = rows.length;
      rows.add(
        StatementRow(
          id: '$statementId-row-$position',
          statementId: statementId,
          position: position,
          originalText: line,
          transactionDate: date,
          description: description,
          amount: amount,
          currency: currency,
          direction: direction,
          confidence: date != null && amount != null && currency != null
              ? 0.8
              : 0.2,
          sourceContext: 'User-reviewed local extraction, line ${position + 1}',
          status: date != null && amount != null && currency != null
              ? StatementRowStatus.pending
              : StatementRowStatus.unresolved,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return rows;
  }

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
  @override
  void initState() {
    super.initState();
    _sourceId = widget.statement.paymentSourceId;
    _rows = [...widget.rows];
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
              '${values.first.transactionDate} · ${values.first.currency} ${values.first.amount}\n${values.first.description ?? values.first.rawCounterparty ?? ''}\n\nLink this statement row instead of creating a duplicate?',
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
          items: widget.sources
              .map(
                (s) => DropdownMenuItem(
                  value: s.id.value,
                  child: Text(s.displayIdentity ?? s.name),
                ),
              )
              .toList(),
          onChanged: (value) async {
            if (value == null) return;
            await widget.service.assignSource(widget.statement.id, value);
            setState(() => _sourceId = value);
          },
        ),
        const SizedBox(height: 16),
        if (_rows.isEmpty)
          const Text(
            'No readable rows were found. Retain this statement and retry extraction later.',
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
                      row.status.name,
                    ].join(' · '),
                  ),
                  if (row.status == StatementRowStatus.pending ||
                      row.status == StatementRowStatus.unresolved)
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed:
                              _sourceId != null &&
                                  row.transactionDate != null &&
                                  row.amount != null &&
                                  row.currency != null
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
