import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
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
  late Future<List<Category>> _categories;
  late Future<List<PaymentSource>> _paymentSources;
  Map<String, String> _categoryNames = const {};

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _categories = _loadCategories();
    _paymentSources = _loadPaymentSources();
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

  Future<List<Category>> _loadCategories() async {
    final result = await _finance?.listCategories();
    final categories = switch (result) {
      ApplicationSuccess<List<Category>>(:final value) => value,
      _ => const <Category>[],
    };
    _categoryNames = {
      for (final category in categories) category.id.value: category.name,
    };
    if (mounted) setState(() {});
    return categories;
  }

  Future<List<PaymentSource>> _loadPaymentSources() async {
    final result = await _finance?.listPaymentSources();
    return switch (result) {
      ApplicationSuccess<List<PaymentSource>>(:final value) => value,
      _ => const [],
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ButlerlySpacing.standard,
              0,
              ButlerlySpacing.standard,
              MediaQuery.viewInsetsOf(context).bottom +
                  ButlerlySpacing.standard,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.text('filters'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: ButlerlySpacing.section),
                  DropdownButtonFormField<String?>(
                    initialValue: _currency,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('currency'),
                    ),
                    items: [
                      DropdownMenuItem(
                        child: Text(context.l10n.text('anyCurrency')),
                      ),
                      for (final code in const ['USD', 'EUR', 'GBP', 'CAD'])
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => _currency = value),
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  DropdownButtonFormField<TransactionDirection?>(
                    initialValue: _direction,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('direction'),
                    ),
                    items: [
                      DropdownMenuItem(
                        child: Text(context.l10n.text('anyDirection')),
                      ),
                      DropdownMenuItem(
                        value: TransactionDirection.income,
                        child: Text(context.l10n.text('income')),
                      ),
                      DropdownMenuItem(
                        value: TransactionDirection.expense,
                        child: Text(context.l10n.text('expense')),
                      ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => _direction = value),
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final value = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                              initialDate: _from ?? DateTime.now(),
                            );
                            if (value != null) {
                              setSheetState(() => _from = value);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _from == null
                                ? context.l10n.text('fromDate')
                                : _searchDate(_from!),
                          ),
                        ),
                      ),
                      const SizedBox(width: ButlerlySpacing.compact),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final value = await showDatePicker(
                              context: context,
                              firstDate: _from ?? DateTime(2000),
                              lastDate: DateTime.now(),
                              initialDate: _to ?? DateTime.now(),
                            );
                            if (value != null) {
                              setSheetState(() => _to = value);
                            }
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            _to == null
                                ? context.l10n.text('toDate')
                                : _searchDate(_to!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  FutureBuilder<List<Category>>(
                    future: _categories,
                    builder: (context, snapshot) =>
                        DropdownButtonFormField<String?>(
                          key: const ValueKey('search-category-filter'),
                          initialValue: _categoryId,
                          decoration: InputDecoration(
                            labelText: context.l10n.text('anyCategory'),
                          ),
                          items: [
                            DropdownMenuItem(
                              child: Text(context.l10n.text('anyCategory')),
                            ),
                            ...?snapshot.data?.map(
                              (value) => DropdownMenuItem(
                                value: value.id.value,
                                child: Text(value.name),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setSheetState(() => _categoryId = value),
                        ),
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  FutureBuilder<List<PaymentSource>>(
                    future: _paymentSources,
                    builder: (context, snapshot) =>
                        DropdownButtonFormField<String?>(
                          initialValue: _paymentSourceId,
                          decoration: InputDecoration(
                            labelText: context.l10n.text('anyPaymentSource'),
                          ),
                          items: [
                            DropdownMenuItem(
                              child: Text(
                                context.l10n.text('anyPaymentSource'),
                              ),
                            ),
                            ...?snapshot.data?.map(
                              (value) => DropdownMenuItem(
                                value: value.id.value,
                                child: Text(value.name),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setSheetState(() => _paymentSourceId = value),
                        ),
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.text('needsReview')),
                    value: _needsReview == true,
                    onChanged: (value) =>
                        setSheetState(() => _needsReview = value ? true : null),
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
          ),
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
            FilterChip(
              selected: _activeFilterCount > 0,
              avatar: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                _activeFilterCount > 0
                    ? '${context.l10n.text('filters')} ($_activeFilterCount)'
                    : context.l10n.text('filters'),
              ),
              onSelected: (_) => _openFilters(),
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
              return ButlerlyCard(
                padding: const EdgeInsets.symmetric(
                  vertical: ButlerlySpacing.compact,
                ),
                child: Column(
                  children: values
                      .map(
                        (value) => ButlerlyRecordRow(
                          title:
                              value.description ??
                              context.l10n.text('untitledTransaction'),
                          subtitle: value.categoryId == null
                              ? null
                              : _categoryNames[value.categoryId],
                          meta: transactionDateLabel(
                            value,
                            pendingLabel: context.l10n.text('datePending'),
                            locale: Localizations.localeOf(
                              context,
                            ).toLanguageTag(),
                          ),
                          amount: localizedDecimal(context, value.amount),
                          currency: value.currency,
                          icon: Icons.receipt_long_outlined,
                          isIncome:
                              value.direction ==
                              TransactionDirection.income.name,
                          needsReview: value.reviewState == 'needsReview',
                          onTap: () => _openDetail(value),
                        ),
                      )
                      .toList(growable: false),
                ),
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
