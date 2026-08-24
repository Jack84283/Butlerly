import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class EvaluateTransactionNormalization {
  const EvaluateTransactionNormalization(
    this.transactions,
    this.preferences,
    this.rates,
    this.clock,
  );
  final TransactionRepository transactions;
  final UserPreferenceRepository preferences;
  final ExchangeRateRepository? rates;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(TransactionId id) async =>
      runApplication('evaluate normalization', () async {
        final transaction = await transactions.findById(id);
        if (transaction == null)
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'transaction not found',
          );
        final preference = await preferences.load();
        if (preference == null)
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'preferences not found',
          );
        final existing = transaction.normalizedMoney
            .where((v) => v.source == NormalizationSource.userEntered)
            .firstOrNull;
        final date =
            DateTime.tryParse(transaction.transactionDate ?? '') ??
            transaction.createdAt;
        final rate = rates == null
            ? null
            : await rates!.findApplicable(
                fromCurrency: transaction.money.currency,
                toCurrency: preference.baseCurrency,
                financialDate: date,
              );
        final existingNormalized = existing;
        final result = normalizeMoney(
          original: transaction.money,
          baseCurrency: preference.baseCurrency,
          exchangeRate: existingNormalized == null ? rate : null,
          userEnteredNormalized:
              existingNormalized != null &&
                  existingNormalized.baseCurrency == preference.baseCurrency &&
                  existingNormalized.original == transaction.money
              ? existingNormalized.converted
              : null,
        );
        final now = clock.now();
        var updated = transaction;
        final reviewId = ReviewIssueId('normalization-${id.value}');
        final issue = transaction.reviewIssues
            .where((v) => v.id == reviewId)
            .firstOrNull;
        if (result.status == NormalizationStatus.missingRate) {
          final next = issue == null
              ? ReviewIssue(
                  id: reviewId,
                  transactionId: id,
                  reason: ReviewIssueReason.normalizationMissing,
                  detail: 'A base-currency normalized amount is required.',
                  createdAt: now,
                )
              : (issue.status == ReviewIssueStatus.active
                    ? issue
                    : issue.reopen());
          updated = issue == null
              ? updated.addReviewIssue(next, now)
              : (issue.status == ReviewIssueStatus.active
                    ? updated
                    : updated.reopenReviewIssue(reviewId, now));
        } else {
          if (result.normalized != null && existing == null)
            updated = updated.replaceNormalizedMoney(
              NormalizedMoney(
                original: transaction.money,
                converted: result.normalized!,
                exchangeRate: result.exchangeRate,
                source: result.source ?? NormalizationSource.exchangeRate,
                baseCurrency: preference.baseCurrency,
                effectiveDate: date.toIso8601String(),
                updatedAt: now,
              ),
              now,
            );
          if (issue?.status == ReviewIssueStatus.active)
            updated = updated.resolveReviewIssue(reviewId, now);
        }
        await transactions.save(updated);
        return TransactionDto.fromDomain(updated);
      });
}

final class ConfirmUserNormalizedAmount {
  const ConfirmUserNormalizedAmount(
    this.transactions,
    this.preferences,
    this.clock,
  );
  final TransactionRepository transactions;
  final UserPreferenceRepository preferences;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call({
    required TransactionId id,
    required Money normalized,
  }) async => runApplication('confirm normalized amount', () async {
    final transaction = await transactions.findById(id);
    final preference = await preferences.load();
    if (transaction == null || preference == null)
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'normalization target not found',
      );
    if (normalized.currency != preference.baseCurrency)
      throw const DomainValidationException(
        code: DomainErrorCode.invalidCurrency,
        field: 'currency',
        message: 'Normalized amount must use the base currency.',
      );
    final now = clock.now();
    var updated = transaction.replaceNormalizedMoney(
      NormalizedMoney(
        original: transaction.money,
        converted: normalized,
        source: NormalizationSource.userEntered,
        baseCurrency: preference.baseCurrency,
        effectiveDate:
            transaction.transactionDate ??
            transaction.createdAt.toIso8601String(),
        updatedAt: now,
      ),
      now,
    );
    final issue = updated.reviewIssues
        .where(
          (v) =>
              v.reason == ReviewIssueReason.normalizationMissing &&
              v.status == ReviewIssueStatus.active,
        )
        .firstOrNull;
    if (issue != null) updated = updated.resolveReviewIssue(issue.id, now);
    await transactions.save(updated);
    return TransactionDto.fromDomain(updated);
  });
}
