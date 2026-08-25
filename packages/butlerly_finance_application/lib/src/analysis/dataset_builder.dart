import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class AnalysisDatasetBuilder {
  const AnalysisDatasetBuilder(
    this.transactions,
    this.preferences,
    this.links, {
    this.candidates,
  });
  final TransactionRepository transactions;
  final UserPreferenceRepository preferences;
  final ReconciliationLinkRepository? links;
  final ReconciliationCandidateRepository? candidates;

  Future<String> timeZoneId() async {
    final preference = await preferences.load();
    return preference?.timeZoneId ?? 'UTC';
  }

  Future<ApplicationDatasetResult> build(AnalysisContext context) async {
    final preference = await preferences.load();
    if (preference == null) {
      return const ApplicationDatasetResult.failure('preferencesUnavailable');
    }
    final source = await transactions.listAll();
    final reconciliationLinks = links == null
        ? const <ReconciliationLink>[]
        : await links!.listAll();
    final reconciliationCandidates = candidates == null
        ? const <ReconciliationCandidate>[]
        : await candidates!.listAll();
    final receiptIds = reconciliationLinks
        .map((value) => value.receiptTransactionId)
        .toSet();
    final quality = <DataQualityIssue>[];
    final result = <AnalysisEconomicTransaction>[];
    for (final transaction in source) {
      if (receiptIds.contains(transaction.id)) continue;
      if (transaction.status != TransactionStatus.active) continue;
      final normalized = transaction.normalizedMoney
          .where(
            (value) =>
                value.baseCurrency == preference.baseCurrency &&
                value.original == transaction.money,
          )
          .firstOrNull
          ?.converted;
      final transactionQuality = <DataQualityIssue>[];
      if (transaction.transactionDate == null) {
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
          transactionDate: transaction.transactionDate,
          status: transaction.status,
          categoryId: transaction.categoryId,
          merchantId: transaction.merchantId,
          paymentSourceId: transaction.paymentSourceId,
          tagIds: transaction.tagIds,
          verified: transaction.reviewState == TransactionReviewState.clear,
          dataQuality: transactionQuality,
        ),
      );
    }
    final start = DateTime.parse(context.period.startDate);
    final end = DateTime.parse(context.period.endDate);
    final length = end.difference(start).inDays + 1;
    final baselineStart = start.subtract(Duration(days: length));
    final baselineEnd = start.subtract(const Duration(days: 1));
    final baseline = _buildTransactions(
      source,
      reconciliationLinks,
      preference.baseCurrency,
      baselineStart,
      baselineEnd,
    );
    return ApplicationDatasetResult.success(
      AnalysisDataset(
        transactions: result,
        baselineTransactions: baseline,
        context: context,
        qualityIssues: quality,
      ),
    );
  }

  List<AnalysisEconomicTransaction> _buildTransactions(
    List<Transaction> source,
    List<ReconciliationLink> links,
    CurrencyCode baseCurrency,
    DateTime start,
    DateTime end,
  ) {
    final receiptIds = links.map((value) => value.receiptTransactionId).toSet();
    return source
        .where((transaction) {
          final date = DateTime.tryParse(transaction.transactionDate ?? '');
          return transaction.status == TransactionStatus.active &&
              !receiptIds.contains(transaction.id) &&
              date != null &&
              !date.isBefore(start) &&
              !date.isAfter(end);
        })
        .map((transaction) {
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
            transactionDate: transaction.transactionDate,
            status: transaction.status,
            categoryId: transaction.categoryId,
            merchantId: transaction.merchantId,
            paymentSourceId: transaction.paymentSourceId,
            tagIds: transaction.tagIds,
            verified: transaction.reviewState == TransactionReviewState.clear,
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
