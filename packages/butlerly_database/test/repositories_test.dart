import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  late ButlerlyDatabase database;
  late SqliteTransactionRepository transactions;
  final now = DateTime.utc(2026, 8, 9, 18);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    transactions = SqliteTransactionRepository(database);
  });

  tearDown(() => database.close());

  test('recalculation preserves acknowledged and dismissed findings', () async {
    final repository = SqliteAnalysisFindingRepository(database);
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R099'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'test.name',
      descriptionKey: 'test.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('b' * 64),
    );
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.original,
    );
    AnalysisFinding finding(String id) => AnalysisFinding(
      id: id,
      rule: rule,
      context: context,
      severity: RuleSeverity.info,
      lifecycle: FindingLifecycle.active,
      generatedAt: now,
    );

    for (final lifecycle in [
      FindingLifecycle.acknowledged,
      FindingLifecycle.dismissed,
    ]) {
      final value = finding('finding-${lifecycle.name}');
      await repository.save(value);
      await repository.updateLifecycle(value.id, lifecycle, now);
      await repository.save(value);
    }

    final rows = await database.connection.query(
      'analysis_findings',
      orderBy: 'id',
    );
    expect(rows.map((row) => row['lifecycle']), [
      FindingLifecycle.acknowledged.name,
      FindingLifecycle.dismissed.name,
    ]);
  });

  test('persists materialized results and scopes stale invalidation', () async {
    final repository = SqliteAnalysisRuleResultRepository(database);
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R001'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'test.name',
      descriptionKey: 'test.description',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: RuleGrouping.none,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('c' * 64),
      resultPersistence: ResultPersistencePolicy.materialized,
    );
    AnalysisContext context(String month) => AnalysisContext(
      period: AnalysisPeriod(
        startDate: '$month-01',
        endDate: '$month-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: CurrencyCode('USD'),
    );
    AnalysisRuleResult result(String month) => AnalysisRuleResult(
      id: 'result-$month',
      ruleId: rule.identity,
      ruleVersion: rule.version,
      definitionHash: rule.definitionHash,
      resultType: AnalysisResultType.metric,
      surface: AnalysisSurface.overview,
      context: context(month),
      payload: '{"value":"10"}',
      calculatedAt: now,
      sourceRevision: 1,
      freshness: AnalysisResultFreshness.fresh,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(result('2026-07'));
    await repository.save(result('2026-08'));
    expect(
      (await repository.find(
        rule: rule,
        context: context('2026-08'),
        sourceRevision: 1,
      ))?.freshness,
      AnalysisResultFreshness.fresh,
    );
    expect(
      await repository.find(
        rule: rule,
        context: context('2026-08'),
        sourceRevision: 2,
      ),
      isNull,
    );
    await repository.markStale(
      periodStart: '2026-08-01',
      periodEnd: '2026-08-31',
    );
    expect(
      (await repository.find(rule: rule, context: context('2026-08'))),
      isNull,
    );
    expect(
      await database.connection.query(
        'analysis_rule_results',
        where: 'id = ?',
        whereArgs: ['result-2026-07'],
      ),
      hasLength(1),
    );
    expect(
      (await database.connection.query(
        'analysis_rule_results',
        where: 'id = ?',
        whereArgs: ['result-2026-07'],
      )).single['freshness'],
      'fresh',
    );
  });

  test(
    'round-trips the bundled multi-measure R016 definition through SQLite',
    () async {
      final source = File(
        '../../apps/butlerly/assets/analysis_rules/metrics/ANL-R016.yaml',
      ).readAsStringSync();
      final parsed = const RestrictedRuleParser().parse(source);
      expect(parsed.diagnostics, isEmpty);
      final validated = const RuleDefinitionValidator().validate(
        parsed.document!,
      );
      expect(validated.diagnostics, isEmpty);
      final definition = validated.definition!;
      final repository = SqliteAnalysisRuleRepository(database);
      await repository.install(
        definition,
        sourceType: 'bundled',
        canonicalDefinition: canonicalize(parsed.document!.values),
      );
      await repository.activate(
        definition.identity,
        definition.version,
        true,
        now,
      );

      final reloaded = (await repository.listActive()).single;
      expect(reloaded.identity.value, 'ANL-R016');
      expect(reloaded.measures, hasLength(3));
      expect(reloaded.measure, reloaded.measures.first);
      expect(
        reloaded.measures[1].filters.single.kind,
        AnalysisFilterKind.direction,
      );
    },
  );

  test(
    'rule upgrades preserve historical versions and activate the new surface',
    () async {
      final repository = SqliteAnalysisRuleRepository(database);
      AnalysisRuleDefinition definition(
        String version,
        String hash,
        AnalysisSurface surface,
      ) => AnalysisRuleDefinition(
        identity: RuleIdentity('ANL-R010'),
        version: RuleVersion(version),
        schemaVersion: '1.0.0',
        type: AnalysisRuleType.metric,
        nameKey: 'analysis.rule.r010.name',
        descriptionKey: 'analysis.rule.r010.description',
        enabled: true,
        status: AnalysisRuleStatus.active,
        period: 'selected_period',
        measure: const RuleMeasure(
          operation: RuleOperation.sum,
          field: 'amount',
        ),
        grouping: RuleGrouping.category,
        baseline: RuleBaseline.none,
        condition: const RuleCondition(operator: 'none'),
        severity: RuleSeverity.info,
        surface: surface,
        definitionHash: RuleDefinitionHash(hash * 64),
      );
      const oldJson =
          '{"descriptionKey":"analysis.rule.r010.description","enabled":true,"grouping":"category","measure":{"field":"amount","operation":"sum"},"nameKey":"analysis.rule.r010.name","period":"selected_period","ruleId":"ANL-R010","ruleVersion":"1.0.0","schemaVersion":"1.0.0","type":"metric"}';
      const newJson =
          '{"descriptionKey":"analysis.rule.r010.description","enabled":true,"grouping":"category","measure":{"field":"amount","operation":"sum"},"nameKey":"analysis.rule.r010.name","period":"selected_period","ruleId":"ANL-R010","ruleVersion":"1.1.0","schemaVersion":"1.0.0","surface":"spending","type":"metric"}';
      await repository.install(
        definition('1.0.0', 'a', AnalysisSurface.overview),
        sourceType: 'bundled',
        canonicalDefinition: oldJson,
      );
      await repository.activate(
        RuleIdentity('ANL-R010'),
        RuleVersion('1.0.0'),
        true,
        now,
      );
      await repository.install(
        definition('1.1.0', 'b', AnalysisSurface.spending),
        sourceType: 'bundled',
        canonicalDefinition: newJson,
      );
      await repository.activate(
        RuleIdentity('ANL-R010'),
        RuleVersion('1.1.0'),
        true,
        now,
      );

      expect(await repository.listDefinitions(), hasLength(2));
      final active = (await repository.listActive()).single;
      expect(active.version.value, '1.1.0');
      expect(active.surface, AnalysisSurface.spending);
    },
  );

  test(
    'persists master-data lifecycle fields without changing stable IDs',
    () async {
      final merchants = SqliteMerchantRepository(database);
      final categories = SqliteCategoryRepository(database);
      final tags = SqliteTagRepository(database);
      final sources = SqlitePaymentSourceRepository(database);

      await merchants.save(
        Merchant(
          id: MerchantId('merchant-stable'),
          name: 'Old Name',
          rawName: 'OLD NAME #123',
        ),
      );
      await categories.save(
        Category(
          id: CategoryId('category-parent'),
          name: 'Food',
          origin: CategoryOrigin.system,
        ),
      );
      await categories.save(
        Category(
          id: CategoryId('category-child'),
          name: 'Dining',
          origin: CategoryOrigin.user,
          parentId: CategoryId('category-parent'),
        ),
      );
      await tags.save(Tag(id: TagId('tag-stable'), name: 'Travel'));
      await sources.save(
        PaymentSource(
          id: PaymentSourceId('source-card'),
          name: 'Visa',
          type: PaymentSourceType.card,
          displayIdentity: 'Personal Visa',
          lastFour: '1234',
        ),
      );

      final storedMerchant = await merchants.findById(
        MerchantId('merchant-stable'),
      );
      final storedTag = await tags.findById(TagId('tag-stable'));
      final storedSource = await sources.findById(
        PaymentSourceId('source-card'),
      );
      await merchants.save(storedMerchant!.archive());
      await tags.save(storedTag!.archive());
      await sources.save(storedSource!.archive());

      final archivedMerchant = await merchants.findById(
        MerchantId('merchant-stable'),
      );
      final storedChild = await categories.findById(
        CategoryId('category-child'),
      );
      final archivedTag = await tags.findById(TagId('tag-stable'));
      final archivedSource = await sources.findById(
        PaymentSourceId('source-card'),
      );
      expect(archivedMerchant!.id.value, 'merchant-stable');
      expect(archivedMerchant.status, MerchantStatus.archived);
      expect(storedChild!.parentId!.value, 'category-parent');
      expect(archivedTag!.status, TagStatus.archived);
      expect(archivedSource!.lastFour, '1234');
    },
  );

  test('round-trips a complete transaction aggregate', () async {
    final paymentSource = PaymentSource(
      id: PaymentSourceId('source-1'),
      name: 'Wallet',
      type: PaymentSourceType.wallet,
    );
    final merchant = Merchant(id: MerchantId('merchant-1'), name: 'Café 東京');
    final category = Category(
      id: CategoryId('category-1'),
      name: 'Dining',
      origin: CategoryOrigin.user,
    );
    final tag = Tag(id: TagId('tag-1'), name: '旅行');
    await SqlitePaymentSourceRepository(database).save(paymentSource);
    await SqliteMerchantRepository(database).save(merchant);
    await SqliteCategoryRepository(database).save(category);
    await SqliteTagRepository(database).save(tag);

    final original = Money(
      amount: DecimalValue.parse('1250.50'),
      currency: CurrencyCode('JPY'),
    );
    var value = Transaction(
      id: TransactionId('transaction-1'),
      timing: KnownTransactionTime(now),
      money: original,
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.import,
      description: '昼ご飯',
      rawCounterparty: 'CAFE TOKYO',
      sourceLanguage: 'ja',
      paymentSourceId: paymentSource.id,
      merchantId: merchant.id,
      categoryId: category.id,
      tagIds: [tag.id],
      provenance: [importProvenance(now)],
      createdAt: now,
      updatedAt: now,
      transactionDate: '2026-08-09',
    );
    value = value.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('review-1'),
        transactionId: value.id,
        reason: ReviewIssueReason.uncertain,
        createdAt: now,
      ),
      now,
    );
    value = value.addNormalizedMoney(
      NormalizedMoney(
        original: original,
        converted: Money(
          amount: DecimalValue.parse('8.45'),
          currency: CurrencyCode('USD'),
        ),
        exchangeRate: ExchangeRate(
          id: ExchangeRateId('rate-1'),
          fromCurrency: CurrencyCode('JPY'),
          toCurrency: CurrencyCode('USD'),
          rate: DecimalValue.parse('0.00676'),
          effectiveAt: now,
          source: 'Test rate source',
        ),
      ),
      now,
    );

    await transactions.save(value);
    final restored = await transactions.findById(value.id);

    expect(restored, isNotNull);
    expect(restored!.money, original);
    expect(restored.description, '昼ご飯');
    expect(restored.sourceLanguage, 'ja');
    expect(restored.paymentSourceId, paymentSource.id);
    expect(restored.tagIds, [tag.id]);
    expect(restored.reviewState, TransactionReviewState.needsReview);
    expect(
      restored.normalizedMoney.single.converted.currency,
      CurrencyCode('USD'),
    );
    expect(restored.provenance.single.originalRepresentation, '元の取引');
  });

  test('maps foreign-key failures without leaking SQLite details', () async {
    final value = minimalTransaction(
      now,
    ).assignMerchant(MerchantId('missing'), now);

    await expectLater(
      transactions.save(value),
      throwsA(
        isA<RepositoryException>().having(
          (error) => error.operation,
          'operation',
          isNot(contains('FOREIGN KEY')),
        ),
      ),
    );
    expect(await transactions.findById(value.id), isNull);
  });

  test(
    'creates, lists, archives, and permanently removes transactions',
    () async {
      final value = minimalTransaction(now);
      await transactions.save(value);
      await transactions.save(
        value.archive(now.add(const Duration(minutes: 1))),
      );

      expect(
        (await transactions.listAll()).single.status,
        TransactionStatus.archived,
      );

      await transactions.removePermanently(value.id);
      expect(await transactions.findById(value.id), isNull);
    },
  );

  test('searches and filters transactions locally', () async {
    final value = Transaction(
      id: TransactionId('searchable-transaction'),
      timing: KnownTransactionTime(now),
      money: Money(
        amount: DecimalValue.parse('42.25'),
        currency: CurrencyCode('EUR'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      description: 'Déjeuner à Paris',
      notes: 'Client meeting',
      provenance: [
        Provenance(
          id: ProvenanceId('search-provenance'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      transactionDate: '2026-08-09',
    );
    await transactions.save(value);

    final matching = await transactions.query(
      TransactionRepositoryQuery(
        text: 'client',
        from: now.subtract(const Duration(days: 1)),
        to: now.add(const Duration(days: 1)),
        currency: 'eur',
        direction: TransactionDirection.expense,
        status: TransactionStatus.active,
        needsReview: false,
      ),
    );
    final excluded = await transactions.query(
      const TransactionRepositoryQuery(text: 'missing'),
    );

    expect(matching.single.id, value.id);
    expect(excluded, isEmpty);
  });

  test('stores evidence links and suggestions separately', () async {
    final transaction = minimalTransaction(now);
    await transactions.save(transaction);
    final evidenceRepository = SqliteEvidenceRepository(database);
    final evidence = EvidenceItem(
      id: EvidenceId('evidence-1'),
      type: EvidenceType.receiptImage,
      originalName: '領収書.jpg',
      mediaType: 'image/jpeg',
      provenance: Provenance(
        id: ProvenanceId('evidence-provenance'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
        originalRepresentation: '領収書.jpg',
        sourceLanguage: 'ja',
      ),
      createdAt: now,
      sourceLanguage: 'ja',
      localFileName: 'evidence-1.jpg',
    );
    await evidenceRepository.save(evidence);
    await evidenceRepository.link(
      AttachmentLink(
        id: AttachmentLinkId('link-1'),
        transactionId: transaction.id,
        evidenceId: evidence.id,
        createdAt: now,
      ),
    );
    await evidenceRepository.link(
      AttachmentLink(
        id: AttachmentLinkId('link-duplicate'),
        transactionId: transaction.id,
        evidenceId: evidence.id,
        createdAt: now,
      ),
    );
    await transactions.save(
      transaction.assignMerchant(null, now.add(const Duration(minutes: 1))),
    );
    expect(
      (await evidenceRepository.listForTransaction(transaction.id)).single.id,
      evidence.id,
    );
    final suggestions = SqliteSuggestionRepository(database);
    final suggestion = Suggestion(
      id: SuggestionId('suggestion-1'),
      transactionId: transaction.id,
      target: SuggestionTarget.category,
      proposedValue: 'Dining',
      method: SuggestionMethod.localAi,
      provenance: Provenance(
        id: ProvenanceId('suggestion-provenance'),
        sourceType: ProvenanceSourceType.localAi,
        capturedAt: now,
        originalRepresentation: 'Dining',
      ),
      createdAt: now,
      confidence: 0.8,
    );
    await suggestions.save(suggestion);

    expect(
      (await evidenceRepository.listForTransaction(
        transaction.id,
      )).single.localFileName,
      'evidence-1.jpg',
    );
    expect(
      (await suggestions.listForTransaction(transaction.id)).single.status,
      SuggestionStatus.proposed,
    );
    await evidenceRepository.remove(evidence.id);
    expect(await evidenceRepository.findById(evidence.id), isNull);
    expect(
      await evidenceRepository.listForTransaction(transaction.id),
      isEmpty,
    );
    expect(
      await database.connection.query(
        'provenances',
        where: 'id = ?',
        whereArgs: ['evidence-provenance'],
      ),
      isEmpty,
    );
  });
}

Transaction minimalTransaction(DateTime now) => Transaction(
  id: TransactionId('transaction-minimal'),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.pending),
  money: Money(amount: DecimalValue.parse('10'), currency: CurrencyCode('EUR')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  provenance: [
    Provenance(
      id: ProvenanceId('manual-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);

Provenance importProvenance(DateTime now) => Provenance(
  id: ProvenanceId('import-provenance'),
  sourceType: ProvenanceSourceType.import,
  capturedAt: now,
  sourceId: 'file-row-1',
  originalRepresentation: '元の取引',
  sourceLanguage: 'ja',
);
