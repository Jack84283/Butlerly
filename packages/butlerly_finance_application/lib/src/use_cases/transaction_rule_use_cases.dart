import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class ListTransactionRules {
  const ListTransactionRules(this.repository);
  final TransactionRuleRepository repository;

  Future<ApplicationResult<List<TransactionRule>>> call() =>
      runApplication('list transaction rules', repository.listAll);
}

final class SaveTransactionRule {
  const SaveTransactionRule(this.repository);
  final TransactionRuleRepository repository;

  Future<ApplicationResult<TransactionRule>> call(TransactionRule rule) =>
      runApplication('save transaction rule', () async {
        await repository.save(rule);
        return rule;
      });
}

final class SetTransactionRuleEnabled {
  const SetTransactionRuleEnabled(this.repository, this.clock);
  final TransactionRuleRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionRule>> call(
    TransactionRule rule,
    bool enabled,
  ) => runApplication('set transaction rule enabled', () async {
    final updated = enabled
        ? rule.enable(clock.now())
        : rule.disable(clock.now());
    await repository.save(updated);
    return updated;
  });
}

final class DeleteTransactionRule {
  const DeleteTransactionRule(this.repository);
  final TransactionRuleRepository repository;

  Future<ApplicationResult<void>> call(String id) => runApplication(
    'delete transaction rule',
    () => repository.remove(TransactionRuleId(id)),
  );
}

final class ApplyTransactionRules {
  const ApplyTransactionRules(this.repository, this.clock);
  final TransactionRuleRepository repository;
  final ApplicationClock clock;

  Future<Transaction> call(Transaction transaction) async {
    final rules = await repository.listAll()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    var result = transaction;
    final at = clock.now();
    for (final rule in rules) {
      if (rule.matches(result)) result = rule.apply(result, at);
    }
    return result;
  }
}
