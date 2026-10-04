import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9, 20);
  late MemoryTransactions transactions;
  late FixedClock clock;

  setUp(() {
    transactions = MemoryTransactions();
    clock = FixedClock(now);
  });

  test(
    'creates a manual transaction with Butlerly identity and provenance',
    () async {
      final result = await CreateTransaction(transactions, clock)(
        CreateTransactionCommand(
          id: 'transaction-1',
          provenanceId: 'provenance-1',
          timing: KnownTransactionTime(now),
          money: money('12.50'),
          direction: TransactionDirection.expense,
          description: 'Lunch',
        ),
      );

      expect(result, isA<ApplicationSuccess<TransactionDto>>());
      final stored = await transactions.findById(
        TransactionId('transaction-1'),
      );
      expect(stored!.sourceType, TransactionSourceType.manual);
      expect(
        stored.provenance.single.sourceType,
        ProvenanceSourceType.userEntry,
      );
    },
  );

  test(
    'saves manual, updated, and imported transactions when merchant enrichment fails',
    () async {
      final merchants = ThrowingMerchants();

      final created =
          await CreateTransaction(transactions, clock, merchants: merchants)(
            CreateTransactionCommand(
              id: 'manual-enrichment-failure',
              provenanceId: 'manual-enrichment-failure-provenance',
              timing: KnownTransactionTime(now),
              money: money('12.50'),
              direction: TransactionDirection.expense,
              rawCounterparty: 'Unknown merchant',
            ),
          );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        transactions.values['manual-enrichment-failure']!.reviewIssues,
        isEmpty,
      );

      transactions.values['updated-enrichment-failure'] = transaction(
        now,
        id: 'updated-enrichment-failure',
        rawCounterparty: 'Unknown merchant',
      );
      final updated =
          await UpdateTransaction(transactions, clock, merchants: merchants)(
            UpdateTransactionCommand(
              id: 'updated-enrichment-failure',
              timing: KnownTransactionTime(now),
              money: money('13.50'),
              direction: TransactionDirection.expense,
              rawCounterparty: 'Unknown merchant',
            ),
          );
      expect(updated, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        transactions.values['updated-enrichment-failure']!.reviewIssues,
        isEmpty,
      );

      final imported =
          await ImportTransaction(transactions, clock, merchants: merchants)(
            ImportTransactionCommand(
              id: 'import-enrichment-failure',
              provenanceId: 'import-enrichment-failure-provenance',
              sourceId: 'transactions.csv',
              originalRepresentation: 'Unknown merchant,12.50',
              money: money('12.50'),
              direction: TransactionDirection.expense,
              transactionDate: '2026-08-09',
              rawCounterparty: 'Unknown merchant',
            ),
          );
      expect(imported, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        transactions.values['import-enrichment-failure']!.reviewIssues,
        isEmpty,
      );
    },
  );

  test(
    'AssignMerchant saves the assignment when merchant enrichment fails',
    () async {
      final merchants = ThrowingMerchants(
        known: Merchant(
          id: MerchantId('merchant.known'),
          name: 'Known merchant',
        ),
      );
      transactions.values['assign-enrichment-failure'] = transaction(
        now,
        id: 'assign-enrichment-failure',
        rawCounterparty: 'Unknown merchant',
      );

      final result = await AssignMerchant(transactions, merchants, clock)(
        'assign-enrichment-failure',
        'merchant.known',
      );

      expect(result, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        transactions.values['assign-enrichment-failure']!.merchantId,
        MerchantId('merchant.known'),
      );
    },
  );

  test(
    'startup reconciliation repairs merchant review state after enrichment recovers',
    () async {
      final merchants = ThrowingMerchants();
      final created =
          await CreateTransaction(transactions, clock, merchants: merchants)(
            CreateTransactionCommand(
              id: 'reconcile-enrichment-failure',
              provenanceId: 'reconcile-enrichment-failure-provenance',
              timing: KnownTransactionTime(now),
              money: money('12.50'),
              direction: TransactionDirection.expense,
              rawCounterparty: 'Unknown merchant',
            ),
          );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        transactions.values['reconcile-enrichment-failure']!.reviewIssues,
        isEmpty,
      );

      final recoveredMerchants = MemoryMerchants();
      final result = await SynchronizeMerchantReviewIssues(
        transactions,
        recoveredMerchants,
        clock.now,
      )();

      expect(result, isA<ApplicationSuccess<int>>());
      expect(
        transactions
            .values['reconcile-enrichment-failure']!
            .reviewIssues
            .single
            .status,
        ReviewIssueStatus.active,
      );
    },
  );

  test('rejects a missing or nested subcategory parent', () async {
    final categories = MemoryCategories();
    final save = SaveCategory(categories);
    final missing = await save(
      Category(
        id: CategoryId('user.child'),
        name: 'Child',
        origin: CategoryOrigin.user,
        parentId: CategoryId('missing'),
      ),
    );
    expect(missing, isA<ApplicationFailure<Category>>());

    await categories.save(
      Category(
        id: CategoryId('root'),
        name: 'Root',
        origin: CategoryOrigin.user,
      ),
    );
    await categories.save(
      Category(
        id: CategoryId('nested'),
        name: 'Nested',
        origin: CategoryOrigin.user,
        parentId: CategoryId('root'),
      ),
    );
    final invalid = await save(
      Category(
        id: CategoryId('grandchild'),
        name: 'Grandchild',
        origin: CategoryOrigin.user,
        parentId: CategoryId('nested'),
      ),
    );
    expect(invalid, isA<ApplicationFailure<Category>>());
  });

  test(
    'applies confirmed history to manual and imported transactions',
    () async {
      final merchants = MemoryMerchants();
      await merchants.save(
        Merchant(
          id: MerchantId('merchant-safeway'),
          name: 'Safeway',
          defaultCategoryId: CategoryId('wrong-default'),
        ),
      );
      transactions.values['historical'] = Transaction(
        id: TransactionId('historical'),
        timing: KnownTransactionTime(now),
        money: money('20'),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        description: 'SAFEWAY #1234',
        merchantId: MerchantId('merchant-safeway'),
        categoryId: CategoryId('food'),
        subcategoryId: CategoryId('groceries'),
        provenance: [
          Provenance(
            id: ProvenanceId('historical-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final classifier = ProposeTransactionClassification(
        transactions,
        merchants,
      );

      await CreateTransaction(transactions, clock, classifier: classifier)(
        CreateTransactionCommand(
          id: 'manual-classified',
          provenanceId: 'manual-classified-provenance',
          timing: KnownTransactionTime(now),
          money: money('12'),
          direction: TransactionDirection.expense,
          description: 'SAFEWAY #5678',
        ),
      );
      expect(
        transactions.values['manual-classified']!.categoryId?.value,
        'food',
      );
      expect(
        transactions.values['manual-classified']!.subcategoryId?.value,
        'groceries',
      );

      await ImportTransaction(transactions, clock, classifier: classifier)(
        ImportTransactionCommand(
          id: 'file-classified',
          provenanceId: 'file-classified-provenance',
          sourceId: 'local.csv',
          originalRepresentation: 'SAFEWAY #5678',
          money: money('12'),
          direction: TransactionDirection.expense,
          transactionDate: '2026-08-09',
          description: 'SAFEWAY #5678',
        ),
      );
      expect(transactions.values['file-classified']!.categoryId?.value, 'food');
      expect(
        transactions.values['file-classified']!.subcategoryId?.value,
        'groceries',
      );
    },
  );

  test('ranks merchant matches by the actual matching evidence', () async {
    final merchants = MemoryMerchants();
    final matchTime = DateTime.utc(2026, 8, 9);
    Future<void> save(Merchant merchant) => merchants.save(merchant);
    await save(
      Merchant(
        id: MerchantId('merchant.canonical'),
        name: 'Canonical',
        defaultCategoryId: CategoryId('category.test'),
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.prefix'),
        name: 'Prefix',
        defaultCategoryId: CategoryId('category.test'),
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.alias'),
        name: 'Alias merchant',
        defaultCategoryId: CategoryId('category.test'),
        aliases: [
          MerchantAlias(
            id: MerchantAliasId('alias.market'),
            merchantId: MerchantId('merchant.alias'),
            alias: 'Market alias',
            createdAt: matchTime,
            updatedAt: matchTime,
          ),
        ],
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.pattern'),
        name: 'Pattern merchant',
        defaultCategoryId: CategoryId('category.test'),
        normalizationPatterns: [
          MerchantNormalizationPattern(
            id: MerchantNormalizationPatternId('pattern.premium'),
            merchantId: MerchantId('merchant.pattern'),
            pattern: 'Premium service',
            createdAt: matchTime,
            updatedAt: matchTime,
          ),
        ],
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.broad'),
        name: 'Broad merchant with a long canonical name',
        defaultCategoryId: CategoryId('category.test'),
        aliases: [
          MerchantAlias(
            id: MerchantAliasId('alias.foo'),
            merchantId: MerchantId('merchant.broad'),
            alias: 'foo',
            createdAt: matchTime,
            updatedAt: matchTime,
          ),
        ],
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.specific'),
        name: 'Specific',
        defaultCategoryId: CategoryId('category.test'),
        normalizationPatterns: [
          MerchantNormalizationPattern(
            id: MerchantNormalizationPatternId('pattern.foo-premium'),
            merchantId: MerchantId('merchant.specific'),
            pattern: 'foo premium',
            createdAt: matchTime,
            updatedAt: matchTime,
          ),
        ],
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.tie-b'),
        name: 'Tie B',
        defaultCategoryId: CategoryId('category.test'),
        aliases: [
          MerchantAlias(
            id: MerchantAliasId('alias.tie-b'),
            merchantId: MerchantId('merchant.tie-b'),
            alias: 'same evidence',
            createdAt: matchTime,
            updatedAt: matchTime,
          ),
        ],
      ),
    );
    await save(
      Merchant(
        id: MerchantId('merchant.tie-a'),
        name: 'Tie A',
        defaultCategoryId: CategoryId('category.test'),
        aliases: [
          MerchantAlias(
            id: MerchantAliasId('alias.tie-a'),
            merchantId: MerchantId('merchant.tie-a'),
            alias: 'same evidence',
            createdAt: matchTime,
            updatedAt: matchTime,
          ),
        ],
      ),
    );

    Future<String?> resolve(String text) async {
      final result = await ProposeTransactionClassification(
        transactions,
        merchants,
      )(description: text);
      expect(result, isA<ApplicationSuccess<ClassificationProposal>>());
      return (result as ApplicationSuccess<ClassificationProposal>)
          .value
          .merchantId
          ?.value;
    }

    expect(await resolve('Canonical'), 'merchant.canonical');
    expect(await resolve('Prefix store 4'), 'merchant.prefix');
    expect(await resolve('Market alias terminal'), 'merchant.alias');
    expect(await resolve('Premium service charge'), 'merchant.pattern');
    expect(await resolve('foo premium'), 'merchant.specific');
    expect(await resolve('same evidence'), 'merchant.tie-a');
  });

  test(
    'AssignMerchant synchronizes the merchant review issue lifecycle',
    () async {
      final merchants = MemoryMerchants();
      await merchants.save(
        Merchant(
          id: MerchantId('merchant.known'),
          name: 'Known merchant',
          defaultCategoryId: CategoryId('category.test'),
        ),
      );
      final issue = ReviewIssue(
        id: ReviewIssueId('$merchantReviewIssuePrefix${'transaction-1'}'),
        transactionId: TransactionId('transaction-1'),
        reason: ReviewIssueReason.merchantNeedsReview,
        createdAt: now,
      );
      transactions.values['transaction-1'] = transaction(
        now,
        rawCounterparty: 'Unknown merchant',
        reviewIssues: [issue],
      );

      final useCase = AssignMerchant(transactions, merchants, clock);
      final assigned = await useCase('transaction-1', 'merchant.known');
      expect(assigned, isA<ApplicationSuccess<TransactionDto>>());
      expect(
        transactions.values['transaction-1']!.merchantId?.value,
        'merchant.known',
      );
      expect(
        transactions.values['transaction-1']!.reviewIssues.single.status,
        ReviewIssueStatus.resolved,
      );

      final cleared = await useCase('transaction-1', null);
      expect(cleared, isA<ApplicationSuccess<TransactionDto>>());
      expect(transactions.values['transaction-1']!.merchantId, isNull);
      expect(
        transactions.values['transaction-1']!.reviewIssues.single.status,
        ReviewIssueStatus.active,
      );
    },
  );

  test(
    'AssignMerchant does not reopen a resolved issue for deterministic merchant evidence',
    () async {
      final matchTime = DateTime.utc(2026, 8, 9);
      final cases = [
        (
          evidence: 'Safeway',
          merchant: Merchant(
            id: MerchantId('merchant.canonical'),
            name: 'Safeway',
            defaultCategoryId: CategoryId('category.test'),
          ),
        ),
        (
          evidence: 'Market alias terminal',
          merchant: Merchant(
            id: MerchantId('merchant.alias'),
            name: 'Market',
            defaultCategoryId: CategoryId('category.test'),
            aliases: [
              MerchantAlias(
                id: MerchantAliasId('alias.market'),
                merchantId: MerchantId('merchant.alias'),
                alias: 'Market alias',
                createdAt: matchTime,
                updatedAt: matchTime,
              ),
            ],
          ),
        ),
        (
          evidence: 'Premium service charge',
          merchant: Merchant(
            id: MerchantId('merchant.pattern'),
            name: 'Premium',
            defaultCategoryId: CategoryId('category.test'),
            normalizationPatterns: [
              MerchantNormalizationPattern(
                id: MerchantNormalizationPatternId('pattern.premium'),
                merchantId: MerchantId('merchant.pattern'),
                pattern: 'Premium service',
                createdAt: matchTime,
                updatedAt: matchTime,
              ),
            ],
          ),
        ),
      ];

      for (final entry in cases.indexed) {
        final index = entry.$1;
        final evidence = entry.$2.evidence;
        final merchant = entry.$2.merchant;
        final localTransactions = MemoryTransactions();
        final localMerchants = MemoryMerchants();
        await localMerchants.save(merchant);
        final transactionId = 'transaction-${index + 1}';
        final issue = ReviewIssue(
          id: ReviewIssueId('$merchantReviewIssuePrefix$transactionId'),
          transactionId: TransactionId(transactionId),
          reason: ReviewIssueReason.merchantNeedsReview,
          createdAt: now,
          status: ReviewIssueStatus.resolved,
          closedAt: now,
        );
        localTransactions.values[transactionId] = transaction(
          now,
          id: transactionId,
          rawCounterparty: evidence,
          reviewIssues: [issue],
        );

        final useCase = AssignMerchant(
          localTransactions,
          localMerchants,
          clock,
        );
        expect(
          await useCase(transactionId, merchant.id.value),
          isA<ApplicationSuccess<TransactionDto>>(),
        );
        expect(
          await useCase(transactionId, null),
          isA<ApplicationSuccess<TransactionDto>>(),
        );
        expect(localTransactions.values[transactionId]!.merchantId, isNull);
        expect(
          localTransactions.values[transactionId]!.reviewIssues.single.status,
          ReviewIssueStatus.resolved,
        );
      }
    },
  );

  test(
    'startup synchronization backfills legacy merchant review issues',
    () async {
      transactions.values['legacy-transaction'] = transaction(
        now,
        id: 'legacy-transaction',
        rawCounterparty: 'Unknown merchant',
      );

      final result = await SynchronizeMerchantReviewIssues(
        transactions,
        MemoryMerchants(),
        clock.now,
      )();

      expect(result, isA<ApplicationSuccess<int>>());
      expect(
        transactions.values['legacy-transaction']!.reviewIssues.single.status,
        ReviewIssueStatus.active,
      );
      expect(
        transactions.values['legacy-transaction']!.reviewIssues.single.reason,
        ReviewIssueReason.merchantNeedsReview,
      );
    },
  );

  test(
    'receipt creation is idempotent and preserves reviewed fields',
    () async {
      final command = ReceiptTransactionCommand(
        id: 'receipt-transaction',
        provenanceId: 'receipt-provenance',
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        transactionDate: '2026-08-09',
        originalRepresentation: 'receipt.jpg',
        rawCounterparty: 'Cafe',
        description: 'Cafe',
        merchantId: 'merchant-1',
        categoryId: 'food',
        paymentSourceId: 'card-1',
        tagIds: ['tag-1', 'tag-2'],
      );
      final useCase = CreateReceiptTransaction(transactions, clock);
      await useCase.call(command);
      await useCase.call(
        ReceiptTransactionCommand(
          id: command.id,
          provenanceId: command.provenanceId,
          money: money('99.00'),
          transactionDate: command.transactionDate,
          originalRepresentation: 'different-source.jpg',
          description: 'Conflicting source',
        ),
      );
      expect(transactions.values, hasLength(1));
      final stored = transactions.values.values.single;
      expect(stored.merchantId?.value, 'merchant-1');
      expect(stored.categoryId?.value, 'food');
      expect(
        stored.tagIds.map((id) => id.value),
        containsAll(['tag-1', 'tag-2']),
      );
    },
  );

  test(
    'applies user rules to receipt transactions before persistence',
    () async {
      final rules = MemoryTransactionRules([
        TransactionRule(
          id: TransactionRuleId('rule.receipt'),
          name: 'Classify cafe receipts',
          descriptionContains: 'cafe',
          assignCategoryId: CategoryId('food'),
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final useCase = CreateReceiptTransaction(
        transactions,
        clock,
        applyRules: ApplyTransactionRules(rules, clock),
      );

      await useCase.call(
        ReceiptTransactionCommand(
          id: 'receipt-rule',
          provenanceId: 'receipt-rule-provenance',
          money: money('8.50'),
          transactionDate: '2026-08-09',
          originalRepresentation: 'cafe.jpg',
          description: 'Cafe latte',
        ),
      );

      expect(
        transactions.values['receipt-rule']!.categoryId,
        CategoryId('food'),
      );
    },
  );

  test(
    'imports a date-only transaction without inventing an instant',
    () async {
      final result = await ImportTransaction(transactions, clock)(
        ImportTransactionCommand(
          id: 'import-1',
          provenanceId: 'import-provenance-1',
          sourceId: 'transactions.csv',
          originalRepresentation: '"2026-08-01","12.50","USD"',
          money: money('12.50'),
          direction: TransactionDirection.expense,
          transactionDate: '2026-08-01',
          rawCounterparty: 'Café Original',
          sourceLanguage: 'es',
        ),
      );

      expect(result, isA<ApplicationSuccess<TransactionDto>>());
      final stored = await transactions.findById(TransactionId('import-1'));
      expect(stored!.sourceType, TransactionSourceType.import);
      expect(stored.timing, isA<UnknownTransactionTime>());
      expect(stored.transactionDate, '2026-08-01');
      expect(stored.timeZoneId, isNull);
      expect(stored.rawCounterparty, 'Café Original');
      expect(stored.sourceLanguage, 'es');
      expect(stored.money, money('12.50'));
      expect(stored.provenance.single.sourceType, ProvenanceSourceType.import);
      expect(
        stored.provenance.single.originalRepresentation,
        '"2026-08-01","12.50","USD"',
      );
    },
  );

  test('rejects invalid imported business dates', () async {
    final result = await ImportTransaction(transactions, clock)(
      ImportTransactionCommand(
        id: 'import-1',
        provenanceId: 'import-provenance-1',
        sourceId: 'transactions.csv',
        originalRepresentation: 'invalid row',
        money: money('12.50'),
        direction: TransactionDirection.expense,
        transactionDate: '08/01/2026',
      ),
    );

    expect(
      result,
      isA<ApplicationFailure<TransactionDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.validation,
      ),
    );
    expect(transactions.values, isEmpty);
  });

  test('updates canonical data while retaining provenance', () async {
    transactions.values['transaction-1'] = transaction(now);
    final result = await UpdateTransaction(transactions, clock)(
      UpdateTransactionCommand(
        id: 'transaction-1',
        timing: KnownTransactionTime(now),
        money: money('20'),
        direction: TransactionDirection.expense,
        description: 'Corrected lunch',
      ),
    );

    expect(result, isA<ApplicationSuccess<TransactionDto>>());
    final stored = transactions.values['transaction-1']!;
    expect(stored.description, 'Corrected lunch');
    expect(stored.provenance.single.id, ProvenanceId('provenance-1'));
  });

  test(
    'passes local search and filters through repository abstraction',
    () async {
      transactions.values['transaction-1'] = transaction(now);
      final result = await ListTransactions(transactions)(
        const ListTransactionsQuery(
          text: 'lunch',
          currency: 'usd',
          paymentSourceId: 'wallet-1',
          needsReview: false,
          includeUndated: true,
        ),
      );

      expect(result, isA<ApplicationSuccess<List<TransactionDto>>>());
      expect(transactions.lastQuery!.text, 'lunch');
      expect(transactions.lastQuery!.currency, 'usd');
      expect(
        transactions.lastQuery!.paymentSourceId,
        PaymentSourceId('wallet-1'),
      );
      expect(transactions.lastQuery!.needsReview, isFalse);
      expect(transactions.lastQuery!.includeUndated, isTrue);
    },
  );

  test(
    'bounds undated fallback records in the requested financial timezone',
    () async {
      final inside = transaction(
        DateTime.utc(2026, 10, 1, 6, 30),
        id: 'inside-period',
        transactionDate: null,
      );
      final outside = transaction(
        DateTime.utc(2026, 10, 1, 7, 30),
        id: 'outside-period',
        transactionDate: null,
      );
      final datedOutside = transaction(
        DateTime.utc(2026, 9, 15, 12),
        id: 'dated-outside-period',
        transactionDate: '2026-10-01',
      );
      transactions.values[inside.id.value] = inside;
      transactions.values[outside.id.value] = outside;
      transactions.values[datedOutside.id.value] = datedOutside;

      final result = await ListTransactions(transactions)(
        ListTransactionsQuery(
          from: DateTime.utc(2026, 9, 1),
          to: DateTime.utc(2026, 9, 30),
          timeZoneId: 'America/Los_Angeles',
          includeUndated: true,
          status: TransactionStatus.active,
        ),
      );

      final resultValues =
          (result as ApplicationSuccess<List<TransactionDto>>).value;
      expect(resultValues.map((value) => value.id), ['inside-period']);
      expect(resultValues.single.financialDate, DateTime.utc(2026, 9, 30));
      expect(
        transactions.lastQuery!.occurredAtFrom,
        DateTime.utc(2026, 9, 1, 7),
      );
      expect(
        transactions.lastQuery!.occurredAtToExclusive,
        DateTime.utc(2026, 10, 1, 7),
      );

      final localMarchFirst = transaction(
        DateTime.utc(2026, 2, 28, 16, 30),
        id: 'positive-offset-inside',
        transactionDate: null,
      );
      final localFebruaryTwentyEighth = transaction(
        DateTime.utc(2026, 2, 28, 15, 30),
        id: 'positive-offset-outside',
        transactionDate: null,
      );
      transactions.values[localMarchFirst.id.value] = localMarchFirst;
      transactions.values[localFebruaryTwentyEighth.id.value] =
          localFebruaryTwentyEighth;

      final positiveOffsetResult = await ListTransactions(transactions)(
        ListTransactionsQuery(
          from: DateTime.utc(2026, 3, 1),
          to: DateTime.utc(2026, 3, 1),
          timeZoneId: 'Asia/Shanghai',
          includeUndated: true,
          status: TransactionStatus.active,
        ),
      );

      final positiveOffsetValues =
          (positiveOffsetResult as ApplicationSuccess<List<TransactionDto>>)
              .value;
      expect(positiveOffsetValues.map((value) => value.id), [
        'positive-offset-inside',
      ]);
      expect(
        positiveOffsetValues.single.financialDate,
        DateTime.utc(2026, 3, 1),
      );
      expect(
        transactions.lastQuery!.occurredAtFrom,
        DateTime.utc(2026, 2, 28, 16),
      );
      expect(
        transactions.lastQuery!.occurredAtToExclusive,
        DateTime.utc(2026, 3, 1, 16),
      );
    },
  );

  test(
    'list and get use the persisted financial timezone when callers omit it',
    () async {
      final value = transaction(
        DateTime.utc(2026, 9, 30, 23, 30),
        id: 'persisted-timezone',
        transactionDate: null,
      );
      transactions.values[value.id.value] = value;
      final preferences = _Preferences('Asia/Tokyo');

      final listed =
          await ListTransactions(transactions, preferences: preferences)(
            ListTransactionsQuery(
              from: DateTime.utc(2026, 10, 1),
              to: DateTime.utc(2026, 10, 1),
              includeUndated: true,
            ),
          );
      expect(
        (listed as ApplicationSuccess<List<TransactionDto>>)
            .value
            .single
            .financialDate,
        DateTime.utc(2026, 10, 1),
      );

      final fetched = await GetTransaction(
        transactions,
        preferences: preferences,
      )('persisted-timezone');
      expect(
        (fetched as ApplicationSuccess<TransactionDto>).value.financialDate,
        DateTime.utc(2026, 10, 1),
      );
    },
  );

  test(
    'invalid persisted timezone returns structured failures for reads and mutations',
    () async {
      final explicit = transaction(
        DateTime.utc(2026, 8, 9, 20),
        id: 'explicit-date-invalid-zone',
        transactionDate: '2026-08-09',
      );
      final fallback = transaction(
        DateTime.utc(2026, 8, 9, 20),
        id: 'occurred-at-invalid-zone',
        transactionDate: null,
      );
      transactions.values[explicit.id.value] = explicit;
      transactions.values[fallback.id.value] = fallback;
      final preferences = _Preferences('Invalid/Timezone');

      final listed =
          await ListTransactions(transactions, preferences: preferences)(
            ListTransactionsQuery(
              from: DateTime.utc(2026, 8, 9),
              to: DateTime.utc(2026, 8, 9),
              status: TransactionStatus.active,
            ),
          );
      expect(
        listed,
        isA<ApplicationFailure<List<TransactionDto>>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.validation,
        ),
      );
      expect(transactions.lastQuery, isNull);

      final unbounded = await ListTransactions(
        transactions,
        preferences: preferences,
      )(const ListTransactionsQuery());
      expect(
        unbounded,
        isA<ApplicationFailure<List<TransactionDto>>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.validation,
        ),
      );

      final fetched = await GetTransaction(
        transactions,
        preferences: preferences,
      )(explicit.id.value);
      expect(
        fetched,
        isA<ApplicationFailure<TransactionDto>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.validation,
        ),
      );

      final sources = MemoryPaymentSources();
      await sources.save(
        PaymentSource(
          id: PaymentSourceId('invalid-zone-source'),
          name: 'Wallet',
          type: PaymentSourceType.wallet,
        ),
      );
      final mutated = await AssignPaymentSource(
        transactions,
        sources,
        clock,
        preferences: preferences,
      )(fallback.id.value, 'invalid-zone-source');
      expect(
        mutated,
        isA<ApplicationFailure<TransactionDto>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.validation,
        ),
      );
      expect(transactions.values[fallback.id.value]!.paymentSourceId, isNull);

      final updated =
          await UpdateTransaction(
            transactions,
            clock,
            preferences: preferences,
          )(
            UpdateTransactionCommand(
              id: fallback.id.value,
              timing: fallback.timing,
              money: fallback.money,
              direction: fallback.direction,
            ),
          );
      expect(
        updated,
        isA<ApplicationFailure<TransactionDto>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.validation,
        ),
      );
    },
  );

  test(
    'missing and unreadable preferences use the explicit UTC fallback',
    () async {
      final value = transaction(
        DateTime.utc(2026, 8, 9, 23, 30),
        id: 'utc-fallback',
        transactionDate: null,
      );
      transactions.values[value.id.value] = value;

      for (final preferences in [
        _Preferences(null),
        _Preferences(null, failOnLoad: true),
      ]) {
        final result =
            await ListTransactions(transactions, preferences: preferences)(
              ListTransactionsQuery(
                from: DateTime.utc(2026, 8, 9),
                to: DateTime.utc(2026, 8, 9),
                status: TransactionStatus.active,
              ),
            );
        expect(result, isA<ApplicationSuccess<List<TransactionDto>>>());
        expect(
          (result as ApplicationSuccess<List<TransactionDto>>)
              .value
              .single
              .financialDate,
          DateTime.utc(2026, 8, 9),
        );
      }
    },
  );

  test('rejects an inverted date range before repository access', () async {
    final result = await ListTransactions(transactions)(
      ListTransactionsQuery(
        from: now,
        to: now.subtract(const Duration(days: 1)),
      ),
    );

    expect(
      result,
      isA<ApplicationFailure<List<TransactionDto>>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.validation,
      ),
    );
    expect(transactions.lastQuery, isNull);
  });

  test('maps repository exceptions to application failures', () async {
    transactions.failure = const RepositoryException(
      RepositoryFailureCode.storageFull,
      'save',
    );
    final result = await CreateTransaction(transactions, clock)(
      CreateTransactionCommand(
        id: 'transaction-1',
        provenanceId: 'provenance-1',
        timing: KnownTransactionTime(now),
        money: money('12.50'),
        direction: TransactionDirection.expense,
      ),
    );

    expect(
      result,
      isA<ApplicationFailure<TransactionDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.storage,
      ),
    );
  });

  test('does not assign a missing category', () async {
    transactions.values['transaction-1'] = transaction(now);
    final result = await AssignCategory(
      transactions,
      MemoryCategories(),
      clock,
    )('transaction-1', 'missing');

    expect(
      result,
      isA<ApplicationFailure<TransactionDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.notFound,
      ),
    );
    expect(transactions.values['transaction-1']!.categoryId, isNull);
  });

  test('archives and restores without permanently deleting', () async {
    transactions.values['transaction-1'] = transaction(now);

    await ArchiveTransaction(transactions, clock)('transaction-1');
    expect(
      transactions.values['transaction-1']!.status,
      TransactionStatus.archived,
    );
    await RestoreTransaction(transactions, clock)('transaction-1');
    expect(
      transactions.values['transaction-1']!.status,
      TransactionStatus.active,
    );
  });

  test('manages and assigns a local payment source', () async {
    final sources = MemoryPaymentSources();
    final source = PaymentSource(
      id: PaymentSourceId('wallet-1'),
      name: 'Cash wallet',
      type: PaymentSourceType.wallet,
    );

    final saved = await SavePaymentSource(sources)(source);
    expect(saved, isA<ApplicationSuccess<PaymentSource>>());
    expect(
      await ListPaymentSources(sources)(),
      isA<ApplicationSuccess<List<PaymentSource>>>(),
    );

    transactions.values['transaction-1'] = transaction(now);
    final assigned = await AssignPaymentSource(
      transactions,
      sources,
      clock,
      preferences: _Preferences('Asia/Tokyo'),
    )('transaction-1', 'wallet-1');
    expect(assigned, isA<ApplicationSuccess<TransactionDto>>());
    expect(
      (assigned as ApplicationSuccess<TransactionDto>).value.financialDate,
      DateTime.utc(2026, 8, 10),
    );
    expect(
      transactions.values['transaction-1']!.paymentSourceId,
      PaymentSourceId('wallet-1'),
    );

    final archived = await ArchivePaymentSource(sources)('wallet-1');
    expect(archived, isA<ApplicationSuccess<PaymentSource>>());
    expect(
      (await sources.findById(PaymentSourceId('wallet-1')))!.status,
      PaymentSourceStatus.archived,
    );
  });

  test('lists and explicitly resolves active local review issues', () async {
    final issue = ReviewIssue(
      id: ReviewIssueId('issue-1'),
      transactionId: TransactionId('transaction-1'),
      reason: ReviewIssueReason.uncertain,
      detail: 'Confirm the transaction amount.',
      createdAt: now,
    );
    transactions.values['transaction-1'] = transaction(
      now,
    ).addReviewIssue(issue, now);

    final listed = await ListReviewItems(transactions)();
    expect(
      listed,
      isA<ApplicationSuccess<List<ReviewItemDto>>>().having(
        (value) => value.value.single.issueId,
        'issue id',
        'issue-1',
      ),
    );
    expect(transactions.reviewQueryCalls, 1);

    final resolved = await ResolveReviewIssue(transactions, clock)(
      'transaction-1',
      'issue-1',
    );
    expect(resolved, isA<ApplicationSuccess<TransactionDto>>());
    expect(
      transactions.values['transaction-1']!.reviewState,
      TransactionReviewState.clear,
    );
    expect(
      transactions.values['transaction-1']!.reviewIssues.single.status,
      ReviewIssueStatus.resolved,
    );
  });

  test('scoped review items are filtered by the application query', () async {
    final inside = transaction(
      DateTime.utc(2026, 9, 5, 12),
      id: 'review-inside',
      transactionDate: '2026-09-05',
    );
    final outside = transaction(
      DateTime.utc(2026, 8, 5, 12),
      id: 'review-outside',
      transactionDate: '2026-08-05',
    );
    for (final value in [inside, outside]) {
      transactions.values[value.id.value] = value.addReviewIssue(
        ReviewIssue(
          id: ReviewIssueId('${value.id.value}-issue'),
          transactionId: value.id,
          reason: ReviewIssueReason.uncertain,
          createdAt: value.updatedAt,
        ),
        value.updatedAt,
      );
    }

    final result = await ListReviewItems(transactions)(
      ListReviewItemsQuery(
        scope: ReviewPeriodScope.fromDateValues(
          startDate: '2026-09-01',
          endDate: '2026-09-16',
          timeZoneId: 'UTC',
        ),
      ),
    );

    expect(result, isA<ApplicationSuccess<List<ReviewItemDto>>>());
    expect(
      (result as ApplicationSuccess<List<ReviewItemDto>>).value.map(
        (item) => item.transactionId,
      ),
      ['review-inside'],
    );
    expect(transactions.reviewQueryCalls, 0);
    expect(transactions.lastQuery?.needsReview, isTrue);
    expect(transactions.lastQuery?.from, DateTime.utc(2026, 9, 1));
    expect(transactions.lastQuery?.to, DateTime.utc(2026, 9, 16));
  });

  test('invalid review scope returns a validation failure', () async {
    final result = await ListReviewItems(transactions)(
      const ListReviewItemsQuery(scope: ReviewPeriodScope.invalid()),
    );

    expect(
      result,
      isA<ApplicationFailure<List<ReviewItemDto>>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.validation,
      ),
    );
    expect(transactions.reviewQueryCalls, 0);
    expect(transactions.lastQuery, isNull);
  });

  test('reversed review dates are an invalid scope', () {
    expect(
      ReviewPeriodScope.fromDateValues(
        startDate: '2026-09-16',
        endDate: '2026-09-01',
        timeZoneId: 'UTC',
      ).isInvalid,
      isTrue,
    );
  });

  test('scoped review uses the authoritative financial timezone', () async {
    final base = transaction(
      DateTime.utc(2026, 9, 1, 7),
      id: 'review-timezone',
    );
    final value = base.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('review-timezone-issue'),
        transactionId: TransactionId('review-timezone'),
        reason: ReviewIssueReason.uncertain,
        createdAt: base.updatedAt,
      ),
      base.updatedAt,
    );
    transactions.values[value.id.value] = value;

    final result = await ListReviewItems(transactions)(
      ListReviewItemsQuery(
        scope: ReviewPeriodScope.fromDateValues(
          startDate: '2026-09-01',
          endDate: '2026-09-01',
          timeZoneId: 'America/Los_Angeles',
        ),
      ),
    );

    expect(result, isA<ApplicationSuccess<List<ReviewItemDto>>>());
    expect(
      (result as ApplicationSuccess<List<ReviewItemDto>>).value,
      hasLength(1),
    );
    expect(transactions.lastQuery?.occurredAtFrom, DateTime.utc(2026, 9, 1, 7));
    expect(
      transactions.lastQuery?.occurredAtToExclusive,
      DateTime.utc(2026, 9, 2, 7),
    );
  });

  test('maps review repository failures to an application failure', () async {
    transactions.failure = const RepositoryException(
      RepositoryFailureCode.unavailable,
      'query transactions for review',
    );

    final result = await ListReviewItems(transactions)();

    expect(
      result,
      isA<ApplicationFailure<List<ReviewItemDto>>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.unavailable,
      ),
    );
  });

  test('needs review is limited to active unresolved issues', () async {
    final base = transaction(now);
    final first = base.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('issue-active'),
        transactionId: base.id,
        reason: ReviewIssueReason.uncertain,
        createdAt: now,
      ),
      now,
    );
    final second = first.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('issue-second'),
        transactionId: base.id,
        reason: ReviewIssueReason.incomplete,
        createdAt: now,
      ),
      now,
    );
    transactions.values[base.id.value] = second;

    final listed = await ListReviewItems(transactions)();
    expect(listed, isA<ApplicationSuccess<List<ReviewItemDto>>>());
    expect(
      (listed as ApplicationSuccess<List<ReviewItemDto>>).value,
      hasLength(2),
    );

    await ResolveReviewIssue(transactions, clock)(
      base.id.value,
      'issue-active',
    );
    final remaining = await ListReviewItems(transactions)();
    expect(
      (remaining as ApplicationSuccess<List<ReviewItemDto>>).value,
      hasLength(1),
    );

    await DismissReviewIssue(transactions, clock)(
      base.id.value,
      'issue-second',
    );
    final closed = await ListReviewItems(transactions)();
    expect((closed as ApplicationSuccess<List<ReviewItemDto>>).value, isEmpty);
  });

  test(
    'review issue and uncategorized membership remain independent',
    () async {
      final base = transaction(now).addReviewIssue(
        ReviewIssue(
          id: ReviewIssueId('issue-independent'),
          transactionId: TransactionId('transaction-1'),
          reason: ReviewIssueReason.uncertain,
          createdAt: now,
        ),
        now,
      );
      transactions.values[base.id.value] = base;

      final review = await ListReviewItems(transactions)();
      expect(
        (review as ApplicationSuccess<List<ReviewItemDto>>).value,
        hasLength(1),
      );
      expect(transactions.values[base.id.value]!.categoryId, isNull);

      await ResolveReviewIssue(transactions, clock)(
        base.id.value,
        'issue-independent',
      );
      expect(
        (await ListReviewItems(transactions)()
                as ApplicationSuccess<List<ReviewItemDto>>)
            .value,
        isEmpty,
      );
      expect(transactions.values[base.id.value]!.categoryId, isNull);
    },
  );

  test(
    'maps evidence retrieval failures without exposing stored content',
    () async {
      final result = await ListEvidenceForTransaction(FailingEvidence())(
        'transaction-1',
      );

      expect(
        result,
        isA<ApplicationFailure<List<EvidenceItem>>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.unavailable,
        ),
      );
    },
  );
}

final class FixedClock implements ApplicationClock {
  const FixedClock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}

final class _Preferences implements UserPreferenceRepository {
  _Preferences(this.timeZoneId, {this.failOnLoad = false});

  final String? timeZoneId;
  final bool failOnLoad;

  @override
  Future<UserPreference?> load() async {
    if (failOnLoad) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'load preferences',
      );
    }
    final value = timeZoneId;
    if (value == null) return null;
    return UserPreference(
      locale: 'en',
      baseCurrency: CurrencyCode('USD'),
      timeZoneId: value,
    );
  }

  @override
  Future<void> save(UserPreference preference) async {}
}

final class MemoryTransactions
    implements TransactionRepository, ReviewTransactionRepository {
  final values = <String, Transaction>{};
  TransactionRepositoryQuery? lastQuery;
  RepositoryException? failure;
  int reviewQueryCalls = 0;

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    lastQuery = query;
    return values.values.where((value) {
      if (query.status != null && value.status != query.status) return false;
      if (query.needsReview == true &&
          value.reviewState != TransactionReviewState.needsReview) {
        return false;
      }

      if (query.from == null && query.to == null) return true;

      final businessDate = value.transactionDate?.trim();
      if (businessDate != null && businessDate.isNotEmpty) {
        if (query.from == null && query.to == null) return true;
        final parsed = DateTime.tryParse(businessDate);
        if (parsed == null) return false;
        final date = DateTime.utc(parsed.year, parsed.month, parsed.day);
        final from = query.from == null
            ? null
            : DateTime.utc(
                query.from!.year,
                query.from!.month,
                query.from!.day,
              );
        final to = query.to == null
            ? null
            : DateTime.utc(query.to!.year, query.to!.month, query.to!.day);
        return (from == null || !date.isBefore(from)) &&
            (to == null || !date.isAfter(to));
      }

      final timing = value.timing;
      if (timing is KnownTransactionTime) {
        final occurredAt = timing.occurredAt;
        return (query.occurredAtFrom == null ||
                !occurredAt.isBefore(query.occurredAtFrom!)) &&
            (query.occurredAtToExclusive == null ||
                occurredAt.isBefore(query.occurredAtToExclusive!));
      }
      return query.includeUndated;
    }).toList();
  }

  @override
  Future<List<Transaction>> queryTransactionsForReview() async {
    reviewQueryCalls++;
    if (failure case final error?) throw error;
    return values.values
        .where(
          (value) =>
              value.status == TransactionStatus.active &&
              value.reviewState == TransactionReviewState.needsReview,
        )
        .toList();
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    if (failure case final error?) throw error;
    values[transaction.id.value] = transaction;
  }
}

final class MemoryMerchants implements MerchantRepository {
  final values = <String, Merchant>{};

  @override
  Future<Merchant?> findById(MerchantId id) async => values[id.value];

  @override
  Future<List<Merchant>> listAll() async => values.values.toList();

  @override
  Future<void> save(Merchant merchant) async =>
      values[merchant.id.value] = merchant;
}

final class ThrowingMerchants implements MerchantRepository {
  ThrowingMerchants({this.known});

  final Merchant? known;

  @override
  Future<Merchant?> findById(MerchantId id) async =>
      known?.id == id ? known : null;

  @override
  Future<List<Merchant>> listAll() async {
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'list merchants',
    );
  }

  @override
  Future<void> save(Merchant merchant) async {}
}

final class MemoryCategories implements CategoryRepository {
  final values = <String, Category>{};

  @override
  Future<Category?> findById(CategoryId id) async => values[id.value];

  @override
  Future<List<Category>> listAll() async => values.values.toList();

  @override
  Future<void> save(Category category) async {
    values[category.id.value] = category;
  }
}

final class MemoryPaymentSources implements PaymentSourceRepository {
  final values = <String, PaymentSource>{};

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => values[id.value];

  @override
  Future<List<PaymentSource>> listAll() async => values.values.toList();

  @override
  Future<void> save(PaymentSource paymentSource) async {
    values[paymentSource.id.value] = paymentSource;
  }
}

final class MemoryTransactionRules implements TransactionRuleRepository {
  MemoryTransactionRules(Iterable<TransactionRule> values)
    : values = values.toList();

  final List<TransactionRule> values;

  @override
  Future<TransactionRule?> findById(TransactionRuleId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<TransactionRule>> listAll() async => List.of(values);

  @override
  Future<void> remove(TransactionRuleId id) async {
    values.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> save(TransactionRule rule) async {
    values.removeWhere((value) => value.id == rule.id);
    values.add(rule);
  }
}

final class FailingEvidence implements EvidenceRepository {
  @override
  Future<void> remove(EvidenceId id) async {}

  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;

  @override
  Future<void> link(AttachmentLink link) async {}

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async {
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'list transaction evidence',
    );
  }

  @override
  Future<void> save(EvidenceItem evidence) async {}

  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}

Money money(String amount) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD'));

Transaction transaction(
  DateTime now, {
  String id = 'transaction-1',
  String? transactionDate,
  String? rawCounterparty,
  List<ReviewIssue> reviewIssues = const [],
}) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(now),
  money: money('12.50'),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  description: 'Lunch',
  rawCounterparty: rawCounterparty,
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-1'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
  transactionDate: transactionDate,
  reviewIssues: reviewIssues,
);
