import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
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
    'production backup continues with missing optional content and excludes derived findings',
    () async {
      final created = await finance.createTransaction(
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
      expect(created, isA<ApplicationSuccess<TransactionDto>>());

      const capturedAt = '2026-11-03T12:00:00.000Z';
      await database.database.insert('provenances', {
        'id': 'backup-production-evidence-provenance',
        'source_type': 'userEntry',
        'captured_at': capturedAt,
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      await database.database.insert('evidence_items', {
        'id': 'backup-production-missing-receipt',
        'type': 'receiptImage',
        'original_name': 'receipt.jpg',
        'media_type': 'image/jpeg',
        'provenance_id': 'backup-production-evidence-provenance',
        'created_at': capturedAt,
        'source_language': null,
        'local_file_name': 'receipts/missing.jpg',
      });
      await database.database.insert('attachment_links', {
        'id': 'backup-production-missing-link',
        'transaction_id': 'backup-production-expense',
        'evidence_id': 'backup-production-missing-receipt',
        'created_at': capturedAt,
      });

      await database.database.insert('analysis_rule_definitions', {
        'rule_id': 'backup-production-rule',
        'rule_version': '1.0.0',
        'schema_version': '1',
        'source_type': 'user',
        'definition': '{}',
        'canonical_definition': '{}',
        'definition_hash': List.filled(64, '0').join(),
        'validation_status': 'valid',
        'validation_diagnostics': null,
        'installed_at': capturedAt,
        'retired_at': null,
      });
      final definition = (await database.database.query(
        'analysis_rule_definitions',
        where: 'rule_id = ?',
        whereArgs: ['backup-production-rule'],
      )).single;
      await database.database.insert('analysis_findings', {
        'id': 'backup-production-derived-finding',
        'rule_id': definition['rule_id'],
        'rule_version': definition['rule_version'],
        'definition_hash': definition['definition_hash'],
        'period_start': '2026-11-01',
        'period_end': '2026-11-30',
        'time_zone_id': 'UTC',
        'payload': jsonEncode({'severity': 'info'}),
        'lifecycle': 'active',
        'generated_at': capturedAt,
        'updated_at': capturedAt,
      });
      await finance.ensureAnalysisRules!();

      final beforeTransactions = await database.database.query('transactions');
      final beforeFindings = await database.database.query('analysis_findings');
      final workspace = services<WorkspaceDataService>();
      const password = 'correct horse battery staple';
      final backupPath = await workspace.createTemporaryBackup(
        'production-missing-content.butlerlybackup',
        password: password,
      );
      addTearDown(() => workspace.discardTemporaryBackup(backupPath));

      final inspection = await workspace.inspect(
        backupPath,
        password: password,
      );
      expect(inspection.warnings, hasLength(1));
      expect(
        inspection.warnings.map((warning) => warning.code),
        contains('missing_receipt'),
      );
      expect(
        inspection.warnings.map((warning) => warning.code),
        isNot(contains('invalid_custom_analysis_rule')),
      );
      final backupDiagnostics = await services<OperationDiagnosticsStore>()
          .recent();
      expect(
        backupDiagnostics.map((diagnostic) => diagnostic.finding.code),
        contains('missing_receipt'),
      );
      expect(
        backupDiagnostics.map((diagnostic) => diagnostic.finding.code),
        isNot(contains('invalid_custom_analysis_rule')),
      );
      final backupReceiptDiagnostic = backupDiagnostics.singleWhere(
        (diagnostic) => diagnostic.finding.code == 'missing_receipt',
      );
      expect(
        backupReceiptDiagnostic.finding.category,
        DataIntegrityFindingCategory.missingReceipt,
      );
      expect(
        backupReceiptDiagnostic.finding.affectedRecords.map(
          (record) => '${record.type}:${record.id}',
        ),
        containsAll(<String>[
          'evidence:backup-production-missing-receipt',
          'transaction:backup-production-expense',
        ]),
      );
      expect(inspection.missingContentCount, 1);
      expect(
        await services<DataIntegrityReportService>().reportHistory(),
        isEmpty,
      );
      expect(await database.database.query('transactions'), beforeTransactions);
      expect(
        await database.database.query('analysis_findings'),
        beforeFindings,
      );

      final report = await services<DataIntegrityReportService>().runReport();
      expect(report.findings, isNotEmpty);
      expect(
        report.findings.map((finding) => finding.code),
        contains('invalid_analysis_rule_definition'),
      );
      expect(
        await services<DataIntegrityReportService>().reportHistory(),
        hasLength(1),
      );
      expect(await database.database.query('transactions'), beforeTransactions);
      expect(
        await database.database.query('analysis_findings'),
        beforeFindings,
      );

      final result = await workspace.restore(
        backupPath,
        mode: LocalRestoreMode.replace,
        password: password,
      );
      expect(result.analysisRebuildFailed, isTrue);
      expect(
        result.warnings.map((warning) => warning.code),
        contains('missing_receipt'),
      );
      expect(
        result.warnings.map((warning) => warning.code),
        isNot(contains('invalid_custom_analysis_rule')),
      );
      final restoreDiagnostics =
          (await services<OperationDiagnosticsStore>().recent())
              .where((diagnostic) => diagnostic.operation == 'restore')
              .toList();
      final restoreReceiptDiagnostic = restoreDiagnostics.singleWhere(
        (diagnostic) => diagnostic.finding.code == 'missing_receipt',
      );
      expect(
        restoreReceiptDiagnostic.finding.category,
        DataIntegrityFindingCategory.missingReceipt,
      );
      expect(
        restoreReceiptDiagnostic.finding.affectedRecords.map(
          (record) => '${record.type}:${record.id}',
        ),
        containsAll(<String>[
          'evidence:backup-production-missing-receipt',
          'transaction:backup-production-expense',
        ]),
      );
      expect(
        restoreDiagnostics.map((diagnostic) => diagnostic.finding.code),
        containsAll(<String>['missing_receipt', 'analysis_rebuild_failed']),
      );
      expect(
        restoreDiagnostics.map((diagnostic) => diagnostic.finding.code),
        isNot(contains('invalid_custom_analysis_rule')),
      );
      expect(
        (await services<OperationDiagnosticsStore>().recent()).every(
          (diagnostic) => diagnostic.operation == 'restore',
        ),
        isTrue,
      );
      expect(
        await services<DataIntegrityReportService>().reportHistory(),
        isEmpty,
      );
      expect(await database.database.query('analysis_findings'), isEmpty);
      expect(
        await database.database.query(
          'evidence_items',
          where: 'id = ?',
          whereArgs: ['backup-production-missing-receipt'],
        ),
        hasLength(1),
      );
      expect(
        await database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['backup-production-expense'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'production backup preserves valid financial records with 77 missing evidence files',
    () async {
      const capturedAt = '2026-11-03T12:00:00.000Z';
      final createdTransactions = <CreateTransactionCommand>[
        CreateTransactionCommand(
          id: 'backup-77-expense',
          provenanceId: 'backup-77-expense-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 1, 12)),
          transactionDate: '2026-11-01',
          money: Money(
            amount: DecimalValue.parse('42.50'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          categoryId: 'category.food.groceries',
        ),
        CreateTransactionCommand(
          id: 'backup-77-income',
          provenanceId: 'backup-77-income-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 2, 12)),
          transactionDate: '2026-11-02',
          money: Money(
            amount: DecimalValue.parse('1200.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.income,
        ),
      ];
      for (final command in createdTransactions) {
        expect(
          await finance.createTransaction(command),
          isA<ApplicationSuccess<TransactionDto>>(),
        );
      }

      await database.database.insert('provenances', {
        'id': 'backup-77-evidence-provenance',
        'source_type': 'userEntry',
        'captured_at': capturedAt,
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      for (var index = 0; index < 77; index++) {
        final evidenceId = 'backup-77-missing-evidence-$index';
        await database.database.insert('evidence_items', {
          'id': evidenceId,
          'type': 'receiptImage',
          'original_name': 'missing-$index.jpg',
          'media_type': 'image/jpeg',
          'provenance_id': 'backup-77-evidence-provenance',
          'created_at': capturedAt,
          'source_language': null,
          'local_file_name': 'receipts/missing-$index.jpg',
        });
        await database.database.insert('attachment_links', {
          'id': 'backup-77-missing-link-$index',
          'transaction_id': index.isEven
              ? 'backup-77-expense'
              : 'backup-77-income',
          'evidence_id': evidenceId,
          'created_at': capturedAt,
        });
      }

      final beforeTransactions = await database.database.query(
        'transactions',
        orderBy: 'id',
      );
      expect(beforeTransactions, hasLength(2));

      final workspace = services<WorkspaceDataService>();
      const password = 'correct horse battery staple';
      final backupPath = await workspace.createTemporaryBackup(
        'production-77-missing-evidence.butlerlybackup',
        password: password,
      );
      addTearDown(() => workspace.discardTemporaryBackup(backupPath));

      final inspection = await workspace.inspect(
        backupPath,
        password: password,
      );
      expect(inspection.missingContentCount, 77);
      final missingEvidenceWarning = inspection.warnings.singleWhere(
        (warning) => warning.code == 'missing_receipt',
      );
      expect(missingEvidenceWarning.count, 77);
      expect(
        missingEvidenceWarning.affectedRecords.where(
          (record) => record.type == 'evidence',
        ),
        hasLength(77),
      );
      expect(
        await database.database.query('transactions', orderBy: 'id'),
        beforeTransactions,
      );

      // Reconstruct the archive into the production database after removing
      // the local transactions. This proves the snapshot retained the valid
      // financial rows while allowing all 77 optional evidence references to
      // remain unresolved.
      await database.database.delete('transactions');
      await workspace.restore(
        backupPath,
        mode: LocalRestoreMode.replace,
        password: password,
      );
      expect(
        await database.database.query('transactions', orderBy: 'id'),
        beforeTransactions,
      );

      final restoredEvidence = await database.database.query(
        'evidence_items',
        where: 'id LIKE ?',
        whereArgs: ['backup-77-missing-evidence-%'],
        orderBy: 'id',
      );
      expect(restoredEvidence, hasLength(77));
      expect(
        restoredEvidence.every(
          (row) =>
              row['local_file_name'] is String &&
              (row['local_file_name']! as String).startsWith(
                'receipts/missing-',
              ),
        ),
        isTrue,
      );
      final restoredLinks = await database.database.query(
        'attachment_links',
        where: 'id LIKE ?',
        whereArgs: ['backup-77-missing-link-%'],
        orderBy: 'id',
      );
      expect(restoredLinks, hasLength(77));

      final report = await services<DataIntegrityReportService>().runReport();
      final missingEvidenceFindings = report.findings
          .where((finding) => finding.code == 'missing_evidence_file')
          .toList();
      expect(missingEvidenceFindings, hasLength(77));
      expect(
        missingEvidenceFindings
            .expand((finding) => finding.affectedRecords)
            .where((record) => record.type == 'evidence'),
        hasLength(77),
      );
    },
  );

  test(
    'merge restore does not bind missing content to unrelated local evidence',
    () async {
      const capturedAt = '2026-11-03T12:00:00.000Z';
      await database.database.insert('provenances', {
        'id': 'backup-production-collision-provenance',
        'source_type': 'userEntry',
        'captured_at': capturedAt,
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      await database.database.insert('evidence_items', {
        'id': 'backup-production-collision-evidence',
        'type': 'receiptImage',
        'original_name': 'collision.txt',
        'media_type': 'text/plain',
        'provenance_id': 'backup-production-collision-provenance',
        'created_at': capturedAt,
        'source_language': null,
        'local_file_name': 'receipts/collision.txt',
      });

      final manager = LocalBackupManager(
        database,
        services<LocalDataManager>(),
      );
      final archive = File(
        path.join(
          temporaryDirectory.path,
          'missing-content-collision.butlerly',
        ),
      );
      await manager.createBackup(archive);

      final unrelated = File(
        path.join(evidenceDirectory.path, 'receipts/collision.txt'),
      )..createSync(recursive: true);
      await unrelated.writeAsString('unrelated local content', flush: true);

      final result = await manager.restore(
        archive,
        mode: LocalRestoreMode.merge,
      );

      expect(
        result.warnings.map((warning) => warning.code),
        contains('missing_receipt'),
      );
      expect(await unrelated.readAsString(), 'unrelated local content');
      final restored =
          (await database.database.query(
                'evidence_items',
                columns: ['local_file_name'],
                where: 'id = ?',
                whereArgs: ['backup-production-collision-evidence'],
              )).single['local_file_name']!
              as String;
      expect(restored, startsWith('unresolved-content/'));
      expect(
        await File(path.join(evidenceDirectory.path, restored)).exists(),
        isFalse,
      );
    },
  );

  test(
    'reports budget scopes whose category hierarchy does not match the scope',
    () async {
      const capturedAt = '2026-11-03T12:00:00.000Z';
      await database.database.insert('categories', {
        'id': 'backup-production-budget-parent',
        'name': 'Budget parent',
        'origin': 'user',
        'parent_id': null,
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('categories', {
        'id': 'backup-production-budget-child',
        'name': 'Budget child',
        'origin': 'user',
        'parent_id': 'backup-production-budget-parent',
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('categories', {
        'id': 'backup-production-budget-nested',
        'name': 'Budget nested',
        'origin': 'user',
        'parent_id': 'backup-production-budget-child',
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('budgets', {
        'id': 'backup-production-invalid-subcategory-budget',
        'scope': 'subcategory',
        'scope_id': 'backup-production-budget-parent',
        'currency': 'USD',
        'amount': '100.00',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('budgets', {
        'id': 'backup-production-invalid-category-budget',
        'scope': 'category',
        'scope_id': 'backup-production-budget-child',
        'currency': 'USD',
        'amount': '50.00',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('budgets', {
        'id': 'backup-production-invalid-nested-subcategory-budget',
        'scope': 'subcategory',
        'scope_id': 'backup-production-budget-nested',
        'currency': 'USD',
        'amount': '25.00',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });

      final beforeBudgets = await database.database.query(
        'budgets',
        orderBy: 'id',
      );
      final beforeCategories = await database.database.query(
        'categories',
        where: 'id LIKE ?',
        whereArgs: ['backup-production-budget-%'],
        orderBy: 'id',
      );
      final manager = LocalBackupManager(
        database,
        services<LocalDataManager>(),
      );
      final archive = File(
        path.join(temporaryDirectory.path, 'invalid-budget-scopes.butlerly'),
      );
      await manager.createBackup(archive);
      final inspection = await manager.inspect(archive);
      expect(inspection.warnings, isEmpty);
      expect(
        inspection.warnings.map((warning) => warning.code),
        isNot(contains('relationship_inconsistency')),
      );
      expect(
        await services<DataIntegrityReportService>().reportHistory(),
        isEmpty,
      );

      final report = await services<DataIntegrityReportService>().runReport();
      final reportFindings = report.findings
          .where((finding) => finding.code == 'invalid_budget_scope_reference')
          .toList();
      expect(reportFindings, hasLength(3));
      expect(
        reportFindings
            .expand((finding) => finding.affectedRecords)
            .map((record) => '${record.type}:${record.id}'),
        containsAll(<String>[
          'budget:backup-production-invalid-subcategory-budget',
          'budget:backup-production-invalid-category-budget',
          'budget:backup-production-invalid-nested-subcategory-budget',
          'category:backup-production-budget-parent',
          'category:backup-production-budget-child',
          'category:backup-production-budget-nested',
        ]),
      );
      expect(
        await database.database.query('budgets', orderBy: 'id'),
        beforeBudgets,
      );
      expect(
        await database.database.query(
          'categories',
          where: 'id LIKE ?',
          whereArgs: ['backup-production-budget-%'],
          orderBy: 'id',
        ),
        beforeCategories,
      );
    },
  );

  test(
    'backup and restore preserve an unresolved relationship without scanning',
    () async {
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'backup-production-orphan-transaction',
          provenanceId: 'backup-production-orphan-transaction-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 3, 12)),
          transactionDate: '2026-11-03',
          money: Money(
            amount: DecimalValue.parse('10.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          categoryId: 'category.food.groceries',
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());

      await database.database.execute('PRAGMA foreign_keys = OFF');
      await database.database.update(
        'transactions',
        {'category_id': 'backup-production-missing-category'},
        where: 'id = ?',
        whereArgs: ['backup-production-orphan-transaction'],
      );
      await database.database.insert('attachment_links', {
        'id': 'backup-production-orphan-attachment',
        'transaction_id': 'backup-production-orphan-transaction',
        'evidence_id': 'backup-production-missing-evidence',
        'created_at': '2026-11-03T12:00:00.000Z',
      });
      await database.database.execute('PRAGMA foreign_keys = ON');

      final manager = LocalBackupManager(
        database,
        services<LocalDataManager>(),
      );
      final archive = File(
        path.join(temporaryDirectory.path, 'legacy-orphan.butlerly'),
      );
      await manager.createBackup(archive);

      final inspection = await manager.inspect(archive);
      expect(inspection.warnings, isEmpty);
      expect(
        inspection.warnings.map((warning) => warning.code),
        isNot(contains('missing_referenced_record')),
      );
      expect(
        await services<DataIntegrityReportService>().reportHistory(),
        isEmpty,
      );

      final result = await manager.restore(
        archive,
        mode: LocalRestoreMode.replace,
      );
      expect(result.warnings, isEmpty);
      expect(result.preservesUnresolvedReferences, isTrue);
      final beforeReport = await database.database.query(
        'attachment_links',
        where: 'id = ?',
        whereArgs: ['backup-production-orphan-attachment'],
      );
      expect(beforeReport, hasLength(1));
      expect(
        await database.database.rawQuery('PRAGMA foreign_key_check'),
        hasLength(2),
      );

      final report = await services<DataIntegrityReportService>().runReport();
      final finding = report.findings.singleWhere(
        (value) => value.code == 'missing_referenced_record',
      );
      expect(
        finding.affectedRecords.any(
          (record) =>
              record.type == 'attachment' &&
              record.id == 'backup-production-orphan-attachment',
        ),
        isTrue,
      );
      expect(
        finding.affectedRecords.any(
          (record) =>
              record.type == 'transaction' &&
              record.id == 'backup-production-orphan-transaction',
        ),
        isTrue,
      );
      expect(
        await database.database.query(
          'attachment_links',
          where: 'id = ?',
          whereArgs: ['backup-production-orphan-attachment'],
        ),
        beforeReport,
      );
    },
  );

  test(
    'backup preserves cyclic user categories without relationship scanning',
    () async {
      const capturedAt = '2026-11-03T12:00:00.000Z';
      await database.database.execute('PRAGMA foreign_keys = OFF');
      await database.database.insert('categories', {
        'id': 'backup-production-cycle-a',
        'name': 'Cycle A',
        'origin': 'user',
        'parent_id': 'backup-production-cycle-b',
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('categories', {
        'id': 'backup-production-cycle-b',
        'name': 'Cycle B',
        'origin': 'user',
        'parent_id': 'backup-production-cycle-a',
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.execute('PRAGMA foreign_keys = ON');

      final before = await database.database.query(
        'categories',
        where: 'id LIKE ?',
        whereArgs: ['backup-production-cycle-%'],
        orderBy: 'id',
      );
      final manager = LocalBackupManager(
        database,
        services<LocalDataManager>(),
      );
      final archive = File(
        path.join(temporaryDirectory.path, 'cyclic-categories.butlerly'),
      );

      await manager.createBackup(archive);
      expect((await manager.inspect(archive)).warnings, isEmpty);
      expect(
        await database.database.query(
          'categories',
          where: 'id LIKE ?',
          whereArgs: ['backup-production-cycle-%'],
          orderBy: 'id',
        ),
        before,
      );

      await manager.restore(archive, mode: LocalRestoreMode.replace);
      expect(
        await database.database.query(
          'categories',
          where: 'id LIKE ?',
          whereArgs: ['backup-production-cycle-%'],
          orderBy: 'id',
        ),
        before,
      );
    },
  );

  test(
    'restore does not reject a user rule colliding with a bundled identity',
    () async {
      final workspace = services<WorkspaceDataService>();
      final rules = SqliteAnalysisRuleRepository(database.persistenceDatabase);

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

  test(
    'restore keeps live missing evidence references without failing',
    () async {
      const provenanceId =
          'backup-production-restore-missing-evidence-provenance';
      const localFileName = 'receipts/restore-missing-evidence.txt';
      final capturedAt = DateTime.utc(2026, 11, 3, 12);
      final evidenceFile = File(
        path.join(evidenceDirectory.path, localFileName),
      )..createSync(recursive: true);
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

      final restoreManager = LocalBackupManager(
        database,
        services<LocalDataManager>(),
      );
      final result = await restoreManager.restore(
        archive,
        mode: LocalRestoreMode.replace,
        password: 'correct horse battery staple',
        postActivationRefresh: () async {},
      );
      expect(result, isA<LocalRestoreResult>());
      expect(await database.database.query('evidence_items'), sourceRows);
      expect(await evidenceFile.exists(), isTrue);
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
