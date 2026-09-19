/// Statement intake policy contains review thresholds only.
///
/// Missing financial values must remain explicit until the user confirms or
/// corrects them. Currency and direction defaults are intentionally excluded:
/// applying them to OCR gaps would turn unknown source data into invented
/// canonical financial values.
final class StatementIntakePolicy {
  const StatementIntakePolicy({this.lowConfidenceThreshold = 0.5});

  final double lowConfidenceThreshold;

  bool needsConfidenceReview(double? confidence) =>
      confidence != null && confidence <= lowConfidenceThreshold;
}
