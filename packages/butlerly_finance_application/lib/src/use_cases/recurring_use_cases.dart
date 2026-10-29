import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/canonical_transactions.dart';
import '../analysis/period_resolver.dart';
import '../dto/recurring_pattern.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';

/// Finds recurring candidates locally from canonical historical transactions.
/// No network or model/provider is involved, and candidates are never written
/// as financial transactions.
final class DetectRecurringPatterns {
  const DetectRecurringPatterns(
    this.transactions, {
    required this.preferences,
    this.links,
    this.candidates,
    this.duplicateGroups,
    this.decisions,
  });

  final TransactionRepository transactions;
  final UserPreferenceRepository preferences;
  final ReconciliationLinkRepository? links;
  final ReconciliationCandidateRepository? candidates;
  final DuplicateCandidateGroupRepository? duplicateGroups;
  final RecurringPatternDecisionRepository? decisions;

  Future<ApplicationResult<List<RecurringPattern>>> call({
    String? timeZoneId,
  }) => runApplication('detect recurring patterns', () async {
    final resolvedTimeZone =
        timeZoneId ?? (await configuredFinancialTimeZone(preferences)).id;
    final canonical = selectCanonicalTransactions(
      source: await transactions.listAll(),
      links: links == null ? const [] : await links!.listAll(),
      reconciliationCandidates: candidates == null
          ? null
          : await candidates!.listAll(),
      duplicateGroups: duplicateGroups == null
          ? const []
          : await duplicateGroups!.list(),
    );
    final detected = RecurringPatternDetector(
      timeZoneId: resolvedTimeZone,
    ).detect(canonical.transactions, qualityIssues: canonical.qualityIssues);
    if (decisions == null || detected.isEmpty) return detected;
    final saved = await decisions!.list();
    final byKey = {for (final decision in saved) decision.patternKey: decision};
    final resolved = <RecurringPattern>[];
    for (final pattern in detected) {
      final decision = byKey[pattern.patternKey];
      resolved.add(
        decision == null ? pattern : pattern.applyDecision(decision),
      );
    }
    return List.unmodifiable(resolved);
  });
}

/// Persists explicit user intent without changing source transactions.
final class SaveRecurringPatternDecision {
  const SaveRecurringPatternDecision(this.repository, this.clock);

  final RecurringPatternDecisionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<RecurringPattern>> confirm(
    RecurringPattern pattern,
  ) => _save(pattern, RecurringPatternDecisionStatus.confirmed);

  Future<ApplicationResult<RecurringPattern>> reject(
    RecurringPattern pattern,
  ) => _save(pattern, RecurringPatternDecisionStatus.rejected);

  Future<ApplicationResult<RecurringPattern>> correct(
    RecurringPattern pattern, {
    RecurringCadence? cadence,
    int? intervalDays,
    DecimalValue? expectedAmount,
  }) => _save(
    pattern.correct(
      cadence: cadence,
      intervalDays: intervalDays,
      expectedAmount: expectedAmount,
    ),
    RecurringPatternDecisionStatus.corrected,
  );

  Future<ApplicationResult<RecurringPattern>> _save(
    RecurringPattern pattern,
    RecurringPatternDecisionStatus status,
  ) => runApplication('save recurring pattern decision', () async {
    final existing = await repository.findByPatternKey(pattern.patternKey);
    final now = clock.now();
    await repository.save(
      RecurringPatternDecision(
        id: existing?.id ?? 'recurring-decision:${pattern.patternKey}',
        patternKey: pattern.patternKey,
        status: status,
        cadence: RecurringPatternDecisionCadence.values.byName(
          pattern.cadence.name,
        ),
        intervalDays: pattern.intervalDays,
        expectedAmount: pattern.expectedAmount,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    return pattern;
  });
}

/// Pure deterministic recognizer used by the application use case and tests.
final class RecurringPatternDetector {
  const RecurringPatternDetector({required this.timeZoneId});

  final String timeZoneId;

  List<RecurringPattern> detect(
    List<Transaction> source, {
    List<DataQualityIssue> qualityIssues = const [],
  }) {
    final groups = <String, List<Transaction>>{};
    for (final transaction in source) {
      if (transaction.status != TransactionStatus.active &&
          transaction.status != TransactionStatus.archived) {
        continue;
      }
      if (transaction.direction == TransactionDirection.transfer ||
          transaction.direction == TransactionDirection.adjustment) {
        continue;
      }
      final date = transactionFinancialDate(transaction, timeZoneId);
      final identity = _identity(transaction);
      if (date == null || identity == null) continue;
      groups.putIfAbsent(identity, () => []).add(transaction);
    }

    final patterns = <RecurringPattern>[];
    for (final entry in groups.entries) {
      final identity = entry.key;
      final values = entry.value;
      values.sort((left, right) {
        final leftDate = transactionFinancialDate(left, timeZoneId)!;
        final rightDate = transactionFinancialDate(right, timeZoneId)!;
        final dateOrder = leftDate.compareTo(rightDate);
        return dateOrder == 0
            ? left.id.value.compareTo(right.id.value)
            : dateOrder;
      });
      if (values.length < 3) continue;
      final dates = values
          .map((value) => transactionFinancialDate(value, timeZoneId)!)
          .toList(growable: false);
      final intervals = <int>[
        for (var index = 1; index < dates.length; index++)
          dates[index].difference(dates[index - 1]).inDays,
      ];
      if (intervals.any((interval) => interval <= 0)) continue;
      final averageInterval =
          intervals.reduce((a, b) => a + b) / intervals.length;
      final cadence = _cadence(averageInterval);
      final intervalDeviation =
          intervals.fold<double>(
            0,
            (total, value) => total + (value - averageInterval).abs(),
          ) /
          intervals.length;
      final amounts = values.map((value) => value.money.amount).toList();
      amounts.sort();
      final minimum = amounts.first;
      final maximum = amounts.last;
      final amountStable =
          maximum
              .subtract(minimum)
              .compareTo(maximum.abs().multiply(DecimalValue.parse('0.10'))) <=
          0;
      final cadenceScore = cadence == RecurringCadence.irregular
          ? 0.2
          : (1 -
                    (intervalDeviation /
                        (averageInterval == 0 ? 1 : averageInterval)))
                .clamp(0.0, 1.0);
      final amountScore = amountStable ? 1.0 : 0.55;
      final confidence = (0.5 * cadenceScore + 0.5 * amountScore).clamp(
        0.0,
        1.0,
      );
      // FIN-084–089 require a reviewable candidate before any optional
      // prediction. A prediction additionally needs three historical records,
      // one recognized cadence with every interval inside that cadence's
      // documented calendar-jitter tolerance, and stable amounts. These
      // evidence gates are deliberately explicit instead of an arbitrary
      // confidence cutoff: confidence remains an explanation of the evidence,
      // while weak or irregular evidence has no forecast date.
      final cadenceConsistent =
          cadence != RecurringCadence.irregular &&
          intervals.every(
            (interval) =>
                (interval - _nominalInterval(cadence)).abs() <=
                _cadenceTolerance(cadence),
          );
      final predictionEligible = cadenceConsistent && amountStable;
      final lastDate = dates.last;
      final intervalDays = averageInterval.round().clamp(1, 366);
      final expected = predictionEligible
          ? switch (cadence) {
              RecurringCadence.monthly => _addCalendarMonths(lastDate, 1),
              RecurringCadence.quarterly => _addCalendarMonths(lastDate, 3),
              _ => lastDate.add(Duration(days: intervalDays)),
            }
          : null;
      final first = values.first;
      final patternTransactionIds = values.map((value) => value.id).toSet();
      patterns.add(
        RecurringPattern(
          id: 'recurring-${values.map((value) => value.id.value).join('-')}',
          patternKey: identity,
          transactionIds: values
              .map((value) => value.id)
              .toList(growable: false),
          direction: first.direction,
          currency: first.money.currency,
          cadence: cadence,
          intervalDays: intervalDays,
          amountMinimum: minimum,
          amountMaximum: maximum,
          expectedAmount: DecimalValue.sum(amounts).divideBy(amounts.length),
          confidence: confidence,
          evidence: [
            '${values.length} canonical transactions',
            'intervals: ${intervals.join(', ')} days',
            if (amountStable)
              'amounts remain within 10 percent'
            else
              'amount range varies beyond 10 percent',
            if (!predictionEligible)
              cadence == RecurringCadence.irregular
                  ? 'next occurrence unavailable: cadence is irregular'
                  : !cadenceConsistent
                  ? 'next occurrence unavailable: intervals are inconsistent'
                  : 'next occurrence unavailable: amounts are inconsistent',
          ],
          status: RecurringPatternStatus.detected,
          qualityIssues: qualityIssues
              .where(
                (issue) =>
                    issue.transactionId == null ||
                    patternTransactionIds.contains(issue.transactionId),
              )
              .toList(growable: false),
          merchantId: first.merchantId,
          counterparty: first.rawCounterparty ?? first.description,
          categoryId: first.categoryId,
          paymentSourceId: first.paymentSourceId,
          latestTransactionDate: _date(lastDate),
          expectedNextDate: expected == null ? null : _date(expected),
        ),
      );
    }
    patterns.sort((left, right) => left.id.compareTo(right.id));
    return List.unmodifiable(patterns);
  }

  String? _identity(Transaction value) {
    final merchant = value.merchantId?.value;
    final counterparty = (value.rawCounterparty ?? value.description)
        ?.trim()
        .toLowerCase();
    final party =
        merchant ??
        (counterparty == null || counterparty.isEmpty ? null : counterparty);
    if (party == null) return null;
    return [
      party,
      value.direction.name,
      value.money.currency.value,
      value.categoryId?.value ?? '',
      value.paymentSourceId?.value ?? '',
    ].join('|');
  }

  RecurringCadence _cadence(double averageInterval) {
    if ((averageInterval - 7).abs() <= 2) return RecurringCadence.weekly;
    if ((averageInterval - 14).abs() <= 3) return RecurringCadence.biweekly;
    if ((averageInterval - 30).abs() <= 4) return RecurringCadence.monthly;
    if ((averageInterval - 91).abs() <= 8) return RecurringCadence.quarterly;
    return RecurringCadence.irregular;
  }

  int _nominalInterval(RecurringCadence cadence) => switch (cadence) {
    RecurringCadence.weekly => 7,
    RecurringCadence.biweekly => 14,
    RecurringCadence.monthly => 30,
    RecurringCadence.quarterly => 91,
    RecurringCadence.irregular => 0,
  };

  int _cadenceTolerance(RecurringCadence cadence) => switch (cadence) {
    // These match the existing cadence recognition windows and allow normal
    // calendar placement jitter without turning irregular activity into a
    // prediction.
    RecurringCadence.weekly => 2,
    RecurringCadence.biweekly => 3,
    RecurringCadence.monthly => 4,
    RecurringCadence.quarterly => 8,
    RecurringCadence.irregular => 0,
  };

  DateTime _addCalendarMonths(DateTime value, int months) {
    final targetMonth = value.month + months;
    final lastDay = DateTime.utc(value.year, targetMonth + 1, 0).day;
    return DateTime.utc(value.year, targetMonth, value.day.clamp(1, lastDay));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
