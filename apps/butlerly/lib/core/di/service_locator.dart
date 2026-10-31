import 'dart:io';

import 'package:butlerly/core/analysis/bundled_analysis_rules.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/evidence_deletion_recovery_state.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
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
  Directory? documentsDirectory,
  Directory? localEvidenceDirectory,
}) {
  services
    ..registerSingleton<AppConfiguration>(configuration)
    ..registerSingleton<AppLogger>(logger)
    ..registerSingleton<LocalDatabase>(database);
  services.registerSingleton<OcrRecognizer>(platformOcrRecognizer());

  final consistencyGate = AnalysisConsistencyGate();
  final localDataManager = LocalDataManager(
    database,
    documentsDirectory: documentsDirectory,
    localEvidenceDirectory: localEvidenceDirectory,
    consistencyGate: consistencyGate,
  );
  final restoreRecoveryState = RestoreRecoveryState(localDataManager);
  final publicationRecoveryState = BackupPublicationRecoveryState();
  final evidenceDeletionRecoveryState = EvidenceDeletionRecoveryState();
  services
    ..registerSingleton<LocalDataManager>(localDataManager)
    ..registerSingleton<AnalysisConsistencyGate>(consistencyGate)
    ..registerSingleton<RestoreRecoveryState>(restoreRecoveryState)
    ..registerSingleton<BackupPublicationRecoveryState>(
      publicationRecoveryState,
    )
    ..registerSingleton<EvidenceDeletionRecoveryState>(
      evidenceDeletionRecoveryState,
    )
    ..registerSingleton<LocalBackupManager>(
      LocalBackupManager(
        database,
        localDataManager,
        recoveryState: restoreRecoveryState,
        publicationRecoveryState: publicationRecoveryState,
        consistencyGate: consistencyGate,
      ),
    );

  services.registerSingleton<WorkspaceDataService>(
    WorkspaceDataService(
      LocalWorkspaceDataGateway(
        services<LocalBackupManager>(),
        localDataManager,
      ),
      consistencyGate: consistencyGate,
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
    final analysisRules = SqliteAnalysisRuleRepository(
      database.persistenceDatabase,
    );
    final analysisFindings = SqliteAnalysisFindingRepository(
      database.persistenceDatabase,
    );
    final analysisResults = SqliteAnalysisRuleResultRepository(
      database.persistenceDatabase,
    );
    final invalidateAnalysis = InvalidateAnalysis(
      analysisFindings,
      results: analysisResults,
      rules: analysisRules,
      consistencyGate: consistencyGate,
    );
    final duplicateRefresh = RefreshDuplicateGroupForTransaction(
      duplicateGroups,
      const SystemApplicationClock(),
    );
    final rawTransactions = SqliteTransactionRepository(
      database.persistenceDatabase,
    );
    final reconciliationCandidates = SqliteReconciliationCandidateRepository(
      database.persistenceDatabase,
    );
    final reconciliationLinks = SqliteReconciliationLinkRepository(
      database.persistenceDatabase,
    );
    final transactions = DuplicateReviewingTransactionRepository(
      rawTransactions,
      duplicateRefresh,
      invalidateAnalysis: invalidateAnalysis,
      consistencyGate: consistencyGate,
    );
    final statements = SqliteStatementRepository(database.persistenceDatabase);
    final evidenceRepository = SqliteEvidenceRepository(
      database.persistenceDatabase,
    );
    late LocalEvidenceStore localEvidenceStore;
    final finance = FinanceServices(
      transactions,
      SqlitePaymentSourceRepository(database.persistenceDatabase),
      SqliteMerchantRepository(database.persistenceDatabase),
      SqliteCategoryRepository(database.persistenceDatabase),
      SqliteTagRepository(database.persistenceDatabase),
      evidenceRepository,
      SqliteUserPreferenceRepository(database.persistenceDatabase),
      masterTranslations: SqliteMasterTranslationRepository(
        database.persistenceDatabase,
      ),
      referenceData: SqliteReferenceDataRepository(
        database.persistenceDatabase,
      ),
      reconciliationCandidates: reconciliationCandidates,
      reconciliationLinks: reconciliationLinks,
      reconciliationWorkflow: SqliteReconciliationWorkflowRepository(
        database.persistenceDatabase,
      ),
      analysisRules: analysisRules,
      analysisFindings: analysisFindings,
      analysisResults: analysisResults,
      statements: statements,
      duplicateGroups: duplicateGroups,
      recurringPatternDecisions: SqliteRecurringPatternDecisionRepository(
        database.persistenceDatabase,
      ),
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
      merchantMatchingConfiguration:
          SqliteMerchantMatchingConfigurationRepository(
            database.persistenceDatabase,
          ),
      transactionRules: SqliteTransactionRuleRepository(
        database.persistenceDatabase,
      ),
      budgetRepository: SqliteBudgetRepository(database.persistenceDatabase),
      financialProfileRepository: SqliteFinancialProfileRepository(
        database.persistenceDatabase,
      ),
      analysisInvalidation: invalidateAnalysis,
      consistencyGate: consistencyGate,
      deleteEvidenceFile: (evidence) =>
          localEvidenceStore.deletePublishedFile(evidence),
      finalizeDeletedEvidenceFile: (evidence) =>
          localEvidenceStore.finalizeDeletedEvidenceFile(evidence),
      withEvidenceMutationLock: EvidenceMutationLock.runExclusive,
      canonicalTransactionIds: () async {
        final selected = selectCanonicalTransactions(
          source: await rawTransactions.listAll(),
          links: await reconciliationLinks.listAll(),
          reconciliationCandidates: await reconciliationCandidates.listAll(),
          duplicateGroups: await duplicateGroups.list(),
        );
        return selected.transactions.map((value) => value.id.value).toSet();
      },
    );
    services
      ..registerSingleton<FinanceServices>(finance)
      ..registerSingleton<LocalEvidenceStore>(
        localEvidenceStore = LocalEvidenceStore(
          services<LocalDataManager>(),
          finance,
        ),
      );
  }
}
