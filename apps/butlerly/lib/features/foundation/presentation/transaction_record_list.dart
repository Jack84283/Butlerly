import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

/// The shared transaction presentation for Transactions, Search, and Home.
/// Grouping is presentation-only; the input order inside each date group is
/// preserved so domain sorting and filtering remain owned by the caller.
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

  @override
  Widget build(BuildContext context) {
    final rows = <TransactionDto, Widget>{
      for (final transaction in transactions)
        transaction: _row(context, transaction),
    };
    if (!groupByFinancialDate) {
      final list = ButlerlyTransactionList(children: rows.values.toList());
      return wrapInCard
          ? ButlerlyCard(padding: EdgeInsets.zero, child: list)
          : list;
    }

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
          Text(
            transactionDateLabel(
              entry.value.first,
              pendingLabel: context.l10n.text('datePending'),
              locale: locale,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ButlerlySpacing.small),
          ButlerlyCard(
            padding: EdgeInsets.zero,
            child: ButlerlyTransactionList(
              children: [
                for (final transaction in entry.value) rows[transaction]!,
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, TransactionDto transaction) {
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
    final title = transaction.description?.trim().isNotEmpty == true
        ? transaction.description!.trim()
        : context.l10n.text('untitledTransaction');
    return ButlerlyRecordRow(
      title: title,
      amount: localizedTransactionAmount(
        context,
        transaction.amount.replaceFirst(RegExp(r'^[+-]'), ''),
      ),
      currency: transaction.currency,
      categoryId: iconCategoryId,
      // An empty label intentionally selects canonical mode so uncategorized
      // rows still receive the neutral leading icon and signed amount layout.
      categoryLabel: parent ?? category ?? '',
      subcategoryLabel: parent == null ? null : category,
      paymentSource: sourceLabel,
      tags: tags,
      meta: showDateInRows
          ? transactionDateLabel(
              transaction,
              pendingLabel: context.l10n.text('datePending'),
              locale: Localizations.localeOf(context).toLanguageTag(),
            )
          : null,
      showDate: showDateInRows,
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
