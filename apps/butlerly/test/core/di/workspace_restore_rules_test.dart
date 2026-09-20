import 'dart:io';

import 'package:butlerly/core/analysis/bundled_analysis_rules.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory root;
  late LocalDatabase database;
  late SqliteAnalysisRuleRepository rules;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    await services.reset();
    root = await Directory.systemTemp.createTemp('butlerly-restore-rules-');
    messenger.setMockMethodCallHandler(channel, (_) async => root.path);
    final logger = AppLogger();
    database = LocalDatabase(
      logger: logger,
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: logger,
    );
    rules = SqliteAnalysisRuleRepository(database.persistenceDatabase);
    await SqliteUserPreferenceRepository(database.persistenceDatabase).save(
      UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
      ),
    );
    final timestamp = DateTime.utc(2026, 9, 1);
    await SqliteTransactionRepository(database.persistenceDatabase).save(
      Transaction(
        id: TransactionId('restored-expense'),
        timing: const UnknownTransactionTime(
          UnknownTransactionTimeReason.unknown,
        ),
        transactionDate: '2026-09-01',
        money: Money(
          amount: DecimalValue.parse('12.34'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        provenance: [
          Provenance(
            id: ProvenanceId('origin'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: timestamp,
          ),
        ],
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  });
  tearDown(() async {
    await services.reset();
    await database.close();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  Future<File> legacyBackup({bool disableCount = false}) async {
    // Exact historical definitions from commit 808305e, before semantic roles.
    final sources = <String, String>{};
    for (var index = 1; index <= 4; index++) {
      final file = File(
        'test/fixtures/legacy_analysis_rules/ANL-R00$index.yaml',
      );
      sources[file.path] = await file.readAsString();
    }
    final installed = await InstallBuiltInRules(rules)(sources);
    expect(installed.diagnostics, isEmpty);
    expect(
      (await rules.listActive()).every((rule) => rule.role == null),
      isTrue,
    );
    if (disableCount) {
      final id = RuleIdentity('ANL-R004');
      final activation = (await rules.existingActivation(id))!;
      await rules.activate(
        id,
        activation.version,
        false,
        DateTime.now().toUtc(),
      );
    }
    final backup = File('${root.path}/legacy.butlerlybackup');
    await services<LocalBackupManager>().createBackup(backup);
    return backup;
  }

  Future<void> expectSummary() async {
    final evaluation = await services<FinanceServices>()
        .calculateAnalysisOverview!
        .currentMonth(DateTime.utc(2026, 9, 10));
    expect(evaluation, isA<ApplicationSuccess<List<RuleExecutionResult>>>());
    final overview = AnalysisOverview.fromResults(
      (evaluation as ApplicationSuccess<List<RuleExecutionResult>>).value,
    );
    expect(overview.spending?.value.toString(), '12.34');
    expect(overview.income?.value.toString(), '0');
    expect(overview.net?.value.toString(), '-12.34');
    expect(overview.transactionCount?.value.toString(), '1');
  }

  for (final mode in LocalRestoreMode.values) {
    test(
      '$mode restore activates current rules before UI refresh without restart',
      () async {
        final backup = await legacyBackup();
        final historical = await database.database.query(
          'analysis_rule_definitions',
        );
        await installBundledAnalysisRules(InstallBuiltInRules(rules));
        await services<WorkspaceDataService>().restore(
          backup.path,
          mode: mode,
          refreshPresentation: expectSummary,
        );
        await expectSummary();
        for (final old in historical) {
          final persisted = await database.database.query(
            'analysis_rule_definitions',
            where: 'rule_id = ? AND rule_version = ?',
            whereArgs: [old['rule_id'], old['rule_version']],
          );
          expect(
            persisted.single['canonical_definition'],
            old['canonical_definition'],
          );
          expect(persisted.single['definition_hash'], old['definition_hash']);
        }
        expect(
          services<LocalBackupManager>().recoveryState.isRecoveryRequired,
          isFalse,
        );
      },
    );
  }
  test(
    'legacy restore preserves disabled activation while upgrading definition',
    () async {
      final backup = await legacyBackup(disableCount: true);
      await services<WorkspaceDataService>().restore(
        backup.path,
        mode: LocalRestoreMode.replace,
      );
      final id = RuleIdentity('ANL-R004');
      final activation = (await rules.existingActivation(id))!;
      expect(activation.enabled, isFalse);
      final definition = (await rules.listDefinitions()).singleWhere(
        (rule) => rule.identity == id && rule.version == activation.version,
      );
      expect(definition.role, AnalysisSemanticRole.eligibleTransactionCount);
    },
  );

  test(
    'rule installation failure keeps restore gated and preserves financial data',
    () async {
      final source = await rootBundle.loadString(
        'assets/analysis_rules/metrics/ANL-R001.yaml',
      );
      final conflicting = source.replaceFirst(
        'role: expenseTotal',
        'role: incompatibleRole',
      );
      final installed = await InstallBuiltInRules(rules)({
        'conflicting.yaml': conflicting,
      });
      expect(installed.diagnostics, isEmpty);
      final backup = File('${root.path}/conflicting.butlerlybackup');
      await services<LocalBackupManager>().createBackup(backup);
      var refreshed = false;
      await expectLater(
        services<WorkspaceDataService>().restore(
          backup.path,
          mode: LocalRestoreMode.replace,
          refreshPresentation: () async {
            refreshed = true;
          },
        ),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );
      expect(refreshed, isFalse);
      expect(
        services<LocalBackupManager>().recoveryState.isRecoveryRequired,
        isTrue,
      );
      expect(await database.database.query('transactions'), hasLength(1));
      final persisted = (await rules.listDefinitions()).singleWhere(
        (rule) => rule.identity.value == 'ANL-R001',
      );
      expect(
        persisted.definitionHash,
        installed.installed.single.definitionHash,
      );
    },
  );
}
