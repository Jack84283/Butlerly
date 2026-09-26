import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

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

  Future<void> _createSettlement(_SettlementListData data) async {
    final finance = _finance;
    final save = finance?.savePaymentSettlement;
    if (finance == null || save == null) return;
    final draft = await showButlerlyBottomSheet<_SettlementDraft>(
      context: context,
      builder: (context) =>
          _SettlementEditorSheet(sources: data.activeCardSources),
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
          subtitle: context.l10n.text('paymentSettlementsSubtitle'),
          onRefresh: _refresh,
          actions: [
            IconButton(
              tooltip: context.l10n.text('addPaymentSettlement'),
              onPressed: data.activeCardSources.isEmpty
                  ? null
                  : () => _createSettlement(data),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
          children: [
            if (data.activeCardSources.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.credit_card_off_outlined,
                title: context.l10n.text('paymentSources'),
                message: context.l10n.text('paymentSourcesSubtitle'),
              )
            else if (data.settlements.isEmpty)
              ButlerlyEmptyState(
                icon: Icons.credit_score_outlined,
                title: context.l10n.text('noPaymentSettlements'),
                message: context.l10n.text('noPaymentSettlementsBody'),
                actionLabel: context.l10n.text('addPaymentSettlement'),
                onAction: () => _createSettlement(data),
              )
            else ...[
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
            ],
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
    setState(() => _detail = _load());
    await _detail;
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
    final draft = await showButlerlyBottomSheet<_SettlementDraft>(
      context: context,
      builder: (context) =>
          _SettlementEditorSheet(sources: widget.sources, existing: detail),
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

  Future<void> _remove() async {
    final remove = widget.finance.deletePaymentSettlement;
    if (remove == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('paymentSettlementRemoveTitle')),
        content: Text(context.l10n.text('paymentSettlementRemoveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('remove')),
          ),
        ],
      ),
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
            title: sourceName,
            subtitle: '${settlement.periodStart} – ${settlement.periodEnd}',
            onRefresh: _refresh,
            actions: [
              IconButton(
                tooltip: context.l10n.text('editPaymentSettlement'),
                onPressed: () => _edit(detail),
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<_SettlementAction>(
                onSelected: (action) async {
                  if (action == _SettlementAction.remove) {
                    await _remove();
                    return;
                  }
                  final status = switch (action) {
                    _SettlementAction.open => PaymentSettlementStatus.open,
                    _SettlementAction.reconciled =>
                      PaymentSettlementStatus.reconciled,
                    _SettlementAction.needsReview =>
                      PaymentSettlementStatus.needsReview,
                    _SettlementAction.remove => PaymentSettlementStatus.open,
                  };
                  await _setStatus(status);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _SettlementAction.open,
                    child: Text(context.l10n.text('markAsOpen')),
                  ),
                  PopupMenuItem(
                    value: _SettlementAction.reconciled,
                    child: Text(context.l10n.text('markAsReconciled')),
                  ),
                  PopupMenuItem(
                    value: _SettlementAction.needsReview,
                    child: Text(context.l10n.text('markNeedsReview')),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _SettlementAction.remove,
                    child: Text(context.l10n.text('remove')),
                  ),
                ],
              ),
            ],
            children: [
              _SettlementSummaryCard(detail: detail),
              const SizedBox(height: ButlerlySpacing.section),
              ButlerlySectionHeader(
                title: context.l10n.text('paymentSettlementComparison'),
              ),
              _SettlementComparisonCard(detail: detail),
              const SizedBox(height: ButlerlySpacing.section),
              ButlerlySectionHeader(
                title: context.l10n.text('paymentSettlementPayment'),
              ),
              _SettlementPaymentCard(settlement: settlement),
              const SizedBox(height: ButlerlySpacing.section),
              ButlerlySectionHeader(
                title: context.l10n.text('paymentSettlementActivity'),
              ),
              if (detail.transactions.isEmpty)
                ButlerlyEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: context.l10n.text('noTransactions'),
                  message: context.l10n.text('noActivityInPeriod'),
                )
              else
                for (final transaction in detail.transactions) ...[
                  TransactionRow(
                    transaction: transaction,
                    paymentSourceNames: widget.sourceNames,
                    showDate: true,
                    showNavigationIndicator: true,
                    onTap: () => _openTransaction(transaction),
                  ),
                  const Divider(height: ButlerlySpacing.section),
                ],
              const SizedBox(height: ButlerlySpacing.structural),
            ],
          ),
        );
      },
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
    return ButlerlyCard(
      onTap: onTap,
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

class _SettlementPaymentCard extends StatelessWidget {
  const _SettlementPaymentCard({required this.settlement});

  final PaymentSettlementDto settlement;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine(
          label: context.l10n.text('amount'),
          value:
              '${settlement.payment.currency.value} '
              '${localizedTransactionAmount(context, settlement.payment.amount.toString())}',
        ),
        const SizedBox(height: ButlerlySpacing.compact),
        _SummaryLine(
          label: context.l10n.text('paymentDate'),
          value: settlement.paymentDate,
        ),
      ],
    ),
  );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryLine(
            label: context.l10n.text('recordedTransactionTotal'),
            value: recorded == null
                ? context.l10n.text('comparisonUnavailable')
                : amount(recorded.amount),
          ),
          const SizedBox(height: ButlerlySpacing.compact),
          _SummaryLine(
            label: context.l10n.text('paymentSettlementAmount'),
            value: amount(settlement.payment.amount),
          ),
          const SizedBox(height: ButlerlySpacing.compact),
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

class _SettlementSummaryCard extends StatelessWidget {
  const _SettlementSummaryCard({required this.detail});

  final PaymentSettlementDetailDto detail;

  @override
  Widget build(BuildContext context) {
    final settlement = detail.settlement;
    return ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SettlementStatusChip(status: settlement.status),
              const Spacer(),
              Text(
                context.l10n.text('manyTransactions', {
                  'count': '${detail.transactionCount}',
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (settlement.statementBalance != null) ...[
            const SizedBox(height: ButlerlySpacing.standard),
            _SummaryLine(
              label: context.l10n.text('statementBalanceOptional'),
              value:
                  '${settlement.statementBalance!.currency.value} '
                  '${localizedTransactionAmount(context, settlement.statementBalance!.amount.toString())}',
            ),
          ],
          if (settlement.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: ButlerlySpacing.compact),
            _SummaryLine(
              label: context.l10n.text('description'),
              value: settlement.description!.trim(),
            ),
          ],
          if (settlement.externalReference?.trim().isNotEmpty == true) ...[
            const SizedBox(height: ButlerlySpacing.compact),
            _SummaryLine(
              label: context.l10n.text('externalReferenceOptional'),
              value: settlement.externalReference!.trim(),
            ),
          ],
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
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: ButlerlySpacing.compact),
        Expanded(child: Text(value)),
      ],
    );
  }
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
  const _SettlementEditorSheet({required this.sources, this.existing});

  final List<PaymentSource> sources;
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
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (selected != null) controller.text = _formatDate(selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEditing && _paymentSourceId == null) return;
    final start = DateTime.parse(_periodStart.text);
    final end = DateTime.parse(_periodEnd.text);
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('paymentSettlementPeriod'))),
      );
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
      title: Text(
        context.l10n.text(
          _isEditing ? 'editPaymentSettlement' : 'addPaymentSettlement',
        ),
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                  DropdownButtonFormField<String>(
                    initialValue: _paymentSourceId,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('paymentSource'),
                    ),
                    items: [
                      for (final item in widget.sources)
                        DropdownMenuItem(
                          value: item.id.value,
                          child: Text(paymentSourceDisplayLabel(item)),
                        ),
                    ],
                    validator: (value) => value == null
                        ? context.l10n.text('choosePaymentSourceToContinue')
                        : null,
                    onChanged: (value) {
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
        ),
      ),
      actions: [
        TextButton(
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
