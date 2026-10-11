import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

enum RecurringPatternStatus { detected, confirmed, rejected, corrected }

enum RecurringCadence { weekly, biweekly, monthly, quarterly, irregular }

/// A deterministic, user-reviewable recurring pattern. Expected occurrences
/// are never included in actual analysis totals.
final class RecurringPattern {
  const RecurringPattern({
    required this.id,
    required this.patternKey,
    required this.transactionIds,
    required this.direction,
    required this.currency,
    required this.cadence,
    required this.intervalDays,
    required this.amountMinimum,
    required this.amountMaximum,
    required this.expectedAmount,
    required this.confidence,
    required this.evidence,
    required this.status,
    this.qualityIssues = const [],
    this.merchantId,
    this.counterparty,
    this.categoryId,
    this.paymentSourceId,
    this.latestTransactionDate,
    this.expectedNextDate,
  });

  final String id;

  /// Stable detector identity, independent of the current transaction IDs.
  final String patternKey;
  final List<TransactionId> transactionIds;
  final TransactionDirection direction;
  final CurrencyCode currency;
  final RecurringCadence cadence;
  final int intervalDays;
  final DecimalValue amountMinimum;
  final DecimalValue amountMaximum;
  final DecimalValue expectedAmount;
  final double confidence;
  final List<String> evidence;
  final List<DataQualityIssue> qualityIssues;
  final RecurringPatternStatus status;
  final MerchantId? merchantId;
  final String? counterparty;
  final CategoryId? categoryId;
  final PaymentSourceId? paymentSourceId;

  /// Latest canonical financial date used to derive the next occurrence.
  ///
  /// It is optional for hand-authored presentation fixtures, but detector
  /// output always carries it so persisted corrections can recalculate the
  /// prediction from the corrected schedule.
  final String? latestTransactionDate;
  final String? expectedNextDate;

  RecurringPattern confirm() => _copy(status: RecurringPatternStatus.confirmed);

  RecurringPattern reject() => _copy(status: RecurringPatternStatus.rejected);

  /// Corrections remain explicit user intent and do not rewrite source
  /// transactions or turn a prediction into an actual transaction.
  RecurringPattern correct({
    RecurringCadence? cadence,
    int? intervalDays,
    DecimalValue? expectedAmount,
  }) => _copy(
    cadence: cadence,
    intervalDays: intervalDays,
    expectedAmount: expectedAmount,
    status: RecurringPatternStatus.corrected,
  );

  RecurringPattern applyDecision(RecurringPatternDecision decision) => _copy(
    cadence: RecurringCadence.values.byName(decision.cadence.name),
    intervalDays: decision.intervalDays,
    expectedAmount: decision.expectedAmount,
    status: switch (decision.status) {
      RecurringPatternDecisionStatus.confirmed =>
        RecurringPatternStatus.confirmed,
      RecurringPatternDecisionStatus.rejected =>
        RecurringPatternStatus.rejected,
      RecurringPatternDecisionStatus.corrected =>
        RecurringPatternStatus.corrected,
    },
  );

  RecurringPattern _copy({
    RecurringCadence? cadence,
    int? intervalDays,
    DecimalValue? expectedAmount,
    RecurringPatternStatus? status,
  }) => RecurringPattern(
    id: id,
    patternKey: patternKey,
    transactionIds: transactionIds,
    direction: direction,
    currency: currency,
    cadence: cadence ?? this.cadence,
    intervalDays: intervalDays ?? this.intervalDays,
    amountMinimum: amountMinimum,
    amountMaximum: amountMaximum,
    expectedAmount: expectedAmount ?? this.expectedAmount,
    confidence: confidence,
    evidence: evidence,
    qualityIssues: qualityIssues,
    status: status ?? this.status,
    merchantId: merchantId,
    counterparty: counterparty,
    categoryId: categoryId,
    paymentSourceId: paymentSourceId,
    latestTransactionDate: latestTransactionDate,
    expectedNextDate: _nextOccurrenceDate(
      latestTransactionDate: latestTransactionDate,
      cadence: cadence ?? this.cadence,
      intervalDays: intervalDays ?? this.intervalDays,
      fallback: expectedNextDate,
    ),
  );
}

String? _nextOccurrenceDate({
  required String? latestTransactionDate,
  required RecurringCadence cadence,
  required int intervalDays,
  required String? fallback,
}) {
  if (latestTransactionDate == null) return fallback;
  final latest = DateTime.parse('${latestTransactionDate}T00:00:00Z');
  final next = switch (cadence) {
    RecurringCadence.monthly => _addCalendarMonths(latest, 1),
    RecurringCadence.quarterly => _addCalendarMonths(latest, 3),
    _ => latest.add(Duration(days: intervalDays)),
  };
  return next.toIso8601String().substring(0, 10);
}

DateTime _addCalendarMonths(DateTime value, int months) {
  final targetMonth = value.month + months;
  final lastDay = DateTime.utc(value.year, targetMonth + 1, 0).day;
  final day = value.day > lastDay ? lastDay : value.day;
  return DateTime.utc(value.year, targetMonth, day);
}
