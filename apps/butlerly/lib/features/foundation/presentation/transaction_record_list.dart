import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared grouped-list presentation for Transactions, Search, and Review.
///
/// Transaction-row semantics are centralized in [TransactionRow]. This widget
/// owns only grouping, section headers, ordering, and list-level decoration.
class TransactionRecordList extends StatelessWidget {
  const TransactionRecordList({
    required this.transactions,
    required this.onTap,
    this.masterData = const TransactionMasterData(),
    this.paymentSourceNames = const {},
    this.possibleDuplicateIds = const {},
    this.possibleDuplicateLabel,
    this.onPossibleDuplicateTap,
    this.navigates = false,
    this.groupByFinancialDate = false,
    this.collapsibleMonthSections = false,
    this.monthSectionsAsCards = false,
    this.dashboardRowStyle = false,
    this.wrapInCard = false,
    this.showDateInRows = false,
    this.supportingContentBuilder,
    this.missingCategoryLabel,
    super.key,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final Set<String> possibleDuplicateIds;
  final String? possibleDuplicateLabel;
  final VoidCallback? onPossibleDuplicateTap;
  final ValueChanged<TransactionDto> onTap;
  final bool navigates;
  final bool groupByFinancialDate;
  final bool collapsibleMonthSections;
  final bool monthSectionsAsCards;
  final bool dashboardRowStyle;
  final bool wrapInCard;
  final bool showDateInRows;
  final Widget Function(BuildContext, TransactionDto)? supportingContentBuilder;
  final String? missingCategoryLabel;

  @override
  Widget build(BuildContext context) {
    final useMonthSections = groupByFinancialDate && !showDateInRows;
    final effectiveShowDateInRows = showDateInRows || useMonthSections;
    final rows = <TransactionDto, Widget>{
      for (final transaction in transactions)
        transaction: TransactionRow(
          transaction: transaction,
          masterData: masterData,
          paymentSourceNames: paymentSourceNames,
          missingCategoryLabel: missingCategoryLabel,
          showDate: effectiveShowDateInRows,
          showTags: !dashboardRowStyle,
          showCategoryPill: dashboardRowStyle,
          compactMoney: dashboardRowStyle,
          supportingContent: supportingContentBuilder?.call(
            context,
            transaction,
          ),
          possibleDuplicate: possibleDuplicateIds.contains(transaction.id),
          possibleDuplicateLabel: possibleDuplicateLabel,
          onPossibleDuplicateTap: onPossibleDuplicateTap,
          onTap: () => onTap(transaction),
          showNavigationIndicator: dashboardRowStyle ? false : navigates,
          variant: dashboardRowStyle
              ? ButlerlyTransactionRowVariant.dashboard
              : ButlerlyTransactionRowVariant.standard,
        ),
    };
    if (!groupByFinancialDate) {
      final list = ButlerlyTransactionList(children: rows.values.toList());
      return wrapInCard
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.subtleSurface,
                borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
                border: Border.all(color: context.colors.border),
              ),
              child: list,
            )
          : list;
    }

    if (useMonthSections) {
      return collapsibleMonthSections
          ? _collapsibleMonthGroupedList(context, rows)
          : _monthGroupedList(context, rows);
    }
    return _dayGroupedList(context, rows);
  }

  Widget _collapsibleMonthGroupedList(
    BuildContext context,
    Map<TransactionDto, Widget> rows,
  ) {
    final groups = <String, List<TransactionDto>>{};
    for (final transaction in transactions) {
      final month = _transactionMonth(transaction);
      final key = month == null
          ? 'pending'
          : '${month.year}-${month.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(transaction);
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    final entries = groups.entries.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(height: ButlerlySpacing.compact),
          _collapsibleMonthSection(
            context,
            entries[index],
            rows,
            locale: locale,
            initiallyExpanded: index == 0,
          ),
        ],
      ],
    );
  }

  Widget _collapsibleMonthSection(
    BuildContext context,
    MapEntry<String, List<TransactionDto>> entry,
    Map<TransactionDto, Widget> rows, {
    required String locale,
    required bool initiallyExpanded,
  }) {
    final label = _monthSectionLabel(
      context,
      entry.value.first,
      locale: locale,
    );
    final summary = _monthCardSummary(context, entry.value);
    final tile = ExpansionTile(
      key: ValueKey('transaction-month-${entry.key}'),
      initiallyExpanded: initiallyExpanded,
      tilePadding: monthSectionsAsCards
          ? const EdgeInsets.symmetric(horizontal: ButlerlySpacing.cardPadding)
          : EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
      shape: const Border(),
      collapsedShape: const Border(),
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(width: ButlerlySpacing.compact),
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary.countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(
                    summary.totalLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: ButlerlySpacing.compact),
        ],
      ),
      children: [
        ButlerlyTransactionList(
          children: [for (final transaction in entry.value) rows[transaction]!],
        ),
      ],
    );
    if (!monthSectionsAsCards) {
      return Material(type: MaterialType.transparency, child: tile);
    }
    return ButlerlyCard(
      key: ValueKey('transaction-month-card-${entry.key}'),
      padding: EdgeInsets.zero,
      semanticLabel: label,
      child: tile,
    );
  }

  _MonthCardSummary _monthCardSummary(
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

    final totalLabel = totals.entries
        .toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    final formattedTotals = totalLabel
        .map(
          (entry) => localizedCompactMoney(
            context,
            DecimalValue.sum(entry.value).toString(),
            entry.key,
          ),
        )
        .join(' · ');
    final count = transactions.length;
    return _MonthCardSummary(
      countLabel: context.l10n.text(
        count == 1 ? 'oneTransaction' : 'manyTransactions',
        {'count': '$count'},
      ),
      totalLabel: formattedTotals,
    );
  }

  Widget _monthGroupedList(
    BuildContext context,
    Map<TransactionDto, Widget> rows,
  ) {
    final groups = <String, List<TransactionDto>>{};
    for (final transaction in transactions) {
      final month = _transactionMonth(transaction);
      final key = month == null
          ? 'pending'
          : '${month.year}-${month.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(transaction);
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          if (entry.key != groups.entries.first.key)
            const SizedBox(height: ButlerlySpacing.section),
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthSectionLabel(
                    context,
                    entry.value.first,
                    locale: locale,
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${entry.value.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.compact),
          ButlerlyTransactionList(
            children: [
              for (final transaction in entry.value) rows[transaction]!,
            ],
          ),
        ],
      ],
    );
  }

  Widget _dayGroupedList(
    BuildContext context,
    Map<TransactionDto, Widget> rows,
  ) {
    final groups = <String, List<TransactionDto>>{};
    for (final transaction in transactions) {
      final date = transactionCalendarDate(
        transaction,
        fallback: DateTime(1970),
      );
      final key = '${date.year}-${date.month}-${date.day}';
      groups.putIfAbsent(key, () => []).add(transaction);
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          if (entry.key != groups.entries.first.key)
            const SizedBox(height: ButlerlySpacing.section),
          Row(
            children: [
              Expanded(
                child: Text(
                  transactionDateLabel(
                    entry.value.first,
                    pendingLabel: context.l10n.text('datePending'),
                    locale: locale,
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${entry.value.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.compact),
          ButlerlyTransactionList(
            children: [
              for (final transaction in entry.value) rows[transaction]!,
            ],
          ),
        ],
      ],
    );
  }

  String _monthSectionLabel(
    BuildContext context,
    TransactionDto transaction, {
    required String locale,
  }) {
    final month = _transactionMonth(transaction);
    if (month == null) return context.l10n.text('datePending');
    return DateFormat.yMMMM(locale).format(month);
  }

  DateTime? _transactionMonth(TransactionDto transaction) {
    final financialDate = transaction.financialDate;
    if (financialDate != null) {
      return DateTime(financialDate.year, financialDate.month);
    }
    final businessDate = transaction.transactionDate?.trim();
    if (businessDate != null && businessDate.isNotEmpty) {
      final parsed = DateTime.tryParse(businessDate);
      if (parsed != null) return DateTime(parsed.year, parsed.month);
    }

    final occurredAt = transaction.occurredAt;
    if (occurredAt == null) return null;
    final utc = occurredAt.toUtc();
    return DateTime(utc.year, utc.month);
  }
}


final class _MonthCardSummary {
  const _MonthCardSummary({
    required this.countLabel,
    required this.totalLabel,
  });

  final String countLabel;
  final String totalLabel;
}
