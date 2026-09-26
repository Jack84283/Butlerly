import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class ListMerchantAliases {
  const ListMerchantAliases(this.repository);
  final MerchantAliasRepository repository;

  Future<ApplicationResult<List<MerchantAlias>>> call(String merchantId) =>
      runApplication(
        'list merchant aliases',
        () => repository.listForMerchant(MerchantId(merchantId)),
      );
}

final class SaveMerchantAlias {
  const SaveMerchantAlias(this.repository, this.clock);
  final MerchantAliasRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<MerchantAlias>> call({
    required String id,
    required String merchantId,
    required String alias,
    String? normalizedAlias,
  }) => runApplication('save merchant alias', () async {
    final now = clock.now();
    final existing = await repository.findById(MerchantAliasId(id));
    final value = MerchantAlias(
      id: MerchantAliasId(id),
      merchantId: MerchantId(merchantId),
      alias: alias,
      normalizedAlias: normalizedAlias,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await repository.save(value);
    return value;
  });
}

final class DeleteMerchantAlias {
  const DeleteMerchantAlias(this.repository);
  final MerchantAliasRepository repository;

  Future<ApplicationResult<void>> call(String id) => runApplication(
    'delete merchant alias',
    () => repository.remove(MerchantAliasId(id)),
  );
}

final class ListMerchantNormalizationPatterns {
  const ListMerchantNormalizationPatterns(this.repository);
  final MerchantNormalizationPatternRepository repository;

  Future<ApplicationResult<List<MerchantNormalizationPattern>>> call(
    String merchantId,
  ) => runApplication(
    'list merchant normalization patterns',
    () => repository.listForMerchant(MerchantId(merchantId)),
  );
}

final class SaveMerchantNormalizationPattern {
  const SaveMerchantNormalizationPattern(this.repository, this.clock);
  final MerchantNormalizationPatternRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<MerchantNormalizationPattern>> call({
    required String id,
    required String merchantId,
    required String pattern,
    String? normalizedPattern,
  }) => runApplication('save merchant normalization pattern', () async {
    final now = clock.now();
    final existing = await repository.findById(
      MerchantNormalizationPatternId(id),
    );
    final value = MerchantNormalizationPattern(
      id: MerchantNormalizationPatternId(id),
      merchantId: MerchantId(merchantId),
      pattern: pattern,
      normalizedPattern: normalizedPattern,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await repository.save(value);
    return value;
  });
}

final class DeleteMerchantNormalizationPattern {
  const DeleteMerchantNormalizationPattern(this.repository);
  final MerchantNormalizationPatternRepository repository;

  Future<ApplicationResult<void>> call(String id) => runApplication(
    'delete merchant normalization pattern',
    () => repository.remove(MerchantNormalizationPatternId(id)),
  );
}
