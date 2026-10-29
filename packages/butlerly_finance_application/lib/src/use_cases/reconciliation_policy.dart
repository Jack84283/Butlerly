import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Current explainable receipt/payment matching policy. Centralized without
/// changing the existing thresholds, ranking weights, or financial meaning.
abstract final class ReconciliationPolicy {
  static const candidateMinimumScore = 0.45;
  static const exactAmountWeight = 0.55;
  static const nearbyAmountWeight = 0.35;
  static const maximumAmountDifferenceRatio = 0.10;
  static const sameDateWeight = 0.25;
  static const nearbyDateWeight = 0.15;
  static const maximumDateDistanceDays = 1;
  static const exactMerchantSimilarity = 0.99;
  static const partialMerchantSimilarity = 0.50;
  static const exactMerchantWeight = 0.15;
  static const partialMerchantWeight = 0.10;
  static const paymentSourceWeight = 0.05;

  static bool validLinkEndpoints(Transaction receipt, Transaction payment) {
    return _validLinkEndpoints(
      receipt,
      payment,
      allowUnassignedManualPayment: false,
    );
  }

  /// Validates a link that was already confirmed and persisted.
  ///
  /// Payment-source assignment is metadata used to qualify new manually
  /// entered payments for reconciliation. It is not part of the confirmed
  /// economic relationship, so removing that metadata must not invalidate an
  /// existing link after restart or recalculation.
  static bool validConfirmedLinkEndpoints(
    Transaction receipt,
    Transaction payment,
  ) {
    return _validLinkEndpoints(
      receipt,
      payment,
      allowUnassignedManualPayment: true,
    );
  }

  static bool _validLinkEndpoints(
    Transaction receipt,
    Transaction payment, {
    required bool allowUnassignedManualPayment,
  }) {
    final paymentRole =
        payment.sourceType == TransactionSourceType.import ||
        payment.sourceType == TransactionSourceType.integration ||
        (payment.sourceType == TransactionSourceType.manual &&
            (allowUnassignedManualPayment || payment.paymentSourceId != null));
    return receipt.sourceType == TransactionSourceType.evidenceCapture &&
        paymentRole &&
        receipt.direction == payment.direction;
  }
}
