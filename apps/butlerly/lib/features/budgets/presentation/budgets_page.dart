import 'dart:async';

import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_category_icon.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/budgets/application/budget_suggestions.dart';
import 'package:butlerly/features/desktop/presentation/desktop_transaction_detail_split_view.dart';
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
  List<Category> _categories = const [];
  List<Merchant> _merchants = const [];
  String? _error;
  Widget? _desktopEditor;

  Future<List<Budget>> _load() async {
    if (_management == null) return [];
    if (_masterData == null && services.isRegistered<FinanceServices>()) {
      final finance = services<FinanceServices>();
      _masterData = await TransactionMasterData.load(finance);
      final categoriesResult = await finance.listCategories();
      final merchantsResult = await finance.listMerchants();
      if (categoriesResult is ApplicationSuccess<List<Category>>) {
        _categories = categoriesResult.value;
      }
      if (merchantsResult is ApplicationSuccess<List<Merchant>>) {
        _merchants = merchantsResult.value;
      }
    }
    final result = await _management.list();
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

  Widget _budgetIcon(Budget budget) {
    final id = budget.scopeId;
    if (id != null && (budget.scope == 'category' ||
        budget.scope == 'subcategory')) {
      final categoryId = budget.scope == 'subcategory'
          ? _masterData?.categoryParentId(id) ?? id
          : id;
      if (ButlerlyCategoryIdentity.forBuiltInId(categoryId) != null) {
        return ButlerlyCategoryIcon(categoryId: categoryId);
      }
      return const Icon(Icons.category_outlined);
    }
    if (budget.scope == 'merchant') {
      return const Icon(Icons.storefront_outlined);
    }
    return const Icon(Icons.savings_outlined);
  }

  String _displayName(Budget budget) {
    if (budget.scopeId == null) return _scopeLabel(budget.scope);
    if (budget.scope == 'merchant') {
      return _masterData?.merchantName(budget.scopeId) ?? budget.scopeId ?? '';
    }
    return _masterData?.categoryName(budget.scopeId) ?? budget.scopeId!;
  }

  Future<void> _edit({Budget? existing}) async {
    final masterData = _masterData;
    var scope = existing?.scope ?? 'overall';
    String? scopeId = existing?.scopeId;
    String? selectedParentId = scope == 'subcategory'
        ? masterData?.categoryParentId(scopeId)
        : null;
    var currency = existing?.currency ?? 'USD';
    String? suggestionMessage;
    var amountText = existing?.amount ?? '';
    try {
      final desktop =
          effectiveButlerlyLayoutMode(
            context,
            MediaQuery.sizeOf(context).width,
          ) ==
          ButlerlyLayoutMode.wide;
      final completion = Completer<Budget?>();
      Widget editor(BuildContext dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return ButlerlySheet(
            title: desktop
                ? Row(
                    children: [
                      Expanded(child: Text(context.l10n.text('budgetEdit'))),
                      IconButton(
                        key: const ValueKey('budget-editor-close'),
                        tooltip: MaterialLocalizations.of(dialogContext)
                            .closeButtonTooltip,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          if (!completion.isCompleted) completion.complete(null);
                        },
                      ),
                    ],
                  )
                : Text(context.l10n.text('budgetEdit')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: ButlerlySpacing.standard),
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
                      selectedParentId = null;
                    }),
                  ),
                  if (scope == 'category') ...[
                    const SizedBox(height: ButlerlySpacing.standard),
                    ButlerlyCategorySelector(
                      key: const ValueKey('budget-category-selector'),
                      categories: _categories,
                      masterData: masterData ?? const TransactionMasterData(),
                      value: scopeId,
                      label: context.l10n.text('budgetCategory'),
                      clearLabel: context.l10n.text('clear'),
                      onChanged: (value) =>
                          setDialogState(() => scopeId = value),
                    ),
                  ],
                  if (scope == 'subcategory') ...[
                    const SizedBox(height: ButlerlySpacing.standard),
                    ButlerlyCategorySelector(
                      key: const ValueKey('budget-parent-category-selector'),
                      categories: _categories,
                      masterData: masterData ?? const TransactionMasterData(),
                      value: selectedParentId,
                      label: context.l10n.text('budgetCategory'),
                      clearLabel: context.l10n.text('clear'),
                      onChanged: (value) => setDialogState(() {
                        selectedParentId = value;
                        scopeId = null;
                      }),
                    ),
                    const SizedBox(height: ButlerlySpacing.standard),
                    ButlerlySubcategorySelector(
                      key: const ValueKey('budget-subcategory-selector'),
                      categories: _categories,
                      masterData: masterData ?? const TransactionMasterData(),
                      parentId: selectedParentId,
                      value: scopeId,
                      label: context.l10n.text('budgetSubcategory'),
                      clearLabel: context.l10n.text('clear'),
                      onChanged: (value) =>
                          setDialogState(() => scopeId = value),
                    ),
                  ],
                  if (scope == 'merchant') ...[
                    const SizedBox(height: ButlerlySpacing.standard),
                    ButlerlyMerchantSelector(
                      key: const ValueKey('budget-merchant-selector'),
                      merchants: _merchants,
                      value: scopeId,
                      label: context.l10n.text('budgetMerchant'),
                      clearLabel: context.l10n.text('clear'),
                      onChanged: (value) =>
                          setDialogState(() => scopeId = value),
                    ),
                  ],
                  const SizedBox(height: ButlerlySpacing.standard),
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
                  const SizedBox(height: ButlerlySpacing.standard),
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
              ButlerlyCancelButton(
                onPressed: () {
                  if (desktop) {
                    completion.complete(null);
                  } else {
                    Navigator.pop(dialogContext);
                  }
                },
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
                  final budget = Budget(
                    id:
                        existing?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    scope: scope,
                    scopeId: scope == 'overall' ? null : scopeId,
                    currency: currency,
                    amount: amountText.trim(),
                  );
                  if (desktop) {
                    completion.complete(budget);
                  } else {
                    Navigator.pop(dialogContext, budget);
                  }
                },
                child: Text(context.l10n.text('save')),
              ),
            ],
          );
        },
      );
      final Future<Budget?> result;
      if (desktop) {
        setState(() {
          _desktopEditor = Material(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(ButlerlySpacing.standard),
                child: editor(context),
              ),
            ),
          );
        });
        result = completion.future;
      } else {
        result = showButlerlyBottomSheet<Budget>(
          context: context,
          builder: editor,
        );
      }
      final submitted = await result;
      if (desktop && mounted) {
        setState(() => _desktopEditor = null);
      }
      if (submitted == null || _management == null) return;
      final saved = await _management.save(submitted);
      if (saved is! ApplicationSuccess<bool>) {
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
  Widget build(BuildContext context) {
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    final page = ButlerlyPage(
      title: context.l10n.text('budgets'),
      fullWidth: desktop,
      pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
      actions: [
        if (_management != null)
          ButlerlyHeaderAddButton(
            buttonKey: const ValueKey('budget-add'),
            label: context.l10n.text('add'),
            onPressed: () => _edit(),
          ),
      ],
      children: [
        if (_management == null)
          Center(child: Text(context.l10n.text('localStorageUnavailable')))
        else
          FutureBuilder<List<Budget>>(
            future: _budgets,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ButlerlyErrorState(
                  title: context.l10n.text('budgetSaveFailure'),
                  message: context.l10n.text('tryAgain'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _refresh,
                );
              }
              if (!snapshot.hasData) {
                return const ButlerlyLoadingState();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.text('budgetsMonthlyDescription'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  if (_error != null) Text(_error!),
                  if (snapshot.data!.isEmpty)
                    ButlerlyEmptyState(
                      icon: Icons.savings_outlined,
                      title: context.l10n.text('budgetsEmpty'),
                      message: context.l10n.text('budgetsMonthlyDescription'),
                    ),
                  for (final budget in snapshot.data!) ...[
                    ButlerlyCard(
                      onTap: () => _edit(existing: budget),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _budgetIcon(budget),
                        title: Text(_displayName(budget)),
                        subtitle: Text(
                          '${_scopeLabel(budget.scope)} · ${budget.currency} ${budget.amount}',
                        ),
                        trailing: IconButton(
                          tooltip: context.l10n.text('delete'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(budget),
                        ),
                      ),
                    ),
                    const SizedBox(height: ButlerlySpacing.cardGap),
                  ],
                ],
              );
            },
          ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
    return desktop
        ? DesktopTransactionDetailSplitView(
            results: page,
            detail: _desktopEditor,
          )
        : page;
  }
}
