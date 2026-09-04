import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({this.showPossibleDuplicates = false, super.key});

  final bool showPossibleDuplicates;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage>
    with SingleTickerProviderStateMixin {
  late Future<List<ReviewItemDto>> _items;
  late Future<List<TransactionDto>> _uncategorized;
  late Future<List<DuplicateCandidateGroup>> _duplicateGroups;
  late Future<TransactionMasterDataSnapshot> _masterData;
  late final TabController _tabController;
  _ReviewView _view = _ReviewView.needsReview;
  String? _loadedLanguageCode;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _view = widget.showPossibleDuplicates
        ? _ReviewView.duplicates
        : _ReviewView.uncategorized;
    _tabController = TabController(
      length: _reviewTabs.length,
      initialIndex: _tabIndex(_view),
      vsync: this,
    );
    _items = _load();
    _uncategorized = _loadUncategorized();
    _duplicateGroups = _loadDuplicateGroups();
    transactionChanges.addListener(_handleTransactionChange);
  }

  @override
  void dispose() {
    _tabController.dispose();
    transactionChanges.removeListener(_handleTransactionChange);
    super.dispose();
  }

  void _handleTransactionChange() {
    if (mounted) _refresh();
  }

  @override
  void didUpdateWidget(covariant ReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showPossibleDuplicates == widget.showPossibleDuplicates) {
      return;
    }
    setState(() {
      _view = widget.showPossibleDuplicates
          ? _ReviewView.duplicates
          : _ReviewView.uncategorized;
      _tabController.index = _tabIndex(_view);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _masterData = _loadMasterData(languageCode);
  }

  Future<TransactionMasterDataSnapshot> _loadMasterData(
    String languageCode,
  ) async {
    final finance = _finance;
    if (finance == null) {
      return const TransactionMasterDataSnapshot(
        presentation: TransactionMasterData(),
        merchants: [],
        categories: [],
        tags: [],
        paymentSources: [],
      );
    }
    return TransactionMasterDataProvider(
      finance,
    ).load(languageCode: languageCode);
  }

  Future<List<ReviewItemDto>> _load() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listReviewItems();
    return switch (result) {
      ApplicationSuccess<List<ReviewItemDto>>(:final value) => value,
      ApplicationFailure<List<ReviewItemDto>>() => throw StateError(
        'Review items could not be loaded.',
      ),
    };
  }

  void _refresh() => setState(() {
    _items = _load();
    _uncategorized = _loadUncategorized();
    _duplicateGroups = _loadDuplicateGroups();
  });

  Future<List<TransactionDto>> _loadUncategorized() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listTransactions(
      const ListTransactionsQuery(
        uncategorized: true,
        status: TransactionStatus.active,
      ),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) => value,
      ApplicationFailure<List<TransactionDto>>() => throw StateError(
        'Uncategorized transactions could not be loaded.',
      ),
    };
  }

  Future<List<DuplicateCandidateGroup>> _loadDuplicateGroups() async {
    final finance = _finance;
    if (finance == null || finance.listDuplicateCandidateGroups == null) {
      return const [];
    }
    final result = await finance.listDuplicateCandidateGroups!();
    return switch (result) {
      ApplicationSuccess<List<DuplicateCandidateGroup>>(:final value) => value,
      ApplicationFailure<List<DuplicateCandidateGroup>>() => throw StateError(
        'Possible duplicates could not be loaded.',
      ),
    };
  }

  Future<void> _rescanDuplicates() async {
    final scan = _finance?.scanExistingTransactionsForDuplicates;
    if (scan == null) return;
    final result = await scan();
    if (!mounted) return;
    if (result is ApplicationFailure<List<DuplicateCandidateGroup>>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('possibleDuplicatesScanFailed')),
        ),
      );
      return;
    }
    final groups = _loadDuplicateGroupsWithoutScan();
    notifyTransactionChanged();
    setState(() {
      _duplicateGroups = groups;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.text('possibleDuplicatesScanComplete')),
      ),
    );
  }

  Future<List<DuplicateCandidateGroup>>
  _loadDuplicateGroupsWithoutScan() async {
    final result = await _finance!.listDuplicateCandidateGroups!();
    return switch (result) {
      ApplicationSuccess<List<DuplicateCandidateGroup>>(:final value) => value,
      ApplicationFailure<List<DuplicateCandidateGroup>>() => throw StateError(
        'Possible duplicates could not be loaded.',
      ),
    };
  }

  Future<void> _resolveDuplicate(
    DuplicateCandidateGroup group,
    DuplicateCandidateGroupStatus status, {
    TransactionId? selectedTransactionId,
  }) async {
    final result = await _finance!.resolveDuplicateCandidateGroup!(
      group.id,
      status,
      selectedTransactionId: selectedTransactionId,
    );
    if (!mounted) return;
    if (result is ApplicationFailure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
    notifyTransactionChanged();
    _refresh();
  }

  Future<void> _close(ReviewItemDto item, {required bool dismiss}) async {
    final finance = _finance;
    if (finance == null) return;
    final ApplicationResult<dynamic> result;
    if (item.issueId.startsWith('reconciliation-')) {
      final candidates = await finance.listReconciliationCandidates();
      final candidate =
          candidates is ApplicationSuccess<List<ReconciliationCandidate>>
          ? candidates.value
                .where((value) => 'reconciliation-${value.id}' == item.issueId)
                .firstOrNull
          : null;
      if (candidate == null) return;
      result = dismiss
          ? await finance.rejectReconciliation(candidate)
          : await finance.confirmReconciliation(candidate);
    } else {
      result = dismiss
          ? await finance.dismissReviewIssue(item.transactionId, item.issueId)
          : await finance.resolveReviewIssue(item.transactionId, item.issueId);
    }
    if (!mounted) return;
    if (result is ApplicationFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
    notifyTransactionChanged();
    _refresh();
  }

  Future<void> _openTransaction(ReviewItemDto item) async {
    final finance = _finance;
    if (finance == null) return;
    final result = await finance.getTransaction(item.transactionId);
    if (!mounted) return;
    if (result case ApplicationSuccess<TransactionDto>(:final value)) {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              TransactionDetailPage(finance: finance, transaction: value),
        ),
      );
      if (changed == true) _refresh();
    }
  }

  Future<void> _openUncategorized(TransactionDto transaction) async {
    final finance = _finance;
    if (finance == null || !mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_finance == null) {
      return ButlerlyEmptyState(
        icon: Icons.fact_check_outlined,
        title: context.l10n.text('reviewEmpty'),
        message: context.l10n.text('reviewEmptyBody'),
      );
    }
    return ButlerlyPage(
      title: context.l10n.text('review'),
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: [
            Tab(
              child: _ReviewSectionLabel(
                title: context.l10n.text('uncategorized'),
                future: _uncategorized,
              ),
            ),
            Tab(
              child: FutureBuilder<List<DuplicateCandidateGroup>>(
                future: _duplicateGroups,
                builder: (context, snapshot) {
                  final count = snapshot.data?.length;
                  final label = context.l10n.text('possibleDuplicates');
                  return Center(
                    child: Text(
                      count == null ? label : '$label ($count)',
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            Tab(
              child: _ReviewSectionLabel(
                title: context.l10n.text('needsReview'),
                future: _items,
              ),
            ),
          ],
          onTap: (index) => setState(() => _view = _reviewTabs[index]),
        ),
        if (_view != _ReviewView.duplicates)
          const SizedBox(height: ButlerlySpacing.section),
        if (_view == _ReviewView.duplicates)
          FutureBuilder<List<DuplicateCandidateGroup>>(
            future: _duplicateGroups,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ButlerlyLoadingState();
              }
              if (snapshot.hasError) {
                return ButlerlyErrorState(
                  title: context.l10n.text('reviewLoadError'),
                  message: context.l10n.text('tryAgain'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _refresh,
                );
              }
              final groups = snapshot.data ?? const [];
              if (groups.isEmpty) {
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _rescanDuplicates,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          context.l10n.text('rescanPossibleDuplicates'),
                        ),
                      ),
                    ),
                    ButlerlyEmptyState(
                      icon: Icons.copy_all_outlined,
                      title: context.l10n.text('noPossibleDuplicates'),
                      message: context.l10n.text('reviewEmptyBody'),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _rescanDuplicates,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        context.l10n.text('rescanPossibleDuplicates'),
                      ),
                    ),
                  ),
                  for (final group in groups)
                    _DuplicateGroupCard(
                      group: group,
                      finance: _finance!,
                      masterData: _masterData,
                      onKeepBoth: () => _resolveDuplicate(
                        group,
                        DuplicateCandidateGroupStatus.keepBoth,
                      ),
                      onConsolidate: (id) => _resolveDuplicate(
                        group,
                        DuplicateCandidateGroupStatus.consolidated,
                        selectedTransactionId: id,
                      ),
                    ),
                ],
              );
            },
          )
        else if (_view == _ReviewView.uncategorized)
          FutureBuilder<List<TransactionDto>>(
            future: _uncategorized,
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <TransactionDto>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const ButlerlyLoadingState();
              }
              if (snapshot.hasError) {
                return ButlerlyErrorState(
                  title: context.l10n.text('reviewLoadError'),
                  message: context.l10n.text('tryAgain'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _refresh,
                );
              }
              if (values.isEmpty) {
                return ButlerlyEmptyState(
                  icon: Icons.sell_outlined,
                  title: context.l10n.text('reviewEmpty'),
                  message: context.l10n.text('reviewEmptyBody'),
                );
              }
              return FutureBuilder<TransactionMasterDataSnapshot>(
                future: _masterData,
                builder: (context, masterSnapshot) => TransactionRecordList(
                  transactions: values,
                  masterData:
                      masterSnapshot.data?.presentation ??
                      const TransactionMasterData(),
                  onTap: _openUncategorized,
                  navigates: true,
                ),
              );
            },
          )
        else if (_view != _ReviewView.needsReview)
          ButlerlyEmptyState(
            icon: _view == _ReviewView.uncategorized
                ? Icons.sell_outlined
                : Icons.copy_all_outlined,
            title: context.l10n.text('reviewEmpty'),
            message: context.l10n.text('reviewEmptyBody'),
          )
        else
          FutureBuilder<List<ReviewItemDto>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ButlerlyLoadingState();
              }
              if (snapshot.hasError) {
                return ButlerlyErrorState(
                  title: context.l10n.text('reviewLoadError'),
                  message: context.l10n.text('tryAgain'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _refresh,
                );
              }
              final items = snapshot.requireData;
              if (items.isEmpty) {
                return ButlerlyEmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: context.l10n.text('reviewEmpty'),
                  message: context.l10n.text('reviewEmptyBody'),
                );
              }
              return Column(
                children: items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: ButlerlySpacing.small,
                        ),
                        child:
                            item.reason ==
                                ReviewIssueReason.normalizationMissing.name
                            ? _NormalizationReviewCard(
                                item: item,
                                finance: _finance!,
                                onDone: _refresh,
                              )
                            : _ReviewTransactionCard(
                                amount: item.amount,
                                currency: item.currency,
                                title:
                                    item.description ??
                                    context.l10n.text('untitledTransaction'),
                                reason:
                                    item.detail ??
                                    _reason(item.reason, context),
                                recommendation: context.l10n.text(
                                  'reviewRecommendation',
                                ),
                                primaryLabel: context.l10n.text('resolve'),
                                onPrimary: () => _close(item, dismiss: false),
                                editLabel: context.l10n.text('edit'),
                                dismissLabel: context.l10n.text('dismiss'),
                                onEdit: () => _openTransaction(item),
                                onDismiss: () => _close(item, dismiss: true),
                              ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }
}

class _ReviewTransactionCard extends StatelessWidget {
  const _ReviewTransactionCard({
    required this.title,
    required this.amount,
    required this.currency,
    required this.reason,
    required this.recommendation,
    required this.primaryLabel,
    required this.onPrimary,
    required this.editLabel,
    required this.dismissLabel,
    required this.onEdit,
    required this.onDismiss,
  });

  final String title;
  final String amount;
  final String currency;
  final String reason;
  final String recommendation;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String editLabel;
  final String dismissLabel;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    padding: const EdgeInsets.symmetric(vertical: ButlerlySpacing.compact),
    child: Column(
      children: [
        ButlerlyRecordRow(
          title: title,
          amount: localizedTransactionAmount(context, amount),
          currency: currency,
          needsReview: true,
        ),
        Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason),
              const SizedBox(height: ButlerlySpacing.small),
              Text(recommendation),
              const SizedBox(height: ButlerlySpacing.standard),
              ButlerlyButtonBar(
                spacing: ButlerlyButtonBarSpacing.none,
                children: [
                  FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
                  OutlinedButton(onPressed: onEdit, child: Text(editLabel)),
                  TextButton(onPressed: onDismiss, child: Text(dismissLabel)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum _ReviewView { needsReview, uncategorized, duplicates }

const _reviewTabs = [
  _ReviewView.uncategorized,
  _ReviewView.duplicates,
  _ReviewView.needsReview,
];

int _tabIndex(_ReviewView view) => _reviewTabs.indexOf(view);

class _ReviewSectionLabel extends StatelessWidget {
  const _ReviewSectionLabel({required this.title, required this.future});

  final String title;
  final Future<List<Object>> future;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Object>>(
    future: future,
    builder: (context, snapshot) {
      final count = snapshot.data?.length;
      return Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: ButlerlySpacing.micro,
          children: [
            Text(title, textAlign: TextAlign.center),
            if (count != null)
              Text(
                '($count)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _DuplicateGroupCard extends StatefulWidget {
  const _DuplicateGroupCard({
    required this.group,
    required this.finance,
    required this.masterData,
    required this.onKeepBoth,
    required this.onConsolidate,
  });

  final DuplicateCandidateGroup group;
  final FinanceServices finance;
  final Future<TransactionMasterDataSnapshot> masterData;
  final VoidCallback onKeepBoth;
  final ValueChanged<TransactionId> onConsolidate;

  @override
  State<_DuplicateGroupCard> createState() => _DuplicateGroupCardState();
}

class _DuplicateGroupCardState extends State<_DuplicateGroupCard> {
  TransactionId? _selectedTransactionId;
  late Future<(List<TransactionDto>, TransactionMasterDataSnapshot)>
  _candidateData;

  @override
  void initState() {
    super.initState();
    _candidateData = _loadCandidateData();
  }

  @override
  void didUpdateWidget(covariant _DuplicateGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id ||
        oldWidget.group.transactionIds != widget.group.transactionIds) {
      _selectedTransactionId = null;
      _candidateData = _loadCandidateData();
    } else if (oldWidget.masterData != widget.masterData) {
      _candidateData = _loadCandidateData();
    }
  }

  Future<List<TransactionDto>> _loadTransactions() => Future.wait(
    widget.group.transactionIds.map(
      (id) async => switch (await widget.finance.getTransaction(id.value)) {
        ApplicationSuccess<TransactionDto>(:final value) => value,
        ApplicationFailure<TransactionDto>() => throw StateError(
          'Transaction unavailable',
        ),
      },
    ),
  );

  Future<(List<TransactionDto>, TransactionMasterDataSnapshot)>
  _loadCandidateData() async =>
      (await _loadTransactions(), await widget.masterData);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
      child: ButlerlyCard(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: ButlerlySpacing.small),
                  Expanded(
                    child: Text(
                      context.l10n.text('possibleDuplicateGroup'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ButlerlySpacing.small),
              Text(_duplicateKeyLabel(context)),
              const SizedBox(height: ButlerlySpacing.small),
              FutureBuilder<
                (List<TransactionDto>, TransactionMasterDataSnapshot)
              >(
                future: _candidateData,
                builder: (context, snapshot) {
                  final transactions = snapshot.data?.$1 ?? const [];
                  final masterData = snapshot.data?.$2;
                  return RadioGroup<TransactionId>(
                    groupValue: _selectedTransactionId,
                    onChanged: (id) =>
                        setState(() => _selectedTransactionId = id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ButlerlyTransactionList(
                          children: [
                            for (final transaction in transactions)
                              ButlerlyTransactionListItem(
                                title:
                                    transaction.description
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? transaction.description!
                                    : context.l10n.text('untitledTransaction'),
                                amount: localizedTransactionAmount(
                                  context,
                                  transaction.amount,
                                ),
                                currency: transaction.currency,
                                meta: transactionDateLabel(
                                  transaction,
                                  pendingLabel: context.l10n.text(
                                    'datePending',
                                  ),
                                  locale: Localizations.localeOf(
                                    context,
                                  ).toLanguageTag(),
                                ),
                                subtitle: _transactionEvidenceLabel(
                                  context,
                                  transaction,
                                  masterData,
                                ),
                                isIncome:
                                    transaction.direction ==
                                    TransactionDirection.income.name,
                                selectionControl:
                                    ButlerlyTransactionSelectionControl<
                                      TransactionId
                                    >(value: TransactionId(transaction.id)),
                                onTap: () => setState(
                                  () => _selectedTransactionId = TransactionId(
                                    transaction.id,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              ButlerlyButtonBar(
                alignment: ButlerlyButtonBarAlignment.start,
                density: ButlerlyButtonBarDensity.compact,
                spacing: ButlerlyButtonBarSpacing.none,
                children: [
                  OutlinedButton(
                    onPressed: widget.onKeepBoth,
                    child: Text(context.l10n.text('keepBoth')),
                  ),
                  Tooltip(
                    message: context.l10n.text('consolidateUseOneHint'),
                    child: FilledButton(
                      onPressed: _selectedTransactionId == null
                          ? null
                          : () => widget.onConsolidate(_selectedTransactionId!),
                      child: Text(context.l10n.text('consolidateUseOne')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _duplicateKeyLabel(BuildContext context) =>
      '${widget.group.duplicateKey.transactionDate} · '
      '${widget.group.duplicateKey.amount} '
      '${widget.group.duplicateKey.currency} · '
      '${_directionLabel(context, widget.group.duplicateKey.direction)}';
}

String _transactionEvidenceLabel(
  BuildContext context,
  TransactionDto transaction,
  TransactionMasterDataSnapshot? masterData,
) {
  final paymentSource = masterData?.paymentSources
      .where((value) => value.id.value == transaction.paymentSourceId)
      .map((value) => value.name)
      .firstOrNull;
  final merchant = masterData?.presentation.merchantName(
    transaction.merchantId,
  );
  final supporting = [
    ?merchant,
    ?paymentSource,
    if (transaction.provenance.isNotEmpty)
      _reviewProvenanceLabel(context, transaction.provenance.first.sourceType),
  ];
  return supporting.where((value) => value.isNotEmpty).join(' · ');
}

String _directionLabel(BuildContext context, String direction) =>
    switch (direction) {
      'income' => context.l10n.text('income'),
      'expense' => context.l10n.text('expense'),
      'transfer' => context.l10n.text('transfer'),
      'refund' => context.l10n.text('refund'),
      'adjustment' => context.l10n.text('adjustment'),
      _ => context.l10n.text('direction'),
    };

String _reviewProvenanceLabel(BuildContext context, String sourceType) =>
    switch (sourceType) {
      'userEntry' => context.l10n.text('enteredLocally'),
      'import' => context.l10n.text('imported'),
      'scan' => context.l10n.text('scanned'),
      'evidenceExtraction' => context.l10n.text('evidenceExtraction'),
      'integration' => context.l10n.text('integration'),
      'deterministicCalculation' => context.l10n.text('calculation'),
      'localAi' => context.l10n.text('localAi'),
      'externalAi' => context.l10n.text('externalAi'),
      'migration' => context.l10n.text('migration'),
      _ => context.l10n.text('recordOrigin'),
    };

class _NormalizationReviewCard extends StatefulWidget {
  const _NormalizationReviewCard({
    required this.item,
    required this.finance,
    required this.onDone,
  });
  final ReviewItemDto item;
  final FinanceServices finance;
  final VoidCallback onDone;
  @override
  State<_NormalizationReviewCard> createState() =>
      _NormalizationReviewCardState();
}

class _NormalizationReviewCardState extends State<_NormalizationReviewCard> {
  late final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final preference = await widget.finance.loadUserPreference();
    if (preference is! ApplicationSuccess<UserPreference?> ||
        preference.value == null) {
      return;
    }
    DecimalValue amount;
    try {
      amount = DecimalValue.parse(_controller.text.trim());
    } on Object {
      return;
    }
    setState(() => _saving = true);
    final result = await widget.finance.confirmUserNormalizedAmount(
      id: TransactionId(widget.item.transactionId),
      normalized: Money(
        amount: amount,
        currency: preference.value!.baseCurrency,
      ),
    );
    if (mounted) setState(() => _saving = false);
    if (result is ApplicationSuccess) {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.item.description ?? context.l10n.text('untitledTransaction'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${localizedTransactionAmount(context, widget.item.amount)} ${widget.item.currency}',
        ),
        const SizedBox(height: ButlerlySpacing.small),
        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: context.l10n.text('normalizedAmount'),
          ),
        ),
        const SizedBox(height: ButlerlySpacing.small),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(context.l10n.text('confirm')),
        ),
      ],
    ),
  );
}

String _reason(String value, BuildContext context) => switch (value) {
  'incomplete' => context.l10n.text('uncategorized'),
  'duplicateCandidate' => context.l10n.text('possibleDuplicates'),
  _ => context.l10n.text('needsReview'),
};
