import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);

  test('applies enabled rules in persisted priority order', () async {
    final repository = _RuleRepository([
      TransactionRule(
        id: TransactionRuleId('rule.tag'),
        name: 'Add vehicle tag',
        priority: 2,
        descriptionContains: 'fuel',
        assignTagId: TagId('tag.vehicle'),
        createdAt: now,
        updatedAt: now,
      ),
      TransactionRule(
        id: TransactionRuleId('rule.category'),
        name: 'Assign transport category',
        priority: 1,
        descriptionContains: 'fuel',
        assignCategoryId: CategoryId('category.transport'),
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final transaction = Transaction(
      id: TransactionId('transaction.fuel'),
      timing: KnownTransactionTime(now),
      money: Money(
        amount: DecimalValue.parse('12.50'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.import,
      description: 'Fuel',
      provenance: [
        Provenance(
          id: ProvenanceId('provenance.fuel'),
          sourceType: ProvenanceSourceType.import,
          capturedAt: now,
          originalRepresentation: 'Fuel',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final result = await ApplyTransactionRules(
      repository,
      _FixedClock(now.add(const Duration(minutes: 1))),
    ).call(transaction);

    expect(result.categoryId, CategoryId('category.transport'));
    expect(result.tagIds, contains(TagId('tag.vehicle')));
  });

  test('disabled persisted rules do not change a transaction', () async {
    final rule = TransactionRule(
      id: TransactionRuleId('rule.disabled'),
      name: 'Disabled',
      enabled: false,
      descriptionContains: 'fuel',
      assignCategoryId: CategoryId('category.transport'),
      createdAt: now,
      updatedAt: now,
    );
    final transaction = _transaction();
    final result = await ApplyTransactionRules(
      _RuleRepository([rule]),
      _FixedClock(now),
    ).call(transaction);

    expect(result.categoryId, isNull);
    expect(result.tagIds, isEmpty);
  });

  test('enable and disable use the repository path', () async {
    final rule = TransactionRule(
      id: TransactionRuleId('rule.toggle'),
      name: 'Toggle',
      descriptionContains: 'fuel',
      assignCategoryId: CategoryId('category.transport'),
      createdAt: now,
      updatedAt: now,
    );
    final repository = _RuleRepository([rule]);
    final useCase = SetTransactionRuleEnabled(
      repository,
      _FixedClock(now.add(const Duration(hours: 1))),
    );

    final disabled = await useCase(rule, false);
    expect(disabled, isA<ApplicationSuccess<TransactionRule>>());
    expect((await repository.listAll()).single.enabled, isFalse);

    final enabled = await useCase((await repository.listAll()).single, true);
    expect(enabled, isA<ApplicationSuccess<TransactionRule>>());
    expect((await repository.listAll()).single.enabled, isTrue);
  });
}

Transaction _transaction() => Transaction(
  id: TransactionId('transaction.fuel'),
  timing: KnownTransactionTime(DateTime.utc(2026, 9, 1, 12)),
  money: Money(
    amount: DecimalValue.parse('12.50'),
    currency: CurrencyCode('USD'),
  ),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.import,
  description: 'Fuel',
  provenance: [
    Provenance(
      id: ProvenanceId('provenance.fuel'),
      sourceType: ProvenanceSourceType.import,
      capturedAt: DateTime.utc(2026, 9, 1, 12),
      originalRepresentation: 'Fuel',
    ),
  ],
  createdAt: DateTime.utc(2026, 9, 1, 12),
  updatedAt: DateTime.utc(2026, 9, 1, 12),
);

final class _FixedClock implements ApplicationClock {
  const _FixedClock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}

final class _RuleRepository implements TransactionRuleRepository {
  _RuleRepository(Iterable<TransactionRule> values) : _values = values.toList();

  final List<TransactionRule> _values;

  @override
  Future<TransactionRule?> findById(TransactionRuleId id) async {
    for (final value in _values) {
      if (value.id == id) return value;
    }
    return null;
  }

  @override
  Future<List<TransactionRule>> listAll() async => List.of(_values);

  @override
  Future<void> remove(TransactionRuleId id) async {
    _values.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> save(TransactionRule rule) async {
    _values.removeWhere((value) => value.id == rule.id);
    _values.add(rule);
  }
}
