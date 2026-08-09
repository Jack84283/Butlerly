import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late Future<List<TransactionDto>> _transactions;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _transactions = _load();
  }

  Future<List<TransactionDto>> _load() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listTransactions(
      const ListTransactionsQuery(),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) => value,
      ApplicationFailure<List<TransactionDto>>() => throw StateError(
        'Transactions could not be loaded.',
      ),
    };
  }

  void _refresh() {
    final reloaded = _load();
    setState(() {
      _transactions = reloaded;
    });
  }

  Future<void> _openEditor([TransactionDto? transaction]) async {
    final finance = _finance;
    if (finance == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionEditorPage(finance: finance, existing: transaction),
      ),
    );
    if (changed == true) _refresh();
  }

  Future<void> _openDetail(TransactionDto transaction) async {
    final finance = _finance;
    if (finance == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_finance == null) {
      return const _TransactionsMessage(
        icon: Icons.storage_outlined,
        title: 'Transaction storage is unavailable',
        message:
            'This platform does not currently provide local transaction storage.',
      );
    }
    return FutureBuilder<List<TransactionDto>>(
      future: _transactions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _TransactionsMessage(
            icon: Icons.error_outline,
            title: 'Transactions could not be loaded',
            message: 'Your existing local data was not changed. Try again.',
            actionLabel: 'Try again',
            onAction: _refresh,
          );
        }
        final values = snapshot.requireData;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openEditor,
            icon: const Icon(Icons.add),
            label: const Text('Add transaction'),
          ),
          body: values.isEmpty
              ? _TransactionsMessage(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message:
                      'Add a transaction to create a private, searchable local record.',
                  actionLabel: 'Add transaction',
                  onAction: _openEditor,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
                  itemCount: values.length + 1,
                  separatorBuilder: (_, index) => index == 0
                      ? const SizedBox(height: 12)
                      : const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Text(
                        'Transactions',
                        style: Theme.of(context).textTheme.headlineMedium,
                      );
                    }
                    final value = values[index - 1];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: Icon(
                        value.direction == TransactionDirection.income.name
                            ? Icons.south_west_outlined
                            : Icons.north_east_outlined,
                      ),
                      title: Text(
                        value.description?.trim().isNotEmpty == true
                            ? value.description!
                            : 'Untitled transaction',
                      ),
                      subtitle: Text(_transactionDate(value)),
                      trailing: Text('${value.amount} ${value.currency}'),
                      onTap: () => _openDetail(value),
                    );
                  },
                ),
        );
      },
    );
  }
}

class TransactionEditorPage extends StatefulWidget {
  const TransactionEditorPage({
    required this.finance,
    this.existing,
    super.key,
  });

  final FinanceServices finance;
  final TransactionDto? existing;

  @override
  State<TransactionEditorPage> createState() => _TransactionEditorPageState();
}

class _TransactionEditorPageState extends State<TransactionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _description;
  late DateTime _date;
  late TransactionDirection _direction;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(text: existing?.amount ?? '');
    _currency = TextEditingController(text: existing?.currency ?? 'USD');
    _description = TextEditingController(text: existing?.description ?? '');
    _date = existing?.occurredAt ?? DateTime.now();
    _direction = TransactionDirection.values.byName(
      existing?.direction ?? TransactionDirection.expense.name,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final money = Money(
      amount: DecimalValue.parse(_amount.text.trim()),
      currency: CurrencyCode(_currency.text.trim()),
    );
    final existing = widget.existing;
    final result = existing == null
        ? await widget.finance.createTransaction(
            CreateTransactionCommand(
              id: 'transaction-${DateTime.now().microsecondsSinceEpoch}',
              provenanceId: 'manual-${DateTime.now().microsecondsSinceEpoch}',
              timing: KnownTransactionTime(_date),
              money: money,
              direction: _direction,
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
            ),
          )
        : await widget.finance.updateTransaction(
            UpdateTransactionCommand(
              id: existing.id,
              timing: KnownTransactionTime(_date),
              money: money,
              direction: _direction,
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
            ),
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is ApplicationFailure<TransactionDto>) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The transaction could not be saved. No data was changed.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null ? 'Add transaction' : 'Edit transaction',
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
            validator: (value) {
              try {
                DecimalValue.parse(value?.trim() ?? '');
                return null;
              } on DomainValidationException {
                return 'Enter a valid amount.';
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Currency'),
            validator: (value) {
              try {
                CurrencyCode(value?.trim() ?? '');
                return null;
              } on DomainValidationException {
                return 'Use a three-letter currency code.';
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TransactionDirection>(
            initialValue: _direction,
            decoration: const InputDecoration(labelText: 'Direction'),
            items: TransactionDirection.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.name)),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _direction = value!),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(_shortDate(_date)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: _date,
              );
              if (selected != null) {
                setState(() => _date = selected);
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save locally'),
          ),
        ],
      ),
    ),
  );
}

class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({
    required this.finance,
    required this.transaction,
    super.key,
  });

  final FinanceServices finance;
  final TransactionDto transaction;

  Future<void> _archive(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      'Archive transaction?',
      'You can restore it later.',
    );
    if (confirmed != true || !context.mounted) return;
    await finance.archiveTransaction(transaction.id);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      'Permanently delete transaction?',
      'This removes the transaction from this device and cannot be undone.',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    await finance.deleteTransactionPermanently(transaction.id);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Transaction detail'),
      actions: [
        IconButton(
          tooltip: 'Edit transaction',
          onPressed: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => TransactionEditorPage(
                  finance: finance,
                  existing: transaction,
                ),
              ),
            );
            if (changed == true && context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          transaction.description ?? 'Untitled transaction',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${transaction.amount} ${transaction.currency}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        _DetailRow(label: 'Direction', value: transaction.direction),
        _DetailRow(label: 'Date', value: _transactionDate(transaction)),
        _DetailRow(label: 'Status', value: transaction.status),
        _DetailRow(
          label: 'Review',
          value: transaction.reviewState == 'needsReview'
              ? 'Needs review'
              : 'Clear',
        ),
        if (transaction.provenance.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Record history',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...transaction.provenance.map(
            (value) => _DetailRow(
              label: _provenanceLabel(value.sourceType),
              value: _shortDate(value.capturedAt),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _EvidenceSection(finance: finance, transactionId: transaction.id),
        if (transaction.merchantId != null)
          _DetailRow(label: 'Merchant', value: transaction.merchantId!),
        if (transaction.categoryId != null)
          _DetailRow(label: 'Category', value: transaction.categoryId!),
        if (transaction.tagIds.isNotEmpty)
          _DetailRow(label: 'Tags', value: transaction.tagIds.join(', ')),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final changed = await _organizeTransaction(
              context,
              finance,
              transaction,
            );
            if (changed == true && context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
          icon: const Icon(Icons.sell_outlined),
          label: const Text('Organize transaction'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: transaction.status == TransactionStatus.archived.name
              ? () async {
                  await finance.restoreTransaction(transaction.id);
                  if (context.mounted) Navigator.of(context).pop(true);
                }
              : () => _archive(context),
          icon: Icon(
            transaction.status == TransactionStatus.archived.name
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
          ),
          label: Text(
            transaction.status == TransactionStatus.archived.name
                ? 'Restore transaction'
                : 'Archive transaction',
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _delete(context),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Permanently delete'),
        ),
      ],
    ),
  );
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.finance, required this.transactionId});

  final FinanceServices finance;
  final String transactionId;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EvidenceItem>>(
    future: finance
        .listEvidenceForTransaction(transactionId)
        .then(
          (result) => switch (result) {
            ApplicationSuccess<List<EvidenceItem>>(:final value) => value,
            ApplicationFailure<List<EvidenceItem>>() => const [],
          },
        ),
    builder: (context, snapshot) {
      final evidence = snapshot.data;
      if (evidence == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Evidence', style: Theme.of(context).textTheme.titleMedium),
          if (evidence.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No evidence metadata is attached locally.'),
            )
          else
            ...evidence.map(
              (value) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_outlined),
                title: Text(value.originalName),
                subtitle: Text(value.mediaType),
              ),
            ),
        ],
      );
    },
  );
}

String _provenanceLabel(String sourceType) => switch (sourceType) {
  'userEntry' => 'Entered locally',
  'import' => 'Imported',
  'scan' => 'Scanned',
  'evidenceExtraction' => 'Evidence extraction',
  'integration' => 'Integration',
  'deterministicCalculation' => 'Calculation',
  'localAi' => 'Local AI',
  'externalAi' => 'External AI',
  'migration' => 'Migration',
  _ => 'Record origin',
};

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}

class _TransactionsMessage extends StatelessWidget {
  const _TransactionsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

Future<bool?> _confirm(
  BuildContext context,
  String title,
  String message, {
  bool destructive = false,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(destructive ? 'Delete permanently' : 'Archive'),
      ),
    ],
  ),
);

Future<bool?> _organizeTransaction(
  BuildContext context,
  FinanceServices finance,
  TransactionDto transaction,
) {
  final merchant = TextEditingController();
  final category = TextEditingController();
  final tag = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Organize transaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: merchant,
              decoration: const InputDecoration(
                labelText: 'New merchant (optional)',
              ),
            ),
            TextField(
              controller: category,
              decoration: const InputDecoration(
                labelText: 'New category (optional)',
              ),
            ),
            TextField(
              controller: tag,
              decoration: const InputDecoration(
                labelText: 'New tag (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final stamp = DateTime.now().microsecondsSinceEpoch;
            if (merchant.text.trim().isNotEmpty) {
              final id = 'merchant-$stamp';
              await finance.saveMerchant(
                Merchant(id: MerchantId(id), name: merchant.text),
              );
              await finance.assignMerchant(transaction.id, id);
            }
            if (category.text.trim().isNotEmpty) {
              final id = 'category-$stamp';
              await finance.saveCategory(
                Category(
                  id: CategoryId(id),
                  name: category.text,
                  origin: CategoryOrigin.user,
                ),
              );
              await finance.assignCategory(transaction.id, id);
            }
            if (tag.text.trim().isNotEmpty) {
              final id = 'tag-$stamp';
              await finance.saveTag(Tag(id: TagId(id), name: tag.text));
              await finance.addTag(transaction.id, id);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          },
          child: const Text('Save organization'),
        ),
      ],
    ),
  ).whenComplete(() {
    merchant.dispose();
    category.dispose();
    tag.dispose();
  });
}

String _transactionDate(TransactionDto value) =>
    value.occurredAt == null ? 'Date pending' : _shortDate(value.occurredAt!);
String _shortDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
