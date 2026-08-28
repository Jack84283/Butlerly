import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';

final class DuplicateTransactionCheckCommand {
  const DuplicateTransactionCheckCommand({
    required this.transactionDate,
    required this.amount,
    required this.currency,
    required this.direction,
    this.paymentSourceId,
    this.merchantId,
    this.excludeTransactionId,
  });

  final String transactionDate;
  final String amount;
  final String currency;
  final TransactionDirection direction;
  final String? paymentSourceId;
  final String? merchantId;
  final String? excludeTransactionId;
}

final class DuplicateTransactionCandidate {
  const DuplicateTransactionCandidate({
    required this.transaction,
    required this.confidence,
    required this.matchingReasons,
  });

  final TransactionDto transaction;
  final double confidence;
  final List<String> matchingReasons;
}

final class DuplicateTransactionCheckResult {
  const DuplicateTransactionCheckResult(this.candidates);
  final List<DuplicateTransactionCandidate> candidates;
  bool get requiresConfirmation =>
      candidates.any((candidate) => candidate.confidence > 0.50);
}

/// Deterministic identity check for canonical transactions.
///
/// This is intentionally separate from [ReconciliationMatcher], whose fuzzy
/// score answers a different question about evidence representing one event.
final class DuplicateTransactionChecker {
  const DuplicateTransactionChecker(this.repository);
  final TransactionRepository repository;

  Future<ApplicationResult<DuplicateTransactionCheckResult>> call(
    DuplicateTransactionCheckCommand command,
  ) => runApplication('check duplicate transaction', () async {
    final amount = DecimalValue.parse(command.amount);
    final currency = command.currency.trim().toUpperCase();
    final candidates = await repository.query(
      TransactionRepositoryQuery(
        from: DateTime.parse(command.transactionDate),
        to: DateTime.parse(command.transactionDate),
        currency: currency,
        direction: command.direction,
        status: TransactionStatus.active,
      ),
    );
    final matches = candidates
        .where(
          (value) =>
              value.id.value != command.excludeTransactionId &&
              value.transactionDate == command.transactionDate &&
              value.money.amount == amount &&
              value.money.currency.value == currency,
        )
        .map(
          (value) => DuplicateTransactionCandidate(
            transaction: TransactionDto.fromDomain(value),
            confidence: 0.75,
            matchingReasons: const [
              'transaction date matches',
              'exact amount and currency match',
              'financial direction matches',
            ],
          ),
        )
        .toList(growable: false);
    return DuplicateTransactionCheckResult(List.unmodifiable(matches));
  });
}
