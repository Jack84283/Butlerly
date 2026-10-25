import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/budgets/application/budget_suggestions.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

/// User-managed monthly spending limits. Suggestions and utilization must
/// come from canonical normalized analysis, never raw transaction row totals.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  late final ManageBudgets? _management =
      services.isRegistered<FinanceServices>()
      ? services<FinanceServices>().manageBudgets
      : null;
  late Future<List<Budget>> _budgets = _load();
  TransactionMasterData? _masterData;
  String? _error;

  Future<List<Budget>> _load() async {
    if (_management == null) return [];
    if (_masterData == null && services.isRegistered<FinanceServices>()) {
      _masterData = await TransactionMasterData.load(
        services<FinanceServices>(),
      );
    }
    final result = await _management!.list();
    if (result is ApplicationSuccess<List<Budget>>) return result.value;
    throw StateError('Monthly budgets could not be loaded.');
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

  String _displayName(Budget budget) {
    if (budget.scopeId == null) return _scopeLabel(budget.scope);
    if (budget.scope == 'merchant') {
      return _masterData?.merchantName(budget.scopeId) ?? budget.scopeId ?? '';
    }
    return _masterData?.categoryName(budget.scopeId) ?? budget.scopeId!;
  }

  Future<void> _edit({Budget? existing}) async {
    final masterData = _masterData;
    final scopes = <String, Map<String, String>>{
      'category': {
        if (masterData != null)
          for (final entry in masterData.categoryNames.entries)
            if (masterData.categoryParentId(entry.key) == null)
              entry.key: entry.value,
      },
      'subcategory': {
        if (masterData != null)
          for (final entry in masterData.categoryNames.entries)
            if (masterData.categoryParentId(entry.key) != null)
              entry.key: entry.value,
      },
      'merchant': masterData?.merchantNames ?? {},
    };
    var scope = existing?.scope ?? 'overall';
    String? scopeId = existing?.scopeId;
    var currency = existing?.currency ?? 'USD';
    String? suggestionMessage;
    var amountText = existing?.amount ?? '';
    try {
      final submitted = await showButlerlyBottomSheet<Budget>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final options = scopes[scope] ?? {};
            if (scope != 'overall' && !options.containsKey(scopeId)) {
              scopeId = options.keys.firstOrNull;
            }
            return ButlerlySheet(
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
                    if (suggestionMessage != null) Text(suggestionMessage!),
                    TextFormField(
                      key: ValueKey('budget-amount-$amountText'),
                      initialValue: amountText,
                      onChanged: (value) => amountText = value,
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
                  onPressed: !services.isRegistered<FinanceServices>()
                      ? null
                      : () async {
                          setDialogState(() => suggestionMessage = null);
                          final suggestion = await suggestMonthlyBudget(
                            finance: services<FinanceServices>(),
                            scope: scope,
                            scopeId: scopeId,
                            currency: currency,
                          );
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            if (suggestion == null) {
                              suggestionMessage = context.l10n.text(
                                'budgetSuggestionUnavailable',
                              );
                            } else {
                              amountText = suggestion.amount;
                              suggestionMessage = context.l10n.text(
                                'budgetSuggestionPreview',
                              );
                            }
                          });
                        },
                  child: Text(context.l10n.text('budgetSuggest')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.l10n.text('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final number = num.tryParse(amountText.trim());
                    if (number == null ||
                        !number.isFinite ||
                        number <= 0 ||
                        (scope != 'overall' && scopeId == null)) {
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      Budget(
                        id:
                            existing?.id ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        scope: scope,
                        scopeId: scope == 'overall' ? null : scopeId,
                        currency: currency,
                        amount: amountText.trim(),
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
      if (submitted == null || _management == null) return;
      final result = await _management!.save(submitted);
      if (result is! ApplicationSuccess<bool>) {
        throw StateError('Monthly budget could not be saved.');
      }
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('budgetSaveFailure'));
      }
    }
  }

  Future<void> _remove(Budget budget) async {
    try {
      final result = await _management?.remove(budget.id);
      if (result is! ApplicationSuccess<bool>) {
        throw StateError('Monthly budget could not be deleted.');
      }
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
    body: _management == null
        ? Center(child: Text(context.l10n.text('localStorageUnavailable')))
        : FutureBuilder<List<Budget>>(
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
    floatingActionButton: _management == null
        ? null
        : FloatingActionButton(
            onPressed: () => _edit(),
            tooltip: context.l10n.text('budgetAdd'),
            child: const Icon(Icons.add),
          ),
  );
}
