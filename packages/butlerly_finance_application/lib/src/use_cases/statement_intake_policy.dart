import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Statement intake policy. Missing extracted financial values remain unknown
/// unless a caller explicitly configures a default; the default P0 workflow
/// never invents currency or direction.
final class StatementIntakePolicy {
  const StatementIntakePolicy({
    this.defaultCurrency,
    this.defaultDirection,
    this.lowConfidenceThreshold = 0.5,
  });

  final String? defaultCurrency;
  final TransactionDirection? defaultDirection;
  final double lowConfidenceThreshold;

  bool needsConfidenceReview(double? confidence) =>
      confidence != null && confidence <= lowConfidenceThreshold;
}
