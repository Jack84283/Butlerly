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
    super.key,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final String? emptyMessage;
  final ValueChanged<TransactionDto> onTap;

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
    super.key,
  });

  final List<TransactionDto> transactions;
  final TransactionMasterData masterData;
  final Map<String, String> paymentSourceNames;
  final String? missingCategoryLabel;
  final String? emptyMessage;
  final ValueChanged<TransactionDto> onTap;

  /// Minimum width needed to keep all six desktop columns readable.
  static const double minimumTableWidth = 760;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The owning inner card provides the complete content inset.
      // Keep the table itself edge-to-edge within that padded space.
      final table = DefaultTextStyle(
        // The table's text must not depend on the host page's inherited style.
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: context.colors.primaryText),
        child: _buildTable(context),
      );
      if (constraints.maxWidth >= minimumTableWidth) return table;
      return SingleChildScrollView(
        key: const ValueKey('desktop-transaction-table-horizontal-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minimumTableWidth, child: table),
      );
    },
  );

  Widget _buildTable(BuildContext context) => Column(
    key: const ValueKey('desktop-transactions-table'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
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
      Divider(height: 12, color: context.colors.cardDivider),
      for (final transaction in transactions) ...[
        _transactionRow(context, transaction),
        Divider(height: 1, thickness: 1, color: context.colors.cardDivider),
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
    style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: context.colors.primaryText,
          fontWeight: FontWeight.w600,
        ),
    textAlign: align,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _transactionRow(BuildContext context, TransactionDto transaction) {
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
    final numericAmount = double.tryParse(transaction.amount);
    final amount = numericAmount == null
        ? '—'
        : '${transaction.direction == 'income' ? '+' : '−'}${NumberFormat.simpleCurrency(name: transaction.currency, locale: Localizations.localeOf(context).toString()).format(numericAmount.abs())}';

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
                  masterData.merchantName(transaction.merchantId) ??
                      transaction.rawCounterparty ??
                      transaction.description ??
                      context.l10n.text('untitledTransaction'),
                  fontWeight: FontWeight.bold,
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
                        mark:
                            masterData.paymentSourceMark(
                              transaction.paymentSourceId,
                            ) ??
                            'other',
                        size: 20,
                      ),
                      const SizedBox(width: ButlerlySpacing.micro),
                    ],
                    Expanded(child: _rowText(context, sourceLabel ?? '—')),
                  ],
                ),
              ),
              SizedBox(
                width: 112,
                child: _rowText(
                  context,
                  amount,
                  align: TextAlign.end,
                  color: context.colors.error,
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
    FontWeight? fontWeight,
    Color? color,
  }) => Text(
    value,
    style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: color ?? context.colors.primaryText,
          fontWeight: fontWeight,
        ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
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
