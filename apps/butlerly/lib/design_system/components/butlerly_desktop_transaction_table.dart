import 'dart:math' as math;

import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The complete desktop transaction section, shared by Home and Search.
///
/// Owns the outer card, title/action row, inner-card inset and transaction
/// table. Hosts provide only their data, labels, actions and optional
/// expansion state; no parent is allowed to add another card around it.
class ButlerlyDesktopTransactionSection extends StatefulWidget {
  const ButlerlyDesktopTransactionSection({
    required this.title,
    required this.transactions,
    required this.masterData,
    required this.onTap,
    this.trailing,
    this.paymentSourceNames = const {},
    this.missingCategoryLabel,
    this.emptyMessage,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.prioritizeAmount = false,
    this.headerKey,
    this.innerCardKey,
    super.key,
  });

  static const double outerPadding = ButlerlyDesktopInnerCard.outerGutter;
  static const double titleTopPadding = 10;
  static const double titleContentGap = ButlerlySpacing.compact;

  final String title;
  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final ValueChanged<TransactionDto> onTap;
  final Widget? trailing;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final String? emptyMessage;
  final bool collapsible;
  final bool initiallyExpanded;
  final bool prioritizeAmount;
  final Key? headerKey;
  final Key? innerCardKey;

  @override
  State<ButlerlyDesktopTransactionSection> createState() =>
      _ButlerlyDesktopTransactionSectionState();
}

class _ButlerlyDesktopTransactionSectionState
    extends State<ButlerlyDesktopTransactionSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsible || widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant ButlerlyDesktopTransactionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsible != widget.collapsible ||
        oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      _expanded = !widget.collapsible || widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.primaryText,
            ),
          ),
        ),
        if (widget.trailing case final trailing?)
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: trailing,
            ),
          ),
        if (widget.collapsible) ...[
          const SizedBox(width: ButlerlySpacing.compact),
          Icon(_expanded ? Icons.expand_less : Icons.expand_more),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(ButlerlyRadius.card),
      ),
      padding: const EdgeInsets.fromLTRB(
        ButlerlyDesktopTransactionSection.outerPadding,
        ButlerlyDesktopTransactionSection.titleTopPadding,
        ButlerlyDesktopTransactionSection.outerPadding,
        ButlerlyDesktopTransactionSection.outerPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.collapsible)
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                key: widget.headerKey,
                onTap: () => setState(() => _expanded = !_expanded),
                child: header,
              ),
            )
          else
            header,
          if (_expanded) ...[
            const SizedBox(
              height: ButlerlyDesktopTransactionSection.titleContentGap,
            ),
            ButlerlyDesktopTransactionTableCard(
              key: widget.innerCardKey,
              transactions: widget.transactions,
              masterData: widget.masterData,
              onTap: widget.onTap,
              paymentSourceNames: widget.paymentSourceNames,
              missingCategoryLabel: widget.missingCategoryLabel,
              emptyMessage: widget.emptyMessage,
              prioritizeAmount: widget.prioritizeAmount,
            ),
          ],
        ],
      ),
    );
  }
}

/// Reusable desktop transaction content: one card surface and one table.
///
/// A full-width box ensures identical child constraints in Home's panel and
/// Search's expandable month sections; the single inner card owns all insets.
class ButlerlyDesktopTransactionTableCard extends StatelessWidget {
  const ButlerlyDesktopTransactionTableCard({
    required this.transactions,
    required this.masterData,
    required this.onTap,
    this.paymentSourceNames = const {},
    this.missingCategoryLabel,
    this.emptyMessage,
    this.selectedTransactionId,
    this.onSelectionChanged,
    this.prioritizeAmount = false,
    super.key,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final String? emptyMessage;
  final ValueChanged<TransactionDto> onTap;
  final String? selectedTransactionId;
  final ValueChanged<String>? onSelectionChanged;
  final bool prioritizeAmount;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ButlerlyDesktopInnerCard(
      child: ButlerlyDesktopTransactionTable(
        transactions: transactions,
        masterData: masterData,
        paymentSourceNames: paymentSourceNames,
        missingCategoryLabel: missingCategoryLabel,
        emptyMessage: emptyMessage,
        onTap: onTap,
        selectedTransactionId: selectedTransactionId,
        onSelectionChanged: onSelectionChanged,
        prioritizeAmount: prioritizeAmount,
      ),
    ),
  );
}

/// The reusable six-column desktop transaction table.
///
/// It consumes already-selected transactions and resolved master-data labels.
/// Hosts own querying, sorting, grouping, totals, card surfaces, refresh, and
/// navigation. Pass an [onTap] callback to preserve each host's own workflow.
///
/// All widths, localization and narrow-panel scrolling remain consistent
/// wherever the table is embedded (Home, Transactions, Search, or Review).
class ButlerlyDesktopTransactionTable extends StatelessWidget {
  const ButlerlyDesktopTransactionTable({
    required this.transactions,
    required this.masterData,
    required this.onTap,
    this.paymentSourceNames = const {},
    this.missingCategoryLabel,
    this.emptyMessage,
    this.selectedTransactionId,
    this.onSelectionChanged,
    this.prioritizeAmount = false,
    super.key,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final String? emptyMessage;
  final ValueChanged<TransactionDto> onTap;
  final String? selectedTransactionId;
  final ValueChanged<String>? onSelectionChanged;
  final bool prioritizeAmount;

  /// Minimum width needed to keep all six desktop columns readable.
  static const double minimumTableWidth = 760;
  static const double selectionColumnWidth = 52;
  static const double minimumAmountColumnWidth = 112;
  static const double _amountColumnSafetyInset = 8;
  static const int _flexColumnTotal = 9;
  static const int _merchantFlex = 3;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final amountColumnWidth = _amountColumnWidth(context, constraints);
      // The owning inner card provides the complete content inset.
      // Keep the table itself edge-to-edge within that padded space.
      final table = DefaultTextStyle(
        // The table's text must not depend on the host page's inherited style.
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: context.colors.primaryText),
        child: onSelectionChanged == null
            ? _buildTable(context, amountColumnWidth)
            : RadioGroup<String>(
                groupValue: selectedTransactionId,
                onChanged: (value) {
                  if (value != null) onSelectionChanged!(value);
                },
                child: _buildTable(context, amountColumnWidth),
              ),
      );
      final minimumWidth =
          minimumTableWidth +
          (prioritizeAmount
              ? 0
              : math.max(0, amountColumnWidth - minimumAmountColumnWidth)) +
          (onSelectionChanged == null ? 0 : selectionColumnWidth);
      if (constraints.maxWidth >= minimumWidth) return table;
      return SingleChildScrollView(
        key: const ValueKey('desktop-transaction-table-horizontal-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minimumWidth, child: table),
      );
    },
  );

  double _amountColumnWidth(BuildContext context, BoxConstraints constraints) {
    final amountStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          color: context.colors.error,
          fontWeight: FontWeight.bold,
        );
    final values = <String>[
      context.l10n.text('amount'),
      for (final transaction in transactions)
        _formatAmount(context, transaction),
    ];
    var measuredWidth = 0.0;
    for (final value in values) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: amountStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      measuredWidth = math.max(measuredWidth, painter.width);
    }
    measuredWidth += _amountColumnSafetyInset;
    final width = math.max(minimumAmountColumnWidth, measuredWidth);
    if (!prioritizeAmount || !constraints.maxWidth.isFinite) return width;

    // Keep the prioritized Amount column in the visible portion of a narrow
    // split view. If a localized value is wider than this allowance, its text
    // wraps inside the same header/row column instead of being ellipsized.
    final leadingWidth =
        (onSelectionChanged == null ? 0 : selectionColumnWidth) + 100;
    final tableWidth =
        minimumTableWidth +
        (onSelectionChanged == null ? 0 : selectionColumnWidth);
    final merchantShare =
        (tableWidth - leadingWidth - minimumAmountColumnWidth) *
        _merchantFlex /
        _flexColumnTotal;
    final maximumVisibleWidth =
        constraints.maxWidth - leadingWidth - merchantShare;
    final availableWidth = math.max(
      minimumAmountColumnWidth,
      maximumVisibleWidth - _amountColumnSafetyInset,
    );
    return math.min(width, availableWidth);
  }

  Widget _buildTable(BuildContext context, double amountColumnWidth) => Column(
    key: const ValueKey('desktop-transactions-table'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          if (onSelectionChanged != null)
            const SizedBox(width: selectionColumnWidth),
          SizedBox(
            key: const ValueKey('desktop-transaction-header-date'),
            width: 100,
            child: _header(context, 'date'),
          ),
          Expanded(
            key: const ValueKey('desktop-transaction-header-merchant'),
            flex: 3,
            child: _header(context, 'merchant'),
          ),
          if (prioritizeAmount)
            SizedBox(
              key: const ValueKey('desktop-transaction-header-amount'),
              width: amountColumnWidth,
              child: _header(context, 'amount', align: TextAlign.end),
            ),
          Expanded(
            key: const ValueKey('desktop-transaction-header-category'),
            flex: 2,
            child: _header(context, 'category'),
          ),
          Expanded(
            key: const ValueKey('desktop-transaction-header-subcategory'),
            flex: 2,
            child: _header(context, 'subcategory'),
          ),
          Expanded(
            key: const ValueKey('desktop-transaction-header-paymentSource'),
            flex: 2,
            child: _header(context, 'paymentSource'),
          ),
          if (!prioritizeAmount)
            SizedBox(
              key: const ValueKey('desktop-transaction-header-amount'),
              width: amountColumnWidth,
              child: _header(context, 'amount', align: TextAlign.end),
            ),
        ],
      ),
      const SizedBox(height: ButlerlyTableTokens.headerToRowsGap),
      Divider(
        height: ButlerlyTableTokens.dividerThickness,
        thickness: ButlerlyTableTokens.dividerThickness,
        color: ButlerlyTableTokens.dividerColor(context),
      ),
      for (final transaction in transactions) ...[
        _transactionRow(context, transaction, amountColumnWidth),
        Divider(
          height: ButlerlyTableTokens.dividerThickness,
          thickness: ButlerlyTableTokens.dividerThickness,
          color: ButlerlyTableTokens.dividerColor(context),
        ),
      ],
      if (transactions.isEmpty && emptyMessage != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(emptyMessage!),
        ),
    ],
  );

  Widget _header(
    BuildContext context,
    String label, {
    TextAlign align = TextAlign.start,
  }) => Text(
    context.l10n.text(label),
    style: ButlerlyTableTokens.headerTextStyle(context),
    textAlign: align,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _transactionRow(
    BuildContext context,
    TransactionDto transaction,
    double amountColumnWidth,
  ) {
    final legacyParentId = transaction.subcategoryId == null
        ? masterData.categoryParentId(transaction.categoryId)
        : null;
    final categoryId = legacyParentId ?? transaction.categoryId;
    final subcategoryId =
        transaction.subcategoryId ??
        (legacyParentId == null ? null : transaction.categoryId);
    final sourceName =
        masterData.paymentSourceName(transaction.paymentSourceId) ??
        paymentSourceNames[transaction.paymentSourceId];
    final sourceLabel = sourceName?.trim();
    final showSource = sourceLabel != null && sourceLabel.isNotEmpty;
    final categoryLabel =
        masterData.categoryName(categoryId) ??
        (categoryId == null
            ? context.l10n.text('uncategorized')
            : missingCategoryLabel ?? context.l10n.text('unavailableCategory'));
    final subcategoryLabel = masterData.categoryName(subcategoryId);
    final amount = _formatAmount(context, transaction);

    final dateCell = SizedBox(
      key: ValueKey('desktop-transaction-cell-date-${transaction.id}'),
      width: 100,
      child: _rowText(context, _date(context, transaction)),
    );
    final merchantCell = Expanded(
      key: ValueKey('desktop-transaction-cell-merchant-${transaction.id}'),
      flex: 3,
      child: _rowText(
        context,
        masterData.merchantName(transaction.merchantId) ??
            transaction.rawCounterparty ??
            transaction.description ??
            context.l10n.text('untitledTransaction'),
        fontWeight: FontWeight.bold,
      ),
    );
    final categoryCell = Expanded(
      key: ValueKey('desktop-transaction-cell-category-${transaction.id}'),
      flex: 2,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: _categoryBadge(context, categoryId, categoryLabel),
      ),
    );
    final subcategoryCell = Expanded(
      key: ValueKey('desktop-transaction-cell-subcategory-${transaction.id}'),
      flex: 2,
      child: _rowText(context, subcategoryLabel ?? '—'),
    );
    final paymentSourceCell = Expanded(
      key: ValueKey('desktop-transaction-cell-paymentSource-${transaction.id}'),
      flex: 2,
      child: Row(
        children: [
          if (showSource) ...[
            ButlerlyPaymentMarkIcon(
              mark:
                  masterData.paymentSourceMark(transaction.paymentSourceId) ??
                  'other',
              size: 20,
            ),
            const SizedBox(width: ButlerlySpacing.micro),
          ],
          Expanded(child: _rowText(context, sourceLabel ?? '—')),
        ],
      ),
    );
    final amountCell = SizedBox(
      key: ValueKey('desktop-transaction-cell-amount-${transaction.id}'),
      width: amountColumnWidth,
      child: _rowText(
        context,
        amount,
        align: TextAlign.end,
        color: context.colors.error,
        fontWeight: FontWeight.bold,
        maxLines: null,
        overflow: null,
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('desktop-transaction-row-${transaction.id}'),
        onTap: () => onTap(transaction),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: ButlerlyTableTokens.rowVerticalPadding,
          ),
          child: Row(
            children: [
              if (onSelectionChanged != null)
                SizedBox(
                  width: selectionColumnWidth,
                  child: Radio<String>(
                    key: ValueKey('duplicate-select-${transaction.id}'),
                    value: transaction.id,
                  ),
                ),
              dateCell,
              merchantCell,
              if (prioritizeAmount) amountCell,
              categoryCell,
              subcategoryCell,
              paymentSourceCell,
              if (!prioritizeAmount) amountCell,
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(BuildContext context, TransactionDto transaction) {
    final numericAmount = double.tryParse(transaction.amount);
    return numericAmount == null
        ? '—'
        : '${transaction.direction == 'income' ? '+' : '−'}${NumberFormat.simpleCurrency(name: transaction.currency, locale: Localizations.localeOf(context).toString()).format(numericAmount.abs())}';
  }

  Widget _rowText(
    BuildContext context,
    String value, {
    TextAlign align = TextAlign.start,
    FontWeight? fontWeight,
    Color? color,
    int? maxLines = 1,
    TextOverflow? overflow = TextOverflow.ellipsis,
  }) => Text(
    value,
    style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: color ?? context.colors.primaryText,
          fontWeight: fontWeight,
        ),
    maxLines: maxLines,
    overflow: overflow,
    textAlign: align,
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
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : ButlerlyCategoryColors.color(identity.categoryColorId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _date(BuildContext context, TransactionDto transaction) {
    final date =
        transaction.financialDate ??
        DateTime.tryParse(transaction.transactionDate ?? '') ??
        transaction.occurredAt;
    if (date == null) return '—';
    return DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    ).format(date);
  }
}
