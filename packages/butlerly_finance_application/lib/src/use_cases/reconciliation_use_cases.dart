import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

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
        final score = _score(receipt, payment);
        if (score < 0.45) continue;
        final reasons = <String>[];
        if (receipt.money == payment.money) {
          reasons.add('amount and currency match');
        }
        if (receipt.transactionDate != null &&
            receipt.transactionDate == payment.transactionDate) {
          reasons.add('transaction date matches');
        }
        if (_merchantText(receipt) == _merchantText(payment)) {
          reasons.add('merchant text matches');
        }
        if (receipt.paymentSourceId != null &&
            receipt.paymentSourceId == payment.paymentSourceId) {
          reasons.add('payment source matches');
        }
        candidates.add(
          ReconciliationCandidate(
            id: 'candidate-${receipt.id.value}-${payment.id.value}',
            receiptTransactionId: receipt.id,
            paymentTransactionId: payment.id,
            score: score,
            reasons: reasons,
          ),
        );
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  double _score(Transaction receipt, Transaction payment) {
    var score = 0.0;
    if (receipt.money == payment.money) {
      score += 0.55;
    }
    if (receipt.transactionDate != null &&
        receipt.transactionDate == payment.transactionDate) {
      score += 0.25;
    }
    if (_merchantText(receipt) == _merchantText(payment) &&
        _merchantText(receipt).isNotEmpty) {
      score += 0.15;
    }
    if (receipt.paymentSourceId != null &&
        receipt.paymentSourceId == payment.paymentSourceId) {
      score += 0.05;
    }
    return score;
  }

  String _merchantText(Transaction value) =>
      (value.rawCounterparty ?? value.description ?? '').trim().toLowerCase();
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
