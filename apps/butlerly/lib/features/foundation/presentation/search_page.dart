import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
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

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _categories = _loadCategories();
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
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listCategories();
    return switch (result) {
      ApplicationSuccess<List<Category>>(:final value) => value,
      ApplicationFailure<List<Category>>() => const [],
    };
  }

  Future<void> _selectDate({required bool isStart}) async {
    final initialDate = isStart ? _from ?? _to : _to ?? _from;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _from = selected;
      } else {
        _to = selected;
      }
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
    if (changed == true) _submit();
  }

  void _submit() {
    final future = _search();
    setState(() {
      _results = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = _finance == null;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Search', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        SearchBar(
          controller: _text,
          leading: const Icon(Icons.search),
          hintText: 'Search transactions and evidence',
          onSubmitted: (_) => _submit(),
          trailing: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.arrow_forward),
              onPressed: unavailable ? null : _submit,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            DropdownButton<String?>(
              value: _currency,
              hint: const Text('Any currency'),
              items: const [null, 'USD', 'EUR', 'GBP', 'JPY']
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value ?? 'Any currency'),
                    ),
                  )
                  .toList(),
              onChanged: unavailable
                  ? null
                  : (value) => setState(() => _currency = value),
            ),
            DropdownButton<TransactionDirection?>(
              value: _direction,
              hint: const Text('Any direction'),
              items: [null, ...TransactionDirection.values]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value?.name ?? 'Any direction'),
                    ),
                  )
                  .toList(),
              onChanged: unavailable
                  ? null
                  : (value) => setState(() => _direction = value),
            ),
            FutureBuilder<List<Category>>(
              future: _categories,
              builder: (context, snapshot) => DropdownButton<String?>(
                value: _categoryId,
                hint: const Text('Any category'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Any category'),
                  ),
                  ...?snapshot.data?.map(
                    (category) => DropdownMenuItem(
                      value: category.id.value,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: unavailable
                    ? null
                    : (value) => setState(() => _categoryId = value),
              ),
            ),
            FutureBuilder<List<PaymentSource>>(
              future: _finance?.listPaymentSources().then(
                (result) => switch (result) {
                  ApplicationSuccess<List<PaymentSource>>(:final value) =>
                    value,
                  ApplicationFailure<List<PaymentSource>>() => const [],
                },
              ),
              builder: (context, snapshot) => DropdownButton<String?>(
                value: _paymentSourceId,
                hint: const Text('Any payment source'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Any payment source'),
                  ),
                  ...?snapshot.data
                      ?.where(
                        (value) => value.status == PaymentSourceStatus.active,
                      )
                      .map(
                        (value) => DropdownMenuItem(
                          value: value.id.value,
                          child: Text(value.name),
                        ),
                      ),
                ],
                onChanged: unavailable
                    ? null
                    : (value) => setState(() => _paymentSourceId = value),
              ),
            ),
            DropdownButton<bool?>(
              value: _needsReview,
              hint: const Text('Any review state'),
              items: const [
                DropdownMenuItem<bool?>(
                  value: null,
                  child: Text('Any review state'),
                ),
                DropdownMenuItem<bool?>(
                  value: true,
                  child: Text('Needs review'),
                ),
                DropdownMenuItem<bool?>(
                  value: false,
                  child: Text('Clear review state'),
                ),
              ],
              onChanged: unavailable
                  ? null
                  : (value) => setState(() => _needsReview = value),
            ),
            OutlinedButton.icon(
              onPressed: unavailable ? null : () => _selectDate(isStart: true),
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                _from == null
                    ? 'From date'
                    : 'From ${MaterialLocalizations.of(context).formatShortDate(_from!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: unavailable ? null : () => _selectDate(isStart: false),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _to == null
                    ? 'To date'
                    : 'To ${MaterialLocalizations.of(context).formatShortDate(_to!)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (unavailable)
          const Text(
            'Search becomes available when local transaction storage is available.',
          )
        else if (_results == null)
          const Text(
            'Search stays on this device and opens the original transaction record.',
          )
        else
          FutureBuilder<List<TransactionDto>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Text(
                  'Search could not be completed. Your local records were not changed.',
                );
              }
              final values = snapshot.requireData;
              if (values.isEmpty) {
                return const Text('No local records match these filters.');
              }
              return Column(
                children: values
                    .map(
                      (value) => ListTile(
                        title: Text(
                          value.description ?? 'Untitled transaction',
                        ),
                        subtitle: Text('${value.amount} ${value.currency}'),
                        trailing: value.reviewState == 'needsReview'
                            ? const Icon(Icons.flag_outlined)
                            : null,
                        onTap: () => _openDetail(value),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
      ],
    );
  }
}
