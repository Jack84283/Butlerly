import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

final _merchantCreatedAt = DateTime.utc(2026, 9, 1, 12);

void main() {
  final createdAt = _merchantCreatedAt;

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

  test(
    'reconciles existing merchant review after configuration changes',
    () async {
      final merchant = Merchant(
        id: MerchantId('merchant.safeway'),
        name: 'Safeway',
      );
      final repository = _ConfigurationRepository()..merchant = merchant;
      final transaction = _merchantReviewTransaction('SAFEWAY GROCERY');
      final transactions = _Transactions(
        synchronizeMerchantReviewIssue(transaction, createdAt),
      );

      final result =
          await UpdateMerchantMatchingConfiguration(
            repository,
            _FixedClock(createdAt.add(const Duration(hours: 1))),
            synchronize: SynchronizeMerchantReviewIssues(
              transactions,
              repository,
              () => createdAt.add(const Duration(hours: 1)),
            ),
          ).call(
            merchant: merchant,
            aliases: const ['Safeway Grocery'],
            patterns: const [],
          );

      expect(result, isA<ApplicationSuccess<Merchant>>());
      expect(
        (await transactions.findById(
          transaction.id,
        ))!.reviewIssues.single.status,
        ReviewIssueStatus.resolved,
      );
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
    implements MerchantMatchingConfigurationRepository, MerchantRepository {
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

  @override
  Future<void> save(Merchant merchant) async => this.merchant = merchant;

  @override
  Future<Merchant?> findById(MerchantId id) async =>
      merchant?.id == id ? merchant : null;

  @override
  Future<List<Merchant>> listAll() async {
    final value = merchant;
    return value == null ? const [] : [value];
  }
}

final class _Transactions implements TransactionRepository {
  _Transactions(Transaction value) : values = {value.id: value};

  final Map<TransactionId, Transaction> values;

  @override
  Future<void> save(Transaction transaction) async =>
      values[transaction.id] = transaction;

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values.toList();

  @override
  Future<void> removePermanently(TransactionId id) async => values.remove(id);
}

Transaction _merchantReviewTransaction(String evidence) => Transaction(
  id: TransactionId('transaction.merchant-review'),
  timing: KnownTransactionTime(_merchantCreatedAt),
  money: Money(amount: DecimalValue.parse('12'), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  rawCounterparty: evidence,
  transactionDate: '2026-09-01',
  provenance: [
    Provenance(
      id: ProvenanceId('provenance.merchant-review'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: _merchantCreatedAt,
    ),
  ],
  createdAt: _merchantCreatedAt,
  updatedAt: _merchantCreatedAt,
);
