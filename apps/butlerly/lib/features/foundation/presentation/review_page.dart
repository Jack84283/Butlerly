import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late Future<List<ReviewItemDto>> _items;
  late Future<List<ReconciliationCandidate>> _candidates;
  _ReviewView _view = _ReviewView.needsReview;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _items = _load();
    _candidates = _loadCandidates();
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
    _candidates = _loadCandidates();
  });

  Future<List<ReconciliationCandidate>> _loadCandidates() async {
    final finance = _finance;
    if (finance == null) return const [];
    await finance.refreshReconciliationCandidates();
    final result = await finance.listReconciliationCandidates();
    return switch (result) {
      ApplicationSuccess<List<ReconciliationCandidate>>(:final value) => value,
      ApplicationFailure<List<ReconciliationCandidate>>() => const [],
    };
  }

  Future<void> _decideCandidate(
    ReconciliationCandidate candidate,
    bool confirm,
  ) async {
    final updated = confirm ? candidate.confirm() : candidate.reject();
    await _finance?.saveReconciliationCandidate(updated);
    if (confirm) {
      await _finance?.saveReconciliationLink(
        ReconciliationLink(
          id: 'link-${candidate.id}',
          candidateId: candidate.id,
          receiptTransactionId: candidate.receiptTransactionId,
          paymentTransactionId: candidate.paymentTransactionId,
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (mounted) _refresh();
  }

  Future<void> _close(ReviewItemDto item, {required bool dismiss}) async {
    final finance = _finance;
    if (finance == null) return;
    final result = dismiss
        ? await finance.dismissReviewIssue(item.transactionId, item.issueId)
        : await finance.resolveReviewIssue(item.transactionId, item.issueId);
    if (!mounted) return;
    if (result is ApplicationFailure<TransactionDto>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('dataPreserved'))),
      );
      return;
    }
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
      subtitle: context.l10n.text('reviewSubtitle'),
      children: [
        SegmentedButton<_ReviewView>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _ReviewView.needsReview,
              label: Text(context.l10n.text('needsReview')),
            ),
            ButtonSegment(
              value: _ReviewView.uncategorized,
              label: Text(context.l10n.text('uncategorized')),
            ),
            ButtonSegment(
              value: _ReviewView.duplicates,
              label: Text(context.l10n.text('possibleDuplicates')),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (value) => setState(() => _view = value.single),
        ),
        const SizedBox(height: ButlerlySpacing.section),
        if (_view == _ReviewView.duplicates)
          FutureBuilder<List<ReconciliationCandidate>>(
            future: _candidates,
            builder: (context, snapshot) {
              final candidates = snapshot.data ?? const [];
              if (candidates.isEmpty) {
                return ButlerlyEmptyState(
                  icon: Icons.copy_all_outlined,
                  title: context.l10n.text('reviewEmpty'),
                  message: context.l10n.text('reviewEmptyBody'),
                );
              }
              return Column(
                children: [
                  for (final candidate in candidates.where(
                    (value) =>
                        value.status == ReconciliationCandidateStatus.proposed,
                  ))
                    _ReconciliationCandidateCard(
                      candidate: candidate,
                      finance: _finance!,
                      onConfirm: () => _decideCandidate(candidate, true),
                      onReject: () => _decideCandidate(candidate, false),
                    ),
                ],
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
                return const Padding(
                  padding: EdgeInsets.all(ButlerlySpacing.large),
                  child: Center(child: CircularProgressIndicator()),
                );
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
                        child: ButlerlyReviewCard(
                          title:
                              item.description ??
                              context.l10n.text('untitledTransaction'),
                          reason: item.detail ?? _reason(item.reason, context),
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

enum _ReviewView { needsReview, uncategorized, duplicates }

class _ReconciliationCandidateCard extends StatelessWidget {
  const _ReconciliationCandidateCard({
    required this.candidate,
    required this.finance,
    required this.onConfirm,
    required this.onReject,
  });

  final ReconciliationCandidate candidate;
  final FinanceServices finance;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  Future<List<TransactionDto?>> _loadTransactions() => Future.wait([
    finance
        .getTransaction(candidate.receiptTransactionId.value)
        .then(
          (result) => result is ApplicationSuccess<TransactionDto>
              ? result.value
              : null,
        ),
    finance
        .getTransaction(candidate.paymentTransactionId.value)
        .then(
          (result) => result is ApplicationSuccess<TransactionDto>
              ? result.value
              : null,
        ),
  ]);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TransactionDto?>>(
    future: _loadTransactions(),
    builder: (context, snapshot) {
      final receipt = snapshot.data?[0];
      final payment = snapshot.data?[1];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(candidate.score * 100).round()}% ${context.l10n.text('matchConfidence')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              _CandidateTransactionSummary(
                label: context.l10n.text('receipt'),
                transaction: receipt,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              _CandidateTransactionSummary(
                label: context.l10n.text('payment'),
                transaction: payment,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              Text(candidate.reasons.join(' · ')),
              const SizedBox(height: ButlerlySpacing.small),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onReject,
                    child: Text(context.l10n.text('dismiss')),
                  ),
                  FilledButton(
                    onPressed: onConfirm,
                    child: Text(context.l10n.text('resolve')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CandidateTransactionSummary extends StatelessWidget {
  const _CandidateTransactionSummary({required this.label, this.transaction});

  final String label;
  final TransactionDto? transaction;

  @override
  Widget build(BuildContext context) {
    final value = transaction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Text(
          value == null
              ? context.l10n.text('unavailableTransaction')
              : '${value.rawCounterparty ?? value.description ?? context.l10n.text('untitledTransaction')} · ${value.currency} ${value.amount} · ${value.transactionDate ?? '—'}',
        ),
      ],
    );
  }
}

String _reason(String value, BuildContext context) => switch (value) {
  'incomplete' => context.l10n.text('uncategorized'),
  'duplicateCandidate' => context.l10n.text('possibleDuplicates'),
  _ => context.l10n.text('needsReview'),
};
