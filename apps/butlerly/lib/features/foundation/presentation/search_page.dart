import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  String? _currency;
  TransactionDirection? _direction;
  String? _categoryId;
  String? _paymentSourceId;
  bool? _needsReview;
  DateTime? _from;
  DateTime? _to;
  Future<List<TransactionDto>>? _results;
  late Future<TransactionMasterDataSnapshot> _masterData;
  late Future<List<String>> _currencies;
  TransactionMasterData _presentation = const TransactionMasterData();
  String? _loadedLanguageCode;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _masterData = _loadMasterData(languageCode);
    _currencies = _loadCurrencies();
    _masterData.then((value) {
      if (mounted && _loadedLanguageCode == languageCode) {
        setState(() => _presentation = value.presentation);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<List<TransactionDto>> _search() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listTransactions(
      ListTransactionsQuery(
        text: _text.text.trim().isEmpty ? null : _text.text.trim(),
        currency: _currency,
        direction: _direction,
        categoryId: _categoryId,
        paymentSourceId: _paymentSourceId,
        needsReview: _needsReview,
        from: _from,
        to: _to,
      ),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) => value,
      ApplicationFailure<List<TransactionDto>>() => throw StateError(
        'Search failed',
      ),
    };
  }

  Future<TransactionMasterDataSnapshot> _loadMasterData(
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

  Future<List<String>> _loadCurrencies() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listTransactions(
      const ListTransactionsQuery(),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) =>
        value.map((transaction) => transaction.currency).toSet().toList()
          ..sort(),
      ApplicationFailure<List<TransactionDto>>() => const [],
    };
  }

  void _submit() => setState(() {
    _results = _search();
  });

  void _clear() {
    setState(() {
      _currency = null;
      _direction = null;
      _categoryId = null;
      _paymentSourceId = null;
      _needsReview = null;
      _from = null;
      _to = null;
      _results = null;
    });
  }

  int get _activeFilterCount => [
    _currency,
    _direction,
    _categoryId,
    _paymentSourceId,
    _needsReview,
    _from,
    _to,
  ].where((value) => value != null).length;

  Future<void> _openFilters() async {
    await showButlerlyBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => ButlerlySheet(
          title: Text(context.l10n.text('filters')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: ButlerlySpacing.compact),
                FutureBuilder<List<String>>(
                  future: _currencies,
                  builder: (context, snapshot) => ButlerlyCurrencyFilter(
                    currencies: snapshot.data ?? const [],
                    value: _currency,
                    label: context.l10n.text('currency'),
                    anyLabel: context.l10n.text('anyCurrency'),
                    onChanged: (value) =>
                        setSheetState(() => _currency = value),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlyDirectionFilter(
                  value: _direction,
                  label: context.l10n.text('direction'),
                  anyLabel: context.l10n.text('anyDirection'),
                  onChanged: (value) => setSheetState(() => _direction = value),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlyDateRangeFilter(
                  from: _from,
                  to: _to,
                  fromLabel: context.l10n.text('fromDate'),
                  toLabel: context.l10n.text('toDate'),
                  formatDate: _searchDate,
                  onFromChanged: (value) => setSheetState(() => _from = value),
                  onToChanged: (value) => setSheetState(() => _to = value),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                FutureBuilder<TransactionMasterDataSnapshot>(
                  future: _masterData,
                  builder: (context, snapshot) => ButlerlyCategoryFilter(
                    key: const ValueKey('search-category-filter'),
                    categories: snapshot.data?.categories ?? const [],
                    masterData:
                        snapshot.data?.presentation ??
                        const TransactionMasterData(),
                    value: _categoryId,
                    label: context.l10n.text('anyCategory'),
                    anyLabel: context.l10n.text('anyCategory'),
                    onChanged: (value) =>
                        setSheetState(() => _categoryId = value),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                FutureBuilder<TransactionMasterDataSnapshot>(
                  future: _masterData,
                  builder: (context, snapshot) => ButlerlyPaymentSourceFilter(
                    sources: snapshot.data?.paymentSources ?? const [],
                    value: _paymentSourceId,
                    label: context.l10n.text('anyPaymentSource'),
                    anyLabel: context.l10n.text('anyPaymentSource'),
                    onChanged: (value) =>
                        setSheetState(() => _paymentSourceId = value),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.standard),
                ButlerlyReviewFilter(
                  value: _needsReview,
                  label: context.l10n.text('needsReview'),
                  onChanged: (value) =>
                      setSheetState(() => _needsReview = value),
                ),
                const SizedBox(height: ButlerlySpacing.section),
                FilledButton(
                  key: const ValueKey('apply-search-filters'),
                  onPressed: () {
                    Navigator.pop(context);
                    _submit();
                  },
                  child: Text(context.l10n.text('applyFilters')),
                ),
                TextButton(
                  onPressed: () {
                    _clear();
                    Navigator.pop(context);
                  },
                  child: Text(context.l10n.text('clearFilters')),
                ),
              ],
            ),
          ),
          actions: const [],
        ),
      ),
    );
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
    if (changed == true) _submit();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ButlerlyPage(
      title: context.l10n.text('search'),
      subtitle: context.l10n.text('searchIntro'),
      children: [
        SearchBar(
          controller: _text,
          hintText: context.l10n.text('searchHint'),
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (_text.text.isNotEmpty)
              IconButton(
                tooltip: context.l10n.text('clear'),
                onPressed: () {
                  _text.clear();
                  _submit();
                },
                icon: const Icon(Icons.close_rounded),
              ),
          ],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Row(
          children: [
            ButlerlyFilterButton(
              selected: _activeFilterCount > 0,
              label: _activeFilterCount > 0
                  ? '${context.l10n.text('filters')} ($_activeFilterCount)'
                  : context.l10n.text('filters'),
              onPressed: _openFilters,
            ),
            if (_activeFilterCount > 0) ...[
              const SizedBox(width: ButlerlySpacing.compact),
              TextButton(
                onPressed: _clear,
                child: Text(context.l10n.text('clearFilters')),
              ),
            ],
          ],
        ),
        const SizedBox(height: ButlerlySpacing.section),
        if (_results == null)
          ButlerlyEmptyState(
            icon: Icons.search_rounded,
            title: context.l10n.text('noSearchYet'),
            message: context.l10n.text('noSearchYetBody'),
          )
        else
          FutureBuilder<List<TransactionDto>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(ButlerlySpacing.large),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return ButlerlyErrorState(
                  title: context.l10n.text('noResults'),
                  message: context.l10n.text('tryAgain'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _submit,
                );
              }
              final values = snapshot.requireData;
              if (values.isEmpty) {
                return ButlerlyEmptyState(
                  icon: Icons.search_off_rounded,
                  title: context.l10n.text('noResults'),
                  message: context.l10n.text('noResultsBody'),
                  actionLabel: context.l10n.text('clearFilters'),
                  onAction: _clear,
                );
              }
              return ButlerlyTransactionList(
                children: values
                    .map(
                      (value) => ButlerlyTransactionListItem(
                        title:
                            value.description ??
                            context.l10n.text('untitledTransaction'),
                        subtitle: value.categoryId == null
                            ? null
                            : _presentation.categoryName(value.categoryId),
                        meta: transactionDateLabel(
                          value,
                          pendingLabel: context.l10n.text('datePending'),
                          locale: Localizations.localeOf(
                            context,
                          ).toLanguageTag(),
                        ),
                        amount: localizedTransactionAmount(
                          context,
                          value.amount,
                        ),
                        currency: value.currency,
                        isIncome:
                            value.direction == TransactionDirection.income.name,
                        needsReview: value.reviewState == 'needsReview',
                        onTap: () => _openDetail(value),
                        showNavigationIndicator: true,
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }
}

String _searchDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
