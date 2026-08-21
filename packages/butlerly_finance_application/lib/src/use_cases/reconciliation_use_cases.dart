import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

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
