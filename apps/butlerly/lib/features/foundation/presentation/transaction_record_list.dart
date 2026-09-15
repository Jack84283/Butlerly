import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The shared transaction presentation for Transactions, Search, Home, and
/// Review.
///
/// Grouping is presentation-only; the input order inside each group is
/// preserved so domain sorting and filtering remain owned by the caller.
/// Transaction/Search ledger callers use [groupByFinancialDate] without
/// [showDateInRows], which presents month section headers and moves the full
/// transaction date into each row. Review callers that already set
/// [showDateInRows] retain day-level grouping.
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
        transaction: _row(
          context,
          transaction,
          showDateInRow: effectiveShowDateInRows,
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
      return _monthGroupedList(context, rows);
    }
    return _dayGroupedList(context, rows);
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

  Widget _row(
    BuildContext context,
    TransactionDto transaction, {
    required bool showDateInRow,
  }) {
    final categoryId = transaction.categoryId;
    final iconCategoryId =
        categoryId != null &&
            ButlerlyCategoryIdentity.forBuiltInId(categoryId) != null
        ? categoryId
        : null;
    final parentId = masterData.categoryParentId(categoryId);
    final category = masterData.categoryName(categoryId);
    final parent = masterData.categoryName(parentId);
    final source = transaction.paymentSourceId == null
        ? null
        : paymentSourceNames[transaction.paymentSourceId!];
    final sourceLabel = source == null || source.trim().isEmpty ? null : source;
    final tags = transaction.tagIds
        .map(masterData.tagName)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    final merchant = masterData.merchantName(transaction.merchantId)?.trim();
    final description = transaction.description?.trim();
    final rawCounterparty = transaction.rawCounterparty?.trim();
    final title = merchant?.isNotEmpty == true
        ? merchant!
        : description?.isNotEmpty == true
        ? description!
        : rawCounterparty?.isNotEmpty == true
        ? rawCounterparty!
        : context.l10n.text('untitledTransaction');
    return ButlerlyRecordRow(
      title: title,
      amount: localizedTransactionAmount(
        context,
        transaction.amount.replaceFirst(RegExp(r'^[+-]'), ''),
      ),
      currency: transaction.currency,
      categoryId: iconCategoryId,
      categoryLabel: parent ?? category ?? missingCategoryLabel ?? '',
      subcategoryLabel: parent == null ? null : category,
      paymentSource: sourceLabel,
      tags: tags,
      supportingContent: supportingContentBuilder?.call(context, transaction),
      meta: showDateInRow
          ? transactionDateLabel(
              transaction,
              pendingLabel: context.l10n.text('datePending'),
              locale: Localizations.localeOf(context).toLanguageTag(),
            )
          : null,
      showDate: showDateInRow,
      isIncome: transaction.direction == TransactionDirection.income.name,
      needsReview: transaction.reviewState == 'needsReview',
      possibleDuplicate: possibleDuplicateIds.contains(transaction.id),
      possibleDuplicateLabel: possibleDuplicateLabel,
      onPossibleDuplicateTap: onPossibleDuplicateTap,
      onTap: () => onTap(transaction),
      showNavigationIndicator: navigates,
    );
  }
}
