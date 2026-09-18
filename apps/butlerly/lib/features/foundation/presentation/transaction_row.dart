import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

/// Canonical transaction-row presentation used across Butlerly.
///
/// Screens provide the transaction, resolved master data, and interaction
/// affordances. This component owns the semantic mapping from transaction data
/// to the visual row so title, amount, metadata, state, and fallbacks cannot
/// drift between Home, Transactions, Search, and Review. Surface-specific
/// density choices such as tag visibility remain explicit inputs.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.transaction,
    required this.onTap,
    this.masterData = const TransactionMasterData(),
    this.paymentSourceNames = const {},
    this.missingCategoryLabel,
    this.showDate = false,
    this.showTags = false,
    this.supportingContent,
    this.possibleDuplicate = false,
    this.possibleDuplicateLabel,
    this.onPossibleDuplicateTap,
    this.showNavigationIndicator = false,
    super.key,
  });

  final TransactionDto transaction;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final bool showDate;
  final bool showTags;
  final Widget? supportingContent;
  final bool possibleDuplicate;
  final String? possibleDuplicateLabel;
  final VoidCallback? onPossibleDuplicateTap;
  final VoidCallback onTap;
  final bool showNavigationIndicator;

  @override
  Widget build(BuildContext context) {
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
        : masterData.paymentSourceName(transaction.paymentSourceId) ??
              paymentSourceNames[transaction.paymentSourceId!];
    final sourceLabel = source == null || source.trim().isEmpty
        ? null
        : source.trim();
    final tags = showTags
        ? transaction.tagIds
              .map(masterData.tagName)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return ButlerlyRecordRow(
      title: transactionRowTitle(context, transaction, masterData),
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
      supportingContent: supportingContent,
      meta: showDate
          ? transactionDateLabel(
              transaction,
              pendingLabel: context.l10n.text('datePending'),
              locale: Localizations.localeOf(context).toLanguageTag(),
            )
          : null,
      showDate: showDate,
      isIncome: transaction.direction == TransactionDirection.income.name,
      needsReview: transaction.reviewState == 'needsReview',
      possibleDuplicate: possibleDuplicate,
      possibleDuplicateLabel: possibleDuplicateLabel,
      onPossibleDuplicateTap: onPossibleDuplicateTap,
      onTap: onTap,
      showNavigationIndicator: showNavigationIndicator,
    );
  }
}

/// Single title policy for transaction rows.
///
/// Merchant is the preferred human-readable identity. Imported/manual text is
/// retained as a fallback when no merchant master-data reference is available.
String transactionRowTitle(
  BuildContext context,
  TransactionDto transaction,
  TransactionMasterData masterData,
) {
  for (final candidate in [
    masterData.merchantName(transaction.merchantId),
    transaction.description,
    transaction.rawCounterparty,
  ]) {
    if (candidate != null && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }
  return context.l10n.text('untitledTransaction');
}
