import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Existing intake defaults, explicit and injectable. Changing defaults is a
/// financial product decision; extraction and import logic must not invent one.
final class StatementIntakePolicy {
  const StatementIntakePolicy({
    this.defaultCurrency = 'USD',
    this.defaultDirection = TransactionDirection.expense,
    this.lowConfidenceThreshold = 0.5,
  });
  final String defaultCurrency;
  final TransactionDirection defaultDirection;
  final double lowConfidenceThreshold;

  bool needsConfidenceReview(double? confidence) =>
      confidence != null && confidence <= lowConfidenceThreshold;
}
