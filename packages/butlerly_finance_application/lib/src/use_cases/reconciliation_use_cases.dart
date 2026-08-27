import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import '../dto/transaction_dto.dart';

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
  const FindReceiptPaymentMatch(this.repository);

  final TransactionRepository repository;

  Future<ApplicationResult<List<ReconciliationMatchCandidate>>> callAll(
    ReceiptPaymentMatchCommand command,
  ) => runApplication('find receipt payment match', () async {
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
      if (!assessment.incompatible && assessment.score >= 0.45) {
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
  });

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
      (value) => value.sourceType == TransactionSourceType.evidenceCapture,
    );
    final payments = transactions.where(
      (value) =>
          value.sourceType == TransactionSourceType.import ||
          value.sourceType == TransactionSourceType.integration ||
          (value.sourceType == TransactionSourceType.manual &&
              value.paymentSourceId != null),
    );
    final candidates = <ReconciliationCandidate>[];
    for (final receipt in receipts) {
      for (final payment in payments) {
        final assessment = ReconciliationMatcher.assess(receipt, payment);
        if (assessment.incompatible) continue;
        final score = assessment.score;
        if (score < 0.45) continue;
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
    } else if (receipt.money == payment.money) {
      score += 0.55;
      reasons.add('amount and currency match');
    } else if (amountRatio != null && amountRatio <= 0.10) {
      // A receipt total can differ from the posted amount because of a tip or
      // a small bank adjustment. Keep this below an exact match so it cannot
      // silently outrank an exact same-day transaction.
      score += 0.35;
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
      score += 0.25;
      reasons.add('transaction date matches');
    } else if (dateDistance != null && dateDistance <= 1) {
      score += 0.15;
      reasons.add('transaction date is within one day');
    } else if (dateDistance != null) {
      conflicts.add('transaction date differs');
    }

    final merchantScore = _merchantSimilarity(receipt, payment);
    if (merchantScore >= 0.99) {
      score += 0.15;
      reasons.add('merchant text matches');
    } else if (merchantScore >= 0.50) {
      score += 0.10;
      reasons.add('merchant text is similar');
    } else if (merchantScore == 0 &&
        (receipt.rawCounterparty != null || payment.rawCounterparty != null)) {
      conflicts.add('merchant text differs');
    }

    if (receipt.paymentSourceId != null &&
        receipt.paymentSourceId == payment.paymentSourceId) {
      score += 0.05;
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
  const ListReconciliationCandidates(this.repository);
  final ReconciliationCandidateRepository repository;

  Future<ApplicationResult<List<ReconciliationCandidate>>> call() async {
    try {
      return ApplicationSuccess(await repository.listAll());
    } on Object {
      return const ApplicationFailure(
        ApplicationFailureDetail(
          code: ApplicationFailureCode.storage,
          operation: 'list reconciliation candidates',
        ),
      );
    }
  }
}

final class SaveReconciliationCandidate {
  const SaveReconciliationCandidate(this.repository);
  final ReconciliationCandidateRepository repository;

  Future<ApplicationResult<void>> call(
    ReconciliationCandidate candidate,
  ) async {
    try {
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
  }
}

final class RefreshReconciliationCandidates {
  const RefreshReconciliationCandidates(this.transactions, this.candidates);

  final TransactionRepository transactions;
  final ReconciliationCandidateRepository candidates;

  Future<ApplicationResult<List<ReconciliationCandidate>>> call() async {
    try {
      final generated = const ReconciliationCandidateGenerator().generate(
        await transactions.listAll(),
      );
      for (final candidate in generated) {
        // A refresh must not resurrect a pair the user already confirmed or
        // rejected. Those decisions are durable review state.
        final existing = await candidates.findById(candidate.id);
        if (existing == null ||
            existing.status == ReconciliationCandidateStatus.proposed) {
          await candidates.save(candidate);
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
  }
}

final class SaveReconciliationLink {
  const SaveReconciliationLink(this.repository);

  final ReconciliationLinkRepository repository;

  Future<ApplicationResult<void>> call(ReconciliationLink link) async {
    try {
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
  }
}

final class ConfirmReconciliation {
  const ConfirmReconciliation(this.repository);

  final ReconciliationWorkflowRepository repository;

  Future<ApplicationResult<void>> call(ReconciliationCandidate candidate) =>
      runApplication('confirm reconciliation', () async {
        if (candidate.status != ReconciliationCandidateStatus.proposed) {
          throw const DomainValidationException(
            code: DomainErrorCode.invalidState,
            field: 'status',
            message:
                'Only proposed reconciliation candidates can be confirmed.',
          );
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
      });
}

final class RejectReconciliation {
  const RejectReconciliation(this.repository);

  final ReconciliationWorkflowRepository repository;

  Future<ApplicationResult<void>> call(ReconciliationCandidate candidate) =>
      runApplication('reject reconciliation', () async {
        if (candidate.status != ReconciliationCandidateStatus.proposed) {
          throw const DomainValidationException(
            code: DomainErrorCode.invalidState,
            field: 'status',
            message: 'Only proposed reconciliation candidates can be rejected.',
          );
        }
        await repository.reject(candidate);
      });
}

final class ListReconciliationLinks {
  const ListReconciliationLinks(this.repository);

  final ReconciliationLinkRepository repository;

  Future<ApplicationResult<List<ReconciliationLink>>> call() async {
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
  }
}
