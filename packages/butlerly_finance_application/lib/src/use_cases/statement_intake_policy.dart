/// Review-only intake policy for statement extraction.
///
/// Missing financial facts remain missing until the user confirms or corrects
/// them. This policy must never invent currency, direction, dates, or amounts.
final class StatementIntakePolicy {
  const StatementIntakePolicy({this.lowConfidenceThreshold = 0.5});

  final double lowConfidenceThreshold;

  bool needsConfidenceReview(double? confidence) =>
      confidence != null && confidence <= lowConfidenceThreshold;
}
