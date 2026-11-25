import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_panel_footer.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_transaction_table.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/desktop/presentation/desktop_transaction_detail_split_view.dart';
import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  String? _selectedDesktopSettlementId;
  TransactionDto? _selectedDesktopTransaction;
  bool _desktopTransactionChanged = false;
  bool _desktopTransactionEditing = false;
  bool _showDesktopEditWarning = false;
  int _settlementTransactionRevision = 0;

  @override
  void initState() {
    super.initState();
    paymentSettlementChanges.addListener(_refresh);
    paymentSourceChanges.addListener(_refresh);
    workspaceRestoreChanges.addListener(_onWorkspaceRestored);
  }

  @override
  void dispose() {
    paymentSettlementChanges.removeListener(_refresh);
    paymentSourceChanges.removeListener(_refresh);
    workspaceRestoreChanges.removeListener(_onWorkspaceRestored);
    super.dispose();
  }

  void _onWorkspaceRestored() {
    if (!mounted) return;
    setState(() {
      _selectedDesktopSettlementId = null;
      _selectedDesktopTransaction = null;
      _desktopTransactionChanged = false;
      _desktopTransactionEditing = false;
      _showDesktopEditWarning = false;
      _data = _load();
    });
  }

  void _closeDesktopSettlement() {
    setState(() {
      _selectedDesktopSettlementId = null;
      _selectedDesktopTransaction = null;
      _desktopTransactionChanged = false;
      _desktopTransactionEditing = false;
      _showDesktopEditWarning = false;
    });
  }

  Future<_SettlementListData> _load() async {
    final finance = _finance;
    final listSettlements = finance?.listPaymentSettlements;
    if (finance == null || listSettlements == null) {
      throw StateError('Payment settlements are unavailable.');
    }
    final settlementResult = await listSettlements();
    if (settlementResult case ApplicationSuccess<List<PaymentSettlementDto>>(
      value: final settlements,
    )) {
      final sourceResult = await finance.listPaymentSources();
      if (sourceResult case ApplicationSuccess<List<PaymentSource>>(
        value: final sources,
      )) {
        return _SettlementListData(settlements: settlements, sources: sources);
      }
    }
    throw StateError('Payment settlements could not be loaded.');
  }

  Future<void> _refresh() async {
    final reloaded = _load();
    setState(() {
      _data = reloaded;
    });
    // The FutureBuilder owns the error state, including retries.
    await reloaded.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  Future<void> _createSettlement(_SettlementListData data) async {
    final finance = _finance;
    final save = finance?.savePaymentSettlement;
    if (finance == null || save == null) return;
    final id = 'settlement-${DateTime.now().microsecondsSinceEpoch}';
    final saved = await showButlerlyBottomSheet<bool>(
      context: context,
      enableDrag: false,
      onHandleDismiss: _dismissIdleSettlementEditor,
      builder: (_) => _SettlementEditorSheet(
        sources: data.activeCardSources,
        save: save,
        id: id,
      ),
    );
    if (mounted && saved == true) {
      _showMessage(context.l10n.text('paymentSettlementSaved'));
    }
  }

  Future<void> _openSettlement(
    PaymentSettlementDto settlement,
    _SettlementListData data,
  ) async {
    final finance = _finance;
    if (finance == null) return;
    if (effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide) {
      if (_desktopTransactionEditing) {
        // The host Scaffold's bottom SnackBar can cover the embedded
        // editor's Save action. Keep the warning in the results pane instead
        // so the unsaved draft stays actionable while the message is shown.
        setState(() => _showDesktopEditWarning = true);
        return;
      }
      final needsRefresh = _desktopTransactionChanged;
      setState(() {
        if (needsRefresh) _settlementTransactionRevision++;
        _selectedDesktopSettlementId = settlement.id;
        _selectedDesktopTransaction = null;
        _desktopTransactionChanged = false;
        _showDesktopEditWarning = false;
      });
      if (needsRefresh) await _refresh();
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentSettlementDetailPage(
          finance: finance,
          settlementId: settlement.id,
          sourceNames: data.sourceNames,
          sources: data.sources,
        ),
      ),
    );
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
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
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
        final activeCards = data.activeCardSources;
        final resultsPage = ButlerlyPage(
          title: context.l10n.text('paymentSettlements'),
          fullWidth: desktop,
          subtitle: context.l10n.text(
            activeCards.isEmpty && data.settlements.isNotEmpty
                ? 'noActiveSettlementCardsBody'
                : 'paymentSettlementsSubtitle',
          ),
          // This feedback must stay visible even when the results table is
          // scrolled: a blocked settlement switch otherwise looks unresponsive.
          pinnedHeader: desktop && _showDesktopEditWarning
              ? Semantics(
                  liveRegion: true,
                  child: ButlerlyCard(
                    key: const ValueKey('desktop-settlement-edit-warning'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ButlerlySpacing.standard,
                      vertical: ButlerlySpacing.compact,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded),
                        const SizedBox(width: ButlerlySpacing.compact),
                        Expanded(
                          child: Text(
                            context.l10n.text(
                              'finishTransactionEditBeforeChangingSettlement',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          pinnedHeaderExtent: 96.0 * MediaQuery.textScalerOf(context).scale(1),
          onRefresh: _refresh,
          actions: [
            ButlerlyHeaderAddButton(
              buttonKey: const ValueKey('payment-settlements-add'),
              closeToHelp: true,
              label: context.l10n.text('addPaymentSettlement'),
              onPressed: activeCards.isEmpty
                  ? null
                  : () => _createSettlement(data),
            ),
          ],
          children: [
            if (data.settlements.isEmpty && activeCards.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.credit_card_off_outlined,
                title: context.l10n.text('noActiveSettlementCards'),
                message: context.l10n.text('noActiveSettlementCardsBody'),
              )
            else if (data.settlements.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.credit_score_outlined,
                title: context.l10n.text('noPaymentSettlements'),
                message: context.l10n.text('noPaymentSettlementsBody'),
                actionLabel: context.l10n.text('addPaymentSettlement'),
                onAction: () => _createSettlement(data),
              )
            else if (desktop) ...[
              _SettlementDesktopOverview(data: data),
              const SizedBox(height: ButlerlySpacing.cardGap),
              _SettlementDesktopTable(
                data: data,
                onOpen: (settlement) => _openSettlement(settlement, data),
                onRefresh: _refresh,
              ),
            ] else ...[
              for (final settlement in data.settlements) ...[
                _SettlementCard(
                  settlement: settlement,
                  sourceName: _settlementSourceLabel(
                    context,
                    data.sources,
                    settlement.paymentSourceId,
                  ),
                  onTap: () => _openSettlement(settlement, data),
                ),
                const SizedBox(height: ButlerlySpacing.small),
              ],
            ],
            const SizedBox(height: ButlerlySpacing.structural),
          ],
        );
        if (!desktop) return resultsPage;
        final selectedSettlement = data.settlements
            .where((item) => item.id == _selectedDesktopSettlementId)
            .firstOrNull;
        final selectedTransaction = _selectedDesktopTransaction;
        return DesktopTransactionDetailSplitView(
          results: resultsPage,
          detail: selectedSettlement == null
              ? null
              : IndexedStack(
                  index: selectedTransaction == null ? 0 : 1,
                  children: [
                    PaymentSettlementDetailPage(
                      key: ValueKey(
                        'desktop-settlement-detail-${selectedSettlement.id}',
                      ),
                      finance: _finance!,
                      settlementId: selectedSettlement.id,
                      transactionRevision: _settlementTransactionRevision,
                      sourceNames: data.sourceNames,
                      sources: data.sources,
                      onClose: _closeDesktopSettlement,
                      onTransactionSelected: (transaction) {
                        setState(() {
                          _selectedDesktopTransaction = transaction;
                          _desktopTransactionChanged = false;
                          _desktopTransactionEditing = false;
                          _showDesktopEditWarning = false;
                        });
                      },
                    ),
                    if (selectedTransaction != null)
                      DesktopTransactionPanel(
                        key: ValueKey(
                          'desktop-settlement-transaction-${selectedTransaction.id}',
                        ),
                        finance: _finance!,
                        transaction: selectedTransaction,
                        onEditingChanged: (editing) {
                          _desktopTransactionEditing = editing;
                          if (!editing && _showDesktopEditWarning) {
                            setState(() => _showDesktopEditWarning = false);
                          }
                        },
                        onChanged: () => _desktopTransactionChanged = true,
                        onClose: (changed) {
                          final needsRefresh =
                              changed || _desktopTransactionChanged;
                          setState(() {
                            if (needsRefresh) _settlementTransactionRevision++;
                            _selectedDesktopTransaction = null;
                            _desktopTransactionChanged = false;
                            _desktopTransactionEditing = false;
                            _showDesktopEditWarning = false;
                          });
                          if (needsRefresh) _refresh();
                        },
                      ),
                  ],
                ),
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
    this.transactionRevision = 0,
    this.onClose,
    this.onTransactionSelected,
    super.key,
  });

  final FinanceServices finance;
  final String settlementId;

  /// Refreshes the loaded settlement transactions without replacing this
  /// State (and losing its scroll position) after an edited/deleted transaction.
  final int transactionRevision;
  final Map<String, String> sourceNames;
  final List<PaymentSource> sources;
  final VoidCallback? onClose;
  final ValueChanged<TransactionDto>? onTransactionSelected;

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
  void didUpdateWidget(covariant PaymentSettlementDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transactionRevision != oldWidget.transactionRevision) {
      // The framework rebuilds after didUpdateWidget; replacing only this
      // Future keeps the detail State, including its scroll position, intact.
      _detail = _load();
    }
  }

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
    setState(() {
      _detail = detail;
    });
    // Keep reload failures in the FutureBuilder's retryable error state.
    await detail.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final refreshedMasterData = await masterData;
    if (!mounted || _detail != detail || _loadedLanguageCode != languageCode) {
      return;
    }
    setState(() => _masterData = refreshedMasterData);
  }

  Future<void> _openTransaction(TransactionDto transaction) async {
    if (widget.onTransactionSelected case final onSelected?) {
      onSelected(transaction);
      return;
    }
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
    final saved = await showButlerlyBottomSheet<bool>(
      context: context,
      enableDrag: false,
      onHandleDismiss: _dismissIdleSettlementEditor,
      builder: (_) => _SettlementEditorSheet(
        sources: widget.sources,
        existing: detail,
        save: save,
        id: detail.settlement.id,
      ),
    );
    if (!mounted || saved != true) return;
    _showMessage(context.l10n.text('paymentSettlementSaved'));
    await _refresh();
  }

  Future<void> _setStatus(PaymentSettlementStatus status) async {
    final setStatus = widget.finance.setPaymentSettlementStatus;
    if (setStatus == null) return;
    final result = await setStatus(widget.settlementId, status);
    if (result is ApplicationSuccess<PaymentSettlementDto>) {
      notifyPaymentSettlementChanged();
    }
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
    if (result is ApplicationSuccess<void>) {
      notifyPaymentSettlementChanged();
    }
    if (!mounted) return;
    if (result is ApplicationFailure<void>) {
      _showMessage(context.l10n.text('dataPreserved'));
      return;
    }
    _showMessage(context.l10n.text('paymentSettlementRemoved'));
    if (widget.onClose case final close?) {
      close();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        widget.onClose == null &&
        effectiveButlerlyLayoutMode(
              context,
              MediaQuery.sizeOf(context).width,
            ) ==
            ButlerlyLayoutMode.wide;
    return FutureBuilder<PaymentSettlementDetailDto>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              leading: widget.onClose == null
                  ? null
                  : ButlerlyPanelCloseButton(onPressed: widget.onClose),
              title: Text(context.l10n.text('paymentSettlement')),
            ),
            body: const ButlerlyLoadingState(),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              leading: widget.onClose == null
                  ? null
                  : ButlerlyPanelCloseButton(onPressed: widget.onClose),
              title: Text(context.l10n.text('paymentSettlements')),
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
        final sourceName = _settlementSourceLabel(
          context,
          widget.sources,
          settlement.paymentSourceId,
        );
        return Scaffold(
          bottomNavigationBar: widget.onClose == null
              ? null
              : ButlerlyDesktopPanelFooter(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: ButlerlySpacing.small,
                    runSpacing: ButlerlySpacing.compact,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey(
                          'desktop-payment-settlement-edit-button',
                        ),
                        onPressed: () => _edit(detail),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(context.l10n.text('edit')),
                      ),
                      TextButton.icon(
                        key: const ValueKey(
                          'desktop-payment-settlement-actions-button',
                        ),
                        onPressed: () => _showActions(context),
                        icon: const Icon(Icons.more_vert),
                        label: Text(context.l10n.text('more')),
                      ),
                    ],
                  ),
                ),
          body: ButlerlyPage(
            title: context.l10n.text('paymentSettlement'),
            fullWidth: desktop,
            onRefresh: _refresh,
            leading: widget.onClose == null
                ? null
                : ButlerlyPanelCloseButton(
                    buttonKey: const ValueKey(
                      'desktop-payment-settlement-close',
                    ),
                    onPressed: widget.onClose,
                  ),
            actions: [
              if (widget.onClose == null) ...[
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

class _SettlementDesktopTable extends StatefulWidget {
  const _SettlementDesktopTable({
    required this.data,
    required this.onOpen,
    required this.onRefresh,
  });

  final _SettlementListData data;
  final ValueChanged<PaymentSettlementDto> onOpen;
  final RefreshCallback onRefresh;

  @override
  State<_SettlementDesktopTable> createState() =>
      _SettlementDesktopTableState();
}

class _SettlementDesktopTableState extends State<_SettlementDesktopTable> {
  static const double minimumWidth = 920;
  static const double viewportHeightFactor = .55;
  static const double dateWidth = 110;
  static const double amountWidth = 145;
  static const double statusWidth = 135;
  static const double arrowWidth = 24;
  static const double wrappedColumnWidth =
      (minimumWidth - dateWidth - amountWidth - statusWidth - arrowWidth) / 2;

  final _verticalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

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
                  SizedBox(width: dateWidth, child: _heading(context, 'date')),
                  Expanded(
                    flex: 3,
                    child: _heading(context, 'paymentSettlementPeriod'),
                  ),
                  SizedBox(
                    width: amountWidth,
                    child: _heading(context, 'paymentSettlementAmount'),
                  ),
                  SizedBox(
                    width: statusWidth,
                    child: _heading(context, 'status'),
                  ),
                  const SizedBox(width: arrowWidth),
                ],
              ),
              const SizedBox(height: ButlerlyTableTokens.headerToRowsGap),
              _divider(context),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.sizeOf(context).height * viewportHeightFactor,
                ),
                // Finite height keeps layout bounded. Shrink wrapping lets a
                // short history use only the height its rows need.
                child: _rows(context),
              ),
            ],
          );
          return Scrollbar(
            controller: _verticalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              key: const ValueKey(
                'desktop-payment-settlements-horizontal-scroll',
              ),
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: constraints.maxWidth < minimumWidth
                    ? minimumWidth
                    : constraints.maxWidth,
                child: Actions(
                  actions: {ScrollIntent: _SettlementTableScrollAction()},
                  child: table,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _rows(BuildContext context) {
    final data = widget.data;
    final list = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        key: const ValueKey('desktop-payment-settlements-rows'),
        controller: _verticalController,
        primary: false,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: data.settlements.length,
        findChildIndexCallback: (key) =>
            data.settlementIndexes[(key as ValueKey<String>).value],
        itemBuilder: (context, index) {
          final settlement = data.settlements[index];
          return Column(
            key: ValueKey(settlement.id),
            children: [_row(context, settlement), _divider(context)],
          );
        },
      ),
    );
    // A drag starting over a long history belongs to the row viewport.
    // Keep pull-to-refresh reachable there on wide mobile layouts.
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => RefreshIndicator.adaptive(
        onRefresh: widget.onRefresh,
        child: list,
      ),
      _ => list,
    };
  }

  Widget _heading(BuildContext context, String key) => Text(
    context.l10n.text(key),
    style: ButlerlyTableTokens.headerTextStyle(context),
  );

  Widget _divider(BuildContext context) => Divider(
    height: ButlerlyTableTokens.dividerThickness,
    thickness: ButlerlyTableTokens.dividerThickness,
    color: ButlerlyTableTokens.dividerColor(context),
  );

  // Keep wrapped rows the same height when opening or closing the detail pane
  // changes the table width. The vertical scroll position then stays anchored.
  Widget _wrappedCell(Text text) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: wrappedColumnWidth),
      child: text,
    ),
  );

  Widget _row(BuildContext context, PaymentSettlementDto settlement) {
    final source = widget.data.sourcesById[settlement.paymentSourceId];
    final locale = Localizations.localeOf(context).toLanguageTag();
    final paymentDate = DateTime.tryParse(settlement.paymentDate);
    final date = paymentDate == null
        ? settlement.paymentDate
        : DateFormat.yMMMd(locale).format(paymentDate);
    final amount =
        '${settlement.payment.currency.value} '
        '${localizedTransactionAmount(context, settlement.payment.amount.toString())}';
    final sourceLabel = Text(
      _settlementSourceDisplayLabel(
        context,
        source,
        settlement.paymentSourceId,
      ),
      maxLines: source == null ? null : 1,
      overflow: source == null ? null : TextOverflow.ellipsis,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('desktop-payment-settlement-${settlement.id}'),
        onTap: () => widget.onOpen(settlement),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: ButlerlyTableTokens.rowVerticalPadding,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: source == null ? _wrappedCell(sourceLabel) : sourceLabel,
              ),
              SizedBox(width: dateWidth, child: Text(date)),
              Expanded(
                flex: 3,
                child: _wrappedCell(
                  Text('${settlement.periodStart} – ${settlement.periodEnd}'),
                ),
              ),
              SizedBox(width: amountWidth, child: Text(amount)),
              SizedBox(
                width: statusWidth,
                child: Text(
                  context.l10n.text(switch (settlement.status) {
                    PaymentSettlementStatus.open => 'paymentSettlementOpen',
                    PaymentSettlementStatus.reconciled =>
                      'paymentSettlementReconciled',
                    PaymentSettlementStatus.needsReview => 'needsReview',
                  }),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: arrowWidth),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementTableScrollAction extends ScrollAction {
  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    if (context == null) return;
    final axis = axisDirectionToAxis(intent.direction);
    var scrollable = Scrollable.maybeOf(context, axis: axis);
    while (scrollable != null) {
      final position = scrollable.position;
      final remaining = scrollable.axisDirection == intent.direction
          ? position.extentAfter
          : position.extentBefore;
      if (remaining > 0 &&
          (scrollable.resolvedPhysics?.shouldAcceptUserOffset(position) ??
              true)) {
        position.moveTo(
          position.pixels +
              ScrollAction.getDirectionalIncrement(scrollable, intent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
        );
        return;
      }
      scrollable = Scrollable.maybeOf(scrollable.context, axis: axis);
    }
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

class _SettlementEditorSheet extends StatefulWidget {
  const _SettlementEditorSheet({
    required this.sources,
    required this.save,
    required this.id,
    this.existing,
  });

  final List<PaymentSource> sources;
  final SavePaymentSettlement save;
  final String id;
  final PaymentSettlementDetailDto? existing;

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
  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final settlement = existing?.settlement;
    _paymentSourceId = settlement?.paymentSourceId;
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

  String? _decimalError(String? value, String field, {bool optional = false}) {
    final text = value?.trim() ?? '';
    if (optional && text.isEmpty) return null;
    try {
      DecimalValue.parse(text);
      return null;
    } on DomainValidationException {
      return '${context.l10n.text(field)}: ${context.l10n.text('invalidAmount')}';
    }
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
    if (mounted && selected != null) controller.text = _formatDate(selected);
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    final sourceId = _paymentSourceId;
    if (sourceId == null) return;
    final periodStart = _periodStart.text.trim();
    final periodEnd = _periodEnd.text.trim();
    if (periodEnd.compareTo(periodStart) < 0) {
      setState(() => _saveError = 'paymentSettlementPeriod');
      return;
    }
    final guard = _SettlementSavePopEntry();
    route!.registerPopEntry(guard);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    var saved = false;
    try {
      final currency = CurrencyCode(_currency.text.trim().toUpperCase());
      final balance = _statementBalance.text.trim();
      final description = _description.text.trim();
      final reference = _externalReference.text.trim();
      final result = await widget.save(
        id: widget.id,
        paymentSourceId: sourceId,
        payment: Money(
          amount: DecimalValue.parse(_amount.text),
          currency: currency,
        ),
        paymentDate: _paymentDate.text.trim(),
        periodStart: periodStart,
        periodEnd: periodEnd,
        status:
            widget.existing?.settlement.status ?? PaymentSettlementStatus.open,
        statementBalance: balance.isEmpty
            ? null
            : Money(amount: DecimalValue.parse(balance), currency: currency),
        description: description.isEmpty ? null : description,
        externalReference: reference.isEmpty ? null : reference,
      );
      saved = result is ApplicationSuccess<PaymentSettlementDto>;
    } catch (_) {
      // Preserve the form if persistence throws instead of returning a result.
    } finally {
      route.unregisterPopEntry(guard);
      guard.canPopNotifier.dispose();
    }
    if (saved) notifyPaymentSettlementChanged();
    if (!mounted) return;
    if (saved && route.isCurrent) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _saveError = saved ? null : 'paymentSettlementSaveFailed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _paymentSourceId == null
        ? null
        : widget.sources
              .where((value) => value.id.value == _paymentSourceId)
              .firstOrNull;
    return ButlerlySheet(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text(
              _isEditing ? 'editPaymentSettlement' : 'addPaymentSettlement',
            ),
          ),
          if (_saveError case final error?)
            Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.text(error),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
              ),
            ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: ExcludeFocus(
          excluding: _saving,
          child: IgnorePointer(
            ignoring: _saving,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isEditing)
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: context.l10n.text('paymentSource'),
                    ),
                    child: Row(
                      children: [
                        if (source != null) ...[
                          ButlerlyPaymentSourceIcon(source: source, size: 24),
                          const SizedBox(width: ButlerlySpacing.micro),
                        ],
                        Expanded(
                          child: Text(
                            _settlementSourceLabel(
                              context,
                              widget.sources,
                              widget.existing!.settlement.paymentSourceId,
                            ),
                          ),
                        ),
                      ],
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
                          leadingIcon: paymentSourceIconForId(
                            widget.sources,
                            field.value,
                          ),
                          entries: [
                            for (final item in widget.sources)
                              DropdownMenuEntry(
                                value: item.id.value,
                                label: paymentSourceDisplayLabel(item),
                                leadingIcon: ButlerlyPaymentSourceIcon(
                                  source: item,
                                  size: 24,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            field.didChange(value);
                            setState(() {
                              _paymentSourceId = value;
                              final selected = widget.sources
                                  .where((item) => item.id.value == value)
                                  .firstOrNull;
                              if (selected?.currency?.trim().isNotEmpty ==
                                  true) {
                                _currency.text = selected!.currency!
                                    .toUpperCase();
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
                  validator: (value) => _decimalError(value, 'amount'),
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
                  validator: (value) => _decimalError(
                    value,
                    'statementBalanceOptional',
                    optional: true,
                  ),
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
        ),
      ),
      actions: [
        ButlerlyCancelButton(
          onPressed: _saving
              ? null
              : () {
                  if (!_saving) Navigator.pop(context);
                },
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(context.l10n.text(_saving ? 'saving' : 'save')),
        ),
      ],
    );
  }
}

void _dismissIdleSettlementEditor(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route?.isCurrent == true &&
      route?.popDisposition == RoutePopDisposition.pop) {
    Navigator.pop(context);
  }
}

final class _SettlementSavePopEntry extends PopEntry<Object?> {
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(false);
}

final class _SettlementListData {
  _SettlementListData({required this.settlements, required this.sources});

  final List<PaymentSettlementDto> settlements;
  final List<PaymentSource> sources;

  late final sourcesById = {
    for (final source in sources) source.id.value: source,
  };
  late final settlementIndexes = {
    for (final (index, settlement) in settlements.indexed) settlement.id: index,
  };

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

String _settlementSourceLabel(
  BuildContext context,
  List<PaymentSource> sources,
  String id,
) {
  final source = sources.where((source) => source.id.value == id).firstOrNull;
  return _settlementSourceDisplayLabel(context, source, id);
}

String _settlementSourceDisplayLabel(
  BuildContext context,
  PaymentSource? source,
  String id,
) {
  if (source == null) {
    return context.l10n.text('missingSettlementSource', {'id': id});
  }
  final label = paymentSourceDisplayLabel(source);
  return source.status == PaymentSourceStatus.archived
      ? '$label (${context.l10n.text('archivedSettlementSource')})'
      : label;
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
