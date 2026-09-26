import 'package:butlerly/core/analysis/bundled_analysis_rules.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/platform_ocr_recognizer.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:get_it/get_it.dart';

final services = GetIt.instance;

void configureDependencies({
  required AppConfiguration configuration,
  required LocalDatabase database,
  required AppLogger logger,
}) {
  services
    ..registerSingleton<AppConfiguration>(configuration)
    ..registerSingleton<AppLogger>(logger)
    ..registerSingleton<LocalDatabase>(database);
  services.registerSingleton<OcrRecognizer>(platformOcrRecognizer());

  final localDataManager = LocalDataManager(database);
  final restoreRecoveryState = RestoreRecoveryState(localDataManager);
  services
    ..registerSingleton<LocalDataManager>(localDataManager)
    ..registerSingleton<RestoreRecoveryState>(restoreRecoveryState)
    ..registerSingleton<LocalBackupManager>(
      LocalBackupManager(
        database,
        localDataManager,
        recoveryState: restoreRecoveryState,
      ),
    );

  services.registerSingleton<WorkspaceDataService>(
    WorkspaceDataService(
      LocalWorkspaceDataGateway(
        services<LocalBackupManager>(),
        localDataManager,
      ),
      refreshSystemData: () async {
        await database.reseedSystemData();
        final finance = services<FinanceServices>();
        final installer = finance.installBuiltInRules;
        if (installer == null) {
          throw StateError('Bundled analysis rule installer is unavailable.');
        }
        final installation = await installBundledAnalysisRules(installer);
        if (installation.diagnostics.isNotEmpty) {
          throw StateError('Bundled analysis rules failed validation.');
        }
        final duplicateRebuild = finance.rebuildDuplicateGroupsAfterRestore;
        if (duplicateRebuild != null) {
          final duplicateResult = await duplicateRebuild();
          if (duplicateResult is ApplicationFailure) {
            throw StateError('Duplicate review state could not be rebuilt.');
          }
        }
      },
    ),
  );

  if (database.status == DatabaseStatus.ready) {
    final duplicateGroups = SqliteDuplicateCandidateGroupRepository(
      database.persistenceDatabase,
    );
    final duplicateRefresh = RefreshDuplicateGroupForTransaction(
      duplicateGroups,
      const SystemApplicationClock(),
    );
    final rawTransactions = SqliteTransactionRepository(
      database.persistenceDatabase,
    );
    final transactions = DuplicateReviewingTransactionRepository(
      rawTransactions,
      duplicateRefresh,
    );
    final statements = SqliteStatementRepository(database.persistenceDatabase);
    final finance = FinanceServices(
      transactions,
      SqlitePaymentSourceRepository(database.persistenceDatabase),
      SqliteMerchantRepository(database.persistenceDatabase),
      SqliteCategoryRepository(database.persistenceDatabase),
      SqliteTagRepository(database.persistenceDatabase),
      SqliteEvidenceRepository(database.persistenceDatabase),
      SqliteUserPreferenceRepository(database.persistenceDatabase),
      masterTranslations: SqliteMasterTranslationRepository(
        database.persistenceDatabase,
      ),
      referenceData: SqliteReferenceDataRepository(
        database.persistenceDatabase,
      ),
      reconciliationCandidates: SqliteReconciliationCandidateRepository(
        database.persistenceDatabase,
      ),
      reconciliationLinks: SqliteReconciliationLinkRepository(
        database.persistenceDatabase,
      ),
      reconciliationWorkflow: SqliteReconciliationWorkflowRepository(
        database.persistenceDatabase,
      ),
      analysisRules: SqliteAnalysisRuleRepository(database.persistenceDatabase),
      analysisFindings: SqliteAnalysisFindingRepository(
        database.persistenceDatabase,
      ),
      analysisResults: SqliteAnalysisRuleResultRepository(
        database.persistenceDatabase,
      ),
      statements: statements,
      duplicateGroups: duplicateGroups,
      paymentSettlements: SqlitePaymentSettlementRepository(
        database.persistenceDatabase,
      ),
      merchantAliases: SqliteMerchantAliasRepository(
        database.persistenceDatabase,
      ),
      merchantNormalizationPatterns:
          SqliteMerchantNormalizationPatternRepository(
            database.persistenceDatabase,
          ),
      transactionRules: SqliteTransactionRuleRepository(
        database.persistenceDatabase,
      ),
    );
    services
      ..registerSingleton<FinanceServices>(finance)
      ..registerSingleton<LocalEvidenceStore>(
        LocalEvidenceStore(services<LocalDataManager>(), finance),
      );
  }
}
