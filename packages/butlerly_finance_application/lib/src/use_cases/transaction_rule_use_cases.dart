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
  const SaveTransactionRule(this.repository, this.categories);
  final TransactionRuleRepository repository;
  final CategoryRepository categories;

  Future<ApplicationResult<TransactionRule>> call(TransactionRule rule) =>
      runApplication('save transaction rule', () async {
        final values = await categories.listAll();
        final byId = {
          for (final category in values) category.id.value: category,
        };
        final conditionCategory = rule.categoryId == null
            ? null
            : byId[rule.categoryId!.value];
        if (conditionCategory?.parentId != null) {
          invalid(
            code: DomainErrorCode.relationshipMismatch,
            field: 'categoryId',
            message: 'A rule condition must reference a root category.',
          );
        }
        final assignedCategory = rule.assignCategoryId == null
            ? null
            : byId[rule.assignCategoryId!.value];
        if (assignedCategory?.parentId != null) {
          invalid(
            code: DomainErrorCode.relationshipMismatch,
            field: 'assignCategoryId',
            message: 'A rule action must assign a root category.',
          );
        }
        final assignedSubcategory = rule.assignSubcategoryId == null
            ? null
            : byId[rule.assignSubcategoryId!.value];
        if (assignedSubcategory != null &&
            (assignedSubcategory.parentId == null ||
                assignedSubcategory.parentId != rule.assignCategoryId)) {
          invalid(
            code: DomainErrorCode.relationshipMismatch,
            field: 'assignSubcategoryId',
            message: 'A rule subcategory must belong to its assigned category.',
          );
        }
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
