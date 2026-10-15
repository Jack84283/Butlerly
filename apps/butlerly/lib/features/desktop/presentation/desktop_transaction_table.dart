import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Desktop presentation of already-filtered transactions within one month.
///
/// The caller retains ownership of querying, sorting, grouping, totals,
/// expansion state, and transaction navigation. Only the row layout differs.
class DesktopTransactionTable extends StatelessWidget {
  const DesktopTransactionTable({
    required this.transactions,
    required this.masterData,
    required this.onTap,
    this.paymentSourceNames = const {},
    this.missingCategoryLabel,
    super.key,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final ValueChanged<TransactionDto> onTap;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('desktop-transactions-table'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: ButlerlySpacing.micro),
        child: Row(
          children: [
            SizedBox(width: 100, child: _header(context, 'date')),
            Expanded(flex: 3, child: _header(context, 'merchant')),
            Expanded(flex: 2, child: _header(context, 'category')),
            Expanded(flex: 2, child: _header(context, 'subcategory')),
            Expanded(flex: 2, child: _header(context, 'paymentSource')),
            SizedBox(
              width: 112,
              child: _header(context, 'amount', align: TextAlign.end),
            ),
          ],
        ),
      ),
      Divider(height: 12, color: context.colors.cardDivider),
      for (var index = 0; index < transactions.length; index++) ...[
        _transactionRow(context, transactions[index]),
        if (index < transactions.length - 1)
          Divider(
            height: 1,
            thickness: 1,
            color: context.colors.cardDivider,
          ),
      ],
    ],
  );

  Widget _header(
    BuildContext context,
    String label, {
    TextAlign align = TextAlign.start,
  }) => Text(
    context.l10n.text(label),
    textAlign: align,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: context.colors.secondaryText,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _transactionRow(BuildContext context, TransactionDto transaction) {
    final legacyParentId = transaction.subcategoryId == null
        ? masterData.categoryParentId(transaction.categoryId)
        : null;
    final categoryId = legacyParentId ?? transaction.categoryId;
    final subcategoryId =
        transaction.subcategoryId ??
        (legacyParentId == null ? null : transaction.categoryId);
    final sourceName = masterData.paymentSourceName(
      transaction.paymentSourceId,
    ) ?? paymentSourceNames[transaction.paymentSourceId];
    final sourceLabel = sourceName?.trim();
    final showSource = sourceLabel != null && sourceLabel.isNotEmpty;
    final categoryLabel = masterData.categoryName(categoryId) ??
        missingCategoryLabel ??
        context.l10n.text('uncategorized');
    final subcategoryLabel = masterData.categoryName(subcategoryId);
    final unsignedAmount = transaction.amount.replaceFirst(
      RegExp(r'^[+-]'),
      '',
    );
    final amount =
        '${transaction.direction == TransactionDirection.income.name ? '+' : '−'}${localizedCompactMoney(context, unsignedAmount, transaction.currency)}';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('desktop-transaction-row-${transaction.id}'),
        onTap: () => onTap(transaction),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: _rowText(context, _date(context, transaction)),
              ),
              Expanded(
                flex: 3,
                child: _rowText(
                  context,
                  transactionRowTitle(context, transaction, masterData),
                  strong: true,
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _categoryBadge(context, categoryId, categoryLabel),
                ),
              ),
              Expanded(
                flex: 2,
                child: _rowText(context, subcategoryLabel ?? '—'),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    if (showSource) ...[
                      ButlerlyPaymentMarkIcon(
                        mark: masterData.paymentSourceMark(
                              transaction.paymentSourceId,
                            ) ??
                            'other',
                        size: 20,
                      ),
                      const SizedBox(width: ButlerlySpacing.micro),
                    ],
                    Expanded(
                      child: _rowText(
                        context,
                        showSource ? sourceLabel : '—',
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 112,
                child: _rowText(
                  context,
                  amount,
                  align: TextAlign.end,
                  strong: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowText(
    BuildContext context,
    String value, {
    TextAlign align = TextAlign.start,
    bool strong = false,
  }) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: strong ? FontWeight.w600 : null,
    ),
  );

  Widget _categoryBadge(
    BuildContext context,
    String? categoryId,
    String label,
  ) {
    final identity = categoryId == null
        ? null
        : ButlerlyCategoryIdentity.forBuiltInId(categoryId);
    final color = identity == null
        ? context.colors.secondaryText
        : ButlerlyCategoryColors.color(identity.categoryColorId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.colors.primaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _date(BuildContext context, TransactionDto transaction) {
    final date = transaction.financialDate ??
        DateTime.tryParse(transaction.transactionDate ?? '') ??
        transaction.occurredAt?.toUtc();
    if (date == null) return context.l10n.text('datePending');
    return DateFormat.yMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(date);
  }
}
