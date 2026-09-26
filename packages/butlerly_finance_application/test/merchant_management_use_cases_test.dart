import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 1, 12);

  test(
    'updates merchant matching configuration through one operation',
    () async {
      final existingAlias = MerchantAlias(
        id: MerchantAliasId('alias.old'),
        merchantId: MerchantId('merchant.costco'),
        alias: 'Costco old',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final existingPattern = MerchantNormalizationPattern(
        id: MerchantNormalizationPatternId('pattern.old'),
        merchantId: MerchantId('merchant.costco'),
        pattern: 'COSTCO OLD',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final repository = _ConfigurationRepository();
      final result =
          await UpdateMerchantMatchingConfiguration(
            repository,
            _FixedClock(createdAt.add(const Duration(hours: 1))),
          ).call(
            merchant: Merchant(
              id: MerchantId('merchant.costco'),
              name: 'Costco',
              rawName: 'COSTCO #1234',
              aliases: [existingAlias],
              normalizationPatterns: [existingPattern],
            ),
            aliases: const ['Costco old'],
            patterns: const ['COSTCO OLD'],
          );

      expect(result, isA<ApplicationSuccess<Merchant>>());
      expect(repository.calls, 1);
      expect(repository.merchant?.name, 'Costco');
      expect(repository.aliases.single.alias, 'Costco old');
      expect(repository.aliases.single.id, existingAlias.id);
      expect(repository.aliases.single.createdAt, existingAlias.createdAt);
      expect(repository.patterns.single.pattern, 'COSTCO OLD');
      expect(repository.patterns.single.id, existingPattern.id);
      expect(repository.patterns.single.createdAt, existingPattern.createdAt);
    },
  );
}

final class _FixedClock implements ApplicationClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _ConfigurationRepository
    implements MerchantMatchingConfigurationRepository {
  int calls = 0;
  Merchant? merchant;
  List<MerchantAlias> aliases = const [];
  List<MerchantNormalizationPattern> patterns = const [];

  @override
  Future<void> saveConfiguration({
    required Merchant merchant,
    required List<MerchantAlias> aliases,
    required List<MerchantNormalizationPattern> patterns,
  }) async {
    calls++;
    this.merchant = merchant;
    this.aliases = List.of(aliases);
    this.patterns = List.of(patterns);
  }
}
