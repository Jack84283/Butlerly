import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class AnalysisDatasetBuilder {
  const AnalysisDatasetBuilder(this.transactions, this.preferences, this.links);
  final TransactionRepository transactions;
  final UserPreferenceRepository preferences;
  final ReconciliationLinkRepository? links;

  Future<ApplicationDatasetResult> build(AnalysisContext context) async {
    final preference = await preferences.load();
    if (preference == null) {
      return const ApplicationDatasetResult.failure('preferencesUnavailable');
    }
    final source = await transactions.listAll();
    final reconciliationLinks = links == null
        ? const <ReconciliationLink>[]
        : await links!.listAll();
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
      if (transaction.transactionDate == null) {
        quality.add(
          DataQualityIssue(
            code: 'missingFinancialDate',
            detail: 'Transaction has no authoritative financial date.',
            transactionId: transaction.id,
          ),
        );
      }
      if (transaction.money.currency != preference.baseCurrency &&
          normalized == null) {
        quality.add(
          DataQualityIssue(
            code: 'missingFx',
            detail:
                'Foreign-currency transaction has no valid normalized value.',
            transactionId: transaction.id,
          ),
        );
      }
      result.add(
        AnalysisEconomicTransaction(
          id: transaction.id,
          money: transaction.money,
          normalizedMoney: normalized,
          direction: transaction.direction,
          transactionDate: transaction.transactionDate,
          categoryId: transaction.categoryId,
          merchantId: transaction.merchantId,
          paymentSourceId: transaction.paymentSourceId,
          tagIds: transaction.tagIds,
          verified: transaction.reviewState == TransactionReviewState.clear,
          dataQuality: quality
              .where((value) => value.transactionId == transaction.id)
              .toList(growable: false),
        ),
      );
    }
    return ApplicationDatasetResult.success(
      AnalysisDataset(
        transactions: result,
        context: context,
        qualityIssues: quality,
      ),
    );
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
