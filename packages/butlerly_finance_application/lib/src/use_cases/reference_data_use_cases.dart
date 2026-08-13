import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

final class InitialMasterData {
  const InitialMasterData({
    this.merchants = const [],
    this.categories = const [],
    this.tags = const [],
  });

  final List<Merchant> merchants;
  final List<Category> categories;
  final List<Tag> tags;
}

final class SeedInitialMasterData {
  const SeedInitialMasterData(this.merchants, this.categories, this.tags);

  final MerchantRepository merchants;
  final CategoryRepository categories;
  final TagRepository tags;

  Future<ApplicationResult<void>> call(InitialMasterData data) =>
      runApplication('seed initial master data', () async {
        for (final merchant in data.merchants) {
          if (await merchants.findById(merchant.id) == null) {
            await merchants.save(merchant);
          }
        }
        for (final category in data.categories) {
          if (await categories.findById(category.id) == null) {
            await categories.save(category);
          }
        }
        for (final tag in data.tags) {
          if (await tags.findById(tag.id) == null) {
            await tags.save(tag);
          }
        }
      });
}

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

final class LoadUserPreference {
  const LoadUserPreference(this.repository);
  final UserPreferenceRepository repository;

  Future<ApplicationResult<UserPreference?>> call() =>
      runApplication('load user preferences', repository.load);
}

final class SaveUserPreference {
  const SaveUserPreference(this.repository);
  final UserPreferenceRepository repository;

  Future<ApplicationResult<UserPreference>> call(UserPreference value) =>
      runApplication('save user preferences', () async {
        await repository.save(value);
        return value;
      });
}

final class StoreAndAttachEvidence {
  const StoreAndAttachEvidence(this.repository);
  final EvidenceRepository repository;

  Future<ApplicationResult<EvidenceItem>> call(
    EvidenceItem evidence,
    AttachmentLink link,
  ) => runApplication('attach evidence', () async {
    if (link.evidenceId != evidence.id) {
      throw const DomainValidationException(
        code: DomainErrorCode.relationshipMismatch,
        field: 'evidenceId',
        message: 'The attachment must reference the selected evidence.',
      );
    }
    await repository.save(evidence);
    await repository.link(link);
    return evidence;
  });
}

final class RemoveEvidence {
  const RemoveEvidence(this.repository);
  final EvidenceRepository repository;

  Future<ApplicationResult<void>> call(String id) => runApplication(
    'remove evidence',
    () => repository.remove(EvidenceId(id)),
  );
}
