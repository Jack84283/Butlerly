import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'canonical_transactions.dart';
import 'period_resolver.dart';

final class AnalysisDatasetBuilder {
  const AnalysisDatasetBuilder(
    this.transactions,
    this.preferences,
    this.links, {
    this.candidates,
    this.duplicateGroups,
    this.categories,
    this.periodResolver = const AnalysisPeriodResolver(),
  });
  final TransactionRepository transactions;
  final UserPreferenceRepository preferences;
  final ReconciliationLinkRepository? links;
  final ReconciliationCandidateRepository? candidates;
  final DuplicateCandidateGroupRepository? duplicateGroups;
  final CategoryRepository? categories;
  final AnalysisPeriodResolver periodResolver;

  Future<String> timeZoneId() async {
    return (await configuredFinancialTimeZone(preferences)).id;
  }

  Future<CurrencyCode?> baseCurrency() async =>
      (await preferences.load())?.baseCurrency;

  Future<ApplicationDatasetResult> build(AnalysisContext context) async {
    final preference = await preferences.load();
    if (preference == null) {
      return const ApplicationDatasetResult.failure('preferencesUnavailable');
    }
    final source = await transactions.listAll();
    final categoriesById = {
      for (final category in await categories?.listAll() ?? <Category>[])
        category.id.value: category,
    };
    final reconciliationLinks = links == null
        ? const <ReconciliationLink>[]
        : await links!.listAll();
    final reconciliationCandidates = candidates == null
        ? const <ReconciliationCandidate>[]
        : await candidates!.listAll();
    final duplicateCandidateGroups = duplicateGroups == null
        ? const <DuplicateCandidateGroup>[]
        : await duplicateGroups!.list();
    final canonical = selectCanonicalTransactions(
      source: source,
      links: reconciliationLinks,
      duplicateGroups: duplicateCandidateGroups,
    );
    final quality = <DataQualityIssue>[
      ...canonical.qualityIssues.where((issue) => issue.transactionId == null),
    ];
    final result = <AnalysisEconomicTransaction>[];
    for (final transaction in canonical.transactions) {
      final transactionDate = transactionFinancialDate(
        transaction,
        context.period.timeZoneId,
      )?.toIso8601String().substring(0, 10);
      final normalized = transaction.normalizedMoney
          .where(
            (value) =>
                value.baseCurrency == preference.baseCurrency &&
                value.original == transaction.money,
          )
          .firstOrNull
          ?.converted;
      final transactionQuality = <DataQualityIssue>[];
      transactionQuality.addAll(
        canonical.issuesByTransaction[transaction.id] ?? const [],
      );
      if (transactionDate == null || transactionDate.isEmpty) {
        transactionQuality.add(
          DataQualityIssue(
            code: 'missingFinancialDate',
            detail: 'Transaction has no authoritative financial date.',
            transactionId: transaction.id,
          ),
        );
      }
      if (transaction.money.currency != preference.baseCurrency &&
          normalized == null) {
        transactionQuality.add(
          DataQualityIssue(
            code: 'missingFx',
            detail:
                'Foreign-currency transaction has no valid normalized value.',
            transactionId: transaction.id,
          ),
        );
      }
      for (final candidate in reconciliationCandidates) {
        if (candidate.status == ReconciliationCandidateStatus.proposed &&
            candidate.paymentTransactionId == transaction.id) {
          transactionQuality.add(
            DataQualityIssue(
              code: 'reconciliationUncertainty',
              detail: 'A reconciliation candidate remains unresolved.',
              transactionId: transaction.id,
            ),
          );
        }
      }
      quality.addAll(transactionQuality);
      result.add(
        AnalysisEconomicTransaction(
          id: transaction.id,
          money: transaction.money,
          normalizedMoney: normalized,
          direction: transaction.direction,
          transactionDate: transactionDate,
          status: transaction.status,
          categoryId: _effectiveCategoryId(transaction, categoriesById),
          subcategoryId: _effectiveSubcategoryId(transaction, categoriesById),
          merchantId: transaction.merchantId,
          paymentSourceId: transaction.paymentSourceId,
          tagIds: transaction.tagIds,
          verified: transaction.reviewState == TransactionReviewState.clear,
          dataQuality: transactionQuality,
        ),
      );
    }
    final primary = periodResolver.resolvePrimary(
      type: 'selected_period',
      context: context,
    );
    if (primary case AnalysisPeriodResolutionFailure(:final code)) {
      return ApplicationDatasetResult.failure(code);
    }
    final supportedPeriods = [
      'selected_period',
      'selected_month',
      'current_month',
      'previous_month',
      'year_to_date',
      'previous_year',
      'rolling_30_days',
      'rolling_90_days',
    ];
    final primaryByPeriod = <String, List<AnalysisEconomicTransaction>>{};
    final baselineByPeriod = <String, List<AnalysisEconomicTransaction>>{};
    for (final type in supportedPeriods) {
      final resolution = type == 'selected_period'
          ? AnalysisPeriodResolved(_windowForContext(context))
          : periodResolver.resolvePrimary(type: type, context: context);
      if (resolution case AnalysisPeriodResolved(:final window)) {
        primaryByPeriod[type] = _buildTransactions(
          canonical,
          preference.baseCurrency,
          window,
          categoriesById,
        );
        final baselineResolution = periodResolver.resolvePreviousEquivalent(
          primary: window,
          elapsedAnchor: context.periodType == 'selected_period'
              ? null
              : _parseDate(context.period.endDate).add(const Duration(days: 1)),
        );
        if (baselineResolution is AnalysisPeriodResolved) {
          final baselineWindow = baselineResolution.window;
          baselineByPeriod[type] = _buildTransactions(
            canonical,
            preference.baseCurrency,
            baselineWindow,
            categoriesById,
          );
        }
      }
    }
    final baseline = baselineByPeriod['selected_period'] ?? const [];
    return ApplicationDatasetResult.success(
      AnalysisDataset(
        transactions: result,
        primaryTransactionsByPeriod: {...primaryByPeriod},
        baselineTransactions: baseline,
        baselineTransactionsByPeriod: baselineByPeriod,
        context: context,
        qualityIssues: quality,
      ),
    );
  }

  // Older data stores a leaf category in categoryId without subcategoryId.
  // Use the same normalization as the transaction editor so those expenses
  // are not incorrectly included in the subcategory "uncategorized" bucket.
  // Do not invent a subcategory when the assigned category is a root.
  CategoryId? _effectiveCategoryId(
    Transaction transaction,
    Map<String, Category> categoriesById,
  ) {
    if (transaction.subcategoryId != null) return transaction.categoryId;
    final parentId = categoriesById[transaction.categoryId?.value]?.parentId;
    return parentId ?? transaction.categoryId;
  }

  CategoryId? _effectiveSubcategoryId(
    Transaction transaction,
    Map<String, Category> categoriesById,
  ) {
    if (transaction.subcategoryId != null) return transaction.subcategoryId;
    final parentId = categoriesById[transaction.categoryId?.value]?.parentId;
    return parentId == null ? null : transaction.categoryId;
  }

  ResolvedAnalysisWindow _windowForContext(AnalysisContext context) {
    final start = _parseDate(context.period.startDate);
    final end = _parseDate(context.period.endDate).add(const Duration(days: 1));
    final partial = {
      'current_month',
      'year_to_date',
      'rolling_30_days',
      'rolling_90_days',
    }.contains(context.periodType);
    final periodType = switch (context.periodType) {
      'current_month' || 'previous_month' || 'selected_month' => 'month',
      'year_to_date' || 'previous_year' => 'year',
      _ => 'custom',
    };
    return ResolvedAnalysisWindow(
      start: start,
      endExclusive: end,
      timeZoneId: context.period.timeZoneId,
      coverage: partial
          ? AnalysisCoverageState.partial
          : AnalysisCoverageState.complete,
      periodType: periodType,
    );
  }

  DateTime _parseDate(String value) {
    final date = DateTime.parse(value);
    return DateTime.utc(date.year, date.month, date.day);
  }

  List<AnalysisEconomicTransaction> _buildTransactions(
    CanonicalTransactionSelection canonical,
    CurrencyCode baseCurrency,
    ResolvedAnalysisWindow window,
    Map<String, Category> categoriesById,
  ) {
    return canonical.transactions
        .where((transaction) {
          final date = transactionFinancialDate(transaction, window.timeZoneId);
          return date != null &&
              !date.isBefore(window.start) &&
              date.isBefore(window.endExclusive);
        })
        .map((transaction) {
          final transactionDate = transactionFinancialDate(
            transaction,
            window.timeZoneId,
          )?.toIso8601String().substring(0, 10);
          final normalized = transaction.normalizedMoney
              .where(
                (value) =>
                    value.baseCurrency == baseCurrency &&
                    value.original == transaction.money,
              )
              .firstOrNull
              ?.converted;
          return AnalysisEconomicTransaction(
            id: transaction.id,
            money: transaction.money,
            normalizedMoney: normalized,
            direction: transaction.direction,
            transactionDate: transactionDate,
            status: transaction.status,
            categoryId: _effectiveCategoryId(transaction, categoriesById),
            subcategoryId: _effectiveSubcategoryId(transaction, categoriesById),
            merchantId: transaction.merchantId,
            paymentSourceId: transaction.paymentSourceId,
            tagIds: transaction.tagIds,
            verified: transaction.reviewState == TransactionReviewState.clear,
            dataQuality:
                canonical.issuesByTransaction[transaction.id] ?? const [],
          );
        })
        .toList(growable: false);
  }
}

sealed class ApplicationDatasetResult {
  const ApplicationDatasetResult();
  const factory ApplicationDatasetResult.success(AnalysisDataset dataset) =
      ApplicationDatasetSuccess;
  const factory ApplicationDatasetResult.failure(String code) =
      ApplicationDatasetFailure;
}

final class ApplicationDatasetSuccess extends ApplicationDatasetResult {
  const ApplicationDatasetSuccess(this.dataset);
  final AnalysisDataset dataset;
}

final class ApplicationDatasetFailure extends ApplicationDatasetResult {
  const ApplicationDatasetFailure(this.code);
  final String code;
}
