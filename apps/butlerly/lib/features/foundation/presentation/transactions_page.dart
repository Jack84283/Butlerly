import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_count_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    this.query = const ListTransactionsQuery(),
  });
  final ListTransactionsQuery query;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage>
    with SingleTickerProviderStateMixin {
  late Future<_TransactionsData> _transactions;
  late final TabController _tabController;
  _TransactionFilter _filter = _TransactionFilter.all;
  String? _loadedLanguageCode;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _TransactionFilter.values.length,
      vsync: this,
    );
    _transactions = Future.value(const _TransactionsData([]));
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
    _tabController.dispose();
    transactionChanges.removeListener(_handleTransactionChange);
    super.dispose();
  }

  void _handleTransactionChange() {
    if (mounted) _refresh();
  }

  Future<_TransactionsData> _load({String? languageCode}) async {
    final finance = _finance;
    if (finance == null) return const _TransactionsData([]);
    final activeLanguageCode =
        languageCode ??
        _loadedLanguageCode ??
        Localizations.localeOf(context).languageCode;
    final result = await finance.listTransactions(widget.query);
    final values = switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) => value,
      ApplicationFailure<List<TransactionDto>>() => throw StateError(
        'Transactions could not be loaded.',
      ),
    };
    return _TransactionsData(
      values,
      masterData: await TransactionMasterData.load(
        finance,
        languageCode: activeLanguageCode,
      ),
      paymentSourceNames: await _paymentSourceNames(finance),
      possibleDuplicateIds: await _possibleDuplicateIds(finance),
    );
  }

  Future<Map<String, String>> _paymentSourceNames(
    FinanceServices finance,
  ) async {
    final result = await finance.listPaymentSources();
    return switch (result) {
      ApplicationSuccess<List<PaymentSource>>(:final value) => {
        for (final source in value)
          source.id.value: source.lastFour == null
              ? source.name
              : '${source.name} ••••${source.lastFour}',
      },
      _ => const {},
    };
  }

  Future<Set<String>> _possibleDuplicateIds(FinanceServices finance) async {
    final list = finance.listDuplicateCandidateGroups;
    if (list == null) return const {};
    final result = await list();
    return switch (result) {
      ApplicationSuccess<List<DuplicateCandidateGroup>>(:final value) => {
        for (final group in value.where((group) => group.isUnresolved))
          for (final id in group.transactionIds) id.value,
      },
      ApplicationFailure<List<DuplicateCandidateGroup>>() => const {},
    };
  }

  void _refresh() {
    final reloaded = _load();
    setState(() {
      _transactions = reloaded;
    });
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
          return const ButlerlyLoadingState();
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
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: [
                Tab(text: context.l10n.text('all')),
                Tab(text: context.l10n.text('income')),
                Tab(text: context.l10n.text('expense')),
                Tab(text: context.l10n.text('archived')),
              ],
              onTap: (index) {
                final filter = _TransactionFilter.values[index];
                if (filter != _filter) setState(() => _filter = filter);
              },
            ),
            const SizedBox(height: ButlerlySpacing.section),
            if (values.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.receipt_long_outlined,
                title: context.l10n.text('noTransactions'),
                message: context.l10n.text('noTransactionsBody'),
                actionLabel: context.l10n.text('addData'),
                onAction: () => GoRouter.of(context).push('/add'),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TransactionCountText(count: visible.length),
                  const SizedBox(height: ButlerlySpacing.compact),
                  TransactionRecordList(
                    transactions: visible,
                    masterData: data.masterData,
                    paymentSourceNames: data.paymentSourceNames,
                    groupByFinancialDate: true,
                    possibleDuplicateIds: data.possibleDuplicateIds,
                    possibleDuplicateLabel: context.l10n.text(
                      'possibleDuplicate',
                    ),
                    onPossibleDuplicateTap: () =>
                        GoRouter.of(context).push('/review?view=duplicates'),
                    onTap: _openDetail,
                    navigates: true,
                  ),
                ],
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
    this.transactions, {
    this.masterData = const TransactionMasterData(),
    this.paymentSourceNames = const {},
    this.possibleDuplicateIds = const {},
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final Set<String> possibleDuplicateIds;
}

sealed class TransactionEditorResult {
  const TransactionEditorResult();
  const factory TransactionEditorResult.saved(TransactionDto transaction) =
      TransactionEditorSaved;
  const factory TransactionEditorResult.cancelled() =
      TransactionEditorCancelled;
  const factory TransactionEditorResult.useExisting(String transactionId) =
      TransactionEditorUseExisting;
}

final class TransactionEditorSaved extends TransactionEditorResult {
  const TransactionEditorSaved(this.transaction);
  final TransactionDto transaction;
}

final class TransactionEditorCancelled extends TransactionEditorResult {
  const TransactionEditorCancelled();
}

final class TransactionEditorUseExisting extends TransactionEditorResult {
  const TransactionEditorUseExisting(this.transactionId);
  final String transactionId;
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
    final snapshot = await TransactionMasterDataProvider(
      widget.finance,
    ).load(languageCode: languageCode);
    return _EditorMasterData.fromSnapshot(snapshot);
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
    final money = Money(
      amount: DecimalValue.parse(_amount.text.trim()),
      currency: CurrencyCode(_currency.text.trim()),
    );
    final existing = widget.existing;
    final proposed = TransactionDto(
      id: existing?.id ?? '__proposed__',
      amount: money.amount.toString(),
      currency: money.currency.value,
      direction: _direction.name,
      status: TransactionStatus.active.name,
      reviewState: TransactionReviewState.clear.name,
      transactionDate: _shortDate(_date),
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      paymentSourceId: _paymentSourceId,
      merchantId: _merchantId,
      categoryId: _categoryId,
      tagIds: _tagIds.toList(growable: false),
    );
    final duplicate = await widget.finance.duplicateTransactionChecker.call(
      DuplicateTransactionCheckCommand(
        transactionDate: proposed.transactionDate!,
        amount: proposed.amount,
        currency: proposed.currency,
        direction: _direction,
        excludeTransactionId: existing?.id,
        paymentSourceId: _paymentSourceId,
        merchantId: _merchantId,
      ),
    );
    if (!mounted) return;
    if (duplicate case ApplicationSuccess<DuplicateTransactionCheckResult>(
      value: final check,
    ) when check.requiresConfirmation) {
      final editorData = await _masterData;
      if (!mounted) return;
      final decision =
          await showButlerlyBottomSheet<ButlerlyDuplicateConfirmationResult>(
            context: context,
            builder: (dialogContext) => ButlerlyDuplicateTransactionConfirmation(
              proposed: proposed,
              candidates: check.candidates,
              paymentSourceLabels: {
                for (final source in editorData.paymentSources)
                  source.id.value: source.lastFour == null
                      ? (source.displayIdentity ?? source.name)
                      : '${source.displayIdentity ?? source.name} ••••${source.lastFour}',
              },
              onDecision: (value) => Navigator.pop(dialogContext, value),
            ),
          );
      if (!mounted || decision == null) {
        return;
      }
      if (decision.decision == ButlerlyDuplicateDecision.useExisting) {
        final selectedId = decision.selectedTransactionId;
        if (selectedId != null) {
          Navigator.of(
            context,
          ).pop(TransactionEditorResult.useExisting(selectedId));
        }
        return;
      }
      if (decision.decision == ButlerlyDuplicateDecision.cancel) return;
    }
    setState(() => _saving = true);
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
    if (result case ApplicationSuccess<TransactionDto>(value: final saved)) {
      Navigator.of(context).pop(TransactionEditorResult.saved(saved));
    }
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
          return Form(
            key: _formKey,
            child: ListView(
              // The editor's wider inset keeps the final action reachable in
              // the established form layout at compact test and phone sizes.
              padding: const EdgeInsets.all(24),
              children: [
                ButlerlyDirectionSelector(
                  value: _direction,
                  expenseLabel: context.l10n.text('expense'),
                  incomeLabel: context.l10n.text('income'),
                  onChanged: (value) => setState(() => _direction = value),
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
                const SizedBox(height: ButlerlySpacing.standard),
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
                const SizedBox(height: ButlerlySpacing.standard),
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
                const SizedBox(height: ButlerlySpacing.standard),
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
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlyMerchantSelector(
                  label: context.l10n.text('merchant'),
                  clearLabel: context.l10n.text('clear'),
                  merchants: data.merchants,
                  value: _merchantId,
                  onChanged: (value) => setState(() => _merchantId = value),
                  onCreate: () => _createMerchant(data),
                  createTooltip: context.l10n.text('merchant'),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlyCategorySelector(
                  label: context.l10n.text('category'),
                  clearLabel: context.l10n.text('clear'),
                  categories: data.categories,
                  masterData: TransactionMasterData(
                    categoryNames: data.categoryLabels,
                    tagNames: data.tagLabels,
                  ),
                  value: selectedParentId,
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlySubcategorySelector(
                  label: context.l10n.text('subcategory'),
                  clearLabel: context.l10n.text('clear'),
                  categories: data.categories,
                  masterData: TransactionMasterData(
                    categoryNames: data.categoryLabels,
                    tagNames: data.tagLabels,
                  ),
                  parentId: selectedParentId,
                  value: selectedCategory?.parentId == null
                      ? null
                      : _categoryId,
                  onChanged: (value) =>
                      setState(() => _categoryId = value ?? selectedParentId),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlyPaymentSourceSelector(
                  label: context.l10n.text('paymentSource'),
                  clearLabel: context.l10n.text('clear'),
                  sources: data.paymentSources,
                  value: _paymentSourceId,
                  onChanged: (value) =>
                      setState(() => _paymentSourceId = value),
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.text('tags'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    ButlerlyTagPicker(
                      searchLabel: context.l10n.text('search'),
                      createLabel: context.l10n.text('addTag'),
                      tags: data.tags,
                      masterData: TransactionMasterData(
                        categoryNames: data.categoryLabels,
                        tagNames: data.tagLabels,
                      ),
                      selected: _tagIds,
                      onChanged: (value) => setState(() => _tagIds = value),
                      onCreate: () => _createTag(data),
                    ),
                  ],
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

  factory _EditorMasterData.fromSnapshot(
    TransactionMasterDataSnapshot snapshot,
  ) => _EditorMasterData(
    merchants: snapshot.merchants,
    categories: snapshot.categories,
    tags: snapshot.tags,
    paymentSources: snapshot.paymentSources,
    categoryLabels: snapshot.presentation.categoryNames,
    tagLabels: snapshot.presentation.tagNames,
  );

  final List<Merchant> merchants;
  final List<Category> categories;
  final List<Tag> tags;
  final List<PaymentSource> paymentSources;
  final Map<String, String> categoryLabels;
  final Map<String, String> tagLabels;
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
  bool _changed = false;

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
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && context.mounted) {
        Navigator.of(context).pop(_changed);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('transactionDetail')),
        actions: [
          IconButton(
            tooltip: context.l10n.text('editTransaction'),
            onPressed: () async {
              final changed = await Navigator.of(context)
                  .push<TransactionEditorResult>(
                    MaterialPageRoute(
                      builder: (_) => TransactionEditorPage(
                        finance: finance,
                        existing: transaction,
                      ),
                    ),
                  );
              if ((changed is TransactionEditorSaved ||
                      changed is TransactionEditorUseExisting) &&
                  context.mounted) {
                _changed = true;
                final refreshed = await finance.getTransaction(transaction.id);
                if (!context.mounted) return;
                if (refreshed case ApplicationSuccess<TransactionDto>(
                  :final value,
                )) {
                  setState(() {
                    transaction = value;
                    _changed = true;
                  });
                }
              }
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${localizedTransactionAmount(context, transaction.amount)} ${transaction.currency}',
                  textAlign: TextAlign.center,
                  style: context.transactionDetailAmount,
                ),
                const SizedBox(height: ButlerlySpacing.micro),
                Text(
                  transaction.description ??
                      context.l10n.text('untitledTransaction'),
                  textAlign: TextAlign.center,
                  style: context.transactionDetailDescription,
                ),
              ],
            ),
          ),
          if (transaction.normalizedMoney.isNotEmpty) ...[
            const SizedBox(height: ButlerlySpacing.compact),
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
          const SizedBox(height: ButlerlySpacing.section),
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
            const SizedBox(height: ButlerlySpacing.standard),
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
          const SizedBox(height: ButlerlySpacing.standard),
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
          const SizedBox(height: ButlerlySpacing.section),
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
                  setState(() {
                    transaction = value;
                    _changed = true;
                  });
                }
              }
            },
            icon: const Icon(Icons.sell_outlined),
            label: Text(context.l10n.text('organizeTransaction')),
          ),
          const SizedBox(height: ButlerlySpacing.small),
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
          const SizedBox(height: ButlerlySpacing.small),
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
          const SizedBox(height: ButlerlySpacing.small),
          ButlerlyDestructiveButton(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_forever_outlined),
            child: Text(context.l10n.text('deletePermanently')),
          ),
        ],
      ),
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
                title: value.mediaType.startsWith('image/')
                    ? ButlerlySecondaryTextAction(
                        onPressed: () => _preview(value),
                        child: Text(context.l10n.text('viewImage')),
                      )
                    : Text(value.originalName),
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
            ButlerlyReadOnlyTagList(
              tagIds: transaction.tagIds.map((id) => id),
              masterData: data,
              label: context.l10n.text('tags'),
              unavailableLabel: context.l10n.text('unavailableTag'),
              compact: true,
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
      destructive
          ? ButlerlyDestructiveButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.text('deletePermanently')),
            )
          : FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.text('archive')),
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
  final presentation = await TransactionMasterData.load(
    finance,
    languageCode: languageCode,
  );
  if (!context.mounted) return false;
  final activeCategories = categories
      .where((value) => value.status == CategoryStatus.active)
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
              ButlerlyMerchantSelector(
                merchants: merchants,
                value: merchantId,
                label: dialogContext.l10n.text('merchant'),
                clearLabel: dialogContext.l10n.text('clear'),
                onChanged: (value) => setDialogState(() => merchantId = value),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              ButlerlyCategorySelector(
                categories: activeCategories,
                masterData: presentation,
                value: parentCategoryId,
                label: dialogContext.l10n.text('category'),
                clearLabel: dialogContext.l10n.text('clear'),
                onChanged: (value) => setDialogState(() {
                  parentCategoryId = value;
                  categoryId = value;
                }),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              ButlerlySubcategorySelector(
                categories: activeCategories,
                masterData: presentation,
                parentId: parentCategoryId,
                value: categoryId == parentCategoryId ? null : categoryId,
                label: dialogContext.l10n.text('subcategory'),
                clearLabel: dialogContext.l10n.text('clear'),
                onChanged: (value) => setDialogState(
                  () => categoryId = value ?? parentCategoryId,
                ),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              ButlerlyTagPicker(
                tags: tags,
                masterData: presentation,
                selected: selectedTagIds,
                searchLabel: dialogContext.l10n.text('search'),
                createLabel: dialogContext.l10n.text('addTag'),
                onChanged: (value) => setDialogState(() {
                  selectedTagIds
                    ..clear()
                    ..addAll(value);
                }),
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
              final result = await finance.updateTransaction(
                UpdateTransactionCommand(
                  id: transaction.id,
                  timing: transaction.occurredAt == null
                      ? const UnknownTransactionTime(
                          UnknownTransactionTimeReason.unknown,
                        )
                      : KnownTransactionTime(transaction.occurredAt!),
                  money: Money(
                    amount: DecimalValue.parse(transaction.amount),
                    currency: CurrencyCode(transaction.currency),
                  ),
                  direction: TransactionDirection.values.byName(
                    transaction.direction,
                  ),
                  transactionDate: transaction.transactionDate,
                  timeZoneId: transaction.timeZoneId,
                  description: transaction.description,
                  notes: transaction.notes,
                  externalReference: transaction.externalReference,
                  paymentSourceId: transaction.paymentSourceId,
                  merchantId: merchantId,
                  categoryId: categoryId,
                  tagIds: selectedTagIds.toList(growable: false),
                  replaceMerchant: true,
                  replaceCategory: true,
                  replaceTags: true,
                ),
              );
              if (!dialogContext.mounted) return;
              if (result is ApplicationFailure) {
                _organizationFailed(dialogContext);
                return;
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

void _organizationFailed(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.text('dataPreserved'))));
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
