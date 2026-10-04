import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// A derived application financial value that is not the direct output of a
/// persisted analysis rule.
///
/// The context, currency, availability, and quality information remain part
/// of the contract so presentation consumers cannot mistake a derived value
/// for an unscoped or device-local calculation.
final class AnalysisValue {
  const AnalysisValue({
    required this.value,
    required this.context,
    this.currency,
    this.availability = AnalysisDataAvailability.sufficient,
    this.qualityIssues = const [],
  });

  final DecimalValue value;
  final CurrencyCode? currency;
  final AnalysisContext context;
  final AnalysisDataAvailability availability;
  final List<DataQualityIssue> qualityIssues;
}
