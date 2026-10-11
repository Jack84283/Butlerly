import '../value_objects/decimal_value.dart';

enum RecurringPatternDecisionStatus { confirmed, rejected, corrected }

enum RecurringPatternDecisionCadence {
  weekly,
  biweekly,
  monthly,
  quarterly,
  irregular,
}

/// Durable user intent for a locally detected recurring pattern.
///
/// This is deliberately separate from transactions and from the detector's
/// derived output. Re-running detection can therefore retain a user's
/// confirmation, rejection, or correction without changing financial data.
final class RecurringPatternDecision {
  const RecurringPatternDecision({
    required this.id,
    required this.patternKey,
    required this.status,
    required this.cadence,
    required this.intervalDays,
    required this.expectedAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String patternKey;
  final RecurringPatternDecisionStatus status;
  final RecurringPatternDecisionCadence cadence;
  final int intervalDays;
  final DecimalValue expectedAmount;
  final DateTime createdAt;
  final DateTime updatedAt;
}
