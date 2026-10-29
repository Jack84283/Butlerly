import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_budget_scope_icon.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/budgets/application/budget_change_notifier.dart';
import 'package:butlerly/features/budgets/application/monthly_budget_actuals.dart';
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
  const _BudgetProgress(this.budget, this.spent, [this.metric]);
  final Budget budget;
  final double? spent;
  final AnalysisMetric? metric;
}

class _HomeBudgetsCardState extends State<HomeBudgetsCard> {
  late Future<List<_BudgetProgress>> _future;
  TransactionMasterData? _labels;
  String _languageCode = 'en';

  @override
  void initState() {
    super.initState();
    _future = _load();
    transactionChanges.addListener(_refresh);
    budgetChanges.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_languageCode != languageCode) {
      _languageCode = languageCode;
      _refresh();
    }
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
      debugPrint(
        'My Budgets: list failed: ${saved.failure.code} '
        '${saved.failure.operation} ${saved.failure.detail ?? ''}',
      );
      throw StateError('Budget list unavailable: ${saved.failure.code}');
    }
    if (saved is! ApplicationSuccess<List<Budget>>) {
      throw StateError('Budget list unavailable');
    }
    final budgets = saved.value;
    if (budgets.isEmpty) return const [];
    try {
      _labels = await TransactionMasterData.load(
        finance,
        languageCode: _languageCode,
      );
    } catch (_) {
      // Missing presentation metadata must not hide saved budgets.
      _labels = null;
    }
    // A budget's amount must not depend on analysis rules being installed,
    // materialized, or producing a nonempty summary metric. The canonical
    // dataset applies the same reconciliation, financial date, and FX policy.
    CanonicalBudgetActuals? canonical;
    try {
      final actualsResult = await finance.calculateCanonicalBudgetActuals(
        month: month,
        budgets: budgets,
      );
      if (actualsResult is ApplicationSuccess<CanonicalBudgetActuals>) {
        canonical = actualsResult.value;
      } else if (actualsResult is ApplicationFailure<CanonicalBudgetActuals>) {
        debugPrint(
          'My Budgets: canonical actuals unavailable: '
          '${actualsResult.failure.code} '
          '${actualsResult.failure.detail ?? ''}',
        );
      }
    } catch (error) {
      debugPrint('My Budgets: canonical actuals error: $error');
    }

    _BudgetProgress progress(Budget budget, [AnalysisMetric? metric]) {
      final exact = canonical?.byBudgetId[budget.id];
      final spent = exact == null ? null : double.tryParse(exact.toString());
      return _BudgetProgress(budget, spent, metric);
    }

    final calculate = finance.calculateAnalysisOverview;
    if (calculate == null) {
      return budgets.map((b) => progress(b)).toList();
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
      return budgets.map((b) => progress(b)).toList();
    }
    if (contextResult is! ApplicationSuccess<AnalysisContext>) {
      return budgets.map((b) => progress(b)).toList();
    }
    late final ApplicationResult<List<RuleExecutionResult>> result;
    try {
      result = await calculate(contextResult.value);
    } catch (_) {
      return budgets.map((b) => progress(b)).toList();
    }
    if (result is! ApplicationSuccess<List<RuleExecutionResult>>) {
      return budgets.map((b) => progress(b)).toList();
    }
    late final AnalysisOverview overview;
    try {
      overview = AnalysisOverview.fromResults(result.value);
    } catch (_) {
      return budgets.map((b) => progress(b)).toList();
    }
    return budgets.map((budget) {
      // Analysis metrics remain optional navigation metadata. They are no
      // longer the source for actual spending or its zero/unavailable state.
      final metric = resolveMonthlyBudgetActual(budget, overview).metric;
      final row = progress(budget, metric);
      if (row.spent == null) {
        debugPrint(
          'My Budgets: monthly actual unavailable for '
          '${budget.scope}/${budget.scopeId} '
          '${month.year}-${month.month}: expected=${budget.currency}',
        );
      }
      return row;
    }).toList();
  }

  void _openBudgetSearch(_BudgetProgress row) {
    final metric = row.metric;
    if (metric == null) return;
    final from = DateTime(widget.month.year, widget.month.month, 1);
    final to = DateTime(widget.month.year, widget.month.month + 1, 0);
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final dimension = row.budget.scope == 'overall'
        ? null
        : analysisRawDimension(metric);
    final params = <String, String>{
      'locked': 'true',
      'from': date(from),
      'to': date(to),
      'analysisRule': metric.rule.identity.value,
      row.budget.scope: ?dimension,
    };
    context.push(Uri(path: '/search', queryParameters: params).toString());
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
    return ButlerlyBudgetScopeIcon(scope: budget.scope);
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
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: () => context.push('/budgets?create=true'),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.text('budgetAdd')),
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            Builder(
              builder: (context) {
                final row = rows[index];
                final limit = double.tryParse(row.budget.amount) ?? 0;
                final spent = row.spent;
                final percentage = spent == null || limit <= 0
                    ? null
                    : spent / limit * 100;
                final overBudget = percentage != null && percentage > 100;
                final progressColor =
                    (overBudget ? context.colors.error : context.colors.info)
                        .withValues(alpha: 1.0);
                return InkWell(
                  onTap: row.metric == null
                      ? null
                      : () => _openBudgetSearch(row),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _icon(row.budget),
                      const SizedBox(width: ButlerlySpacing.small),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _name(row.budget),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: ButlerlySpacing.compact),
                                Text(
                                  percentage == null
                                      ? '—'
                                      : '${percentage.round()}%',
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: progressColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: ButlerlySpacing.micro),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                ButlerlyRadius.full,
                              ),
                              child: SizedBox(
                                height: 7,
                                child: LinearProgressIndicator(
                                  value: percentage == null
                                      ? 0
                                      : (percentage / 100).clamp(0.0, 1.0),
                                  color: progressColor,
                                  backgroundColor: progressColor.withValues(
                                    alpha: 0.14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: ButlerlySpacing.micro),
                            Text(
                              spent == null
                                  ? context.l10n.text('budgetActualUnavailable')
                                  : '${spent.toStringAsFixed(2)} / ${row.budget.amount} ${row.budget.currency}',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (index < rows.length - 1) ...[
              SizedBox(
                height: widget.embedded
                    ? ButlerlySpacing.compact
                    : ButlerlySpacing.small,
              ),
              if (widget.embedded) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.cardDivider,
                ),
                const SizedBox(height: ButlerlySpacing.compact),
              ],
            ],
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final content = _contents();
    if (widget.embedded) return content;
    return SizedBox(
      width: double.infinity,
      child: ButlerlyCard(
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
      ),
    );
  }
}
