import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
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
          showTags: true,
          supportingContent: supportingContentBuilder?.call(
            context,
            transaction,
          ),
          possibleDuplicate: possibleDuplicateIds.contains(transaction.id),
          possibleDuplicateLabel: possibleDuplicateLabel,
          onPossibleDuplicateTap: onPossibleDuplicateTap,
          onTap: () => onTap(transaction),
          showNavigationIndicator: navigates,
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
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.subtleSurface,
              borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
              border: Border.all(color: context.colors.border),
            ),
            child: ExpansionTile(
              key: ValueKey('transaction-month-${entries[index].key}'),
              initiallyExpanded: index == 0,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: ButlerlySpacing.standard,
              ),
              childrenPadding: const EdgeInsets.only(
                left: ButlerlySpacing.standard,
                right: ButlerlySpacing.standard,
                bottom: ButlerlySpacing.standard,
              ),
              title: Text(
                _monthSectionLabel(
                  context,
                  entries[index].value.first,
                  locale: locale,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                context.l10n.text('transactionCount', {
                  'count': '${entries[index].value.length}',
                }),
              ),
              children: [
                ButlerlyTransactionList(
                  children: [
                    for (final transaction in entries[index].value)
                      rows[transaction]!,
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
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
