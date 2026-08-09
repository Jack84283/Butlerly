sealed class TransactionTiming {
  const TransactionTiming();
}

final class KnownTransactionTime extends TransactionTiming {
  KnownTransactionTime(DateTime occurredAt) : occurredAt = occurredAt.toUtc();

  final DateTime occurredAt;
}

enum UnknownTransactionTimeReason { pending, unknown }

final class UnknownTransactionTime extends TransactionTiming {
  const UnknownTransactionTime(this.reason);

  final UnknownTransactionTimeReason reason;
}
