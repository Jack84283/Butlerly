import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/invalidation.dart';
import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'reconciliation_policy.dart';

final class ReceiptPaymentMatchCommand {
  const ReceiptPaymentMatchCommand({
    required this.amount,
    required this.currency,
    required this.transactionDate,
    required this.merchant,
    this.paymentSourceId,
    this.direction = TransactionDirection.expense,
  });

  final Money amount;
  final String? transactionDate;
  final String? merchant;
  final String currency;
  final String? paymentSourceId;
  final TransactionDirection direction;
}

final class FindReceiptPaymentMatch {
  const FindReceiptPaymentMatch(this.repository, {this.consistencyGate});

  final TransactionRepository repository;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<List<ReconciliationMatchCandidate>>> callAll(
    ReceiptPaymentMatchCommand command,
  ) => _runExclusive(
    () => runApplication('find receipt payment match', () async {
      final receipt = Transaction(
        id: TransactionId('__receipt_match__'),
        timing: const UnknownTransactionTime(
          UnknownTransactionTimeReason.unknown,
        ),
        money: command.amount,
        direction: command.direction,
        sourceType: TransactionSourceType.evidenceCapture,
        transactionDate: command.transactionDate,
        rawCounterparty: command.merchant,
        paymentSourceId: command.paymentSourceId == null
            ? null
            : PaymentSourceId(command.paymentSourceId!),
        provenance: [
          Provenance(
            id: ProvenanceId('__receipt_match_provenance__'),
            sourceType: ProvenanceSourceType.scan,
            capturedAt: DateTime.utc(1970),
            originalRepresentation: 'receipt match input',
          ),
        ],
        createdAt: DateTime.utc(1970),
        updatedAt: DateTime.utc(1970),
      );
      final scored = <ReconciliationMatchCandidate>[];
      for (final transaction in await repository.listAll()) {
        final isPayment =
            transaction.status == TransactionStatus.active &&
            (transaction.sourceType == TransactionSourceType.import ||
                transaction.sourceType == TransactionSourceType.integration ||
                transaction.sourceType == TransactionSourceType.manual);
        if (!isPayment) continue;
        final assessment = ReconciliationMatcher.assess(receipt, transaction);
        if (!assessment.incompatible &&
            assessment.score >= ReconciliationPolicy.candidateMinimumScore) {
          scored.add(
            ReconciliationMatchCandidate(
              transaction: TransactionDto.fromDomain(transaction),
              assessment: assessment,
            ),
          );
        }
      }
      scored.sort((a, b) => b.assessment.score.compareTo(a.assessment.score));
      return List.unmodifiable(scored);
    }),
  );

  Future<ApplicationResult<TransactionDto?>> call(
    ReceiptPaymentMatchCommand command,
  ) => callAll(command).then(
    (result) => switch (result) {
      ApplicationSuccess<List<ReconciliationMatchCandidate>>(:final value)
          when value.length == 1 =>
        ApplicationSuccess(value.first.transaction),
      _ => const ApplicationSuccess<TransactionDto?>(null),
    },
  );

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class ReconciliationMatchCandidate {
  const ReconciliationMatchCandidate({
    required this.transaction,
    required this.assessment,
  });
  final TransactionDto transaction;
  final ReconciliationAssessment assessment;
}

final class ReconciliationCandidateGenerator {
  const ReconciliationCandidateGenerator();

  List<ReconciliationCandidate> generate(List<Transaction> transactions) {
    final receipts = transactions.where(
      (value) =>
          value.status == TransactionStatus.active &&
          value.sourceType == TransactionSourceType.evidenceCapture,
    );
    final payments = transactions.where(
      (value) =>
          value.status == TransactionStatus.active &&
          (value.sourceType == TransactionSourceType.import ||
              value.sourceType == TransactionSourceType.integration ||
              (value.sourceType == TransactionSourceType.manual &&
                  value.paymentSourceId != null)),
    );
    final candidates = <ReconciliationCandidate>[];
    for (final receipt in receipts) {
      for (final payment in payments) {
        if (!ReconciliationPolicy.validLinkEndpoints(receipt, payment)) {
          continue;
        }
        final assessment = ReconciliationMatcher.assess(receipt, payment);
        if (assessment.incompatible) continue;
        final score = assessment.score;
        if (score < ReconciliationPolicy.candidateMinimumScore) continue;
        candidates.add(
          ReconciliationCandidate(
            id: 'candidate-${receipt.id.value}-${payment.id.value}',
            receiptTransactionId: receipt.id,
            paymentTransactionId: payment.id,
            score: score,
            reasons: assessment.reasons,
          ),
        );
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }
}

final class ReconciliationAssessment {
  const ReconciliationAssessment({
    required this.score,
    required this.reasons,
    this.incompatible = false,
    this.conflicts = const [],
  });

  final double score;
  final List<String> reasons;
  final bool incompatible;
  final List<String> conflicts;
}

/// Shared matching rules for Review and the scan-to-match shortcut.
///
/// The score is deliberately explainable. A near match is allowed to become
/// a candidate, but callers must still resolve ties instead of auto-merging.
final class ReconciliationMatcher {
  const ReconciliationMatcher._();

  static ReconciliationAssessment assess(
    Transaction receipt,
    Transaction payment,
  ) {
    if (!_directionsCanMatch(receipt.direction, payment.direction)) {
      return const ReconciliationAssessment(
        score: 0,
        reasons: ['transaction direction conflicts'],
        conflicts: ['transaction direction conflicts'],
        incompatible: true,
      );
    }

    var score = 0.0;
    final reasons = <String>[];
    final amountRatio = _amountDifferenceRatio(receipt, payment);
    final conflicts = <String>[];
    if (receipt.money.currency != payment.money.currency) {
      conflicts.add('currency conflicts');
      if (receipt.money.amount != payment.money.amount) {
        conflicts.add('amount differs');
      }
    } else if (receipt.money == payment.money) {
      score += ReconciliationPolicy.exactAmountWeight;
      reasons.add('amount and currency match');
    } else if (amountRatio != null &&
        amountRatio <= ReconciliationPolicy.maximumAmountDifferenceRatio) {
      // A receipt total can differ from the posted amount because of a tip or
      // a small bank adjustment. Keep this below an exact match so it cannot
      // silently outrank an exact same-day transaction.
      score += ReconciliationPolicy.nearbyAmountWeight;
      reasons.add('amount is within 10% (possible tip or adjustment)');
      conflicts.add('amount differs');
    } else {
      conflicts.add('amount differs');
    }

    final dateDistance = _dateDistance(
      receipt.transactionDate,
      payment.transactionDate,
    );
    if (dateDistance == 0) {
      score += ReconciliationPolicy.sameDateWeight;
      reasons.add('transaction date matches');
    } else if (dateDistance != null &&
        dateDistance <= ReconciliationPolicy.maximumDateDistanceDays) {
      score += ReconciliationPolicy.nearbyDateWeight;
      reasons.add('transaction date is within one day');
    } else if (dateDistance != null) {
      conflicts.add('transaction date differs');
    }

    final merchantScore = _merchantSimilarity(receipt, payment);
    if (merchantScore >= ReconciliationPolicy.exactMerchantSimilarity) {
      score += ReconciliationPolicy.exactMerchantWeight;
      reasons.add('merchant text matches');
    } else if (merchantScore >=
        ReconciliationPolicy.partialMerchantSimilarity) {
      score += ReconciliationPolicy.partialMerchantWeight;
      reasons.add('merchant text is similar');
    } else if (merchantScore == 0 &&
        (receipt.rawCounterparty != null || payment.rawCounterparty != null)) {
      conflicts.add('merchant text differs');
    }

    if (receipt.paymentSourceId != null &&
        receipt.paymentSourceId == payment.paymentSourceId) {
      score += ReconciliationPolicy.paymentSourceWeight;
      reasons.add('payment source matches');
    } else if (receipt.paymentSourceId != null &&
        payment.paymentSourceId != null) {
      conflicts.add('payment source differs');
    }
    return ReconciliationAssessment(
      score: score,
      reasons: List.unmodifiable(reasons),
      conflicts: List.unmodifiable(conflicts),
    );
  }

  static bool _directionsCanMatch(
    TransactionDirection receipt,
    TransactionDirection payment,
  ) => receipt == payment;

  static double? _amountDifferenceRatio(Transaction left, Transaction right) {
    if (left.money.currency != right.money.currency) return null;
    final a = double.tryParse(left.money.amount.toString());
    final b = double.tryParse(right.money.amount.toString());
    if (a == null || b == null || a == 0) return null;
    return (a - b).abs() / a.abs();
  }

  static int? _dateDistance(String? left, String? right) {
    if (left == null || right == null) return null;
    final a = DateTime.tryParse(left);
    final b = DateTime.tryParse(right);
    if (a == null || b == null) return null;
    return a.difference(b).inDays.abs();
  }

  static double _merchantSimilarity(Transaction left, Transaction right) {
    final a = _merchantTokens(left);
    final b = _merchantTokens(right);
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  static Set<String> _merchantTokens(Transaction value) =>
      (value.rawCounterparty ?? value.description ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .split(' ')
          .where((token) => token.length > 1 && !_merchantNoise.contains(token))
          .toSet();

  static const _merchantNoise = {
    'inc',
    'llc',
    'ltd',
    'co',
    'company',
    'store',
    'shop',
    'pos',
    'online',
  };
}

final class ListReconciliationCandidates {
  const ListReconciliationCandidates(
    this.repository, {
    this.transactions,
    this.consistencyGate,
  });
  final ReconciliationCandidateRepository repository;
  final TransactionRepository? transactions;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<List<ReconciliationCandidate>>> call() =>
      _runExclusive(() async {
        try {
          final values = await repository.listAll();
          final transactionRepository = transactions;
          if (transactionRepository == null) return ApplicationSuccess(values);
          final activeIds = (await transactionRepository.listAll())
              .where((value) => value.status == TransactionStatus.active)
              .map((value) => value.id)
              .toSet();
          return ApplicationSuccess(
            values
                .where(
                  (value) =>
                      activeIds.contains(value.receiptTransactionId) &&
                      activeIds.contains(value.paymentTransactionId),
                )
                .toList(growable: false),
          );
        } on Object {
          return const ApplicationFailure(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.storage,
              operation: 'list reconciliation candidates',
            ),
          );
        }
      });

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class SaveReconciliationCandidate {
  const SaveReconciliationCandidate(
    this.repository, {
    this.invalidateAnalysis,
    this.consistencyGate,
  });
  final ReconciliationCandidateRepository repository;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<void>> call(ReconciliationCandidate candidate) =>
      _runExclusive(() async {
        try {
          final invalidation = invalidateAnalysis;
          if (invalidation != null) {
            final result = await invalidation(
              AnalysisInvalidationReason.reconciliationChanged,
              DateTime.now().toUtc(),
            );
            if (result is ApplicationFailure<void>) {
              throw const RepositoryException(
                RepositoryFailureCode.unavailable,
                'invalidate analysis before saving reconciliation candidate',
              );
            }
          }
          await repository.save(candidate);
          return const ApplicationSuccess(null);
        } on Object {
          return const ApplicationFailure(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.storage,
              operation: 'save reconciliation candidate',
            ),
          );
        }
      });

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class RefreshReconciliationCandidates {
  const RefreshReconciliationCandidates(
    this.transactions,
    this.candidates, {
    this.invalidateAnalysis,
    this.consistencyGate,
  });

  final TransactionRepository transactions;
  final ReconciliationCandidateRepository candidates;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<List<ReconciliationCandidate>>>
  call() => _runExclusive(() async {
    try {
      final invalidation = invalidateAnalysis;
      if (invalidation != null) {
        final result = await invalidation(
          AnalysisInvalidationReason.reconciliationChanged,
          DateTime.now().toUtc(),
        );
        if (result is ApplicationFailure<void>) {
          throw const RepositoryException(
            RepositoryFailureCode.unavailable,
            'invalidate analysis before refreshing reconciliation candidates',
          );
        }
      }
      final generated = const ReconciliationCandidateGenerator().generate(
        await transactions.listAll(),
      );
      final generatedIds = generated.map((value) => value.id).toSet();
      final now = DateTime.now().toUtc();
      for (final existing in await candidates.listAll()) {
        if (existing.status != ReconciliationCandidateStatus.proposed ||
            generatedIds.contains(existing.id)) {
          continue;
        }
        await candidates.save(existing.reject());
        final receipt = await transactions.findById(
          existing.receiptTransactionId,
        );
        final issue = receipt?.reviewIssues
            .where(
              (value) =>
                  value.id.value == 'reconciliation-${existing.id}' &&
                  value.status == ReviewIssueStatus.active,
            )
            .firstOrNull;
        if (receipt != null && issue != null) {
          await transactions.save(receipt.resolveReviewIssue(issue.id, now));
        }
      }
      for (final candidate in generated) {
        // A refresh must not resurrect a pair the user already confirmed or
        // rejected. Those decisions are durable review state.
        final existing = await candidates.findById(candidate.id);
        if (existing == null ||
            existing.status == ReconciliationCandidateStatus.proposed) {
          await candidates.save(candidate);
        }
        if (candidate.status == ReconciliationCandidateStatus.proposed) {
          final transaction = await transactions.findById(
            candidate.receiptTransactionId,
          );
          if (transaction != null &&
              transaction.status == TransactionStatus.active) {
            final issueId = ReviewIssueId('reconciliation-${candidate.id}');
            final issue = transaction.reviewIssues
                .where((value) => value.id == issueId)
                .firstOrNull;
            final updated = issue == null
                ? transaction.addReviewIssue(
                    ReviewIssue(
                      id: issueId,
                      transactionId: transaction.id,
                      reason: ReviewIssueReason.uncertain,
                      detail:
                          'Possible transaction match: ${candidate.paymentTransactionId.value}',
                      createdAt: now,
                    ),
                    now,
                  )
                : transaction;
            if (!identical(updated, transaction)) {
              await transactions.save(updated);
            }
          }
        }
      }
      return ApplicationSuccess(generated);
    } on Object {
      return const ApplicationFailure(
        ApplicationFailureDetail(
          code: ApplicationFailureCode.storage,
          operation: 'refresh reconciliation candidates',
        ),
      );
    }
  });

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class SaveReconciliationLink {
  const SaveReconciliationLink(
    this.repository, {
    required this.candidates,
    this.invalidateAnalysis,
    this.consistencyGate,
  });

  final ReconciliationLinkRepository repository;
  final ReconciliationCandidateRepository candidates;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<void>> call(ReconciliationLink link) =>
      _runExclusive(() async {
        try {
          final candidate = await candidates.findById(link.candidateId);
          if (candidate == null) {
            throw const RepositoryException(
              RepositoryFailureCode.notFound,
              'save reconciliation link candidate',
            );
          }
          if (candidate.status != ReconciliationCandidateStatus.confirmed) {
            throw const DomainValidationException(
              code: DomainErrorCode.invalidState,
              field: 'candidateId',
              message:
                  'Only confirmed reconciliation candidates can be linked.',
            );
          }
          if (candidate.receiptTransactionId != link.receiptTransactionId ||
              candidate.paymentTransactionId != link.paymentTransactionId) {
            throw const DomainValidationException(
              code: DomainErrorCode.relationshipMismatch,
              field: 'candidateId',
              message: 'The reconciliation link must match its candidate.',
            );
          }
          final existing = await repository.listAll();
          for (final current in existing) {
            final isSame =
                current.id == link.id &&
                current.candidateId == link.candidateId &&
                current.receiptTransactionId == link.receiptTransactionId &&
                current.paymentTransactionId == link.paymentTransactionId;
            if (isSame) return const ApplicationSuccess(null);
            if (current.id == link.id ||
                current.candidateId == link.candidateId ||
                current.receiptTransactionId == link.receiptTransactionId ||
                current.paymentTransactionId == link.paymentTransactionId) {
              throw const RepositoryException(
                RepositoryFailureCode.constraint,
                'conflicting reconciliation link',
              );
            }
          }
          final invalidation = invalidateAnalysis;
          if (invalidation != null) {
            final result = await invalidation(
              AnalysisInvalidationReason.reconciliationChanged,
              DateTime.now().toUtc(),
            );
            if (result is ApplicationFailure<void>) {
              throw const RepositoryException(
                RepositoryFailureCode.unavailable,
                'invalidate analysis after reconciliation link',
              );
            }
          }
          await repository.save(link);
          return const ApplicationSuccess(null);
        } on Object {
          return const ApplicationFailure(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.storage,
              operation: 'save reconciliation link',
            ),
          );
        }
      });

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class ConfirmReconciliation {
  const ConfirmReconciliation(
    this.repository, {
    this.transactions,
    this.invalidateAnalysis,
    this.consistencyGate,
  });

  final ReconciliationWorkflowRepository repository;
  final TransactionRepository? transactions;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<void>> call(
    ReconciliationCandidate candidate,
  ) => _runExclusive(
    () => runApplication('confirm reconciliation', () async {
      if (candidate.status != ReconciliationCandidateStatus.proposed) {
        throw const DomainValidationException(
          code: DomainErrorCode.invalidState,
          field: 'status',
          message: 'Only proposed reconciliation candidates can be confirmed.',
        );
      }
      final transactionRepository = transactions;
      if (transactionRepository != null) {
        final receipt = await transactionRepository.findById(
          candidate.receiptTransactionId,
        );
        final payment = await transactionRepository.findById(
          candidate.paymentTransactionId,
        );
        if (receipt == null || payment == null) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'confirm reconciliation endpoints',
          );
        }
        if (!ReconciliationPolicy.validLinkEndpoints(receipt, payment)) {
          throw const DomainValidationException(
            code: DomainErrorCode.relationshipMismatch,
            field: 'candidateId',
            message: 'The reconciliation endpoints are invalid.',
          );
        }
      }
      final invalidation = invalidateAnalysis;
      if (invalidation != null) {
        final result = await invalidation(
          AnalysisInvalidationReason.reconciliationChanged,
          DateTime.now().toUtc(),
        );
        if (result is ApplicationFailure<void>) {
          throw const RepositoryException(
            RepositoryFailureCode.unavailable,
            'invalidate analysis before reconciliation confirmation',
          );
        }
      }
      await repository.confirm(
        candidate,
        ReconciliationLink(
          id: 'link-${candidate.id}',
          candidateId: candidate.id,
          receiptTransactionId: candidate.receiptTransactionId,
          paymentTransactionId: candidate.paymentTransactionId,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      if (transactions != null) await _resolveIssue(transactions!, candidate);
    }),
  );

  static Future<void> _resolveIssue(
    TransactionRepository transactions,
    ReconciliationCandidate candidate,
  ) async {
    final transaction = await transactions.findById(
      candidate.receiptTransactionId,
    );
    final issue = transaction?.reviewIssues
        .where(
          (value) =>
              value.id.value == 'reconciliation-${candidate.id}' &&
              value.status == ReviewIssueStatus.active,
        )
        .firstOrNull;
    if (transaction != null && issue != null) {
      await transactions.save(
        transaction.resolveReviewIssue(issue.id, DateTime.now().toUtc()),
      );
    }
  }

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class RejectReconciliation {
  const RejectReconciliation(
    this.repository, {
    this.transactions,
    this.invalidateAnalysis,
    this.consistencyGate,
  });

  final ReconciliationWorkflowRepository repository;
  final TransactionRepository? transactions;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<void>> call(ReconciliationCandidate candidate) =>
      _runExclusive(
        () => runApplication('reject reconciliation', () async {
          if (candidate.status != ReconciliationCandidateStatus.proposed) {
            throw const DomainValidationException(
              code: DomainErrorCode.invalidState,
              field: 'status',
              message:
                  'Only proposed reconciliation candidates can be rejected.',
            );
          }
          final invalidation = invalidateAnalysis;
          if (invalidation != null) {
            final result = await invalidation(
              AnalysisInvalidationReason.reconciliationChanged,
              DateTime.now().toUtc(),
            );
            if (result is ApplicationFailure<void>) {
              throw const RepositoryException(
                RepositoryFailureCode.unavailable,
                'invalidate analysis before reconciliation rejection',
              );
            }
          }
          await repository.reject(candidate);
          if (transactions != null) {
            await ConfirmReconciliation._resolveIssue(transactions!, candidate);
          }
        }),
      );

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

final class ListReconciliationLinks {
  const ListReconciliationLinks(this.repository, {this.consistencyGate});

  final ReconciliationLinkRepository repository;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<List<ReconciliationLink>>> call() =>
      _runExclusive(() async {
        try {
          return ApplicationSuccess(await repository.listAll());
        } on Object {
          return const ApplicationFailure(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.storage,
              operation: 'list reconciliation links',
            ),
          );
        }
      });

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}
