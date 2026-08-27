import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
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
  String? _loadedLanguageCode;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _transactions = _load(languageCode: languageCode);
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_handleTransactionChange);
    super.dispose();
  }

  void _handleTransactionChange() {
    if (mounted) _refresh();
  }

  Future<_TransactionsData> _load({String? languageCode}) async {
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
    return _TransactionsData(
      values,
      await TransactionMasterData.load(
        finance,
        languageCode: languageCode ?? 'en',
      ),
    );
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
              tooltip: context.l10n.text('addTransaction'),
              onPressed: _openEditor,
              icon: const Icon(Icons.add_rounded),
            ),
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
                child: ButlerlySeparatedList(
                  children: visible
                      .map(
                        (value) => ButlerlyRecordRow(
                          title: value.description?.trim().isNotEmpty == true
                              ? value.description!
                              : context.l10n.text('untitledTransaction'),
                          subtitle: data.masterData.summary(value),
                          meta: _transactionDate(value, context),
                          amount: localizedTransactionAmount(
                            context,
                            value.amount,
                          ),
                          currency: value.currency,
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
  late final TextEditingController _notes;
  late DateTime _date;
  late TransactionDirection _direction;
  late String? _merchantId;
  late String? _categoryId;
  late String? _paymentSourceId;
  late Set<String> _tagIds;
  late Future<_EditorMasterData> _masterData;
  String _loadedLanguageCode = 'en';
  bool _dateChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(text: existing?.amount ?? '');
    _currency = TextEditingController(text: existing?.currency ?? 'USD');
    _description = TextEditingController(text: existing?.description ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _date = existing == null
        ? DateTime.now()
        : transactionCalendarDate(existing, fallback: DateTime.now());
    _direction = TransactionDirection.values.byName(
      existing?.direction ?? TransactionDirection.expense.name,
    );
    _merchantId = existing?.merchantId;
    _categoryId = existing?.categoryId;
    _paymentSourceId = existing?.paymentSourceId;
    _tagIds = {...?existing?.tagIds};
    _masterData = _loadMasterData(_loadedLanguageCode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (languageCode != _loadedLanguageCode) {
      _loadedLanguageCode = languageCode;
      _masterData = _loadMasterData(languageCode);
    }
  }

  Future<_EditorMasterData> _loadMasterData(String languageCode) async {
    final results = await Future.wait([
      widget.finance.listMerchants(),
      widget.finance.listCategories(),
      widget.finance.listTags(),
      widget.finance.listPaymentSources(),
    ]);
    final categoryLabels = switch (await widget.finance.loadMasterTranslations(
      masterType: 'category',
      locale: languageCode == 'zh' ? 'zh-Hans' : languageCode,
    )) {
      ApplicationSuccess<Map<String, String>>(:final value) => value,
      _ => const <String, String>{},
    };
    final tagLabels = switch (await widget.finance.loadMasterTranslations(
      masterType: 'tag',
      locale: languageCode == 'zh' ? 'zh-Hans' : languageCode,
    )) {
      ApplicationSuccess<Map<String, String>>(:final value) => value,
      _ => const <String, String>{},
    };
    return _EditorMasterData(
      merchants: results[0] is ApplicationSuccess<List<Merchant>>
          ? (results[0] as ApplicationSuccess<List<Merchant>>).value
          : const [],
      categories: results[1] is ApplicationSuccess<List<Category>>
          ? (results[1] as ApplicationSuccess<List<Category>>).value
          : const [],
      tags: results[2] is ApplicationSuccess<List<Tag>>
          ? (results[2] as ApplicationSuccess<List<Tag>>).value
          : const [],
      paymentSources: results[3] is ApplicationSuccess<List<PaymentSource>>
          ? (results[3] as ApplicationSuccess<List<PaymentSource>>).value
          : const [],
      categoryLabels: categoryLabels,
      tagLabels: tagLabels,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _description.dispose();
    _notes.dispose();
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
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              merchantId: _merchantId,
              categoryId: _categoryId,
              paymentSourceId: _paymentSourceId,
              tagIds: _tagIds.toList(growable: false),
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
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              merchantId: _merchantId,
              categoryId: _categoryId,
              paymentSourceId: _paymentSourceId,
              tagIds: _tagIds.toList(growable: false),
              replaceMerchant: true,
              replaceCategory: true,
              replacePaymentSource: true,
              replaceTags: true,
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? context.l10n.text('addTransaction')
              : context.l10n.text('editTransaction'),
        ),
      ),
      body: FutureBuilder<_EditorMasterData>(
        future: _masterData,
        initialData: const _EditorMasterData(
          merchants: [],
          categories: [],
          tags: [],
          paymentSources: [],
          categoryLabels: {},
          tagLabels: {},
        ),
        builder: (context, snapshot) {
          final data = snapshot.requireData;
          final selectedCategory = data.categories
              .where((value) => value.id.value == _categoryId)
              .firstOrNull;
          final selectedParentId =
              selectedCategory?.parentId?.value ??
              (selectedCategory != null && selectedCategory.parentId == null
                  ? selectedCategory.id.value
                  : null);
          final activeCategories = data.categories
              .where((value) => value.status == CategoryStatus.active)
              .toList(growable: false);
          return Form(
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                const SizedBox(height: ButlerlySpacing.standard),
                TextFormField(
                  controller: _notes,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('notesOptional'),
                    prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                ButlerlySelectField<String>(
                  label: context.l10n.text('merchant'),
                  value: _merchantId,
                  entries: [
                    for (final value in data.merchants.where(
                      (v) => v.status == MerchantStatus.active,
                    ))
                      DropdownMenuEntry(
                        value: value.id.value,
                        label: value.name,
                      ),
                  ],
                  onChanged: (value) => setState(() => _merchantId = value),
                  onCreate: () => _createMerchant(data),
                ),
                const SizedBox(height: 16),
                ButlerlySelectField<String>(
                  label: context.l10n.text('category'),
                  value: selectedParentId,
                  entries: [
                    for (final value in activeCategories.where(
                      (v) => v.parentId == null,
                    ))
                      DropdownMenuEntry(
                        value: value.id.value,
                        label:
                            data.categoryLabels[value.id.value] ?? value.name,
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 16),
                ButlerlySelectField<String>(
                  label: context.l10n.text('subcategory'),
                  value: selectedCategory?.parentId == null
                      ? null
                      : _categoryId,
                  entries: [
                    for (final value in activeCategories.where(
                      (v) => v.parentId?.value == selectedParentId,
                    ))
                      DropdownMenuEntry(
                        value: value.id.value,
                        label:
                            data.categoryLabels[value.id.value] ?? value.name,
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _categoryId = value ?? selectedParentId),
                ),
                const SizedBox(height: 16),
                ButlerlySelectField<String>(
                  label: context.l10n.text('paymentSource'),
                  value: _paymentSourceId,
                  entries: [
                    for (final value in data.paymentSources.where(
                      (v) => v.status == PaymentSourceStatus.active,
                    ))
                      DropdownMenuEntry(
                        value: value.id.value,
                        label: value.displayIdentity ?? value.name,
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _paymentSourceId = value),
                ),
                const SizedBox(height: 16),
                _TagSelector(
                  tags: data.tags
                      .where((v) => v.status == TagStatus.active)
                      .toList(),
                  labels: data.tagLabels,
                  selected: _tagIds,
                  onChanged: (value) => setState(() => _tagIds = value),
                  onCreate: () => _createTag(data),
                ),
                const SizedBox(height: ButlerlySpacing.section),
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
          );
        },
      ),
    );
  }

  Future<void> _createMerchant(_EditorMasterData data) async {
    final name = await _prompt(context, 'New merchant');
    if (name == null || !mounted) return;
    final existing = data.merchants
        .where(
          (merchant) =>
              merchant.status == MerchantStatus.active &&
              merchant.name.trim().toLowerCase() == name.trim().toLowerCase(),
        )
        .firstOrNull;
    if (existing != null) {
      setState(() => _merchantId = existing.id.value);
      return;
    }
    final value = Merchant(
      id: MerchantId('merchant-${DateTime.now().microsecondsSinceEpoch}'),
      name: name,
      rawName: name,
    );
    try {
      final result = await widget.finance.saveMerchant(value);
      if (!mounted) return;
      if (result is ApplicationSuccess<Merchant>) {
        setState(() {
          _merchantId = value.id.value;
          _masterData = _loadMasterData(_loadedLanguageCode);
        });
      } else {
        _showMasterDataError();
      }
    } catch (_) {
      if (mounted) _showMasterDataError();
    }
  }

  Future<void> _createTag(_EditorMasterData data) async {
    final name = await _prompt(context, 'New tag');
    if (name == null || !mounted) return;
    final value = Tag(
      id: TagId('tag-${DateTime.now().microsecondsSinceEpoch}'),
      name: name,
    );
    try {
      final result = await widget.finance.saveTag(value);
      if (!mounted) return;
      if (result is ApplicationSuccess<Tag>) {
        setState(() {
          _tagIds.add(value.id.value);
          _masterData = _loadMasterData(_loadedLanguageCode);
        });
      } else {
        _showMasterDataError();
      }
    } catch (_) {
      if (mounted) _showMasterDataError();
    }
  }

  void _showMasterDataError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.text('tagSaveFailed'))));
  }
}

final class _EditorMasterData {
  const _EditorMasterData({
    required this.merchants,
    required this.categories,
    required this.tags,
    required this.paymentSources,
    required this.categoryLabels,
    required this.tagLabels,
  });
  final List<Merchant> merchants;
  final List<Category> categories;
  final List<Tag> tags;
  final List<PaymentSource> paymentSources;
  final Map<String, String> categoryLabels;
  final Map<String, String> tagLabels;
}

class _TagSelector extends StatelessWidget {
  const _TagSelector({
    required this.tags,
    required this.labels,
    required this.selected,
    required this.onChanged,
    required this.onCreate,
  });
  final List<Tag> tags;
  final Map<String, String> labels;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.text('tags'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Wrap(
        spacing: ButlerlySpacing.compact,
        children: [
          for (final tag in tags)
            FilterChip(
              label: Text(labels[tag.id.value] ?? tag.name),
              selected: selected.contains(tag.id.value),
              onSelected: (checked) {
                final next = {...selected};
                checked ? next.add(tag.id.value) : next.remove(tag.id.value);
                onChanged(next);
              },
            ),
          ActionChip(
            label: Text(context.l10n.text('addTag')),
            avatar: const Icon(Icons.add),
            onPressed: onCreate,
          ),
        ],
      ),
    ],
  );
}

Future<String?> _prompt(BuildContext context, String title) async {
  final value = await showButlerlyBottomSheet<String>(
    context: context,
    builder: (context) => _PromptSheet(title: title),
  );
  return value?.trim().isEmpty == true ? null : value?.trim();
}

class _PromptSheet extends StatefulWidget {
  const _PromptSheet({required this.title});

  final String title;

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ButlerlySheet(
    title: Text(widget.title),
    content: TextField(controller: _controller, autofocus: true),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(context.l10n.text('save')),
      ),
    ],
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
    final evidenceResult = await finance.listEvidenceForTransaction(
      transaction.id,
    );
    if (evidenceResult is! ApplicationSuccess<List<EvidenceItem>>) {
      if (context.mounted) _showEvidenceCleanupFailure(context);
      return;
    }
    for (final evidence in evidenceResult.value) {
      if (!await services<LocalEvidenceStore>().remove(evidence)) {
        if (context.mounted) _showEvidenceCleanupFailure(context);
        return;
      }
    }
    await finance.deleteTransactionPermanently(transaction.id);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  void _showEvidenceCleanupFailure(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('evidenceCleanupFailed'))),
    );
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
              final refreshed = await finance.getTransaction(transaction.id);
              if (!context.mounted) return;
              if (refreshed case ApplicationSuccess<TransactionDto>(
                :final value,
              )) {
                setState(() => transaction = value);
              }
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
          '${localizedTransactionAmount(context, transaction.amount)} ${transaction.currency}',
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
              value:
                  '${localizedTransactionAmount(context, value.amount)} ${value.currency}',
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
        if (transaction.notes?.trim().isNotEmpty == true)
          _DetailRow(
            label: context.l10n.text('notes'),
            value: transaction.notes!,
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
          onPressed: () async {
            final assigned = await _assignPaymentSource(
              context,
              finance,
              transaction,
            );
            if (assigned != null && context.mounted) {
              setState(() => transaction = assigned);
            }
          },
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

class _EvidenceSection extends StatefulWidget {
  const _EvidenceSection({required this.finance, required this.transactionId});

  final FinanceServices finance;
  final String transactionId;

  @override
  State<_EvidenceSection> createState() => _EvidenceSectionState();
}

class _EvidenceSectionState extends State<_EvidenceSection> {
  late Future<List<EvidenceItem>> _evidence = _load();

  @override
  void initState() {
    super.initState();
    transactionChanges.addListener(_refreshFromTransactionChange);
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_refreshFromTransactionChange);
    super.dispose();
  }

  void _refreshFromTransactionChange() {
    if (!mounted) return;
    setState(() {
      _evidence = _load();
    });
  }

  Future<List<EvidenceItem>> _load() => widget.finance
      .listEvidenceForTransaction(widget.transactionId)
      .then(
        (result) => switch (result) {
          ApplicationSuccess<List<EvidenceItem>>(:final value) => value,
          ApplicationFailure<List<EvidenceItem>>() => throw StateError(
            'Evidence metadata could not be loaded.',
          ),
        },
      );

  Future<void> _attach() async {
    const types = XTypeGroup(
      label: 'Receipts and documents',
      extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp', 'pdf'],
    );
    final source = await openFile(acceptedTypeGroups: const [types]);
    if (source == null || !mounted) return;
    final stored = await services<LocalEvidenceStore>().attach(
      transactionId: widget.transactionId,
      source: source,
    );
    if (!mounted) return;
    if (stored) setState(() => _evidence = _load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.text(
            stored ? 'evidenceAttached' : 'evidenceAttachFailed',
          ),
        ),
      ),
    );
  }

  Future<void> _remove(EvidenceItem evidence) async {
    final confirmed = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(context.l10n.text('removeEvidenceTitle')),
        content: Text(context.l10n.text('removeEvidenceBody')),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await services<LocalEvidenceStore>().remove(evidence);
    if (mounted && removed) setState(() => _evidence = _load());
  }

  Future<void> _preview(EvidenceItem evidence) async {
    final file = await services<LocalEvidenceStore>().fileFor(evidence);
    final extractionResult = await widget.finance.getExtractionForEvidence(
      evidence.id.value,
    );
    final extraction = switch (extractionResult) {
      ApplicationSuccess<Extraction?>(:final value) => value,
      ApplicationFailure<Extraction?>() => null,
    };
    final exists = file != null && await file.exists();
    if (!mounted) return;
    if (!exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('evidenceFileMissing'))),
      );
      return;
    }
    final availableFile = file;
    final isImage = evidence.mediaType.startsWith('image/');
    final rawText =
        extraction?.values['rawText'] ??
        extraction?.provenance.originalRepresentation;
    await showButlerlyBottomSheet<void>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(evidence.originalName),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: ListView(
            shrinkWrap: true,
            children: [
              SizedBox(
                height: 360,
                child: isImage
                    ? InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.file(
                          availableFile,
                          semanticLabel: context.l10n.text('evidencePreview'),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              _EvidenceFileSummary(evidence: evidence),
                        ),
                      )
                    : _EvidenceFileSummary(evidence: evidence),
              ),
              const SizedBox(height: ButlerlySpacing.standard),
              Text(
                'Extracted text',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ButlerlySpacing.compact),
              if (rawText?.trim().isNotEmpty == true)
                SelectableText(rawText!)
              else
                Text(context.l10n.text('extractedTextUnavailable')),
              if (extraction != null) ...[
                const SizedBox(height: ButlerlySpacing.standard),
                Text(
                  'Confirmed extraction',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: ButlerlySpacing.compact),
                for (final entry in extraction.values.entries.where(
                  (entry) => entry.key != 'rawText',
                ))
                  _DetailRow(label: entry.key, value: entry.value),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('done')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EvidenceItem>>(
    future: _evidence,
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _attach,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(context.l10n.text('attachEvidence')),
            ),
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
                onTap: () => _preview(value),
                trailing: IconButton(
                  tooltip: context.l10n.text('remove'),
                  onPressed: () => _remove(value),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _EvidenceFileSummary extends StatelessWidget {
  const _EvidenceFileSummary({required this.evidence});

  final EvidenceItem evidence;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.text('evidencePreview'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.description_outlined, size: 64),
        const SizedBox(height: ButlerlySpacing.small),
        Text(evidence.originalName, textAlign: TextAlign.center),
        Text(evidence.mediaType, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: ButlerlySpacing.small),
        Text(
          context.l10n.text('evidenceStoredLocally'),
          textAlign: TextAlign.center,
        ),
      ],
    ),
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
  late Future<TransactionMasterData> _masterData;
  String? _languageCode;

  @override
  void initState() {
    super.initState();
    _masterData = Future.value(const TransactionMasterData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    _masterData = TransactionMasterData.load(
      widget.finance,
      languageCode: languageCode,
    );
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
            ..._categoryRows(context, data, transaction.categoryId),
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

List<Widget> _categoryRows(
  BuildContext context,
  TransactionMasterData data,
  String? categoryId,
) {
  final name = data.categoryName(categoryId);
  final parentId = data.categoryParentId(categoryId);
  if (parentId == null) {
    return [
      _DetailRow(
        label: context.l10n.text('category'),
        value: name ?? context.l10n.text('unavailableCategory'),
      ),
    ];
  }
  return [
    _DetailRow(
      label: context.l10n.text('category'),
      value:
          data.categoryName(parentId) ??
          context.l10n.text('unavailableCategory'),
    ),
    _DetailRow(
      label: context.l10n.text('subcategory'),
      value: name ?? context.l10n.text('unavailableCategory'),
    ),
  ];
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
}) => showButlerlyBottomSheet<bool>(
  context: context,
  builder: (context) => ButlerlySheet(
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
  final languageCode = Localizations.localeOf(context).languageCode;
  final categoryLabels = switch (await finance.loadMasterTranslations(
    masterType: 'category',
    locale: languageCode == 'zh' ? 'zh-Hans' : languageCode,
  )) {
    ApplicationSuccess<Map<String, String>>(:final value) => value,
    _ => const <String, String>{},
  };
  if (!context.mounted) return false;
  final merchantOptions = merchants
      .map((value) => _MasterDataOption(value.id.value, value.name))
      .toList(growable: false);
  String categoryName(Category value) =>
      categoryLabels[value.id.value] ?? value.name;
  final activeCategories = categories
      .where((value) => value.status == CategoryStatus.active)
      .toList(growable: false);
  List<_MasterDataOption> subcategoryOptions(String? parentId) =>
      activeCategories
          .where((value) => value.parentId?.value == parentId)
          .map(
            (value) => _MasterDataOption(value.id.value, categoryName(value)),
          )
          .toList(growable: false);
  final tagOptions = tags
      .map((value) => _MasterDataOption(value.id.value, value.name))
      .toList(growable: false);

  String? merchantId = transaction.merchantId;
  String? categoryId = transaction.categoryId;
  final selectedTagIds = transaction.tagIds.toSet();
  final initialCategory = activeCategories
      .where((value) => value.id.value == categoryId)
      .firstOrNull;
  String? parentCategoryId = initialCategory?.parentId?.value;
  return showButlerlyBottomSheet<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => ButlerlySheet(
        title: Text(dialogContext.l10n.text('organizeTransaction')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OrganizerMenuField(
                label: dialogContext.l10n.text('merchant'),
                icon: Icons.storefront_outlined,
                value: merchantId,
                placeholder: dialogContext.l10n.text('unassigned'),
                options: merchantOptions,
                includeUnassigned: true,
                onSelected: (value) => setDialogState(
                  () => merchantId = value.isEmpty ? null : value,
                ),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              _OrganizerMenuField(
                label: dialogContext.l10n.text('category'),
                icon: Icons.category_outlined,
                value: parentCategoryId ?? categoryId,
                placeholder: dialogContext.l10n.text('unassigned'),
                options: activeCategories
                    .where((value) => value.parentId == null)
                    .map(
                      (value) => _MasterDataOption(
                        value.id.value,
                        categoryName(value),
                      ),
                    )
                    .toList(growable: false),
                includeUnassigned: true,
                onSelected: (value) => setDialogState(() {
                  parentCategoryId = value.isEmpty ? null : value;
                  categoryId = parentCategoryId;
                }),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              if (subcategoryOptions(parentCategoryId).isNotEmpty)
                _OrganizerMenuField(
                  label: dialogContext.l10n.text('subcategory'),
                  icon: Icons.account_tree_outlined,
                  value:
                      parentCategoryId == null || categoryId == parentCategoryId
                      ? null
                      : categoryId,
                  placeholder: dialogContext.l10n.text('unassigned'),
                  options: subcategoryOptions(parentCategoryId),
                  includeUnassigned: true,
                  onSelected: (value) => setDialogState(
                    () => categoryId = value.isEmpty ? parentCategoryId : value,
                  ),
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
              _OrganizerMenuField(
                key: ValueKey(selectedTagIds.length),
                label: dialogContext.l10n.text('addTag'),
                icon: Icons.sell_outlined,
                placeholder: dialogContext.l10n.text('addTag'),
                options: tagOptions
                    .where((option) => !selectedTagIds.contains(option.id))
                    .toList(growable: false),
                onSelected: (value) {
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

class _OrganizerMenuField extends StatelessWidget {
  const _OrganizerMenuField({
    required this.label,
    required this.icon,
    required this.placeholder,
    required this.options,
    required this.onSelected,
    this.value,
    this.includeUnassigned = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String placeholder;
  final List<_MasterDataOption> options;
  final bool includeUnassigned;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => DropdownMenu<String>(
      initialSelection: value,
      width: constraints.maxWidth,
      menuHeight: 192,
      label: Text(label),
      leadingIcon: Icon(icon),
      hintText: placeholder,
      inputDecorationTheme: Theme.of(context).inputDecorationTheme,
      menuStyle: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(constraints.maxWidth, double.infinity),
        ),
        backgroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surface,
        ),
      ),
      dropdownMenuEntries: [
        if (includeUnassigned)
          DropdownMenuEntry<String>(
            value: '',
            label: context.l10n.text('unassigned'),
          ),
        for (final option in options)
          DropdownMenuEntry<String>(value: option.id, label: option.name),
      ],
      onSelected: (selected) => onSelected(selected ?? ''),
    ),
  );
}

String? _optionName(List<_MasterDataOption> options, String? id) {
  for (final option in options) {
    if (option.id == id) return option.name;
  }
  return null;
}

Future<TransactionDto?> _assignPaymentSource(
  BuildContext context,
  FinanceServices finance,
  TransactionDto transaction,
) async {
  final result = await finance.listPaymentSources();
  if (!context.mounted) return null;
  if (result is! ApplicationSuccess<List<PaymentSource>>) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('paymentSourcesLoadError'))),
    );
    return null;
  }
  final sources = result.value
      .where((value) => value.status == PaymentSourceStatus.active)
      .toList(growable: false);
  final sourceId = await showButlerlyBottomSheet<String?>(
    context: context,
    builder: (dialogContext) => ButlerlySheet(
      title: Text(dialogContext.l10n.text('assignPaymentSource')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => Navigator.pop(dialogContext),
            title: Text(dialogContext.l10n.text('noPaymentSource')),
          ),
          ...sources.map(
            (value) => ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(dialogContext, value.id.value),
              title: Text(value.name),
            ),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return null;
  final assigned = await finance.assignPaymentSource(transaction.id, sourceId);
  if (assigned is ApplicationSuccess<TransactionDto>) {
    notifyTransactionChanged();
    return assigned.value;
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('paymentSourceAssignError'))),
      );
    }
  }
  return null;
}

String _transactionDate(TransactionDto value, BuildContext context) =>
    transactionDateLabel(
      value,
      pendingLabel: context.l10n.text('datePending'),
      locale: Localizations.localeOf(context).toLanguageTag(),
    );

String _shortDate(DateTime value) => shortDateLabel(value);
