import 'dart:async';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
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

class _TransactionsPageState extends State<TransactionsPage> {
  late Future<_TransactionsData> _transactions;
  final TextEditingController _search = TextEditingController();
  String? _currency;
  TransactionDirection? _direction;
  TransactionStatus? _status;
  String? _categoryId;
  String? _paymentSourceId;
  bool? _needsReview;
  bool _includeUndated = false;
  late DateTime? _from;
  late DateTime? _to;
  late Future<TransactionMasterDataSnapshot> _filterMasterData;
  late Future<List<String>> _currencies;
  String? _loadedLanguageCode;
  int _loadGeneration = 0;
  bool _hasLoadedTransactions = false;
  bool _defaultPeriodResolved = false;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _currency = widget.query.currency;
    _direction = widget.query.direction;
    _status = widget.query.status;
    _categoryId = widget.query.categoryId;
    _paymentSourceId = widget.query.paymentSourceId;
    _needsReview = widget.query.needsReview;
    _from = widget.query.from ?? DateTime.utc(now.year, now.month - 3, 1);
    _to = widget.query.to ?? DateTime.utc(now.year, now.month, now.day);
    _includeUndated = widget.query.includeUndated;
    _transactions = Future.value(const _TransactionsData([]));
    transactionChanges.addListener(_handleTransactionChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _filterMasterData = _loadFilterMasterData(languageCode);
    final generation = ++_loadGeneration;
    _transactions = _load(languageCode: languageCode).then((data) {
      if (generation == _loadGeneration) {
        _hasLoadedTransactions = true;
      }
      return data;
    });
    _currencies = _transactions.then((data) {
      final currencies = data.transactions
          .map((transaction) => transaction.currency)
          .toSet()
          .toList();
      currencies.sort();
      return currencies;
    });
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_handleTransactionChange);
    _search.dispose();
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
    await _ensureDefaultPeriod(finance);
    final result = await finance.listTransactions(_repositoryQuery());
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

  Future<void> _ensureDefaultPeriod(FinanceServices finance) async {
    if (_defaultPeriodResolved) return;
    _defaultPeriodResolved = true;
    if (widget.query.from != null || widget.query.to != null) return;

    final result = await finance.resolveHomePeriod(instant: DateTime.now());
    if (result case ApplicationSuccess<HomePeriodResolution>(:final value)) {
      final end = DateTime.parse(value.period.endDate);
      _from = DateTime.utc(end.year, end.month - 3, 1);
      _to = DateTime.utc(end.year, end.month, end.day);
    }
  }

  Future<TransactionMasterDataSnapshot> _loadFilterMasterData(
    String languageCode,
  ) async {
    final finance = _finance;
    if (finance == null) {
      return const TransactionMasterDataSnapshot(
        presentation: TransactionMasterData(),
        merchants: [],
        categories: [],
        tags: [],
        paymentSources: [],
      );
    }
    return TransactionMasterDataProvider(
      finance,
    ).load(languageCode: languageCode);
  }

  Future<Map<String, String>> _paymentSourceNames(
    FinanceServices finance,
  ) async {
    final result = await finance.listPaymentSources();
    return switch (result) {
      ApplicationSuccess<List<PaymentSource>>(:final value) => {
        for (final source in value)
          source.id.value: paymentSourceDisplayLabel(source),
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

  Future<void> _refresh() async {
    final generation = ++_loadGeneration;
    final reloaded = _load();
    if (!_hasLoadedTransactions) {
      final tracked = reloaded.then((data) {
        if (generation == _loadGeneration) {
          _hasLoadedTransactions = true;
        }
        return data;
      });
      setState(() {
        _transactions = tracked;
      });
      try {
        await tracked;
      } catch (_) {
        // FutureBuilder owns the initial-load error presentation.
      }
      return;
    }
    try {
      final data = await reloaded;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = Future.value(data);
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
    }
  }

  ListTransactionsQuery _repositoryQuery() => ListTransactionsQuery(
    text: widget.query.text,
    transactionIds: widget.query.transactionIds,
    from: _from,
    to: _to,
    timeZoneId: widget.query.timeZoneId,
    categoryId: _categoryId,
    paymentSourceId: _paymentSourceId,
    currency: _currency,
    direction: _direction,
    status: _status,
    needsReview: _needsReview,
    uncategorized: widget.query.uncategorized,
    includeUndated: _includeUndated,
  );

  bool _matchesFilters(TransactionDto transaction, _TransactionsData data) {
    final query = _search.text.trim().toLowerCase();
    final date = _calendarDate(
      transactionCalendarDate(transaction, fallback: DateTime.utc(1970)),
    );
    final from = _from == null ? null : _calendarDate(_from!);
    final to = _to == null ? null : _calendarDate(_to!);
    final isTrulyUndated =
        (transaction.transactionDate == null ||
            transaction.transactionDate!.trim().isEmpty) &&
        transaction.occurredAt == null;
    if (!(_includeUndated && isTrulyUndated)) {
      if (from != null && date.isBefore(from)) return false;
      if (to != null && date.isAfter(to)) return false;
    }
    if (_currency != null && transaction.currency != _currency) return false;
    if (_direction != null && transaction.direction != _direction!.name) {
      return false;
    }
    if (_status != null && transaction.status != _status!.name) return false;
    if (_categoryId != null && transaction.categoryId != _categoryId) {
      return false;
    }
    if (_paymentSourceId != null &&
        transaction.paymentSourceId != _paymentSourceId) {
      return false;
    }
    if (_needsReview == true &&
        transaction.reviewState != TransactionReviewState.needsReview.name) {
      return false;
    }
    if (query.isEmpty) return true;

    final searchable = <String?>[
      transaction.description,
      transaction.rawCounterparty,
      transaction.amount,
      transaction.currency,
      transaction.transactionDate,
      data.masterData.merchantName(transaction.merchantId),
      data.masterData.categoryName(transaction.categoryId),
      data.masterData.subcategoryName(transaction.subcategoryId),
      data.masterData.paymentSourceName(transaction.paymentSourceId),
      data.paymentSourceNames[transaction.paymentSourceId],
      ...transaction.tagIds.map(data.masterData.tagName),
    ];
    return searchable.whereType<String>().any(
      (value) => value.toLowerCase().contains(query),
    );
  }

  DateTime _calendarDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  int get _activeFilterCount => [
    _currency,
    _direction,
    _status,
    _categoryId,
    _paymentSourceId,
    _needsReview,
    if (_includeUndated) true,
    _from,
    _to,
  ].where((value) => value != null).length;

  void _clearFilters() {
    setState(() {
      _currency = null;
      _direction = null;
      _status = null;
      _categoryId = null;
      _paymentSourceId = null;
      _needsReview = null;
      _includeUndated = false;
      _from = null;
      _to = null;
    });
    unawaited(_refresh());
  }

  Future<void> _openFilters() async {
    await showButlerlyBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ButlerlyTransactionFilterSheet(
        value: ButlerlyTransactionFilterValue(
          currency: _currency,
          direction: _direction,
          status: _status,
          categoryId: _categoryId,
          paymentSourceId: _paymentSourceId,
          needsReview: _needsReview,
          includeUndated: _includeUndated,
          from: _from,
          to: _to,
        ),
        currencies: _currencies,
        masterData: _filterMasterData,
        formatDate: _transactionFilterDate,
        onApply: (value) {
          setState(() {
            _currency = value.currency;
            _direction = value.direction;
            _status = value.status;
            _categoryId = value.categoryId;
            _paymentSourceId = value.paymentSourceId;
            _needsReview = value.needsReview;
            _includeUndated = value.includeUndated;
            _from = value.from;
            _to = value.to;
          });
          unawaited(_refresh());
          Navigator.pop(sheetContext);
        },
        onClear: () {
          Navigator.pop(sheetContext);
          _clearFilters();
        },
      ),
    );
  }

  Widget _transactionSearchControls(BuildContext context) =>
      ButlerlyTransactionSearchControls(
        controlsKey: const ValueKey('transactions-pinned-controls'),
        searchFieldKey: const ValueKey('transactions-search-field'),
        controller: _search,
        activeFilterCount: _activeFilterCount,
        onSearch: () => setState(() {}),
        onChanged: (_) => setState(() {}),
        onClear: () {
          _search.clear();
          setState(() {});
        },
        onFilter: _openFilters,
      );

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
            .where((value) => _matchesFilters(value, data))
            .toList(growable: false);
        return ButlerlyPage(
          title: context.l10n.text('transactions'),
          onRefresh: _refresh,
          refreshKey: const ValueKey('transactions-pull-to-refresh'),
          pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
          pinnedHeaderExtent: ButlerlySize.searchPinnedHeaderHeight,
          pinnedHeader: _transactionSearchControls(context),
          children: [
            if (values.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.receipt_long_outlined,
                title: context.l10n.text('noTransactions'),
                message: context.l10n.text('noTransactionsBody'),
                actionLabel: context.l10n.text('addData'),
                onAction: () => GoRouter.of(context).push('/add'),
              )
            else ...[
              if (visible.isEmpty)
                ButlerlyEmptyState(
                  icon: Icons.search_off_rounded,
                  title: context.l10n.text('noResults'),
                  message: context.l10n.text('noResultsBody'),
                  actionLabel: _search.text.trim().isNotEmpty
                      ? context.l10n.text('clearSearch')
                      : context.l10n.text('clearFilters'),
                  onAction: () {
                    if (_search.text.trim().isNotEmpty) {
                      _search.clear();
                      setState(() {});
                    } else {
                      _clearFilters();
                    }
                  },
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        TransactionCountText(count: visible.length),
                        const SizedBox(width: ButlerlySpacing.compact),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              _transactionsTotalAmount(context, visible),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ButlerlySpacing.compact),
                    TransactionRecordList(
                      transactions: visible,
                      masterData: data.masterData,
                      paymentSourceNames: data.paymentSourceNames,
                      groupByFinancialDate: true,
                      collapsibleMonthSections: true,
                      monthSectionsAsCards: true,
                      dashboardRowStyle: true,
                      missingCategoryLabel: context.l10n.text('uncategorized'),
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
            ],
            const SizedBox(height: ButlerlySpacing.structural),
          ],
        );
      },
    );
  }
}

String _transactionFilterDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _transactionsTotalAmount(
  BuildContext context,
  List<TransactionDto> transactions,
) {
  final totals = <String, List<DecimalValue>>{};
  for (final transaction in transactions) {
    final currency = transaction.currency.trim().toUpperCase();
    if (currency.isEmpty) continue;
    final amount = DecimalValue.parse(
      transaction.amount.replaceFirst(RegExp(r'^[+-]'), ''),
    );
    totals.putIfAbsent(currency, () => []).add(amount);
  }

  final entries = totals.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map(
        (entry) => localizedCompactMoney(
          context,
          DecimalValue.sum(entry.value).toString(),
          entry.key,
        ),
      )
      .join(' · ');
}

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
  late String? _subcategoryId;
  late String? _paymentSourceId;
  late Set<String> _tagIds;
  late Future<_EditorMasterData> _masterData;
  String _loadedLanguageCode = 'en';
  bool _dateChanged = false;
  bool _saving = false;
  bool _classificationOverridden = false;
  int _classificationRequest = 0;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _classificationOverridden = existing != null;
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
    _subcategoryId = existing?.subcategoryId;
    _paymentSourceId = existing?.paymentSourceId;
    _tagIds = {...?existing?.tagIds};
    _description.addListener(_handleDescriptionChanged);
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
    final data = _EditorMasterData.fromSnapshot(snapshot);
    _normalizeClassification(data);
    return data;
  }

  void _normalizeClassification(_EditorMasterData data) {
    if (widget.existing == null) return;

    if (_subcategoryId == null) {
      if (_categoryId == null) return;
      final category = data.categories
          .where((value) => value.id.value == _categoryId)
          .firstOrNull;
      final parentId = category?.parentId?.value;
      if (parentId == null) return;
      _subcategoryId = _categoryId;
      _categoryId = parentId;
      return;
    }

    final subcategory = data.categories
        .where((value) => value.id.value == _subcategoryId)
        .firstOrNull;
    if (subcategory == null) return;

    final parentId = subcategory.parentId?.value;
    if (parentId == null) {
      _subcategoryId = null;
      return;
    }
    if (_categoryId == null) {
      _categoryId = parentId;
      return;
    }
    if (parentId != _categoryId) {
      _subcategoryId = null;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _description.removeListener(_handleDescriptionChanged);
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _handleDescriptionChanged() {
    if (_classificationOverridden) return;
    unawaited(_refreshClassification());
  }

  Future<void> _refreshClassification() async {
    final request = ++_classificationRequest;
    final result = await widget.finance.proposeTransactionClassification(
      merchantId: _merchantId == null ? null : MerchantId(_merchantId!),
      description: _description.text.trim(),
      excludeTransactionId: widget.existing == null
          ? null
          : TransactionId(widget.existing!.id),
    );
    if (!mounted ||
        request != _classificationRequest ||
        _classificationOverridden) {
      return;
    }
    if (result case ApplicationSuccess<ClassificationProposal>(
      value: final proposal,
    )) {
      setState(() {
        if (_merchantId == null && proposal.merchantId != null) {
          _merchantId = proposal.merchantId!.value;
        }
        _categoryId = proposal.categoryId?.value;
        _subcategoryId = proposal.subcategoryId?.value;
      });
    }
  }

  Future<void> _selectMerchant(String? value) async {
    setState(() => _merchantId = value);
    if (!_classificationOverridden) await _refreshClassification();
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
      subcategoryId: _subcategoryId,
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
            builder: (dialogContext) =>
                ButlerlyDuplicateTransactionConfirmation(
                  proposed: proposed,
                  candidates: check.candidates,
                  paymentSourceLabels: {
                    for (final source in editorData.paymentSources)
                      source.id.value: paymentSourceDisplayLabel(source),
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
              subcategoryId: _subcategoryId,
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
              subcategoryId: _subcategoryId,
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
      body: ButlerlyResponsiveBody(
        contentKey: const ValueKey('transaction-editor-content'),
        child: FutureBuilder<_EditorMasterData>(
          future: _masterData,
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
                onAction: () => setState(() {
                  _masterData = _loadMasterData(_loadedLanguageCode);
                }),
              );
            }
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
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      key: const ValueKey('transaction-editor-list'),
                      // Keep the final field clear of the persistent action.
                      padding: const EdgeInsets.fromLTRB(
                        ButlerlySpacing.pagePadding,
                        ButlerlySpacing.compact,
                        ButlerlySpacing.pagePadding,
                        ButlerlySpacing.bottomActionSpacing,
                      ),
                      children: [
                        ButlerlyCard(
                          key: const ValueKey(
                            'transaction-editor-financial-card',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TransactionEditorCardHeader(
                                icon: Icons.payments_outlined,
                                title: context.l10n.text('amount'),
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final amountField = TextFormField(
                                    key: const ValueKey(
                                      'transaction-amount-field',
                                    ),
                                    controller: _amount,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                    decoration: InputDecoration(
                                      labelText: context.l10n.text('amount'),
                                      prefixIcon: const Icon(
                                        Icons.payments_outlined,
                                      ),
                                    ),
                                    validator: (value) {
                                      try {
                                        DecimalValue.parse(value?.trim() ?? '');
                                        return null;
                                      } on DomainValidationException {
                                        return context.l10n.text(
                                          'invalidAmount',
                                        );
                                      }
                                    },
                                  );
                                  final currencyField = TextFormField(
                                    key: const ValueKey(
                                      'transaction-currency-field',
                                    ),
                                    controller: _currency,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      labelText: context.l10n.text('currency'),
                                    ),
                                    validator: (value) {
                                      try {
                                        CurrencyCode(value?.trim() ?? '');
                                        return null;
                                      } on DomainValidationException {
                                        return context.l10n.text(
                                          'invalidCurrency',
                                        );
                                      }
                                    },
                                  );
                                  if (constraints.maxWidth < 280) {
                                    return Column(
                                      children: [
                                        amountField,
                                        const SizedBox(
                                          height: ButlerlySpacing.standard,
                                        ),
                                        currencyField,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: amountField),
                                      const SizedBox(
                                        width: ButlerlySpacing.compact,
                                      ),
                                      SizedBox(
                                        width: 112,
                                        child: currencyField,
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              ButlerlyDirectionSelector(
                                value: _direction,
                                expenseLabel: context.l10n.text('expense'),
                                incomeLabel: context.l10n.text('income'),
                                onChanged: (value) =>
                                    setState(() => _direction = value),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ButlerlySpacing.cardGap),
                        ButlerlyCard(
                          key: const ValueKey(
                            'transaction-editor-organization-card',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TransactionEditorCardHeader(
                                icon: Icons.receipt_long_outlined,
                                title: context.l10n.text('transactionDetail'),
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              ButlerlyMerchantSelector(
                                key: const ValueKey(
                                  'transaction-merchant-selector',
                                ),
                                label: context.l10n.text('merchant'),
                                clearLabel: context.l10n.text('clear'),
                                merchants: data.merchants,
                                value: _merchantId,
                                onChanged: _selectMerchant,
                                onCreate: () => _createMerchant(data),
                                createTooltip: context.l10n.text('merchant'),
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              ButlerlyCategorySelector(
                                key: const ValueKey(
                                  'transaction-category-selector',
                                ),
                                label: context.l10n.text('category'),
                                clearLabel: context.l10n.text('clear'),
                                categories: data.categories,
                                masterData: TransactionMasterData(
                                  categoryNames: data.categoryLabels,
                                  tagNames: data.tagLabels,
                                ),
                                value: selectedParentId,
                                onChanged: (value) => setState(() {
                                  _classificationOverridden = true;
                                  _categoryId = value;
                                  _subcategoryId = null;
                                }),
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              ButlerlySubcategorySelector(
                                key: const ValueKey(
                                  'transaction-subcategory-selector',
                                ),
                                label: context.l10n.text('subcategory'),
                                clearLabel: context.l10n.text('clear'),
                                categories: data.categories,
                                masterData: TransactionMasterData(
                                  categoryNames: data.categoryLabels,
                                  tagNames: data.tagLabels,
                                ),
                                parentId: selectedParentId,
                                value: _subcategoryId,
                                onChanged: (value) => setState(() {
                                  _classificationOverridden = true;
                                  _subcategoryId = value;
                                  _categoryId = selectedParentId;
                                }),
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              ButlerlyPaymentSourceSelector(
                                key: const ValueKey(
                                  'transaction-payment-source-selector',
                                ),
                                label: context.l10n.text('paymentSource'),
                                clearLabel: context.l10n.text('clear'),
                                sources: data.paymentSources,
                                value: _paymentSourceId,
                                onChanged: (value) =>
                                    setState(() => _paymentSourceId = value),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ButlerlySpacing.cardGap),
                        ButlerlyCard(
                          key: const ValueKey('transaction-editor-date-card'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TransactionEditorCardHeader(
                                icon: Icons.calendar_month_outlined,
                                title: context.l10n.text('date'),
                              ),
                              const SizedBox(height: ButlerlySpacing.compact),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(context.l10n.text('date')),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      MaterialLocalizations.of(
                                        context,
                                      ).formatMediumDate(_date),
                                    ),
                                    const SizedBox(
                                      width: ButlerlySpacing.small,
                                    ),
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      color: _transactionCardIconColor(context),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  final selected = await showButlerlyDatePicker(
                                    context: context,
                                    title: context.l10n.text('date'),
                                    cancelLabel: context.l10n.text('cancel'),
                                    doneLabel: context.l10n.text('done'),
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
                            ],
                          ),
                        ),
                        const SizedBox(height: ButlerlySpacing.cardGap),
                        ButlerlyCard(
                          key: const ValueKey(
                            'transaction-editor-description-card',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TransactionEditorCardHeader(
                                icon: Icons.notes_rounded,
                                title: context.l10n.text('notes'),
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              TextFormField(
                                key: const ValueKey(
                                  'transaction-description-field',
                                ),
                                controller: _description,
                                decoration: InputDecoration(
                                  labelText: context.l10n.text(
                                    'descriptionOptional',
                                  ),
                                  prefixIcon: const Icon(Icons.notes_rounded),
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
                              TextFormField(
                                key: const ValueKey('transaction-notes-field'),
                                controller: _notes,
                                decoration: InputDecoration(
                                  labelText: context.l10n.text('notesOptional'),
                                  prefixIcon: const Icon(
                                    Icons.sticky_note_2_outlined,
                                  ),
                                ),
                                maxLines: 3,
                              ),
                              const SizedBox(height: ButlerlySpacing.standard),
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
                                onChanged: (value) =>
                                    setState(() => _tagIds = value),
                                onCreate: () => _createTag(data),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ButlerlySpacing.pagePadding,
                        0,
                        ButlerlySpacing.pagePadding,
                        ButlerlySpacing.standard,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('transaction-save-locally'),
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _saving
                                ? context.l10n.text('saving')
                                : context.l10n.text('saveLocally'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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

Color _transactionCardIconColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

class _TransactionEditorCardHeader extends StatelessWidget {
  const _TransactionEditorCardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: _transactionCardIconColor(context)),
      const SizedBox(width: ButlerlySpacing.compact),
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _EditorMasterData {
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

  Future<void> _editTransaction() async {
    final changed = await Navigator.of(context).push<TransactionEditorResult>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionEditorPage(finance: finance, existing: transaction),
      ),
    );
    if ((changed is TransactionEditorSaved ||
            changed is TransactionEditorUseExisting) &&
        mounted) {
      _changed = true;
      final refreshed = await finance.getTransaction(transaction.id);
      if (!mounted) return;
      if (refreshed case ApplicationSuccess<TransactionDto>(:final value)) {
        setState(() {
          transaction = value;
          _changed = true;
        });
      }
    }
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
            key: const ValueKey('transaction-detail-edit-action'),
            tooltip: context.l10n.text('edit'),
            onPressed: _editTransaction,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ButlerlyResponsiveBody(
        contentKey: const ValueKey('transaction-detail-content'),
        child: ListView(
          key: const ValueKey('transaction-detail-list'),
          padding: const EdgeInsets.fromLTRB(
            ButlerlySpacing.pagePadding,
            ButlerlySpacing.compact,
            ButlerlySpacing.pagePadding,
            ButlerlySpacing.pagePadding,
          ),
          children: [
            ButlerlyCard(
              key: const ValueKey('transaction-detail-summary-card'),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(14);
                  final stackSummary =
                      constraints.maxWidth < 320 || textScale > 20;
                  final identity = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        transaction.description ??
                            context.l10n.text('untitledTransaction'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: ButlerlySpacing.micro),
                      Text(
                        _transactionDate(transaction, context),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                  final amount = Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            localizedTransactionAmount(
                              context,
                              transaction.amount,
                            ),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      Text(
                        transaction.currency,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                  final icon = Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(
                        ButlerlyRadius.standard,
                      ),
                    ),
                    child: Icon(
                      Icons.receipt_long_outlined,
                      color: _transactionCardIconColor(context),
                    ),
                  );
                  if (stackSummary) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: ButlerlySpacing.standard),
                            Expanded(child: identity),
                          ],
                        ),
                        const SizedBox(height: ButlerlySpacing.standard),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: amount,
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      icon,
                      const SizedBox(width: ButlerlySpacing.standard),
                      Expanded(flex: 3, child: identity),
                      const SizedBox(width: ButlerlySpacing.standard),
                      Expanded(flex: 2, child: amount),
                    ],
                  );
                },
              ),
            ),
            if (transaction.merchantId != null ||
                transaction.categoryId != null ||
                transaction.subcategoryId != null ||
                transaction.paymentSourceId != null) ...[
              const SizedBox(height: ButlerlySpacing.cardGap),
              ButlerlyCard(
                key: const ValueKey('transaction-detail-classification-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TransactionDetailCardHeader(
                      icon: Icons.credit_card_outlined,
                      title: context.l10n.text('transactionDetail'),
                    ),
                    const SizedBox(height: ButlerlySpacing.compact),
                    _DetailItemGroup(
                      children: [
                        if (transaction.merchantId != null ||
                            transaction.categoryId != null ||
                            transaction.subcategoryId != null)
                          _TransactionMasterDataRows(
                            key: ValueKey(
                              'detail-${transaction.updatedAt.microsecondsSinceEpoch}-${transaction.tagIds.join(',')}',
                            ),
                            finance: finance,
                            transaction: transaction,
                            showTags: false,
                            showDividers: true,
                          ),
                        if (transaction.paymentSourceId != null)
                          _PaymentSourceRow(
                            finance: finance,
                            paymentSourceId: transaction.paymentSourceId!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: ButlerlySpacing.cardGap),
            ButlerlyCard(
              key: const ValueKey('transaction-detail-amount-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TransactionDetailCardHeader(
                    icon: Icons.payments_outlined,
                    title: context.l10n.text('amount'),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  _DetailItemGroup(
                    children: [
                      _DetailRow(
                        icon: Icons.payments_outlined,
                        label: context.l10n.text('amount'),
                        value: localizedTransactionAmount(
                          context,
                          transaction.amount,
                        ),
                      ),
                      _DetailRow(
                        icon: Icons.currency_exchange_outlined,
                        label: context.l10n.text('currency'),
                        value: transaction.currency,
                      ),
                      _DetailRow(
                        icon: Icons.swap_vert_rounded,
                        label: context.l10n.text('direction'),
                        value: context.l10n.text(transaction.direction),
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
                  ),
                ],
              ),
            ),
            const SizedBox(height: ButlerlySpacing.cardGap),
            ButlerlyCard(
              key: const ValueKey('transaction-detail-date-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TransactionDetailCardHeader(
                    icon: Icons.calendar_month_outlined,
                    title: context.l10n.text('date'),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  _DetailItemGroup(
                    children: [
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: context.l10n.text('date'),
                        value: _transactionDate(transaction, context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: ButlerlySpacing.cardGap),
            ButlerlyCard(
              key: const ValueKey('transaction-detail-notes-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TransactionDetailCardHeader(
                    icon: Icons.notes_rounded,
                    title: context.l10n.text('notesAndTags'),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  _DetailItemGroup(
                    children: [
                      _DetailRow(
                        icon: Icons.sticky_note_2_outlined,
                        label: context.l10n.text('notes'),
                        value: transaction.notes?.trim().isNotEmpty == true
                            ? transaction.notes!
                            : context.l10n.text('notSet'),
                      ),
                      _TransactionTagsDetailRow(
                        key: ValueKey(
                          'tags-${transaction.updatedAt.microsecondsSinceEpoch}-${transaction.tagIds.join(',')}',
                        ),
                        finance: finance,
                        transaction: transaction,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: ButlerlySpacing.cardGap),
            _EvidenceSection(finance: finance, transactionId: transaction.id),
            const SizedBox(height: ButlerlySpacing.cardGap),
            ButlerlyCard(
              key: const ValueKey('transaction-detail-record-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TransactionDetailCardHeader(
                    icon: Icons.info_outline_rounded,
                    title: context.l10n.text('status'),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  _DetailItemGroup(
                    children: [
                      _DetailRow(
                        icon: Icons.inventory_2_outlined,
                        label: context.l10n.text('status'),
                        value: context.l10n.text(transaction.status),
                      ),
                      _DetailRow(
                        icon: Icons.fact_check_outlined,
                        label: context.l10n.text('reviewState'),
                        value: transaction.reviewState == 'needsReview'
                            ? context.l10n.text('needsReview')
                            : context.l10n.text('clear'),
                      ),
                      ...transaction.provenance.map(
                        (value) => _DetailRow(
                          icon: Icons.history_rounded,
                          label: context.l10n.text('origin'),
                          value: _provenanceLabel(context, value.sourceType),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: ButlerlySpacing.section),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackActions =
                    constraints.maxWidth < 360 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20;
                final editButton = OutlinedButton.icon(
                  key: const ValueKey('transaction-detail-edit-button'),
                  onPressed: _editTransaction,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.l10n.text('edit')),
                );
                final deleteButton = ButlerlyDestructiveButton(
                  key: const ValueKey('transaction-detail-delete-button'),
                  onPressed: () => _delete(context),
                  icon: const Icon(Icons.delete_forever_outlined),
                  child: Text(context.l10n.text('delete')),
                );
                if (stackActions) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      editButton,
                      const SizedBox(height: ButlerlySpacing.small),
                      deleteButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: editButton),
                    const SizedBox(width: ButlerlySpacing.small),
                    Expanded(child: deleteButton),
                  ],
                );
              },
            ),
            const SizedBox(height: ButlerlySpacing.structural),
          ],
        ),
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
      return ButlerlyCard(
        key: const ValueKey('transaction-detail-evidence-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TransactionDetailCardHeader(
              icon: Icons.image_outlined,
              title: context.l10n.text('evidence'),
            ),
            const SizedBox(height: ButlerlySpacing.compact),
            if (evidence.isEmpty)
              Text(
                context.l10n.text('noEvidence'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              _DetailItemGroup(
                children: [
                  ...evidence.map(
                    (value) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        value.mediaType.startsWith('image/')
                            ? Icons.image_outlined
                            : Icons.attach_file_outlined,
                      ),
                      title: ButlerlySecondaryTextAction(
                        onPressed: () => _preview(value),
                        child: Text(
                          value.mediaType.startsWith('image/')
                              ? context.l10n.text('viewImage')
                              : context.l10n.text('evidence'),
                        ),
                      ),
                      onTap: () => _preview(value),
                      trailing: IconButton(
                        tooltip: context.l10n.text('remove'),
                        onPressed: () => _remove(value),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
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
    this.showTags = true,
    this.showDividers = false,
    super.key,
  });

  final FinanceServices finance;
  final TransactionDto transaction;
  final bool showTags;
  final bool showDividers;

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
      final rows = <Widget>[
        if (transaction.merchantId != null)
          _DetailRow(
            icon: Icons.storefront_outlined,
            label: context.l10n.text('merchant'),
            value:
                data.merchantName(transaction.merchantId) ??
                context.l10n.text('unavailableMerchant'),
          ),
        if (transaction.categoryId != null || transaction.subcategoryId != null)
          ..._categoryRows(
            context,
            data,
            transaction.categoryId,
            transaction.subcategoryId,
          ),
        if (widget.showTags && transaction.tagIds.isNotEmpty)
          ButlerlyReadOnlyTagList(
            tagIds: transaction.tagIds.map((id) => id),
            masterData: data,
            label: context.l10n.text('tags'),
            unavailableLabel: context.l10n.text('unavailableTag'),
            compact: true,
          ),
      ];
      return widget.showDividers
          ? _DetailItemStack(children: rows)
          : Column(children: rows);
    },
  );
}

List<Widget> _categoryRows(
  BuildContext context,
  TransactionMasterData data,
  String? categoryId,
  String? subcategoryId,
) {
  final legacyParentId = subcategoryId == null
      ? data.categoryParentId(categoryId)
      : null;
  final effectiveCategoryId = legacyParentId ?? categoryId;
  final effectiveSubcategoryId =
      subcategoryId ?? (legacyParentId == null ? null : categoryId);
  return [
    if (effectiveCategoryId != null)
      _DetailRow(
        icon: Icons.sell_outlined,
        label: context.l10n.text('category'),
        value:
            data.categoryName(effectiveCategoryId) ??
            context.l10n.text('unavailableCategory'),
      ),
    if (effectiveSubcategoryId != null)
      _DetailRow(
        icon: Icons.label_outline_rounded,
        label: context.l10n.text('subcategory'),
        value:
            data.categoryName(effectiveSubcategoryId) ??
            context.l10n.text('unavailableCategory'),
      ),
  ];
}

class _TransactionTagsDetailRow extends StatefulWidget {
  const _TransactionTagsDetailRow({
    required this.finance,
    required this.transaction,
    super.key,
  });

  final FinanceServices finance;
  final TransactionDto transaction;

  @override
  State<_TransactionTagsDetailRow> createState() =>
      _TransactionTagsDetailRowState();
}

class _TransactionTagsDetailRowState extends State<_TransactionTagsDetailRow> {
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
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: ButlerlySpacing.compact),
          child: LinearProgressIndicator(),
        );
      }
      final data = snapshot.data ?? const TransactionMasterData();
      final labels = widget.transaction.tagIds
          .map((id) => data.tagName(id) ?? context.l10n.text('unavailableTag'))
          .toList(growable: false);
      return _DetailRow(
        icon: Icons.label_outline_rounded,
        label: context.l10n.text('tags'),
        value: labels.isEmpty ? context.l10n.text('notSet') : labels.join(', '),
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
        icon: Icons.credit_card_outlined,
        label: context.l10n.text('paymentSource'),
        value: source == null
            ? context.l10n.text('unavailablePaymentSource')
            : paymentSourceDisplayLabel(source),
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

class _DetailItemGroup extends StatelessWidget {
  const _DetailItemGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: ButlerlySpacing.standard),
      child: _DetailItemStack(children: children),
    ),
  );
}

class _DetailItemStack extends StatelessWidget {
  const _DetailItemStack({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < children.length; index++) ...[
        children[index],
        if (index < children.length - 1)
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    ],
  );
}

class _TransactionDetailCardHeader extends StatelessWidget {
  const _TransactionDetailCardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: _transactionCardIconColor(context)),
      const SizedBox(width: ButlerlySpacing.compact),
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: ButlerlySpacing.compact),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: ButlerlySpacing.standard),
        ],
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),
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

String _transactionDate(TransactionDto value, BuildContext context) =>
    transactionDateLabel(
      value,
      pendingLabel: context.l10n.text('datePending'),
      locale: Localizations.localeOf(context).toLanguageTag(),
    );

String _shortDate(DateTime value) => shortDateLabel(value);
