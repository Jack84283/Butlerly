/// A user-approved monthly spending limit. A null scopeId is reserved for
/// the single overall-spending budget per currency.
final class Budget {
  const Budget({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.currency,
    required this.amount,
  });

  final String id;
  final String scope;
  final String? scopeId;
  final String currency;

  /// An exact decimal string; calculations must never use binary floating
  /// point as the stored representation.
  final String amount;
}

abstract interface class BudgetRepository {
  Future<List<Budget>> list();
  Future<void> save(Budget budget);
  Future<void> remove(String id);
}
