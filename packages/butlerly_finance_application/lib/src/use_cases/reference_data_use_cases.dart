import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

final class SavePaymentSource {
  const SavePaymentSource(this.repository);
  final PaymentSourceRepository repository;

  Future<ApplicationResult<PaymentSource>> call(PaymentSource value) =>
      runApplication('save payment source', () async {
        await repository.save(value);
        return value;
      });
}

final class ListPaymentSources {
  const ListPaymentSources(this.repository);
  final PaymentSourceRepository repository;

  Future<ApplicationResult<List<PaymentSource>>> call() =>
      runApplication('list payment sources', () async {
        return List.unmodifiable(await repository.listAll());
      });
}

final class ArchivePaymentSource {
  const ArchivePaymentSource(this.repository);
  final PaymentSourceRepository repository;

  Future<ApplicationResult<PaymentSource>> call(String id) =>
      runApplication('archive payment source', () async {
        final existing = await repository.findById(PaymentSourceId(id));
        if (existing == null) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'archive payment source',
          );
        }
        final archived = existing.archive();
        await repository.save(archived);
        return archived;
      });
}

final class SaveMerchant {
  const SaveMerchant(this.repository);
  final MerchantRepository repository;

  Future<ApplicationResult<Merchant>> call(Merchant value) =>
      runApplication('save merchant', () async {
        await repository.save(value);
        return value;
      });
}

final class ListMerchants {
  const ListMerchants(this.repository);
  final MerchantRepository repository;

  Future<ApplicationResult<List<Merchant>>> call() =>
      runApplication('list merchants', () async {
        return List.unmodifiable(await repository.listAll());
      });
}

final class SaveCategory {
  const SaveCategory(this.repository);
  final CategoryRepository repository;

  Future<ApplicationResult<Category>> call(Category value) =>
      runApplication('save category', () async {
        await repository.save(value);
        return value;
      });
}

final class ListCategories {
  const ListCategories(this.repository);
  final CategoryRepository repository;

  Future<ApplicationResult<List<Category>>> call() =>
      runApplication('list categories', () async {
        return List.unmodifiable(await repository.listAll());
      });
}

final class SaveTag {
  const SaveTag(this.repository);
  final TagRepository repository;

  Future<ApplicationResult<Tag>> call(Tag value) =>
      runApplication('save tag', () async {
        await repository.save(value);
        return value;
      });
}

final class ListTags {
  const ListTags(this.repository);
  final TagRepository repository;

  Future<ApplicationResult<List<Tag>>> call() =>
      runApplication('list tags', () async {
        return List.unmodifiable(await repository.listAll());
      });
}
