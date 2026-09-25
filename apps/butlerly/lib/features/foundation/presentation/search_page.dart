import 'dart:async';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/settlement_transaction_visibility.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_count_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

const _selectiveConditionEvidenceMarker = 'conditionEvidence:selective';

final class InsightDrillDownRefreshDecision {
  const InsightDrillDownRefreshDecision({
    required this.forceNoResults,
    required this.transactionIds,
  });

  final bool forceNoResults;
  final List<String>? transactionIds;
}

InsightDrillDownRefreshDecision resolveInsightDrillDownRefresh(
  InsightsEvaluation evaluation, {
  required String ruleId,
  String? dimension,
}) {
  InsightResult? refreshed;
  for (final insight in evaluation.activeFindings) {
    if (insight.rule.identity.value == ruleId &&
        insight.dimension == dimension) {
      refreshed = insight;
      break;
    }
  }
  if (refreshed == null) {
    return const InsightDrillDownRefreshDecision(
      forceNoResults: true,
      transactionIds: null,
    );
  }

  final remainsSelective =
      refreshed.finding?.supportingMetrics.contains(
        _selectiveConditionEvidenceMarker,
      ) ??
      false;
  if (!remainsSelective) {
    return const InsightDrillDownRefreshDecision(
      forceNoResults: false,
      transactionIds: null,
    );
  }

  final transactionIds = refreshed.evidence
      .map((evidence) => evidence.transactionId.value)
      .toList(growable: false);
  return InsightDrillDownRefreshDecision(
    forceNoResults: transactionIds.isEmpty,
    transactionIds: transactionIds,
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    this.initialFrom,
    this.initialTo,
    this.initialQuery,
    this.readOnly = false,
    this.insightRuleId,
    this.insightDimension,
    super.key,
  });

  final DateTime? initialFrom;
  final DateTime? initialTo;
  final ListTransactionsQuery? initialQuery;
  final bool readOnly;
  final String? insightRuleId;
  final String? insightDimension;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  List<String>? _transactionIds;
  String? _currency;
  TransactionDirection? _direction;
  String? _categoryId;
  String? _paymentSourceId;
  TransactionStatus? _status;
  bool? _needsReview;
  bool _uncategorized = false;
  bool _forceNoResults = false;
  DateTime? _from;
  DateTime? _to;
  Future<List<TransactionDto>>? _results;
  late Future<TransactionMasterDataSnapshot> _masterData;
  late Future<List<String>> _currencies;
  TransactionMasterData _presentation = const TransactionMasterData();
  Map<String, String> _paymentSourceNames = const {};
  String? _loadedLanguageCode;
  Timer? _searchDebounce;
  int _searchGeneration = 0;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  bool get _retriesInsightDrillDown =>
      widget.readOnly && widget.insightRuleId != null;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    _text.text = query?.text ?? '';
    _transactionIds = query?.transactionIds;
    _currency = query?.currency;
    _direction = query?.direction;
    _categoryId = query?.categoryId;
    _paymentSourceId = query?.paymentSourceId;
    _status = query?.status;
    _needsReview = query?.needsReview;
    _uncategorized = query?.uncategorized ?? false;
    _from = query?.from ?? widget.initialFrom;
    _to = query?.to ?? widget.initialTo;
    if (query != null || _from != null || _to != null) _results = _search();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_loadedLanguageCode == languageCode) return;
    _loadedLanguageCode = languageCode;
    _masterData = _loadMasterData(languageCode);
    _currencies = _loadCurrencies();
    _updatePresentation(_masterData, languageCode);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _updatePresentation(
    Future<TransactionMasterDataSnapshot> masterData,
    String languageCode,
  ) {
    masterData.then((value) {
      if (mounted && _loadedLanguageCode == languageCode) {
        setState(() {
          _presentation = value.presentation;
          _paymentSourceNames = {
            for (final source in value.paymentSources)
              source.id.value: source.lastFour == null
                  ? source.name
                  : '${source.name} ••••${source.lastFour}',
          };
        });
      }
    });
  }

  Future<List<TransactionDto>> _search() async {
    if (_forceNoResults) return const [];
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listTransactions(
      ListTransactionsQuery(
        text: _text.text.trim().isEmpty ? null : _text.text.trim(),
        transactionIds: _transactionIds,
        currency: _currency,
        direction: _direction,
        categoryId: _categoryId,
        paymentSourceId: _paymentSourceId,
        status: _status,
        needsReview: _needsReview,
        uncategorized: _uncategorized,
        from: _from,
        to: _to,
      ),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) =>
        excludeSettlementPaymentTransactions(
          value,
          await settlementPaymentTransactionIds(finance),
        ),
      ApplicationFailure<List<TransactionDto>>() => throw StateError(
        'Search failed',
      ),
    };
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

  Future<List<String>> _loadCurrencies() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listTransactions(
      const ListTransactionsQuery(),
    );
    return switch (result) {
      ApplicationSuccess<List<TransactionDto>>(:final value) =>
        excludeSettlementPaymentTransactions(
          value,
          await settlementPaymentTransactionIds(finance),
        ).map((transaction) => transaction.currency).toSet().toList()..sort(),
      ApplicationFailure<List<TransactionDto>>() => const [],
    };
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _submit);
  }

  void _submit() {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final future = _search();
    if (!mounted) return;
    setState(() {
      _results = _latestSearch(future, generation);
    });
  }

  Future<List<TransactionDto>> _latestSearch(
    Future<List<TransactionDto>> future,
    int generation,
  ) async {
    final value = await future;
    if (generation != _searchGeneration) return const [];
    return value;
  }

  void _clearFilters() {
    setState(() {
      _transactionIds = null;
      _currency = null;
      _direction = null;
      _categoryId = null;
      _paymentSourceId = null;
      _status = null;
      _needsReview = null;
      _uncategorized = false;
      _forceNoResults = false;
      _from = null;
      _to = null;
    });
    _submit();
  }

  void _resetSearch() {
    _text.clear();
    _clearFilters();
  }

  Future<void> _refreshInsightEvidence() async {
    final ruleId = widget.insightRuleId;
    final from = _from;
    final to = _to;
    if (ruleId == null || from == null || to == null) return;

    final calculateInsights = _finance?.calculateInsights;
    if (calculateInsights == null) {
      throw StateError('Insight analysis is unavailable.');
    }
    final contextResult = await calculateInsights.contextForDates(
      startDate: _searchDate(from),
      endDate: _searchDate(to),
    );
    if (contextResult is! ApplicationSuccess<AnalysisContext>) {
      throw StateError('Unable to resolve Insight drill-down period.');
    }
    final evaluationResult = await calculateInsights.call(contextResult.value);
    if (evaluationResult is! ApplicationSuccess<InsightsEvaluation>) {
      throw StateError('Unable to refresh Insight drill-down.');
    }

    final decision = resolveInsightDrillDownRefresh(
      evaluationResult.value,
      ruleId: ruleId,
      dimension: widget.insightDimension,
    );
    _forceNoResults = decision.forceNoResults;
    _transactionIds = decision.transactionIds;
  }

  Future<void> _refreshAfterTransactionChange() async {
    _searchDebounce?.cancel();
    _searchGeneration++;
    final languageCode =
        _loadedLanguageCode ?? Localizations.localeOf(context).languageCode;
    try {
      await _refreshInsightEvidence();
      final results = _search();
      final masterData = _loadMasterData(languageCode);
      final currencies = _loadCurrencies();
      if (!mounted) return;
      setState(() {
        _results = results;
        _masterData = masterData;
        _currencies = currencies;
      });
      _updatePresentation(masterData, languageCode);
      await Future.wait([results, masterData, currencies]);
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _results = Future<List<TransactionDto>>.error(error, stackTrace);
      });
    }
  }

  int get _activeFilterCount => [
    if (_transactionIds?.isNotEmpty ?? false) _transactionIds,
    _currency,
    _direction,
    _categoryId,
    _paymentSourceId,
    _status,
    _needsReview,
    if (_uncategorized) true,
    _from,
    _to,
  ].where((value) => value != null).length;

  Future<void> _openFilters() async {
    if (widget.readOnly) return;
    await showButlerlyBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ButlerlyTransactionFilterSheet(
        value: ButlerlyTransactionFilterValue(
          currency: _currency,
          direction: _direction,
          status: _status,
          categoryId: _categoryId,
          paymentSourceId: _paymentSourceId,
          needsReview: _needsReview,
          from: _from,
          to: _to,
        ),
        currencies: _currencies,
        masterData: _masterData,
        formatDate: _searchDate,
        onApply: (value) {
          _currency = value.currency;
          _direction = value.direction;
          _status = value.status;
          _categoryId = value.categoryId;
          _paymentSourceId = value.paymentSourceId;
          _needsReview = value.needsReview;
          _from = value.from;
          _to = value.to;
          Navigator.pop(sheetContext);
          _submit();
        },
        onClear: () {
          Navigator.pop(sheetContext);
          _clearFilters();
        },
      ),
    );
  }

  Future<void> _openDetail(TransactionDto transaction) async {
    final finance = _finance;
    if (finance == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    if (changed == true && mounted) {
      notifyTransactionChanged();
      await _refreshAfterTransactionChange();
    }
  }

  Widget _searchControls(BuildContext context) =>
      ButlerlyTransactionSearchControls(
        controller: _text,
        activeFilterCount: _activeFilterCount,
        onSearch: _submit,
        onChanged: (_) {
          setState(() {});
          _scheduleSearch();
        },
        onClear: () {
          _text.clear();
          _submit();
        },
        onFilter: _openFilters,
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ButlerlyPage(
      title: context.l10n.text('search'),
      onRefresh: () async {
        if (_results == null) return;
        await _refreshAfterTransactionChange();
      },
      refreshKey: const ValueKey('search-pull-to-refresh'),
      pinnedSpacing: widget.readOnly
          ? ButlerlyPinnedPageSpacing.defaults
          : ButlerlyPinnedPageSpacing.tightHeader,
      pinnedHeaderExtent: widget.readOnly
          ? ButlerlySize.minimumTarget
          : ButlerlySize.searchPinnedHeaderHeight,
      pinnedHeader: widget.readOnly ? null : _searchControls(context),
      children: [
        if (!widget.readOnly) ...[
          if (_activeFilterCount > 0)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _clearFilters,
                child: Text(context.l10n.text('clearFilters')),
              ),
            ),
        ] else ...[
          _LockedSearchCriteria(
            transactionIds: _transactionIds,
            from: _from,
            to: _to,
            categoryId: _categoryId,
            paymentSourceId: _paymentSourceId,
            currency: _currency,
            direction: _direction,
            uncategorized: _uncategorized,
            presentation: _presentation,
            paymentSourceNames: _paymentSourceNames,
          ),
          const SizedBox(height: ButlerlySpacing.standard),
        ],
        if (_results == null)
          ButlerlyEmptyState(
            icon: Icons.search_rounded,
            title: context.l10n.text('noSearchYet'),
            message: context.l10n.text('noSearchYetBody'),
          )
        else
          FutureBuilder<List<TransactionDto>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ButlerlyLoadingState();
              }
              if (snapshot.hasError) {
                return ButlerlyErrorState(
                  title: context.l10n.text('noResults'),
                  message: context.l10n.text('tryAgain'),
                  preserved: context.l10n.text('dataPreserved'),
                  actionLabel: context.l10n.text('tryAgain'),
                  onAction: _retriesInsightDrillDown
                      ? _refreshAfterTransactionChange
                      : _submit,
                );
              }
              final values = snapshot.requireData;
              if (values.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TransactionCountText(count: values.length),
                    const SizedBox(height: ButlerlySpacing.compact),
                    ButlerlyEmptyState(
                      icon: Icons.search_off_rounded,
                      title: context.l10n.text('noResults'),
                      message: context.l10n.text('noResultsBody'),
                      actionLabel: widget.readOnly
                          ? null
                          : context.l10n.text('clearSearch'),
                      onAction: widget.readOnly ? null : _resetSearch,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TransactionCountText(count: values.length),
                  const SizedBox(height: ButlerlySpacing.compact),
                  TransactionRecordList(
                    transactions: values,
                    masterData: _presentation,
                    paymentSourceNames: _paymentSourceNames,
                    groupByFinancialDate: true,
                    onTap: _openDetail,
                    navigates: true,
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }
}

class _LockedSearchCriteria extends StatelessWidget {
  const _LockedSearchCriteria({
    required this.transactionIds,
    required this.from,
    required this.to,
    required this.categoryId,
    required this.paymentSourceId,
    required this.currency,
    required this.direction,
    required this.uncategorized,
    required this.presentation,
    required this.paymentSourceNames,
  });

  final List<String>? transactionIds;
  final DateTime? from;
  final DateTime? to;
  final String? categoryId;
  final String? paymentSourceId;
  final String? currency;
  final TransactionDirection? direction;
  final bool uncategorized;
  final TransactionMasterData presentation;
  final Map<String, String> paymentSourceNames;

  @override
  Widget build(BuildContext context) {
    final criteria = <String>[
      if (from != null || to != null)
        '${from == null ? '…' : _searchDate(from!)} – ${to == null ? '…' : _searchDate(to!)}',
      if (uncategorized)
        '${context.l10n.text('category')}: ${context.l10n.text('uncategorized')}'
      else if (categoryId != null)
        '${context.l10n.text('category')}: ${presentation.categoryName(categoryId!) ?? categoryId!}',
      if (paymentSourceId != null)
        '${context.l10n.text('paymentSource')}: ${paymentSourceNames[paymentSourceId!] ?? paymentSourceId!}',
      if (currency != null) '${context.l10n.text('currency')}: $currency',
      if (direction != null)
        '${context.l10n.text('direction')}: ${direction!.name}',
      if (transactionIds?.isNotEmpty ?? false)
        context.l10n.text('supportingTransactions', {
          'count': '${transactionIds!.length}',
        }),
    ];
    return ButlerlyCard(
      key: const ValueKey('locked-search-criteria'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text('filters'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: ButlerlySpacing.small),
          for (final criterion in criteria)
            Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.micro),
              child: Text(criterion),
            ),
        ],
      ),
    );
  }
}

String _searchDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
