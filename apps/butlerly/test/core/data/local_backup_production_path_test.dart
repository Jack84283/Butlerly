import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late Directory databaseDirectory;
  late Directory temporaryDirectory;
  late Directory evidenceDirectory;
  late LocalDatabase database;
  late FinanceServices finance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    await services.reset();
    root = await Directory.systemTemp.createTemp('butlerly-backup-production-');
    databaseDirectory = Directory(path.join(root.path, 'database'))
      ..createSync(recursive: true);
    temporaryDirectory = Directory(path.join(root.path, 'temporary'))
      ..createSync(recursive: true);
    evidenceDirectory = Directory(path.join(root.path, 'evidence'))
      ..createSync(recursive: true);
    final documentsDirectory = Directory(path.join(root.path, 'documents'))
      ..createSync(recursive: true);
    messenger.setMockMethodCallHandler(
      pathProviderChannel,
      (_) async => temporaryDirectory.path,
    );

    final logger = AppLogger();
    database = LocalDatabase(
      logger: logger,
      factory: databaseFactoryFfi,
      databaseDirectory: databaseDirectory.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: logger,
      documentsDirectory: documentsDirectory,
      localEvidenceDirectory: evidenceDirectory,
    );
    finance = services<FinanceServices>();
    await finance.saveUserPreference(
      UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        firstUseCompleted: true,
      ),
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    await services.reset();
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'production portable backup repairs a missing bundled rule definition',
    () async {
      final expense = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'backup-production-expense',
          provenanceId: 'backup-production-expense-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 3, 12)),
          transactionDate: '2026-11-03',
          money: Money(
            amount: DecimalValue.parse('42.50'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          categoryId: 'category.food.groceries',
        ),
      );
      expect(expense, isA<ApplicationSuccess<TransactionDto>>());
      final income = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'backup-production-income',
          provenanceId: 'backup-production-income-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 4, 12)),
          transactionDate: '2026-11-04',
          money: Money(
            amount: DecimalValue.parse('100.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.income,
        ),
      );
      expect(income, isA<ApplicationSuccess<TransactionDto>>());

      final budget = await finance.manageBudgets!.save(
        const Budget(
          id: 'backup-production-budget',
          scope: 'overall',
          scopeId: null,
          currency: 'USD',
          amount: '250.00',
        ),
      );
      expect(budget, isA<ApplicationSuccess<bool>>());

      await database.database.insert('financial_profiles', {
        'profile_id': 'financial-profile:default',
        'schema_version': 1,
        'survey_version': '1.0',
        'household_size': 'two',
        'dependents_count': null,
        'housing_situation': null,
        'primary_spending_categories': '["category.food"]',
        'expense_predictability': null,
        'categories_to_improve': '[]',
        'primary_financial_goal': 'saveMore',
        'has_monthly_savings_target': 0,
        'monthly_savings_target': null,
        'monthly_savings_target_currency': null,
        'goal_timeframe': null,
        'budgeting_preference': null,
        'preferred_insight_types': '["spendingTrends"]',
        'survey_status': 'inProgress',
        'created_at': '2026-11-01T00:00:00.000Z',
        'updated_at': '2026-11-01T00:00:00.000Z',
        'completed_at': null,
      });

      final evidenceFile = File(
        path.join(evidenceDirectory.path, 'receipts', 'receipt.txt'),
      )..createSync(recursive: true);
      await evidenceFile.writeAsString('receipt fixture', flush: true);
      final capturedAt = DateTime.utc(2026, 11, 3, 12);
      final evidence = EvidenceItem(
        id: EvidenceId('backup-production-receipt'),
        type: EvidenceType.receiptImage,
        originalName: 'receipt.txt',
        mediaType: 'text/plain',
        provenance: Provenance(
          id: ProvenanceId('backup-production-receipt-provenance'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: capturedAt,
        ),
        createdAt: capturedAt,
        localFileName: 'receipts/receipt.txt',
      );
      final attached = await finance.storeAndAttachEvidence(
        evidence,
        AttachmentLink(
          id: AttachmentLinkId('backup-production-receipt-link'),
          transactionId: TransactionId('backup-production-expense'),
          evidenceId: evidence.id,
          createdAt: capturedAt,
        ),
      );
      expect(attached, isA<ApplicationSuccess<EvidenceItem>>());

      final rules = SqliteAnalysisRuleRepository(database.persistenceDatabase);
      await finance.ensureAnalysisRules!();
      final userRule = await _installUserRule(rules);
      await rules.activate(
        userRule.identity,
        userRule.version,
        false,
        capturedAt,
      );
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': userRule.identity.value,
        'configuration': '{}',
        'updated_at': capturedAt.toIso8601String(),
      });
      await rules.activate(
        RuleIdentity('ANL-R020'),
        RuleVersion('1.5.0'),
        false,
        capturedAt,
      );

      final categoryDefinition = (await database.database.query(
        'analysis_rule_definitions',
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: ['ANL-R010', '1.1.0'],
        limit: 1,
      )).single;
      final categoryActivation = (await database.database.query(
        'analysis_rule_activations',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
        limit: 1,
      )).single;
      final findingDefinition = (await database.database.query(
        'analysis_rule_definitions',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R026'],
        limit: 1,
      )).single;
      await database.database.insert('analysis_findings', {
        'id': 'backup-production-finding',
        'rule_id': 'ANL-R026',
        'rule_version': findingDefinition['rule_version'],
        'definition_hash': findingDefinition['definition_hash'],
        'period_start': '2026-11-01',
        'period_end': '2026-11-30',
        'time_zone_id': 'UTC',
        'payload': jsonEncode({
          'dimension': 'category.food.groceries',
          'severity': 'info',
          'currentValue': '100',
          'percentageChange': '100',
          'supportingMetrics': const <String>[],
          'evidence': [
            {
              'transactionId': 'backup-production-expense',
              'evidenceId': evidence.id.value,
            },
          ],
          'qualityIssues': const <Object>[],
          'datasetMode': 'allEligible',
          'currencyBasis': 'baseCurrency',
          'baseCurrency': 'USD',
        }),
        'lifecycle': 'acknowledged',
        'generated_at': capturedAt.toIso8601String(),
        'updated_at': capturedAt.toIso8601String(),
      });

      // This is the damaged state that can be left by a partial bundled-rule
      // install: the activation survives, but its definition does not.
      await database.database.delete(
        'analysis_rule_definitions',
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: ['ANL-R010', '1.1.0'],
      );
      expect(
        (await database.database.query(
          'analysis_rule_activations',
          where: 'rule_id = ?',
          whereArgs: ['ANL-R010'],
        )).single,
        categoryActivation,
      );

      final homeAfterDamage = await finance.loadHomeOverview(
        instant: DateTime.utc(2026, 11, 15, 12),
      );
      expect(homeAfterDamage, isA<ApplicationSuccess<HomeOverview>>());
      expect(
        await database.database.query(
          'analysis_rule_definitions',
          where: 'rule_id = ?',
          whereArgs: ['ANL-R010'],
        ),
        isEmpty,
      );

      final diagnosticLogger = _RecordingLogger();
      final diagnosticManager = LocalBackupManager(
        database,
        services<LocalDataManager>(),
        logger: diagnosticLogger,
      );
      final diagnosticDestination = File(
        path.join(temporaryDirectory.path, 'without-recovery.butlerlybackup'),
      );
      await expectLater(
        diagnosticManager.createPortableBackup(
          diagnosticDestination,
          password: 'correct horse battery staple',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        diagnosticLogger.stage,
        'Portable backup failed at stage: backup analysis-rule validation',
      );
      expect(diagnosticLogger.exceptionType, 'FormatException');
      expect(await diagnosticDestination.exists(), isFalse);

      final transactionsBefore = await database.database.query('transactions');
      final budgetsBefore = await database.database.query('budgets');
      final profilesBefore = await database.database.query(
        'financial_profiles',
      );
      final evidenceBefore = await database.database.query('evidence_items');
      final linksBefore = await database.database.query('attachment_links');
      final findingsBefore = await database.database.query('analysis_findings');

      const password = 'correct horse battery staple';
      final workspace = services<WorkspaceDataService>();
      final encryptedPath = await workspace.createTemporaryBackup(
        'production.butlerlybackup',
        password: password,
      );
      final encrypted = File(encryptedPath);
      addTearDown(() => workspace.discardTemporaryBackup(encryptedPath));
      expect(await encrypted.exists(), isTrue);
      expect(
        await services<LocalBackupManager>().isEncryptedBackup(encrypted),
        isTrue,
      );

      final decrypted = File(path.join(root.path, 'decrypted.butlerlybackup'));
      await const BackupEncryption().decrypt(
        encrypted,
        decrypted,
        password: password,
      );
      expect(
        await services<LocalBackupManager>().inspect(
          encrypted,
          password: password,
        ),
        isA<BackupInspection>(),
      );

      expect(await database.database.query('transactions'), transactionsBefore);
      expect(await database.database.query('budgets'), budgetsBefore);
      expect(
        await database.database.query('financial_profiles'),
        profilesBefore,
      );
      expect(await database.database.query('evidence_items'), evidenceBefore);
      expect(await database.database.query('attachment_links'), linksBefore);
      expect(await evidenceFile.readAsString(), 'receipt fixture');
      expect(
        await database.database.query('analysis_findings'),
        findingsBefore,
      );

      final restoredCategory = await database.database.query(
        'analysis_rule_definitions',
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: ['ANL-R010', '1.1.0'],
      );
      expect(restoredCategory, hasLength(1));
      expect(
        restoredCategory.single['definition_hash'],
        categoryDefinition['definition_hash'],
      );
      final restoredCategoryActivation = (await database.database.query(
        'analysis_rule_activations',
        columns: ['active_rule_version', 'enabled'],
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
      )).single;
      expect(
        restoredCategoryActivation['active_rule_version'],
        categoryActivation['active_rule_version'],
      );
      expect(
        restoredCategoryActivation['enabled'],
        categoryActivation['enabled'],
      );
      expect(
        (await database.database.query(
          'analysis_rule_activations',
          columns: ['enabled'],
          where: 'rule_id = ?',
          whereArgs: ['ANL-R020'],
        )).single['enabled'],
        0,
      );
      expect(
        (await database.database.query(
          'analysis_rule_activations',
          columns: ['enabled'],
          where: 'rule_id = ?',
          whereArgs: [userRule.identity.value],
        )).single['enabled'],
        0,
      );
    },
  );
}

final class _RecordingLogger extends AppLogger {
  String? stage;
  String? exceptionType;

  @override
  void severe(String message, Object error, StackTrace? stackTrace) {
    stage = message;
    exceptionType = error.runtimeType.toString();
  }
}

Future<AnalysisRuleDefinition> _installUserRule(
  SqliteAnalysisRuleRepository rules,
) async {
  const source = '''
schemaVersion: "1.0.0"
ruleId: ANL-R777
ruleVersion: "1.0.0"
enabled: true
surface: spending
type: metric
nameKey: analysis.rule.user.name
descriptionKey: analysis.rule.user.description
period: selected_period
grouping: category
measure:
  operation: sum
  field: amount
  currencyBasis: baseCurrency
filters:
  direction: expense
result:
  persistence: materialized
  refresh: onInvalidation
''';
  final parsed = const RestrictedRuleParser().parse(source);
  final validation = const RuleDefinitionValidator().validate(parsed.document!);
  final definition = validation.definition;
  if (definition == null) {
    throw StateError(
      validation.diagnostics.map((value) => value.message).join('; '),
    );
  }
  final canonical = canonicalize(parsed.document!.values);
  await rules.install(
    definition,
    sourceType: 'user',
    canonicalDefinition: canonical,
  );
  return definition;
}
