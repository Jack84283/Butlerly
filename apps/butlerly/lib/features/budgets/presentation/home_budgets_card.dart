import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/budgets/application/budget_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Home spending-versus-budget summary; consumes the canonical analysis use case.
class HomeBudgetsCard extends StatefulWidget {
  const HomeBudgetsCard({
    required this.month,
    this.embedded = false,
    super.key,
  });

  final DateTime month;
  final bool embedded;

  @override
  State<HomeBudgetsCard> createState() => _HomeBudgetsCardState();
}

class _BudgetProgress {
  const _BudgetProgress(this.budget, this.spent);
  final Budget budget;
  final double? spent;
}

class _HomeBudgetsCardState extends State<HomeBudgetsCard> {
  late Future<List<_BudgetProgress>> _future;
  TransactionMasterData? _labels;

  @override
  void initState() {
    super.initState();
    _future = _load();
    transactionChanges.addListener(_refresh);
    budgetChanges.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant HomeBudgetsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _refresh();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  @override
  void dispose() {
    transactionChanges.removeListener(_refresh);
    budgetChanges.removeListener(_refresh);
    super.dispose();
  }

  Future<List<_BudgetProgress>> _load() async {
    // Snapshot the selected month before awaiting storage or metadata.
    final month = widget.month;
    if (!services.isRegistered<FinanceServices>()) return const [];
    final finance = services<FinanceServices>();
    final management = finance.manageBudgets;
    if (management == null) return const [];
    final saved = await management.list();
    if (saved is ApplicationFailure<List<Budget>>) {
      debugPrint('My Budgets: list failed: ${saved.failure.code} '
          '${saved.failure.operation} ${saved.failure.detail ?? ''}');
      throw StateError('Budget list unavailable: ${saved.failure.code}');
    }
    if (saved is! ApplicationSuccess<List<Budget>>) {
      throw StateError('Budget list unavailable');
    }
    final budgets = saved.value;
    if (budgets.isEmpty) return const [];
    try {
      _labels = await TransactionMasterData.load(finance);
    } catch (_) {
      // Missing presentation metadata must not hide saved budgets.
      _labels = null;
    }
    final calculate = finance.calculateAnalysisOverview;
    if (calculate == null) {
      return budgets.map((b) => _BudgetProgress(b, null)).toList();
    }
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    late final ApplicationResult<AnalysisContext> contextResult;
    try {
      contextResult = await calculate.contextForDates(
        startDate: date(first),
        endDate: date(last),
      );
    } catch (_) {
      return budgets.map((b) => _BudgetProgress(b, null)).toList();
    }
    if (contextResult is! ApplicationSuccess<AnalysisContext>) {
      return budgets.map((b) => _BudgetProgress(b, null)).toList();
    }
    late final ApplicationResult<List<RuleExecutionResult>> result;
    try {
      result = await calculate(contextResult.value);
    } catch (_) {
      return budgets.map((b) => _BudgetProgress(b, null)).toList();
    }
    if (result is! ApplicationSuccess<List<RuleExecutionResult>>) {
      return budgets.map((b) => _BudgetProgress(b, null)).toList();
    }
    late final AnalysisOverview overview;
    try {
      overview = AnalysisOverview.fromResults(result.value);
    } catch (_) {
      return budgets.map((b) => _BudgetProgress(b, null)).toList();
    }
    return budgets.map((budget) {
      final AnalysisMetric? metric = switch (budget.scope) {
        'overall' => overview.spending,
        'category' =>
          overview.categories
              .where((m) => m.dimension == budget.scopeId)
              .firstOrNull,
        'subcategory' =>
          overview.subcategories
              .where((m) => m.dimension == budget.scopeId)
              .firstOrNull,
        'merchant' =>
          overview.merchants
              .where((m) => m.dimension == budget.scopeId)
              .firstOrNull,
        _ => null,
      };
      // Match the availability rule used by Home's spending summary.
      // Quality warnings should not suppress an otherwise usable amount.
      // Currency must still match so we never compare unlike amounts.
      final metricCurrency =
          metric?.currency?.value ?? metric?.context.baseCurrency?.value;
      if (metric == null ||
          metric.availability != AnalysisDataAvailability.sufficient ||
          metricCurrency != budget.currency) {
        debugPrint('My Budgets: monthly metric unavailable for '
            '${budget.scope}/${budget.scopeId} '
            '${month.year}-${month.month}: '
            'metric=${metric == null ? 'missing' : metric.availability}, '
            'currency=${metric?.currency?.value}, expected=${budget.currency}, '
            'quality=${metric?.qualityIssues.length}');
        return _BudgetProgress(budget, null);
      }
      return _BudgetProgress(budget, double.tryParse(metric.value.toString()));
    }).toList();
  }

  String _name(Budget budget) {
    if (budget.scopeId == null) return context.l10n.text('budgetOverall');
    if (budget.scope == 'merchant') {
      return _labels?.merchantName(budget.scopeId) ?? budget.scopeId!;
    }
    return _labels?.categoryName(budget.scopeId) ?? budget.scopeId!;
  }

  Widget _icon(Budget budget) {
    final id = budget.scopeId;
    if (id != null &&
        (budget.scope == 'category' || budget.scope == 'subcategory')) {
      final parent = budget.scope == 'subcategory'
          ? _labels?.categoryParentId(id) ?? id
          : id;
      if (ButlerlyCategoryIdentity.forBuiltInId(parent) != null) {
        return ButlerlyCategoryIcon(categoryId: parent);
      }
    }
    final glyph = budget.scope == 'merchant'
        ? Icons.storefront_outlined
        : budget.scope == 'overall'
        ? Icons.savings_outlined
        : Icons.category_outlined;
    return SizedBox.square(
      dimension: ButlerlySize.categoryIconContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: Icon(
          glyph,
          size: ButlerlySize.categoryIconGlyph,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _contents() => FutureBuilder<List<_BudgetProgress>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ButlerlyLoadingState();
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.text('budgetLoadUnavailable')),
            const SizedBox(height: ButlerlySpacing.small),
            TextButton(
              onPressed: _refresh,
              child: Text(context.l10n.text('tryAgain')),
            ),
          ],
        );
      }
      final rows = snapshot.data ?? const <_BudgetProgress>[];
      if (rows.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.text('budgetsEmpty')),
            const SizedBox(height: ButlerlySpacing.small),
            FilledButton.icon(
              onPressed: () => context.push('/budgets?create=true'),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.text('budgetAdd')),
            ),
          ],
        );
      }
      return Column(
        children: [
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _icon(row.budget),
                const SizedBox(width: ButlerlySpacing.small),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name(row.budget),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: ButlerlySpacing.compact),
                      if (row.spent case final spent?)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            ButlerlyRadius.pill,
                          ),
                          child: LinearProgressIndicator(
                            minHeight: ButlerlySpacing.compact,
                            value:
                                (spent /
                                        (double.tryParse(row.budget.amount) ??
                                            1))
                                    .clamp(0.0, 1.0),
                          ),
                        )
                      else
                        Text('—', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: ButlerlySpacing.micro),
                      Text(
                        row.spent == null
                            ? context.l10n.text('budgetActualUnavailable')
                            : '${row.spent!.toStringAsFixed(2)} / ${row.budget.amount} ${row.budget.currency}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ButlerlySpacing.small),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final content = _contents();
    if (widget.embedded) return content;
    return ButlerlyCard(
      key: const ValueKey('home-budgets-card'),
      variant: ButlerlyCardVariant.dashboard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ButlerlyCardHeader(title: context.l10n.text('myBudgets')),
          const SizedBox(height: ButlerlySpacing.standard),
          content,
        ],
      ),
    );
  }
}
