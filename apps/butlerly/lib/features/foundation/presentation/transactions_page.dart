import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late Future<_TransactionsData> _transactions;
  _TransactionFilter _filter = _TransactionFilter.all;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _transactions = _load();
    transactionChanges.addListener(_handleTransactionChange);
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_handleTransactionChange);
    super.dispose();
  }

  void _handleTransactionChange() {
    if (mounted) _refresh();
  }

  Future<_TransactionsData> _load() async {
    final finance = _finance;
    if (finance == null) return const _TransactionsData([]);
    final result = await finance.listTransactions(
      const ListTransactionsQuery(),
    );
    final values = switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) => value,
      ApplicationFailure<List<TransactionDto>>() => throw StateError(
        'Transactions could not be loaded.',
      ),
    };
    return _TransactionsData(values, await TransactionMasterData.load(finance));
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
      return ButlerlyEmptyState(
        icon: Icons.storage_outlined,
        title: context.l10n.text('loadTransactionsError'),
        message: context.l10n.text('dataPreserved'),
      );
    }
    return FutureBuilder<_TransactionsData>(
      future: _transactions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ButlerlyErrorState(
            title: context.l10n.text('loadTransactionsError'),
            message: context.l10n.text('tryAgain'),
            preserved: context.l10n.text('dataPreserved'),
            actionLabel: context.l10n.text('tryAgain'),
            onAction: _refresh,
          );
        }
        final data = snapshot.requireData;
        final values = data.transactions;
        final visible = values
            .where(
              (value) => switch (_filter) {
                _TransactionFilter.all => true,
                _TransactionFilter.income =>
                  value.direction == TransactionDirection.income.name,
                _TransactionFilter.expense =>
                  value.direction == TransactionDirection.expense.name,
                _TransactionFilter.archived =>
                  value.status == TransactionStatus.archived.name,
              },
            )
            .toList(growable: false);
        return ButlerlyPage(
          title: context.l10n.text('transactions'),
          actions: [
            IconButton(
              tooltip: context.l10n.text('search'),
              onPressed: () => GoRouter.of(context).go('/search'),
              icon: const Icon(Icons.search_rounded),
            ),
          ],
          children: [
            SizedBox(
              height: ButlerlySize.preferredTarget,
              child: SegmentedButton<_TransactionFilter>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _TransactionFilter.all,
                    label: Text(context.l10n.text('all')),
                  ),
                  ButtonSegment(
                    value: _TransactionFilter.income,
                    label: Text(context.l10n.text('income')),
                  ),
                  ButtonSegment(
                    value: _TransactionFilter.expense,
                    label: Text(context.l10n.text('expense')),
                  ),
                  ButtonSegment(
                    value: _TransactionFilter.archived,
                    label: Text(context.l10n.text('archived')),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.single),
              ),
            ),
            const SizedBox(height: ButlerlySpacing.section),
            if (values.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.receipt_long_outlined,
                title: context.l10n.text('noTransactions'),
                message: context.l10n.text('noTransactionsBody'),
                actionLabel: context.l10n.text('addTransaction'),
                onAction: _openEditor,
              )
            else if (visible.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: context.l10n.text('noResults'),
                message: context.l10n.text('noResultsBody'),
                actionLabel: context.l10n.text('clearFilters'),
                onAction: () =>
                    setState(() => _filter = _TransactionFilter.all),
              )
            else
              ButlerlyCard(
                padding: const EdgeInsets.symmetric(
                  vertical: ButlerlySpacing.compact,
                ),
                child: Column(
                  children: visible
                      .map(
                        (value) => ButlerlyRecordRow(
                          title: value.description?.trim().isNotEmpty == true
                              ? value.description!
                              : context.l10n.text('untitledTransaction'),
                          subtitle: data.masterData.summary(value),
                          meta: _transactionDate(value, context),
                          amount: value.amount,
                          currency: value.currency,
                          icon:
                              value.direction ==
                                  TransactionDirection.income.name
                              ? Icons.work_outline_rounded
                              : Icons.shopping_bag_outlined,
                          isIncome:
                              value.direction ==
                              TransactionDirection.income.name,
                          needsReview: value.reviewState == 'needsReview',
                          onTap: () => _openDetail(value),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            const SizedBox(height: ButlerlySpacing.structural),
          ],
        );
      },
    );
  }
}

enum _TransactionFilter { all, income, expense, archived }

final class _TransactionsData {
  const _TransactionsData(
    this.transactions, [
    this.masterData = const TransactionMasterData(),
  ]);

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
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
  bool _dateChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(text: existing?.amount ?? '');
    _currency = TextEditingController(text: existing?.currency ?? 'USD');
    _description = TextEditingController(text: existing?.description ?? '');
    _date = existing == null
        ? DateTime.now()
        : transactionCalendarDate(existing, fallback: DateTime.now());
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
    final timing =
        existing != null && !_dateChanged && existing.occurredAt != null
        ? KnownTransactionTime(existing.occurredAt!)
        : KnownTransactionTime(_date);
    final result = existing == null
        ? await widget.finance.createTransaction(
            CreateTransactionCommand(
              id: 'transaction-${DateTime.now().microsecondsSinceEpoch}',
              provenanceId: 'manual-${DateTime.now().microsecondsSinceEpoch}',
              timing: timing,
              money: money,
              direction: _direction,
              transactionDate: _shortDate(_date),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
            ),
          )
        : await widget.finance.updateTransaction(
            UpdateTransactionCommand(
              id: existing.id,
              timing: timing,
              money: money,
              direction: _direction,
              transactionDate: _shortDate(_date),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
            ),
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is ApplicationFailure<TransactionDto>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
    notifyTransactionChanged();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null
            ? context.l10n.text('addTransaction')
            : context.l10n.text('editTransaction'),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SegmentedButton<TransactionDirection>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: TransactionDirection.expense,
                icon: const Icon(Icons.arrow_upward_rounded),
                label: Text(context.l10n.text('expense')),
              ),
              ButtonSegment(
                value: TransactionDirection.income,
                icon: const Icon(Icons.arrow_downward_rounded),
                label: Text(context.l10n.text('income')),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (selection) =>
                setState(() => _direction = selection.single),
          ),
          const SizedBox(height: ButlerlySpacing.section),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.l10n.text('amount'),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
            validator: (value) {
              try {
                DecimalValue.parse(value?.trim() ?? '');
                return null;
              } on DomainValidationException {
                return context.l10n.text('invalidAmount');
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: context.l10n.text('currency'),
            ),
            validator: (value) {
              try {
                CurrencyCode(value?.trim() ?? '');
                return null;
              } on DomainValidationException {
                return context.l10n.text('invalidCurrency');
              }
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text('date')),
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
                setState(() {
                  _date = selected;
                  _dateChanged = true;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _description,
            decoration: InputDecoration(
              labelText: context.l10n.text('descriptionOptional'),
              prefixIcon: const Icon(Icons.notes_rounded),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? context.l10n.text('saving')
                  : context.l10n.text('saveLocally'),
            ),
          ),
        ],
      ),
    ),
  );
}

class TransactionDetailPage extends StatefulWidget {
  const TransactionDetailPage({
    required this.finance,
    required this.transaction,
    super.key,
  });

  final FinanceServices finance;
  final TransactionDto transaction;

  @override
  State<TransactionDetailPage> createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  late TransactionDto transaction;

  FinanceServices get finance => widget.finance;

  @override
  void initState() {
    super.initState();
    transaction = widget.transaction;
  }

  Future<void> _archive(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      context.l10n.text('archiveTitle'),
      context.l10n.text('archiveBody'),
    );
    if (confirmed != true || !context.mounted) return;
    await finance.archiveTransaction(transaction.id);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      context.l10n.text('deleteTitle'),
      context.l10n.text('deleteBody'),
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    await finance.deleteTransactionPermanently(transaction.id);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text('transactionDetail')),
      actions: [
        IconButton(
          tooltip: context.l10n.text('editTransaction'),
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
          transaction.description ?? context.l10n.text('untitledTransaction'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${transaction.amount} ${transaction.currency}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (transaction.normalizedMoney.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.text('referenceAmounts'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          ...transaction.normalizedMoney.map(
            (value) => _DetailRow(
              label: context.l10n.text('referenceCurrency', {
                'currency': value.currency,
              }),
              value: '${value.amount} ${value.currency}',
            ),
          ),
        ],
        const SizedBox(height: 24),
        _DetailRow(
          label: context.l10n.text('direction'),
          value: context.l10n.text(transaction.direction),
        ),
        _DetailRow(
          label: context.l10n.text('date'),
          value: _transactionDate(transaction, context),
        ),
        _DetailRow(
          label: context.l10n.text('status'),
          value: context.l10n.text(transaction.status),
        ),
        _DetailRow(
          label: context.l10n.text('reviewState'),
          value: transaction.reviewState == 'needsReview'
              ? context.l10n.text('needsReview')
              : context.l10n.text('clear'),
        ),
        if (transaction.provenance.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            context.l10n.text('recordHistory'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...transaction.provenance.map(
            (value) => _DetailRow(
              label: context.l10n.text('origin'),
              value: _provenanceLabel(context, value.sourceType),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _EvidenceSection(finance: finance, transactionId: transaction.id),
        _TransactionMasterDataRows(
          key: ValueKey(
            '${transaction.updatedAt.microsecondsSinceEpoch}-${transaction.tagIds.join(',')}',
          ),
          finance: finance,
          transaction: transaction,
        ),
        if (transaction.paymentSourceId != null)
          _PaymentSourceRow(
            finance: finance,
            paymentSourceId: transaction.paymentSourceId!,
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final changed = await _organizeTransaction(
              context,
              finance,
              transaction,
            );
            if (changed == true && context.mounted) {
              final refreshed = await finance.getTransaction(transaction.id);
              if (!context.mounted) return;
              if (refreshed case ApplicationSuccess<TransactionDto>(
                :final value,
              )) {
                setState(() => transaction = value);
              }
            }
          },
          icon: const Icon(Icons.sell_outlined),
          label: Text(context.l10n.text('organizeTransaction')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _assignPaymentSource(context, finance, transaction),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(context.l10n.text('assignPaymentSource')),
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
                ? context.l10n.text('restoreTransaction')
                : context.l10n.text('archiveTransaction'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _delete(context),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(context.l10n.text('deletePermanently')),
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
            ApplicationFailure<List<EvidenceItem>>() => throw StateError(
              'Evidence metadata could not be loaded.',
            ),
          },
        ),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(context.l10n.text('evidenceLoadError'));
      }
      final evidence = snapshot.data;
      if (evidence == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text('evidence'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (evidence.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.l10n.text('noEvidence')),
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

class _TransactionMasterDataRows extends StatefulWidget {
  const _TransactionMasterDataRows({
    required this.finance,
    required this.transaction,
    super.key,
  });

  final FinanceServices finance;
  final TransactionDto transaction;

  @override
  State<_TransactionMasterDataRows> createState() =>
      _TransactionMasterDataRowsState();
}

class _TransactionMasterDataRowsState
    extends State<_TransactionMasterDataRows> {
  late final Future<TransactionMasterData> _masterData;

  @override
  void initState() {
    super.initState();
    _masterData = TransactionMasterData.load(widget.finance);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TransactionMasterData>(
    future: _masterData,
    builder: (context, snapshot) {
      final transaction = widget.transaction;
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: ButlerlySpacing.compact),
          child: LinearProgressIndicator(),
        );
      }
      final data = snapshot.data ?? const TransactionMasterData();
      return Column(
        children: [
          if (transaction.merchantId != null)
            _DetailRow(
              label: context.l10n.text('merchant'),
              value:
                  data.merchantName(transaction.merchantId) ??
                  context.l10n.text('unavailableMerchant'),
            ),
          if (transaction.categoryId != null)
            _DetailRow(
              label: context.l10n.text('category'),
              value:
                  data.categoryName(transaction.categoryId) ??
                  context.l10n.text('unavailableCategory'),
            ),
          if (transaction.tagIds.isNotEmpty)
            _DetailRow(
              label: context.l10n.text('tags'),
              value: transaction.tagIds
                  .map(
                    (id) =>
                        data.tagName(id) ?? context.l10n.text('unavailableTag'),
                  )
                  .join(', '),
            ),
        ],
      );
    },
  );
}

class _PaymentSourceRow extends StatelessWidget {
  const _PaymentSourceRow({
    required this.finance,
    required this.paymentSourceId,
  });

  final FinanceServices finance;
  final String paymentSourceId;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PaymentSource>>(
    future: finance.listPaymentSources().then(
      (result) => switch (result) {
        ApplicationSuccess<List<PaymentSource>>(:final value) => value,
        ApplicationFailure<List<PaymentSource>>() => const [],
      },
    ),
    builder: (context, snapshot) {
      final source = snapshot.data
          ?.where((value) => value.id.value == paymentSourceId)
          .firstOrNull;
      return _DetailRow(
        label: context.l10n.text('paymentSource'),
        value: source?.name ?? context.l10n.text('unavailablePaymentSource'),
      );
    },
  );
}

String _provenanceLabel(BuildContext context, String sourceType) =>
    switch (sourceType) {
      'userEntry' => context.l10n.text('enteredLocally'),
      'import' => context.l10n.text('imported'),
      'scan' => context.l10n.text('scanned'),
      'evidenceExtraction' => context.l10n.text('evidenceExtraction'),
      'integration' => context.l10n.text('integration'),
      'deterministicCalculation' => context.l10n.text('calculation'),
      'localAi' => context.l10n.text('localAi'),
      'externalAi' => context.l10n.text('externalAi'),
      'migration' => context.l10n.text('migration'),
      _ => context.l10n.text('recordOrigin'),
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
        child: Text(context.l10n.text('cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          context.l10n.text(destructive ? 'deletePermanently' : 'archive'),
        ),
      ),
    ],
  ),
);

Future<bool?> _organizeTransaction(
  BuildContext context,
  FinanceServices finance,
  TransactionDto transaction,
) async {
  final masterDataResults = await Future.wait([
    finance.listMerchants(),
    finance.listCategories(),
    finance.listTags(),
  ]);
  if (!context.mounted) return false;
  final merchants = switch (masterDataResults[0]) {
    ApplicationSuccess<List<Merchant>>(:final value) => value,
    _ => const <Merchant>[],
  };
  final categories = switch (masterDataResults[1]) {
    ApplicationSuccess<List<Category>>(:final value) => value,
    _ => const <Category>[],
  };
  final tags = switch (masterDataResults[2]) {
    ApplicationSuccess<List<Tag>>(:final value) => value,
    _ => const <Tag>[],
  };
  final merchantOptions = merchants
      .map((value) => _MasterDataOption(value.id.value, value.name))
      .toList(growable: false);
  final categoryOptions = categories
      .map((value) => _MasterDataOption(value.id.value, value.name))
      .toList(growable: false);
  final tagOptions = tags
      .map((value) => _MasterDataOption(value.id.value, value.name))
      .toList(growable: false);

  String? merchantId = transaction.merchantId;
  String? categoryId = transaction.categoryId;
  final selectedTagIds = transaction.tagIds.toSet();
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(dialogContext.l10n.text('organizeTransaction')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: merchantId,
                isExpanded: true,
                hint: Text(dialogContext.l10n.text('unassigned')),
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.text('merchant'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(dialogContext.l10n.text('unassigned')),
                  ),
                  ...merchantOptions.map(
                    (option) => DropdownMenuItem(
                      value: option.id,
                      child: Text(option.name),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    merchantId = value?.isEmpty == true ? null : value,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                isExpanded: true,
                hint: Text(dialogContext.l10n.text('unassigned')),
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.text('category'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(dialogContext.l10n.text('unassigned')),
                  ),
                  ...categoryOptions.map(
                    (option) => DropdownMenuItem(
                      value: option.id,
                      child: Text(option.name),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    categoryId = value?.isEmpty == true ? null : value,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              if (selectedTagIds.isNotEmpty) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    dialogContext.l10n.text('assignedTags'),
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.compact),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: ButlerlySpacing.compact,
                    runSpacing: ButlerlySpacing.compact,
                    children: selectedTagIds
                        .map(
                          (id) => InputChip(
                            label: Text(
                              _optionName(tagOptions, id) ??
                                  dialogContext.l10n.text('unavailableTag'),
                            ),
                            tooltip: dialogContext.l10n.text('removeTag'),
                            onDeleted: () =>
                                setDialogState(() => selectedTagIds.remove(id)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.small),
              ],
              DropdownButtonFormField<String>(
                key: ValueKey(selectedTagIds.length),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.text('addTag'),
                ),
                items: tagOptions
                    .where((option) => !selectedTagIds.contains(option.id))
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedTagIds.add(value));
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await finance.assignMerchant(transaction.id, merchantId);
              await finance.assignCategory(transaction.id, categoryId);
              for (final id in transaction.tagIds) {
                if (!selectedTagIds.contains(id)) {
                  await finance.removeTag(transaction.id, id);
                }
              }
              for (final id in selectedTagIds) {
                if (!transaction.tagIds.contains(id)) {
                  await finance.addTag(transaction.id, id);
                }
              }
              notifyTransactionChanged();
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: Text(dialogContext.l10n.text('saveOrganization')),
          ),
        ],
      ),
    ),
  );
}

final class _MasterDataOption {
  const _MasterDataOption(this.id, this.name);

  final String id;
  final String name;
}

String? _optionName(List<_MasterDataOption> options, String? id) {
  for (final option in options) {
    if (option.id == id) return option.name;
  }
  return null;
}

Future<void> _assignPaymentSource(
  BuildContext context,
  FinanceServices finance,
  TransactionDto transaction,
) async {
  final result = await finance.listPaymentSources();
  if (!context.mounted) return;
  if (result is! ApplicationSuccess<List<PaymentSource>>) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('paymentSourcesLoadError'))),
    );
    return;
  }
  final sources = result.value
      .where((value) => value.status == PaymentSourceStatus.active)
      .toList(growable: false);
  final sourceId = await showDialog<String?>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(dialogContext.l10n.text('assignPaymentSource')),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.l10n.text('noPaymentSource')),
        ),
        ...sources.map(
          (value) => SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, value.id.value),
            child: Text(value.name),
          ),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  final assigned = await finance.assignPaymentSource(transaction.id, sourceId);
  if (!context.mounted) return;
  if (assigned is ApplicationSuccess<TransactionDto>) {
    Navigator.of(context).pop(true);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('paymentSourceAssignError'))),
    );
  }
}

String _transactionDate(TransactionDto value, BuildContext context) =>
    transactionDateLabel(value, pendingLabel: context.l10n.text('datePending'));

String _shortDate(DateTime value) => shortDateLabel(value);
