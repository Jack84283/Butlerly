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
}
