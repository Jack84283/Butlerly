import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// A compact drill-through identity with optional snapshot evidence.
///
/// The selected grouping and period explain the result, but the authoritative
/// transaction set comes from the Analysis engine. The IDs are kept in route
/// state rather than placed in an unbounded URL.
final class AnalysisSearchSelection {
  const AnalysisSearchSelection({
    required this.context,
    required this.ruleId,
    required this.dimension,
    this.evidenceIds = const [],
  });

  final AnalysisContext context;
  final String ruleId;
  final String? dimension;
  final List<String> evidenceIds;

  bool get isSnapshot => evidenceIds.isNotEmpty;

  /// Recalculate only when evidence was not attached to the selected metric.
  /// The engine applies canonical reconciliation, period, rule and dataset
  /// eligibility before selecting the evidence. Never broaden an empty result
  /// to all transactions in the period.
  Future<List<String>> resolveEvidence({
    required Future<ApplicationResult<List<RuleExecutionResult>>> Function(
      AnalysisContext,
    )
    calculate,
  }) async {
    if (evidenceIds.isNotEmpty) return evidenceIds.toSet().toList();
    final calculated = await calculate(context);
    if (calculated is! ApplicationSuccess<List<RuleExecutionResult>>) {
      throw StateError('Unable to recalculate Analysis evidence.');
    }
    return {
      for (final result in calculated.value)
        if (result.rule.identity.value == ruleId &&
            result.metric != null &&
            result.metric!.availability ==
                AnalysisDataAvailability.sufficient &&
            (dimension == null ||
                result.metric!.dimension?.split(':').first == dimension))
          for (final evidence in result.metric!.evidence)
            evidence.transactionId.value,
    }.toList(growable: false);
  }
}
