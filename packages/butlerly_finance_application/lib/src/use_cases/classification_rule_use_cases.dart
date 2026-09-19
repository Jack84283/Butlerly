import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

final class ListClassificationRules {
  const ListClassificationRules(this.repository);
  final ClassificationRuleRepository repository;

  Future<ApplicationResult<List<ClassificationRule>>> call() =>
      runApplication('list classification rules', () async {
        final values = await repository.listAll();
        return List.unmodifiable(values);
      });
}

final class SaveClassificationRule {
  const SaveClassificationRule(
    this.repository,
    this.merchants,
    this.categories,
    this.tags,
  );

  final ClassificationRuleRepository repository;
  final MerchantRepository merchants;
  final CategoryRepository categories;
  final TagRepository tags;

  Future<ApplicationResult<ClassificationRule>> call(
    ClassificationRule rule,
  ) => runApplication('save classification rule', () async {
    if (rule.merchantId != null &&
        await merchants.findById(rule.merchantId!) == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'save classification rule merchant',
      );
    }
    if (rule.categoryId != null &&
        await categories.findById(rule.categoryId!) == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'save classification rule category',
      );
    }
    if (rule.subcategoryId != null) {
      final subcategory = await categories.findById(rule.subcategoryId!);
      if (subcategory == null || subcategory.parentId != rule.categoryId) {
        throw const RepositoryException(
          RepositoryFailureCode.constraint,
          'save classification rule subcategory',
        );
      }
    }
    for (final tagId in rule.tagIds) {
      if (await tags.findById(tagId) == null) {
        throw const RepositoryException(
          RepositoryFailureCode.notFound,
          'save classification rule tag',
        );
      }
    }
    await repository.save(rule);
    return rule;
  });
}

final class SetClassificationRuleEnabled {
  const SetClassificationRuleEnabled(this.repository, this.clock);
  final ClassificationRuleRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<ClassificationRule>> call(
    ClassificationRuleId id,
    bool enabled,
  ) => runApplication('set classification rule enabled', () async {
    final current = await repository.findById(id);
    if (current == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'set classification rule enabled',
      );
    }
    final updated = current.copyWith(enabled: enabled, updatedAt: clock.now());
    await repository.save(updated);
    return updated;
  });
}

final class DeleteClassificationRule {
  const DeleteClassificationRule(this.repository);
  final ClassificationRuleRepository repository;

  Future<ApplicationResult<void>> call(ClassificationRuleId id) =>
      runApplication(
        'delete classification rule',
        () => repository.remove(id),
      );
}
