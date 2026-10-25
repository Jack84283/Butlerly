import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:flutter/material.dart';

/// User-managed monthly spending limits. Suggestions and utilization must
/// come from canonical normalized analysis, never raw transaction row totals.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  late final SqliteBudgetRepository? _repository =
      services.isRegistered<LocalDatabase>() &&
          services<LocalDatabase>().status == DatabaseStatus.ready
      ? SqliteBudgetRepository(services<LocalDatabase>().persistenceDatabase)
      : null;
  late Future<List<StoredBudget>> _budgets = _load();
  TransactionMasterData? _masterData;
  String? _error;

  Future<List<StoredBudget>> _load() async {
    if (_repository == null) return [];
    if (_masterData == null && services.isRegistered<FinanceServices>()) {
      _masterData = await TransactionMasterData.load(
        services<FinanceServices>(),
      );
    }
    return _repository!.list();
  }

  void _refresh() {
    setState(() {
      _error = null;
      _budgets = _load();
    });
  }

  String _scopeLabel(String scope) => switch (scope) {
    'overall' => context.l10n.text('budgetOverall'),
    'category' => context.l10n.text('budgetCategory'),
    'subcategory' => context.l10n.text('budgetSubcategory'),
    'merchant' => context.l10n.text('budgetMerchant'),
    _ => scope,
  };

  String _displayName(StoredBudget budget) {
    if (budget.scopeId == null) return _scopeLabel(budget.scope);
    if (budget.scope == 'merchant') {
      return _masterData?.merchantName(budget.scopeId) ?? budget.scopeId!;
    }
    return _masterData?.categoryName(budget.scopeId) ?? budget.scopeId!;
  }

  Future<void> _edit({StoredBudget? existing}) async {
    final masterData = _masterData;
    final scopes = <String, Map<String, String>>{
      'category':
          masterData?.categoryNames.entries
              .where((entry) => masterData!.categoryParentId(entry.key) == null)
              .fold(<String, String>{}, (map, entry) {
                map[entry.key] = entry.value;
                return map;
              }) ??
          {},
      'subcategory':
          masterData?.categoryNames.entries
              .where((entry) => masterData!.categoryParentId(entry.key) != null)
              .fold(<String, String>{}, (map, entry) {
                map[entry.key] = entry.value;
                return map;
              }) ??
          {},
      'merchant': masterData?.merchantNames ?? {},
    };
    var scope = existing?.scope ?? 'overall';
    String? scopeId = existing?.scopeId;
    var currency = existing?.currency ?? 'USD';
    final amount = TextEditingController(text: existing?.amount ?? '');
    try {
      final submitted = await showDialog<StoredBudget>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final options = scopes[scope] ?? {};
            if (scope != 'overall' && !options.containsKey(scopeId)) {
              scopeId = options.keys.firstOrNull;
            }
            return AlertDialog(
              title: Text(context.l10n.text('budgetEdit')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: scope,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('budgetScope'),
                      ),
                      items: [
                        for (final value in const [
                          'overall',
                          'category',
                          'subcategory',
                          'merchant',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(_scopeLabel(value)),
                          ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        scope = value ?? scope;
                        scopeId = null;
                      }),
                    ),
                    if (scope != 'overall')
                      DropdownButtonFormField<String>(
                        key: ValueKey(scope),
                        initialValue: scopeId,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('budgetTarget'),
                        ),
                        items: [
                          for (final entry in options.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => scopeId = value),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: currency,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('budgetCurrency'),
                      ),
                      items: [
                        for (final value in const [
                          'USD',
                          'CNY',
                          'EUR',
                          'GBP',
                          'JPY',
                        ])
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => currency = value ?? currency),
                    ),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.text('budgetAmount'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.l10n.text('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final number = num.tryParse(amount.text.trim());
                    if (number == null ||
                        !number.isFinite ||
                        number <= 0 ||
                        (scope != 'overall' && scopeId == null)) {
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      StoredBudget(
                        id:
                            existing?.id ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        scope: scope,
                        scopeId: scope == 'overall' ? null : scopeId,
                        currency: currency,
                        amount: amount.text.trim(),
                      ),
                    );
                  },
                  child: Text(context.l10n.text('save')),
                ),
              ],
            );
          },
        ),
      );
      if (submitted == null || _repository == null) return;
      await _repository!.save(submitted);
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('budgetSaveFailure'));
      }
    } finally {
      amount.dispose();
    }
  }

  Future<void> _remove(StoredBudget budget) async {
    try {
      await _repository?.remove(budget.id);
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('budgetSaveFailure'));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('budgets'))),
    body: _repository == null
        ? Center(child: Text(context.l10n.text('localStorageUnavailable')))
        : FutureBuilder<List<StoredBudget>>(
            future: _budgets,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(context.l10n.text('budgetSaveFailure')),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(context.l10n.text('budgetsMonthlyDescription')),
                  const SizedBox(height: 12),
                  if (_error != null) Text(_error!),
                  if (snapshot.data!.isEmpty)
                    Text(context.l10n.text('budgetsEmpty')),
                  for (final budget in snapshot.data!)
                    Card(
                      child: ListTile(
                        title: Text(_displayName(budget)),
                        subtitle: Text(
                          '${_scopeLabel(budget.scope)} · ${budget.currency} ${budget.amount}',
                        ),
                        onTap: () => _edit(existing: budget),
                        trailing: IconButton(
                          tooltip: context.l10n.text('delete'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(budget),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    floatingActionButton: _repository == null
        ? null
        : FloatingActionButton(
            onPressed: () => _edit(),
            tooltip: context.l10n.text('budgetAdd'),
            child: const Icon(Icons.add),
          ),
  );
}
