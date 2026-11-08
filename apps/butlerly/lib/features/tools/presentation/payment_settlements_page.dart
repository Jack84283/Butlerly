import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_transaction_table.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class PaymentSettlementsPage extends StatefulWidget {
  const PaymentSettlementsPage({super.key});

  @override
  State<PaymentSettlementsPage> createState() => _PaymentSettlementsPageState();
}

class _PaymentSettlementsPageState extends State<PaymentSettlementsPage> {
  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  late Future<_SettlementListData> _data = _load();

  @override
  void initState() {
    super.initState();
    workspaceRestoreChanges.addListener(_onWorkspaceRestored);
  }

  @override
  void dispose() {
    workspaceRestoreChanges.removeListener(_onWorkspaceRestored);
    super.dispose();
  }

  void _onWorkspaceRestored() {
    if (!mounted) return;
    setState(() => _data = _load());
  }

  Future<_SettlementListData> _load() async {
    final finance = _finance;
    final listSettlements = finance?.listPaymentSettlements;
    if (finance == null || listSettlements == null) {
      throw StateError('Payment settlements are unavailable.');
    }
    final settlementResult = await listSettlements();
    final sourceResult = await finance.listPaymentSources();
    if (settlementResult case ApplicationSuccess<List<PaymentSettlementDto>>(
      value: final settlements,
    )) {
      if (sourceResult case ApplicationSuccess<List<PaymentSource>>(
        value: final sources,
      )) {
        return _SettlementListData(settlements: settlements, sources: sources);
      }
    }
    throw StateError('Payment settlements could not be loaded.');
  }

  Future<void> _refresh() async {
    setState(() => _data = _load());
    await _data;
  }

  /// The Add action should never strand a user in a prerequisite sheet.
  /// A missing active credit card opens the real Payment Sources create page,
  /// then resumes settlement entry when the source has been saved.
  Future<void> _onAddSettlement(_SettlementListData data) async {
    if (data.activeCardSources.isNotEmpty) {
      await _createSettlement(data);
      return;
    }

    final bool? created;
    if (GoRouter.maybeOf(context) != null) {
      created = await context.push<bool>(
        '/payment-sources?create=true&from=settlements',
      );
    } else {
      // Routerless host contexts (including widget tests) use the same
      // prerequisite flow with an explicit Scaffold.
      created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: PaymentSourcesPage(
              openCreateOnStart: true,
              fromPaymentSettlement: true,
            ),
          ),
        ),
      );
    }
    if (!mounted || created != true) return;

    await _refresh();
    if (!mounted) return;
    final updated = await _data;
    if (!mounted) return;
    if (updated.activeCardSources.isNotEmpty) {
      await _createSettlement(updated);
    } else {
      _showMessage(context.l10n.text('paymentSettlementNeedsCardSource'));
    }
  }

  /// Let desktop users inspect, activate, or add Payment Sources without
  /// losing settlement history. Refresh eligible cards after returning.
  Future<void> _managePaymentSources() async {
    if (GoRouter.maybeOf(context) != null) {
      await context.push<void>('/payment-sources');
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: PaymentSourcesPage()),
        ),
      );
    }
    if (mounted) await _refresh();
  }

  Future<void> _createSettlement(_SettlementListData data) async {
    final finance = _finance;
    final save = finance?.savePaymentSettlement;
    if (finance == null || save == null) {
      _showMessage(context.l10n.text('paymentSettlementSaveFailed'));
      return;
    }
    final draft = await _openSettlementEditorPage(
      context: context,
      sources: data.activeCardSources,
    );
    if (!mounted || draft == null) return;

    final token = DateTime.now().microsecondsSinceEpoch;
    final result = await save(
      id: 'settlement-$token',
      paymentSourceId: draft.paymentSourceId,
      payment: Money(
        amount: DecimalValue.parse(draft.amount),
        currency: CurrencyCode(draft.currency),
      ),
      paymentDate: draft.paymentDate,
      periodStart: draft.periodStart,
      periodEnd: draft.periodEnd,
      statementBalance: draft.statementBalance == null
          ? null
          : Money(
              amount: DecimalValue.parse(draft.statementBalance!),
              currency: CurrencyCode(draft.currency),
            ),
      description: draft.description,
      externalReference: draft.externalReference,
    );
    if (!mounted) return;
    if (result is ApplicationFailure<PaymentSettlementDto>) {
      _showMessage(context.l10n.text('paymentSettlementSaveFailed'));
      return;
    }

    _showMessage(context.l10n.text('paymentSettlementSaved'));
    await _refresh();
  }

  Future<void> _openSettlement(
    PaymentSettlementDto settlement,
    _SettlementListData data,
  ) async {
    final finance = _finance;
    if (finance == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentSettlementDetailPage(
          finance: finance,
          settlementId: settlement.id,
          sourceNames: data.sourceNames,
          sources: data.sources,
        ),
      ),
    );
    if (changed == true && mounted) await _refresh();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    if (_finance?.listPaymentSettlements == null) {
      return ButlerlyEmptyState(
        icon: Icons.storage_outlined,
        title: context.l10n.text('localStorageUnavailable'),
        message: context.l10n.text('dataPreserved'),
      );
    }

    return FutureBuilder<_SettlementListData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ButlerlyLoadingState();
        }
        if (snapshot.hasError) {
          return ButlerlyErrorState(
            title: context.l10n.text('paymentSettlements'),
            message: context.l10n.text('tryAgain'),
            preserved: context.l10n.text('dataPreserved'),
            actionLabel: context.l10n.text('tryAgain'),
            onAction: _refresh,
          );
        }
        final data = snapshot.requireData;
        return ButlerlyPage(
          title: context.l10n.text('paymentSettlements'),
          fullWidth: desktop,
          subtitle: context.l10n.text('paymentSettlementsSubtitle'),
          onRefresh: _refresh,
          actions: [
            ButlerlyHeaderAddButton(
              buttonKey: const ValueKey('payment-settlements-add'),
              closeToHelp: true,
              label: context.l10n.text('addPaymentSettlement'),
              onPressed: () => _onAddSettlement(data),
            ),
          ],
          children: [
            if (desktop) ...[
              _SettlementDesktopSources(
                data: data,
                onManage: _managePaymentSources,
                onAdd: () => _onAddSettlement(data),
              ),
              const SizedBox(height: ButlerlySpacing.cardGap),
              // Do not hide saved settlements when their source is archived.
              if (data.settlements.isNotEmpty) ...[
                _SettlementDesktopOverview(data: data),
                const SizedBox(height: ButlerlySpacing.cardGap),
                _SettlementDesktopTable(
                  data: data,
                  onOpen: (settlement) => _openSettlement(settlement, data),
                ),
              ] else
                ButlerlyEmptyState(
                  icon: Icons.credit_score_outlined,
                  title: context.l10n.text('noPaymentSettlements'),
                  message: data.activeCardSources.isEmpty
                      ? context.l10n.text('paymentSettlementNeedsCardSource')
                      : context.l10n.text('noPaymentSettlementsBody'),
                  actionLabel: context.l10n.text(
                    data.activeCardSources.isEmpty
                        ? 'addPaymentSource'
                        : 'addPaymentSettlement',
                  ),
                  onAction: () => _onAddSettlement(data),
                ),
            ] else if (data.settlements.isNotEmpty) ...[
              // Historical settlements remain accessible even if a card
              // source is archived or none are currently eligible.
              for (final settlement in data.settlements) ...[
                _SettlementCard(
                  settlement: settlement,
                  sourceName:
                      data.sourceNames[settlement.paymentSourceId] ??
                      settlement.paymentSourceId,
                  onTap: () => _openSettlement(settlement, data),
                ),
                const SizedBox(height: ButlerlySpacing.small),
              ],
            ] else if (data.activeCardSources.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.credit_card_off_outlined,
                title: context.l10n.text('paymentSources'),
                message: context.l10n.text('paymentSettlementNeedsCardSource'),
                actionLabel: context.l10n.text('addPaymentSource'),
                onAction: () => _onAddSettlement(data),
              )
            else
              ButlerlyEmptyState(
                icon: Icons.credit_score_outlined,
                title: context.l10n.text('noPaymentSettlements'),
                message: context.l10n.text('noPaymentSettlementsBody'),
                actionLabel: context.l10n.text('addPaymentSettlement'),
                onAction: () => _createSettlement(data),
              ),
            const SizedBox(height: ButlerlySpacing.structural),
          ],
        );
      },
    );
  }
}

class PaymentSettlementDetailPage extends StatefulWidget {
  const PaymentSettlementDetailPage({
    required this.finance,
    required this.settlementId,
    required this.sourceNames,
    required this.sources,
    super.key,
  });

  final FinanceServices finance;
  final String settlementId;
  final Map<String, String> sourceNames;
  final List<PaymentSource> sources;

  @override
  State<PaymentSettlementDetailPage> createState() =>
      _PaymentSettlementDetailPageState();
}

class _PaymentSettlementDetailPageState
    extends State<PaymentSettlementDetailPage> {
  late Future<PaymentSettlementDetailDto> _detail = _load();
  TransactionMasterData _masterData = const TransactionMasterData();
  String? _loadedLanguageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    TransactionMasterData.load(widget.finance, languageCode: languageCode).then(
      (value) {
        if (!mounted || _loadedLanguageCode != languageCode) return;
        setState(() => _masterData = value);
      },
    );
  }

  Future<PaymentSettlementDetailDto> _load() async {
    final getDetail = widget.finance.getPaymentSettlementDetail;
    if (getDetail == null) {
      throw StateError('Payment settlement detail is unavailable.');
    }
    final result = await getDetail(widget.settlementId);
    if (result case ApplicationSuccess<PaymentSettlementDetailDto>(
      value: final detail,
    )) {
      return detail;
    }
    throw StateError('Payment settlement detail could not be loaded.');
  }

  Future<void> _refresh() async {
    final detail = _load();
    final languageCode =
        _loadedLanguageCode ?? Localizations.localeOf(context).languageCode;
    final masterData = TransactionMasterData.load(
      widget.finance,
      languageCode: languageCode,
    );
    setState(() => _detail = detail);
    await detail;
    final refreshedMasterData = await masterData;
    if (!mounted || _loadedLanguageCode != languageCode) return;
    setState(() => _masterData = refreshedMasterData);
  }

  Future<void> _openTransaction(TransactionDto transaction) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionDetailPage(
          finance: widget.finance,
          transaction: transaction,
        ),
      ),
    );
    if (changed == true && mounted) await _refresh();
  }

  Future<void> _edit(PaymentSettlementDetailDto detail) async {
    final save = widget.finance.savePaymentSettlement;
    if (save == null) return;
    final draft = await _openSettlementEditorPage(
      context: context,
      sources: widget.sources,
      existing: detail,
    );
    if (!mounted || draft == null) return;

    final result = await save(
      id: detail.settlement.id,
      paymentSourceId: detail.settlement.paymentSourceId,
      payment: Money(
        amount: DecimalValue.parse(draft.amount),
        currency: CurrencyCode(draft.currency),
      ),
      paymentDate: draft.paymentDate,
      periodStart: draft.periodStart,
      periodEnd: draft.periodEnd,
      status: detail.settlement.status,
      statementBalance: draft.statementBalance == null
          ? null
          : Money(
              amount: DecimalValue.parse(draft.statementBalance!),
              currency: CurrencyCode(draft.currency),
            ),
      description: draft.description,
      externalReference: draft.externalReference,
    );
    if (!mounted) return;
    if (result is ApplicationFailure<PaymentSettlementDto>) {
      _showMessage(context.l10n.text('paymentSettlementSaveFailed'));
      return;
    }
    _showMessage(context.l10n.text('paymentSettlementSaved'));
    await _refresh();
  }

  Future<void> _setStatus(PaymentSettlementStatus status) async {
    final setStatus = widget.finance.setPaymentSettlementStatus;
    if (setStatus == null) return;
    final result = await setStatus(widget.settlementId, status);
    if (!mounted) return;
    if (result is ApplicationFailure<PaymentSettlementDto>) {
      _showMessage(context.l10n.text('paymentSettlementSaveFailed'));
      return;
    }
    await _refresh();
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showButlerlySelectionSheet<_SettlementAction>(
      context: context,
      title: context.l10n.text('paymentSettlement'),
      options: [
        ButlerlySelectionOption(
          value: _SettlementAction.open,
          child: Text(context.l10n.text('markAsOpen')),
        ),
        ButlerlySelectionOption(
          value: _SettlementAction.reconciled,
          child: Text(context.l10n.text('markAsReconciled')),
        ),
        ButlerlySelectionOption(
          value: _SettlementAction.needsReview,
          child: Text(context.l10n.text('markNeedsReview')),
        ),
        ButlerlySelectionOption(
          value: _SettlementAction.remove,
          child: Text(context.l10n.text('remove')),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == _SettlementAction.remove) {
      await _remove();
      return;
    }
    final status = switch (action) {
      _SettlementAction.open => PaymentSettlementStatus.open,
      _SettlementAction.reconciled => PaymentSettlementStatus.reconciled,
      _SettlementAction.needsReview => PaymentSettlementStatus.needsReview,
      _SettlementAction.remove => PaymentSettlementStatus.open,
    };
    await _setStatus(status);
  }

  Future<void> _remove() async {
    final remove = widget.finance.deletePaymentSettlement;
    if (remove == null) return;
    final confirmed = await showButlerlyConfirmationSheet(
      context: context,
      title: context.l10n.text('paymentSettlementRemoveTitle'),
      message: context.l10n.text('paymentSettlementRemoveBody'),
      cancelLabel: context.l10n.text('cancel'),
      confirmLabel: context.l10n.text('remove'),
      destructive: true,
    );
    if (!mounted || confirmed != true) return;
    final result = await remove(widget.settlementId);
    if (!mounted) return;
    if (result is ApplicationFailure<void>) {
      _showMessage(context.l10n.text('dataPreserved'));
      return;
    }
    _showMessage(context.l10n.text('paymentSettlementRemoved'));
    Navigator.of(context).pop(true);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide;
    return FutureBuilder<PaymentSettlementDetailDto>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: ButlerlyLoadingState());
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(context.l10n.text('paymentSettlements')),
              actions: const [ButlerlyContextHelpButton(articleId: 'ch-16')],
            ),
            body: ButlerlyErrorState(
              title: context.l10n.text('paymentSettlements'),
              message: context.l10n.text('tryAgain'),
              preserved: context.l10n.text('dataPreserved'),
              actionLabel: context.l10n.text('tryAgain'),
              onAction: _refresh,
            ),
          );
        }
        final detail = snapshot.requireData;
        final settlement = detail.settlement;
        final sourceName =
            widget.sourceNames[settlement.paymentSourceId] ??
            settlement.paymentSourceId;
        return Scaffold(
          body: ButlerlyPage(
            title: context.l10n.text('paymentSettlement'),
            fullWidth: desktop,
            onRefresh: _refresh,
            actions: [
              IconButton(
                tooltip: context.l10n.text('editPaymentSettlement'),
                onPressed: () => _edit(detail),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: context.l10n.text('more'),
                onPressed: () => _showActions(context),
                icon: const Icon(Icons.more_vert),
              ),
            ],
            children: [
              _SettlementBasicInfoCard(detail: detail, sourceName: sourceName),
              ButlerlySectionHeader(
                title: context.l10n.text('paymentSettlementComparison'),
              ),
              _SettlementComparisonCard(detail: detail),
              ButlerlySectionHeader(
                title: context.l10n.text(
                  'paymentSettlementPeriodTransactions',
                  {'count': '${detail.transactionCount}'},
                ),
              ),
              if (detail.transactions.isEmpty)
                ButlerlyEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: context.l10n.text('noTransactions'),
                  message: context.l10n.text('noActivityInPeriod'),
                )
              else if (desktop)
                ButlerlyDesktopTransactionTableCard(
                  transactions: detail.transactions,
                  masterData: _masterData,
                  paymentSourceNames: widget.sourceNames,
                  onTap: _openTransaction,
                )
              else
                ButlerlyTransactionInnerCard(
                  child: ButlerlyTransactionList(
                    children: [
                      for (final transaction in detail.transactions)
                        TransactionRow(
                          transaction: transaction,
                          masterData: _masterData,
                          paymentSourceNames: widget.sourceNames,
                          showDate: true,
                          showNavigationIndicator: true,
                          onTap: () => _openTransaction(transaction),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: ButlerlySpacing.structural),
            ],
          ),
        );
      },
    );
  }
}

/// Connect Payment Settlements to its eligible card sources on desktop.
/// Other source types remain managed in Payment Sources, and archived cards
/// still resolve historic settlement labels without becoming selectable.
class _SettlementDesktopSources extends StatelessWidget {
  const _SettlementDesktopSources({
    required this.data,
    required this.onManage,
    required this.onAdd,
  });

  final _SettlementListData data;
  final VoidCallback onManage;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final activeCards = data.activeCardSources;
    return ButlerlyCard(
      child: Column(
        key: const ValueKey('desktop-settlement-payment-sources'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.text('paymentSources'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('desktop-settlement-manage-sources'),
                onPressed: onManage,
                icon: const Icon(Icons.credit_card_outlined),
                label: Text(context.l10n.text('viewAll')),
              ),
            ],
          ),
          const SizedBox(height: ButlerlySpacing.compact),
          if (activeCards.isEmpty)
            Text(
              context.l10n.text('paymentSettlementNeedsCardSource'),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: ButlerlySpacing.compact,
              runSpacing: ButlerlySpacing.compact,
              children: [
                for (final source in activeCards)
                  Chip(
                    key: ValueKey('settlement-eligible-source-${source.id.value}'),
                    avatar: const Icon(Icons.credit_card_outlined, size: 18),
                    label: Text(paymentSourceDisplayLabel(source)),
                  ),
              ],
            ),
          if (activeCards.isEmpty) ...[
            const SizedBox(height: ButlerlySpacing.standard),
            OutlinedButton.icon(
              key: const ValueKey('desktop-settlement-add-source'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.text('addPaymentSource')),
            ),
          ],
        ],
      ),
    );
  }
}

/// High-level desktop counters. These are counts, never summed across currencies.
class _SettlementDesktopOverview extends StatelessWidget {
  const _SettlementDesktopOverview({required this.data});

  final _SettlementListData data;

  @override
  Widget build(BuildContext context) {
    final settlements = data.settlements;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = <Widget>[
          _SettlementCounterCard(
            label: context.l10n.text('paymentSettlements'),
            count: settlements.length,
          ),
          _SettlementCounterCard(
            label: context.l10n.text('paymentSettlementOpen'),
            count: settlements
                .where((value) => value.status == PaymentSettlementStatus.open)
                .length,
          ),
          _SettlementCounterCard(
            label: context.l10n.text('paymentSettlementReconciled'),
            count: settlements
                .where(
                  (value) => value.status == PaymentSettlementStatus.reconciled,
                )
                .length,
          ),
          _SettlementCounterCard(
            label: context.l10n.text('needsReview'),
            count: settlements
                .where(
                  (value) =>
                      value.status == PaymentSettlementStatus.needsReview,
                )
                .length,
          ),
        ];
        const gap = ButlerlySpacing.cardGap;
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _SettlementCounterCard extends StatelessWidget {
  const _SettlementCounterCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: ButlerlySpacing.small),
        Text('$count', style: Theme.of(context).textTheme.headlineMedium),
      ],
    ),
  );
}

class _SettlementDesktopTable extends StatelessWidget {
  const _SettlementDesktopTable({required this.data, required this.onOpen});

  final _SettlementListData data;
  final ValueChanged<PaymentSettlementDto> onOpen;

  static const double minimumWidth = 920;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    padding: const EdgeInsets.all(ButlerlySpacing.cardGap),
    child: ButlerlyDesktopInnerCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final table = Column(
            key: const ValueKey('desktop-payment-settlements-table'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(flex: 3, child: _heading(context, 'paymentSource')),
                  SizedBox(width: 110, child: _heading(context, 'date')),
                  Expanded(
                    flex: 3,
                    child: _heading(context, 'paymentSettlementPeriod'),
                  ),
                  SizedBox(
                    width: 145,
                    child: _heading(context, 'paymentSettlementAmount'),
                  ),
                  SizedBox(width: 135, child: _heading(context, 'status')),
                  const SizedBox(width: 24),
                ],
              ),
              const SizedBox(height: ButlerlyTableTokens.headerToRowsGap),
              _divider(context),
              for (final settlement in data.settlements) ...[
                _row(context, settlement),
                _divider(context),
              ],
            ],
          );
          if (constraints.maxWidth >= minimumWidth) return table;
          return SingleChildScrollView(
            key: const ValueKey(
              'desktop-payment-settlements-horizontal-scroll',
            ),
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minimumWidth, child: table),
          );
        },
      ),
    ),
  );

  Widget _heading(BuildContext context, String key) => Text(
    context.l10n.text(key),
    style: ButlerlyTableTokens.headerTextStyle(context),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _divider(BuildContext context) => Divider(
    height: ButlerlyTableTokens.dividerThickness,
    thickness: ButlerlyTableTokens.dividerThickness,
    color: ButlerlyTableTokens.dividerColor(context),
  );

  Widget _row(BuildContext context, PaymentSettlementDto settlement) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final paymentDate = DateTime.tryParse(settlement.paymentDate);
    final date = paymentDate == null
        ? settlement.paymentDate
        : DateFormat.yMMMd(locale).format(paymentDate);
    final amount =
        '${settlement.payment.currency.value} '
        '${localizedTransactionAmount(context, settlement.payment.amount.toString())}';
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('desktop-payment-settlement-${settlement.id}'),
        onTap: () => onOpen(settlement),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: ButlerlyTableTokens.rowVerticalPadding,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  data.sourceNames[settlement.paymentSourceId] ??
                      settlement.paymentSourceId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 110, child: Text(date)),
              Expanded(
                flex: 3,
                child: Text(
                  '${settlement.periodStart} – ${settlement.periodEnd}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 145,
                child: Text(
                  amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 135,
                child: Text(
                  context.l10n.text(switch (settlement.status) {
                    PaymentSettlementStatus.open => 'paymentSettlementOpen',
                    PaymentSettlementStatus.reconciled =>
                      'paymentSettlementReconciled',
                    PaymentSettlementStatus.needsReview => 'needsReview',
                  }),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({
    required this.settlement,
    required this.sourceName,
    required this.onTap,
  });

  final PaymentSettlementDto settlement;
  final String sourceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final paymentDate = DateTime.tryParse(settlement.paymentDate);
    final formattedDate = paymentDate == null
        ? settlement.paymentDate
        : DateFormat.yMMMd(locale).format(paymentDate);
    final amount =
        '${settlement.payment.currency.value} '
        '${localizedTransactionAmount(context, settlement.payment.amount.toString())}';
    return ButlerlyCard(
      onTap: onTap,
      semanticLabel: '$sourceName, $amount, $formattedDate',
      child: Row(
        children: [
          ButlerlyActionIcon(icon: Icons.credit_score_outlined),
          const SizedBox(width: ButlerlySpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sourceName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: ButlerlySpacing.micro),
                Text(amount, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: ButlerlySpacing.micro),
                Text(
                  formattedDate,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: ButlerlySpacing.micro),
                Text(
                  '${settlement.periodStart} – ${settlement.periodEnd}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (settlement.statementBalance != null) ...[
                  const SizedBox(height: ButlerlySpacing.micro),
                  Text(
                    '${settlement.statementBalance!.currency.value} '
                    '${localizedTransactionAmount(context, settlement.statementBalance!.amount.toString())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: ButlerlySpacing.compact),
          _SettlementStatusChip(status: settlement.status),
          const SizedBox(width: ButlerlySpacing.micro),
          Icon(Icons.chevron_right_rounded, color: context.colors.tertiaryText),
        ],
      ),
    );
  }
}

class _SettlementComparisonCard extends StatelessWidget {
  const _SettlementComparisonCard({required this.detail});

  final PaymentSettlementDetailDto detail;

  @override
  Widget build(BuildContext context) {
    final settlement = detail.settlement;
    final recorded = detail.recordedTransactionTotal;
    final difference = detail.paymentDifference;
    final currency = settlement.payment.currency.value;

    String amount(DecimalValue value) =>
        '$currency ${localizedTransactionAmount(context, value.toString())}';

    return ButlerlyCard(
      color: context.colors.selection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryLine(
            label: context.l10n.text('recordedTransactionTotal'),
            value: recorded == null
                ? context.l10n.text('comparisonUnavailable')
                : amount(recorded.amount),
          ),
          _SummaryLine(
            label: context.l10n.text('paymentSettlementAmount'),
            value: amount(detail.paymentAmount.amount),
          ),
          _SummaryLine(
            label: context.l10n.text('paymentSettlementDifference'),
            value: difference == null
                ? context.l10n.text('comparisonUnavailable')
                : amount(difference.amount),
          ),
        ],
      ),
    );
  }
}

class _SettlementBasicInfoCard extends StatelessWidget {
  const _SettlementBasicInfoCard({
    required this.detail,
    required this.sourceName,
  });

  final PaymentSettlementDetailDto detail;
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final settlement = detail.settlement;
    final currency = settlement.payment.currency.value;
    final paymentAmount =
        '$currency ${localizedTransactionAmount(context, detail.paymentAmount.amount.toString())}';

    return ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryLine(
            label: context.l10n.text('date'),
            value: settlement.paymentDate,
          ),
          _SummaryLine(
            label: context.l10n.text('paymentSource'),
            value: sourceName,
          ),
          _SummaryLine(
            label: context.l10n.text('paymentSettlementPeriod'),
            value: '${settlement.periodStart} – ${settlement.periodEnd}',
          ),
          _SummaryLine(
            label: context.l10n.text('paymentSettlementAmount'),
            value: paymentAmount,
          ),
          ButlerlyKeyValueRow.widget(
            label: context.l10n.text('status'),
            valueWidget: _SettlementStatusChip(status: settlement.status),
          ),
          _SummaryLine(
            label: context.l10n.text('note'),
            value: settlement.description?.trim().isNotEmpty == true
                ? settlement.description!.trim()
                : '—',
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ButlerlyKeyValueRow(label: label, value: value);
}

class _SettlementStatusChip extends StatelessWidget {
  const _SettlementStatusChip({required this.status});

  final PaymentSettlementStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      PaymentSettlementStatus.open => context.l10n.text(
        'paymentSettlementOpen',
      ),
      PaymentSettlementStatus.reconciled => context.l10n.text(
        'paymentSettlementReconciled',
      ),
      PaymentSettlementStatus.needsReview => context.l10n.text('needsReview'),
    };
    final icon = switch (status) {
      PaymentSettlementStatus.open => Icons.schedule_outlined,
      PaymentSettlementStatus.reconciled => Icons.check_circle_outline,
      PaymentSettlementStatus.needsReview => Icons.warning_amber_outlined,
    };
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Settlement entry is a long, editable form. Use a dedicated route instead
/// of stacking an interactive form inside a constrained modal bottom sheet.
/// This keeps fields, dropdowns and Save/Cancel reachable on device and desktop.
Future<_SettlementDraft?> _openSettlementEditorPage({
  required BuildContext context,
  required List<PaymentSource> sources,
  PaymentSettlementDetailDto? existing,
}) => Navigator.of(context).push<_SettlementDraft>(
  MaterialPageRoute(
    builder: (routeContext) => Scaffold(
      key: const ValueKey('payment-settlement-editor-page'),
      appBar: AppBar(
        title: Text(
          routeContext.l10n.text(
            existing == null ? 'addPaymentSettlement' : 'editPaymentSettlement',
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ButlerlySize.readableWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(ButlerlySpacing.standard),
              child: _SettlementEditorSheet(
                sources: sources,
                existing: existing,
                showTitle: false,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _SettlementEditorSheet extends StatefulWidget {
  const _SettlementEditorSheet({
    required this.sources,
    this.existing,
    this.showTitle = true,
  });

  final List<PaymentSource> sources;
  final PaymentSettlementDetailDto? existing;
  final bool showTitle;

  @override
  State<_SettlementEditorSheet> createState() => _SettlementEditorSheetState();
}

class _SettlementEditorSheetState extends State<_SettlementEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _paymentDate;
  late final TextEditingController _periodStart;
  late final TextEditingController _periodEnd;
  late final TextEditingController _statementBalance;
  late final TextEditingController _description;
  late final TextEditingController _externalReference;
  late String? _paymentSourceId;
  String? _submitError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final settlement = existing?.settlement;
    _paymentSourceId = settlement?.paymentSourceId ??
        (widget.sources.length == 1 ? widget.sources.single.id.value : null);
    _amount = TextEditingController(
      text: settlement?.payment.amount.toString() ?? '',
    );
    _currency = TextEditingController(
      text: settlement?.payment.currency.value ?? 'USD',
    );
    _paymentDate = TextEditingController(
      text: settlement?.paymentDate ?? _today(),
    );
    _periodStart = TextEditingController(
      text: settlement?.periodStart ?? _firstOfMonth(),
    );
    _periodEnd = TextEditingController(text: settlement?.periodEnd ?? _today());
    _statementBalance = TextEditingController(
      text: settlement?.statementBalance?.amount.toString() ?? '',
    );
    _description = TextEditingController(text: settlement?.description ?? '');
    _externalReference = TextEditingController(
      text: settlement?.externalReference ?? '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _paymentDate.dispose();
    _periodStart.dispose();
    _periodEnd.dispose();
    _statementBalance.dispose();
    _description.dispose();
    _externalReference.dispose();
    super.dispose();
  }

  String? _requiredDate(String? value) {
    final text = value?.trim() ?? '';
    final parsed = DateTime.tryParse(text);
    if (text.length != 10 || parsed == null || _formatDate(parsed) != text) {
      return context.l10n.text('datePending');
    }
    return null;
  }

  String? _requiredAmount(String? value) =>
      num.tryParse(value?.trim() ?? '') == null
      ? context.l10n.text('invalidAmount')
      : null;

  String? _optionalAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return num.tryParse(text) == null
        ? context.l10n.text('invalidAmount')
        : null;
  }

  String? _currencyValidator(String? value) =>
      RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
      ? null
      : context.l10n.text('invalidCurrency');

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final selected = await showButlerlyDatePicker(
      context: context,
      title: context.l10n.text('date'),
      cancelLabel: context.l10n.text('cancel'),
      doneLabel: context.l10n.text('done'),
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (selected != null) controller.text = _formatDate(selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      // A SnackBar belongs to the underlying page and can be obscured by
      // this modal sheet. Show validation beside Save instead.
      setState(() {
        _submitError = _paymentSourceId == null && !_isEditing
            ? context.l10n.text('choosePaymentSourceToContinue')
            : _requiredAmount(_amount.text) ??
                  _currencyValidator(_currency.text) ??
                  _requiredDate(_paymentDate.text) ??
                  _requiredDate(_periodStart.text) ??
                  _requiredDate(_periodEnd.text) ??
                  _optionalAmount(_statementBalance.text) ??
                  context.l10n.text('tryAgain');
      });
      return;
    }
    if (!_isEditing && _paymentSourceId == null) {
      setState(() {
        _submitError = context.l10n.text('choosePaymentSourceToContinue');
      });
      return;
    }
    final start = DateTime.parse(_periodStart.text);
    final end = DateTime.parse(_periodEnd.text);
    if (end.isBefore(start)) {
      setState(() {
        _submitError = context.l10n.text('paymentSettlementPeriod');
      });
      return;
    }
    Navigator.pop(
      context,
      _SettlementDraft(
        paymentSourceId:
            _paymentSourceId ?? widget.existing!.settlement.paymentSourceId,
        amount: _amount.text.trim(),
        currency: _currency.text.trim().toUpperCase(),
        paymentDate: _paymentDate.text.trim(),
        periodStart: _periodStart.text.trim(),
        periodEnd: _periodEnd.text.trim(),
        statementBalance: _statementBalance.text.trim().isEmpty
            ? null
            : _statementBalance.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        externalReference: _externalReference.text.trim().isEmpty
            ? null
            : _externalReference.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _paymentSourceId == null
        ? null
        : widget.sources
              .where((value) => value.id.value == _paymentSourceId)
              .firstOrNull;
    return ButlerlySheet(
      title: widget.showTitle
          ? Text(
              context.l10n.text(
                _isEditing ? 'editPaymentSettlement' : 'addPaymentSettlement',
              ),
            )
          : null,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isEditing)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: context.l10n.text('paymentSource'),
                ),
                child: Text(
                  source == null
                      ? widget.existing!.settlement.paymentSourceId
                      : paymentSourceDisplayLabel(source),
                ),
              )
            else
              FormField<String>(
                initialValue: _paymentSourceId,
                validator: (value) => value == null
                    ? context.l10n.text('choosePaymentSourceToContinue')
                    : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ButlerlySelectField<String>(
                      label: context.l10n.text('paymentSource'),
                      value: field.value,
                      entries: [
                        for (final item in widget.sources)
                          DropdownMenuEntry(
                            value: item.id.value,
                            label: paymentSourceDisplayLabel(item),
                          ),
                      ],
                      onChanged: (value) {
                        field.didChange(value);
                        setState(() {
                          _paymentSourceId = value;
                          final selected = widget.sources
                              .where((item) => item.id.value == value)
                              .firstOrNull;
                          if (selected?.currency?.trim().isNotEmpty == true) {
                            _currency.text = selected!.currency!.toUpperCase();
                          }
                        });
                      },
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: ButlerlySpacing.micro,
                          left: ButlerlySpacing.standard,
                        ),
                        child: Text(
                          field.errorText!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: context.l10n.text('amount'),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _requiredAmount,
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _currency,
              decoration: InputDecoration(
                labelText: context.l10n.text('currency'),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: _currencyValidator,
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _paymentDate,
              readOnly: true,
              onTap: () => _pickDate(_paymentDate),
              decoration: InputDecoration(
                labelText: context.l10n.text('paymentDate'),
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              validator: _requiredDate,
            ),
            const SizedBox(height: ButlerlySpacing.section),
            Text(
              context.l10n.text('paymentSettlementPeriod'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ButlerlySpacing.compact),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _periodStart,
                    readOnly: true,
                    onTap: () => _pickDate(_periodStart),
                    decoration: InputDecoration(
                      labelText: context.l10n.text('fromDate'),
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                    validator: _requiredDate,
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.standard),
                Expanded(
                  child: TextFormField(
                    controller: _periodEnd,
                    readOnly: true,
                    onTap: () => _pickDate(_periodEnd),
                    decoration: InputDecoration(
                      labelText: context.l10n.text('toDate'),
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                    validator: _requiredDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _statementBalance,
              decoration: InputDecoration(
                labelText: context.l10n.text('statementBalanceOptional'),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _optionalAmount,
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _description,
              decoration: InputDecoration(
                labelText: context.l10n.text('descriptionOptional'),
              ),
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _externalReference,
              decoration: InputDecoration(
                labelText: context.l10n.text('externalReferenceOptional'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_submitError != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _submitError!,
              key: const ValueKey('payment-settlement-submit-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ButlerlyCancelButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.text('save')),
        ),
      ],
    );
  }
}

final class _SettlementDraft {
  const _SettlementDraft({
    required this.paymentSourceId,
    required this.amount,
    required this.currency,
    required this.paymentDate,
    required this.periodStart,
    required this.periodEnd,
    this.statementBalance,
    this.description,
    this.externalReference,
  });

  final String paymentSourceId;
  final String amount;
  final String currency;
  final String paymentDate;
  final String periodStart;
  final String periodEnd;
  final String? statementBalance;
  final String? description;
  final String? externalReference;
}

final class _SettlementListData {
  const _SettlementListData({required this.settlements, required this.sources});

  final List<PaymentSettlementDto> settlements;
  final List<PaymentSource> sources;

  List<PaymentSource> get activeCardSources => sources
      .where(
        (source) =>
            source.status == PaymentSourceStatus.active &&
            source.type == PaymentSourceType.card,
      )
      .toList(growable: false);

  Map<String, String> get sourceNames => {
    for (final source in sources)
      source.id.value: paymentSourceDisplayLabel(source),
  };
}

enum _SettlementAction { open, reconciled, needsReview, remove }

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _today() => _formatDate(DateTime.now());

String _firstOfMonth() {
  final now = DateTime.now();
  return _formatDate(DateTime(now.year, now.month, 1));
}
