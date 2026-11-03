import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
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
    'production backup stays read-only until explicit rule repair',
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

      // Continue with the same on-disk database after a close/reopen boundary.
      // This exercises the existing-install path rather than only an
      // in-memory or newly created database.
      await services.reset();
      await database.close();
      database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: databaseDirectory.path,
      );
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );
      finance = services<FinanceServices>();

      final rules = SqliteAnalysisRuleRepository(database.persistenceDatabase);
      await services<WorkspaceDataService>().repairAnalysisRules();
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

      // Synthetic partial-install fixture for the repair/rollback contract.
      // This test is not evidence that the affected iPhone had this state;
      // the protected device copy is diagnosed separately.
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
        throwsA(
          predicate<BackupAnalysisRuleValidationException>(
            (error) => error.canRepair,
          ),
        ),
      );
      expect(
        diagnosticLogger.stage,
        'Portable backup failed at stage: backup analysis-rule validation',
      );
      expect(
        diagnosticLogger.exceptionType,
        'BackupAnalysisRuleValidationException',
      );
      expect(await diagnosticDestination.exists(), isFalse);

      final transactionsBefore = await database.database.query('transactions');
      final budgetsBefore = await database.database.query('budgets');
      final profilesBefore = await database.database.query(
        'financial_profiles',
      );
      final evidenceBefore = await database.database.query('evidence_items');
      final linksBefore = await database.database.query('attachment_links');
      final findingsBefore = await database.database.query('analysis_findings');
      final ruleDefinitionsBefore = await database.database.query(
        'analysis_rule_definitions',
        orderBy: 'rule_id, rule_version',
      );
      final ruleProvenanceBefore = await database.database.query(
        'analysis_rule_provenance',
        orderBy: 'rule_id, rule_version',
      );
      final ruleActivationsBefore = await database.database.query(
        'analysis_rule_activations',
        orderBy: 'rule_id',
      );
      final ruleConfigurationsBefore = await database.database.query(
        'analysis_rule_configurations',
        orderBy: 'rule_id',
      );

      const password = 'correct horse battery staple';
      final workspace = services<WorkspaceDataService>();
      await expectLater(
        workspace.createTemporaryBackup(
          'without-explicit-repair.butlerlybackup',
          password: password,
        ),
        throwsA(
          predicate<BackupAnalysisRuleValidationException>(
            (error) => error.canRepair,
          ),
        ),
      );
      expect(await database.database.query('transactions'), transactionsBefore);
      expect(await database.database.query('budgets'), budgetsBefore);
      expect(
        await database.database.query('financial_profiles'),
        profilesBefore,
      );
      expect(await database.database.query('evidence_items'), evidenceBefore);
      expect(await database.database.query('attachment_links'), linksBefore);
      expect(
        await database.database.query('analysis_findings'),
        findingsBefore,
      );
      expect(
        await database.database.query(
          'analysis_rule_definitions',
          where: 'rule_id = ?',
          whereArgs: ['ANL-R010'],
        ),
        isEmpty,
      );
      expect(
        await database.database.query(
          'analysis_rule_definitions',
          orderBy: 'rule_id, rule_version',
        ),
        ruleDefinitionsBefore,
      );
      expect(
        await database.database.query(
          'analysis_rule_provenance',
          orderBy: 'rule_id, rule_version',
        ),
        ruleProvenanceBefore,
      );
      expect(
        await database.database.query(
          'analysis_rule_activations',
          orderBy: 'rule_id',
        ),
        ruleActivationsBefore,
      );
      expect(
        await database.database.query(
          'analysis_rule_configurations',
          orderBy: 'rule_id',
        ),
        ruleConfigurationsBefore,
      );

      await workspace.repairAnalysisRules();

      // The bundled installer restores missing definitions and activations,
      // but it does not repair malformed user configuration. The backup UI
      // must therefore keep the neutral failure message for this case.
      await database.database.delete(
        'analysis_rule_configurations',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
      );
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': 'ANL-R010',
        'configuration': '{invalid-json',
        'updated_at': capturedAt.toIso8601String(),
      });
      BackupAnalysisRuleValidationException? configurationError;
      try {
        await workspace.createTemporaryBackup(
          'invalid-bundled-configuration.butlerlybackup',
          password: password,
        );
        fail('Malformed bundled configuration should fail backup validation.');
      } on BackupAnalysisRuleValidationException catch (error) {
        configurationError = error;
      }
      expect(configurationError, isNotNull);
      expect(configurationError.canRepair, isFalse);
      await database.database.delete(
        'analysis_rule_configurations',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
      );
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
      expect(
        await database.database.query(
          'analysis_rule_provenance',
          orderBy: 'rule_id, rule_version',
        ),
        ruleProvenanceBefore,
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
      final preservedUserDefinition = (await database.database.query(
        'analysis_rule_definitions',
        columns: ['source_type', 'definition_hash'],
        where: 'rule_id = ?',
        whereArgs: [userRule.identity.value],
      )).single;
      expect(preservedUserDefinition['source_type'], 'user');
      expect(
        preservedUserDefinition['definition_hash'],
        userRule.definitionHash.value,
      );

      final restoredRoot = await Directory.systemTemp.createTemp(
        'butlerly-backup-restored-',
      );
      final restoredDatabaseDirectory = Directory(
        path.join(restoredRoot.path, 'database'),
      )..createSync(recursive: true);
      final restoredEvidenceDirectory = Directory(
        path.join(restoredRoot.path, 'evidence'),
      )..createSync(recursive: true);
      final restoredDocumentsDirectory = Directory(
        path.join(restoredRoot.path, 'documents'),
      )..createSync(recursive: true);
      final restoredDatabase = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: restoredDatabaseDirectory.path,
      );
      await restoredDatabase.initialize();
      final restoredDataManager = LocalDataManager(
        restoredDatabase,
        documentsDirectory: restoredDocumentsDirectory,
        localEvidenceDirectory: restoredEvidenceDirectory,
      );
      final restoredManager = LocalBackupManager(
        restoredDatabase,
        restoredDataManager,
      );
      final restoredWorkspace = WorkspaceDataService(
        LocalWorkspaceDataGateway(restoredManager, restoredDataManager),
        refreshSystemData: () async {},
      );
      addTearDown(() async {
        await restoredDatabase.close();
        await restoredRoot.delete(recursive: true);
      });

      await restoredWorkspace.restore(
        encrypted.path,
        mode: LocalRestoreMode.replace,
        password: password,
      );
      expect(
        await restoredDatabase.database.query(
          'transactions',
          where: 'id IN (?, ?)',
          whereArgs: ['backup-production-expense', 'backup-production-income'],
        ),
        hasLength(2),
      );
      expect(
        await restoredDatabase.database.query(
          'analysis_rule_definitions',
          where: 'rule_id = ? AND rule_version = ?',
          whereArgs: ['ANL-R010', '1.1.0'],
        ),
        hasLength(1),
      );
      expect(
        await restoredDatabase.database.query(
          'analysis_rule_provenance',
          where: 'rule_id = ? AND rule_version = ?',
          whereArgs: ['ANL-R010', '1.1.0'],
        ),
        contains(containsPair('source_type', 'bundled')),
      );
      expect(
        await restoredDatabase.database.query(
          'budgets',
          where: 'id = ?',
          whereArgs: ['backup-production-budget'],
        ),
        hasLength(1),
      );
      expect(
        await restoredDatabase.database.query('financial_profiles'),
        hasLength(1),
      );
      expect(
        await restoredDatabase.database.query(
          'attachment_links',
          where: 'id = ?',
          whereArgs: ['backup-production-receipt-link'],
        ),
        hasLength(1),
      );
      expect(
        await restoredDatabase.database.query(
          'analysis_findings',
          where: 'id = ?',
          whereArgs: ['backup-production-finding'],
        ),
        hasLength(1),
      );
      expect(
        (await restoredDatabase.database.query(
          'analysis_rule_activations',
          columns: ['enabled'],
          where: 'rule_id = ?',
          whereArgs: [userRule.identity.value],
        )).single['enabled'],
        0,
      );
      final restoredUserDefinition = (await restoredDatabase.database.query(
        'analysis_rule_definitions',
        columns: ['source_type', 'definition_hash'],
        where: 'rule_id = ?',
        whereArgs: [userRule.identity.value],
      )).single;
      expect(restoredUserDefinition['source_type'], 'user');
      expect(
        restoredUserDefinition['definition_hash'],
        userRule.definitionHash.value,
      );
      final restoredUserConfiguration = (await restoredDatabase.database.query(
        'analysis_rule_configurations',
        columns: ['configuration'],
        where: 'rule_id = ?',
        whereArgs: [userRule.identity.value],
      )).single;
      expect(restoredUserConfiguration['configuration'], '{}');
      expect(
        File(
          path.join(restoredEvidenceDirectory.path, 'receipts', 'receipt.txt'),
        ).readAsStringSync(),
        'receipt fixture',
      );

      const unresolvedOperationId = 'unresolved-external-publication';
      final unresolvedRecovery = BackupPublicationRecovery(
        operationId: unresolvedOperationId,
        sourcePath: path.join(
          databaseDirectory.path,
          '.portable-backup-encrypted-$unresolvedOperationId.butlerlybackup',
        ),
        destinationPath: path.join(
          root.path,
          'external-destination',
          'portable.butlerlybackup',
        ),
        previousPath: path.join(
          databaseDirectory.path,
          '.portable-backup-previous-$unresolvedOperationId.butlerlybackup',
        ),
        hadExistingDestination: false,
        previousReady: false,
      );
      await const FileBackupPublicationRecoveryStore().write(
        databaseDirectory,
        unresolvedRecovery,
      );
      final temporaryPath = await workspace.createTemporaryBackup(
        'temporary-with-unresolved-external-marker.butlerlybackup',
        password: password,
      );
      addTearDown(() => workspace.discardTemporaryBackup(temporaryPath));
      expect(await File(temporaryPath).exists(), isTrue);
      expect(
        services<LocalBackupManager>()
            .publicationRecoveryState
            .isRecoveryRequired,
        isFalse,
      );
      expect(
        await FileBackupPublicationRecoveryStore.markerFile(
          databaseDirectory,
          unresolvedOperationId,
        ).exists(),
        isTrue,
      );

      final temporaryDestinationDirectory = Directory(
        path.join(
          temporaryDirectory.path,
          'temporary-publication-failure.butlerlybackup',
        ),
      )..createSync(recursive: true);
      BackupStorageException? temporaryPublicationError;
      try {
        await workspace.createTemporaryBackup(
          'temporary-publication-failure.butlerlybackup',
          password: password,
        );
        fail('Temporary publication failure should be reported as storage.');
      } on BackupStorageException catch (error) {
        temporaryPublicationError = error;
      } finally {
        if (temporaryDestinationDirectory.existsSync()) {
          temporaryDestinationDirectory.deleteSync(recursive: true);
        }
      }
      expect(temporaryPublicationError, isNotNull);
      expect(
        services<LocalBackupManager>()
            .publicationRecoveryState
            .isRecoveryRequired,
        isFalse,
      );

      messenger.setMockMethodCallHandler(
        pathProviderChannel,
        (_) async => throw PlatformException(code: 'temporary_directory'),
      );
      BackupStorageException? temporaryDirectoryError;
      try {
        await workspace.createTemporaryBackup(
          'temporary-directory-failure.butlerlybackup',
          password: password,
        );
        fail('Temporary-directory failure should be reported as storage.');
      } on BackupStorageException catch (error) {
        temporaryDirectoryError = error;
      }
      expect(temporaryDirectoryError, isNotNull);
    },
  );

  test(
    'restore does not reject a user rule colliding with a bundled identity',
    () async {
      final workspace = services<WorkspaceDataService>();
      final rules = SqliteAnalysisRuleRepository(database.persistenceDatabase);
      await workspace.repairAnalysisRules();

      final bundled = await rootBundle.loadString(
        'assets/analysis_rules/metrics/ANL-R010.yaml',
      );
      final custom = bundled.replaceFirst(
        'descriptionKey: analysis.rule.r010.description',
        'descriptionKey: custom.rule.r010.description',
      );
      final parsed = const RestrictedRuleParser().parse(custom);
      final validation = const RuleDefinitionValidator().validate(
        parsed.document!,
      );
      final customDefinition = validation.definition!;
      await database.database.delete(
        'analysis_rule_configurations',
        where: 'rule_id = ?',
        whereArgs: [customDefinition.identity.value],
      );
      await database.database.delete(
        'analysis_rule_activations',
        where: 'rule_id = ?',
        whereArgs: [customDefinition.identity.value],
      );
      await database.database.delete(
        'analysis_rule_provenance',
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: [
          customDefinition.identity.value,
          customDefinition.version.value,
        ],
      );
      await database.database.delete(
        'analysis_rule_definitions',
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: [
          customDefinition.identity.value,
          customDefinition.version.value,
        ],
      );
      await rules.install(
        customDefinition,
        sourceType: 'user',
        canonicalDefinition: canonicalize(parsed.document!.values),
      );
      await rules.activate(
        customDefinition.identity,
        customDefinition.version,
        true,
        DateTime.utc(2026, 11, 5),
      );
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': customDefinition.identity.value,
        'configuration': '{"custom":true}',
        'updated_at': '2026-11-05T00:00:00.000Z',
      });

      final backup = File(
        path.join(temporaryDirectory.path, 'custom-collision.butlerlybackup'),
      );
      const password = 'correct horse battery staple';
      await workspace.createPortableBackup(backup.path, password: password);

      await workspace.restore(
        backup.path,
        mode: LocalRestoreMode.replace,
        password: password,
      );

      final restoredDefinition = (await database.database.query(
        'analysis_rule_definitions',
        columns: ['source_type', 'definition_hash'],
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: [
          customDefinition.identity.value,
          customDefinition.version.value,
        ],
      )).single;
      expect(restoredDefinition['source_type'], 'user');
      expect(
        restoredDefinition['definition_hash'],
        customDefinition.definitionHash.value,
      );
      expect(
        (await database.database.query(
          'analysis_rule_provenance',
          where: 'rule_id = ? AND rule_version = ?',
          whereArgs: [
            customDefinition.identity.value,
            customDefinition.version.value,
          ],
        )).single['source_type'],
        'user',
      );
      expect(
        (await database.database.query(
          'analysis_rule_configurations',
          columns: ['configuration'],
          where: 'rule_id = ?',
          whereArgs: [customDefinition.identity.value],
        )).single['configuration'],
        '{"custom":true}',
      );
    },
  );

  test(
    'rule repair fails atomically when persisted bundled provenance is unknown',
    () async {
      final workspace = services<WorkspaceDataService>();
      await database.database.insert('analysis_rule_provenance', {
        'rule_id': 'ANL-R998',
        'rule_version': '1.0.0',
        'source_type': 'bundled',
        'definition_hash': List.filled(64, 'a').join(),
        'recorded_at': '2026-11-05T00:00:00.000Z',
      });

      await expectLater(
        workspace.repairAnalysisRules(),
        throwsA(isA<StateError>()),
      );
      expect(
        await database.database.query(
          'analysis_rule_definitions',
          where: 'rule_id = ?',
          whereArgs: ['ANL-R001'],
        ),
        isEmpty,
      );
      expect(
        await database.database.query(
          'analysis_rule_provenance',
          where: 'rule_id = ?',
          whereArgs: ['ANL-R998'],
        ),
        hasLength(1),
      );
    },
  );

  test('reports generic archive inspection failures accurately', () async {
    // The database schema permits these legacy enum columns, while the
    // portable-backup contract rejects unknown values. This reaches the
    // production snapshot/decrypt/inspect path without manufacturing a
    // malformed archive or changing the backup engine's integrity checks.
    await database.database.insert('payment_sources', {
      'id': 'backup-production-invalid-payment-source',
      'name': 'Invalid fixture',
      'type': 'unsupported-type',
      'status': 'unsupported-status',
      'created_at': '2026-11-03T12:00:00.000Z',
      'updated_at': '2026-11-03T12:00:00.000Z',
    });

    final diagnosticLogger = _RecordingLogger();
    final diagnosticManager = LocalBackupManager(
      database,
      services<LocalDataManager>(),
      logger: diagnosticLogger,
    );
    final destination = File(
      path.join(
        temporaryDirectory.path,
        'invalid-archive-content.butlerlybackup',
      ),
    );

    await expectLater(
      diagnosticManager.createPortableBackup(
        destination,
        password: 'correct horse battery staple',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      diagnosticLogger.stage,
      'Portable backup failed at stage: backup archive inspection',
    );
    expect(diagnosticLogger.exceptionType, 'FormatException');
    expect(await destination.exists(), isFalse);
  });

  test('reports missing evidence during collection accurately', () async {
    const provenanceId = 'backup-production-missing-evidence-provenance';
    await database.database.insert('provenances', {
      'id': provenanceId,
      'source_type': 'userEntry',
      'captured_at': '2026-11-03T12:00:00.000Z',
      'source_id': null,
      'original_representation': null,
      'source_language': null,
    });
    await database.database.insert('evidence_items', {
      'id': 'backup-production-missing-evidence',
      'type': 'receiptImage',
      'original_name': 'missing-receipt.pdf',
      'media_type': 'application/pdf',
      'provenance_id': provenanceId,
      'created_at': '2026-11-03T12:00:00.000Z',
      'source_language': null,
      'local_file_name': 'receipts/missing-receipt.pdf',
    });

    final diagnosticLogger = _RecordingLogger();
    final diagnosticManager = LocalBackupManager(
      database,
      services<LocalDataManager>(),
      logger: diagnosticLogger,
    );
    final destination = File(
      path.join(temporaryDirectory.path, 'missing-evidence.butlerlybackup'),
    );

    await expectLater(
      diagnosticManager.createPortableBackup(
        destination,
        password: 'correct horse battery staple',
      ),
      throwsA(
        isA<BackupFailureException>()
            .having((error) => error.stage, 'stage', 'evidence collection')
            .having((error) => error.errorType, 'error type', 'StateError'),
      ),
    );
    expect(
      diagnosticLogger.stage,
      'Portable backup failed at stage: evidence collection',
    );
    expect(diagnosticLogger.exceptionType, 'StateError');
    expect(await destination.exists(), isFalse);
  });

  test(
    'explicit evidence recovery restores a protected copy without SQLite writes',
    () async {
      const provenanceId = 'backup-production-evidence-recovery-provenance';
      const evidenceId = 'backup-production-evidence-recovery';
      const localFileName = 'receipts/recoverable-receipt.txt';
      final capturedAt = DateTime.utc(2026, 11, 3, 12);
      final evidenceFile = File(
        path.join(evidenceDirectory.path, localFileName),
      )..createSync(recursive: true);
      await evidenceFile.writeAsString('protected receipt copy', flush: true);
      await database.database.insert('provenances', {
        'id': provenanceId,
        'source_type': 'userEntry',
        'captured_at': capturedAt.toIso8601String(),
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      await database.database.insert('evidence_items', {
        'id': evidenceId,
        'type': 'receiptImage',
        'original_name': 'recoverable-receipt.txt',
        'media_type': 'text/plain',
        'provenance_id': provenanceId,
        'created_at': capturedAt.toIso8601String(),
        'source_language': null,
        'local_file_name': localFileName,
      });
      await finance.createTransaction(
        CreateTransactionCommand(
          id: 'backup-production-evidence-recovery-transaction',
          provenanceId: provenanceId,
          timing: KnownTransactionTime(capturedAt),
          transactionDate: '2026-11-03',
          money: Money(
            amount: DecimalValue.parse('24.50'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          categoryId: 'category.food.groceries',
        ),
      );

      const password = 'correct horse battery staple';
      final archive = File(
        path.join(temporaryDirectory.path, 'protected-copy.butlerlybackup'),
      );
      await services<LocalBackupManager>().createPortableBackup(
        archive,
        password: password,
      );
      final sourceEvidenceRows = await database.database.query(
        'evidence_items',
      );
      final sourceRuleRows = await database.database.query(
        'analysis_rule_definitions',
      );
      final sourceTransactionRows = await database.database.query(
        'transactions',
      );
      await evidenceFile.delete();

      final result = await services<LocalBackupManager>()
          .recoverMissingEvidence(archive, password: password);

      expect(result.recoveredCount, 1);
      expect(result.alreadyPresentCount, 0);
      expect(result.unresolvedCount, 0);
      expect(await evidenceFile.readAsString(), 'protected receipt copy');
      expect(
        await database.database.query('evidence_items'),
        sourceEvidenceRows,
      );
      expect(
        await database.database.query('analysis_rule_definitions'),
        sourceRuleRows,
      );
      expect(
        await database.database.query('transactions'),
        sourceTransactionRows,
      );

      // The protected copy is usable through all three production paths after
      // evidence recovery: a new backup, Merge, and Replace.
      final recoveredArchive = File(
        path.join(temporaryDirectory.path, 'recovered-copy.butlerly'),
      );
      await services<LocalBackupManager>().createPortableBackup(
        recoveredArchive,
        password: password,
      );
      await services<LocalBackupManager>().restore(
        recoveredArchive,
        mode: LocalRestoreMode.merge,
        password: password,
        postActivationRefresh: () async {},
      );
      await services<LocalBackupManager>().restore(
        recoveredArchive,
        mode: LocalRestoreMode.replace,
        password: password,
        postActivationRefresh: () async {},
      );
      expect(
        await database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['backup-production-evidence-recovery-transaction'],
        ),
        hasLength(1),
      );
      expect(await evidenceFile.readAsString(), 'protected receipt copy');
    },
  );

  test('evidence recovery never overwrites a conflicting live file', () async {
    const provenanceId = 'backup-production-evidence-conflict-provenance';
    const localFileName = 'receipts/conflicting-receipt.txt';
    final capturedAt = DateTime.utc(2026, 11, 3, 12);
    final evidenceFile = File(path.join(evidenceDirectory.path, localFileName))
      ..createSync(recursive: true);
    await evidenceFile.writeAsString('original bytes', flush: true);
    await database.database.insert('provenances', {
      'id': provenanceId,
      'source_type': 'userEntry',
      'captured_at': capturedAt.toIso8601String(),
      'source_id': null,
      'original_representation': null,
      'source_language': null,
    });
    await database.database.insert('evidence_items', {
      'id': 'backup-production-evidence-conflict',
      'type': 'receiptImage',
      'original_name': 'conflicting-receipt.txt',
      'media_type': 'text/plain',
      'provenance_id': provenanceId,
      'created_at': capturedAt.toIso8601String(),
      'source_language': null,
      'local_file_name': localFileName,
    });
    final archive = File(
      path.join(temporaryDirectory.path, 'conflicting-copy.butlerlybackup'),
    );
    await services<LocalBackupManager>().createBackup(archive);
    await evidenceFile.writeAsString('user replacement bytes', flush: true);

    final result = await services<LocalBackupManager>().recoverMissingEvidence(
      archive,
    );

    expect(result.recoveredCount, 0);
    expect(result.unresolvedCount, 1);
    expect(await evidenceFile.readAsString(), 'user replacement bytes');
  });

  test(
    'evidence recovery reports unresolved rows without discarding verified files',
    () async {
      const firstProvenance = 'backup-production-partial-first-provenance';
      const secondProvenance = 'backup-production-partial-second-provenance';
      const firstPath = 'receipts/partial-first.txt';
      const secondPath = 'receipts/partial-second.txt';
      final capturedAt = DateTime.utc(2026, 11, 3, 12);
      final firstFile = File(path.join(evidenceDirectory.path, firstPath))
        ..createSync(recursive: true);
      await firstFile.writeAsString('recoverable', flush: true);
      await database.database.insert('provenances', {
        'id': firstProvenance,
        'source_type': 'userEntry',
        'captured_at': capturedAt.toIso8601String(),
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      await database.database.insert('evidence_items', {
        'id': 'backup-production-partial-first',
        'type': 'receiptImage',
        'original_name': 'partial-first.txt',
        'media_type': 'text/plain',
        'provenance_id': firstProvenance,
        'created_at': capturedAt.toIso8601String(),
        'source_language': null,
        'local_file_name': firstPath,
      });
      final archive = File(
        path.join(temporaryDirectory.path, 'partial-copy.butlerlybackup'),
      );
      await services<LocalBackupManager>().createBackup(archive);

      await database.database.insert('provenances', {
        'id': secondProvenance,
        'source_type': 'userEntry',
        'captured_at': capturedAt.toIso8601String(),
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      await database.database.insert('evidence_items', {
        'id': 'backup-production-partial-second',
        'type': 'receiptImage',
        'original_name': 'partial-second.txt',
        'media_type': 'text/plain',
        'provenance_id': secondProvenance,
        'created_at': capturedAt.toIso8601String(),
        'source_language': null,
        'local_file_name': secondPath,
      });
      await firstFile.delete();

      final result = await services<LocalBackupManager>()
          .recoverMissingEvidence(archive);

      expect(result.recoveredCount, 1);
      expect(result.unresolvedCount, 1);
      expect(await firstFile.readAsString(), 'recoverable');
      expect(
        await File(path.join(evidenceDirectory.path, secondPath)).exists(),
        isFalse,
      );
    },
  );

  test('reports generic inspection failures accurately', () async {
    final archive = File(
      path.join(temporaryDirectory.path, 'invalid-inspection.butlerlybackup'),
    )..writeAsStringSync('not a Butlerly backup');
    final diagnosticLogger = _RecordingLogger();
    final diagnosticManager = LocalBackupManager(
      database,
      services<LocalDataManager>(),
      logger: diagnosticLogger,
    );

    await expectLater(
      diagnosticManager.inspect(archive),
      throwsA(isA<FormatException>()),
    );
    expect(
      diagnosticLogger.stage,
      'Backup inspection failed at stage: archive inspection',
    );
    expect(diagnosticLogger.exceptionType, 'FormatException');
  });

  test('reports missing live evidence during restore safety backup', () async {
    const provenanceId =
        'backup-production-restore-missing-evidence-provenance';
    const localFileName = 'receipts/restore-missing-evidence.txt';
    final capturedAt = DateTime.utc(2026, 11, 3, 12);
    final evidenceFile = File(path.join(evidenceDirectory.path, localFileName))
      ..createSync(recursive: true);
    await evidenceFile.writeAsString('restore evidence fixture', flush: true);
    await database.database.insert('provenances', {
      'id': provenanceId,
      'source_type': 'userEntry',
      'captured_at': capturedAt.toIso8601String(),
      'source_id': null,
      'original_representation': null,
      'source_language': null,
    });
    await database.database.insert('evidence_items', {
      'id': 'backup-production-restore-missing-evidence',
      'type': 'receiptImage',
      'original_name': 'restore-missing-evidence.txt',
      'media_type': 'text/plain',
      'provenance_id': provenanceId,
      'created_at': capturedAt.toIso8601String(),
      'source_language': null,
      'local_file_name': localFileName,
    });

    final archive = File(
      path.join(
        temporaryDirectory.path,
        'restore-missing-evidence.butlerlybackup',
      ),
    );
    final sourceRows = await database.database.query('evidence_items');
    final sourceManager = LocalBackupManager(
      database,
      services<LocalDataManager>(),
    );
    await sourceManager.createPortableBackup(
      archive,
      password: 'correct horse battery staple',
    );
    await evidenceFile.delete();

    final diagnosticLogger = _RecordingLogger();
    final restoreManager = LocalBackupManager(
      database,
      services<LocalDataManager>(),
      logger: diagnosticLogger,
    );
    await expectLater(
      restoreManager.restore(
        archive,
        mode: LocalRestoreMode.replace,
        password: 'correct horse battery staple',
        postActivationRefresh: () async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      diagnosticLogger.stage,
      'Restore failed at stage: pre-restore safety backup: evidence collection',
    );
    expect(diagnosticLogger.exceptionType, 'StateError');
    expect(await database.database.query('evidence_items'), sourceRows);
    expect(await evidenceFile.exists(), isFalse);
  });
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
