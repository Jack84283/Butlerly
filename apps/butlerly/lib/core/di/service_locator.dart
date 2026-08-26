import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
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

  services.registerSingleton<LocalDataManager>(LocalDataManager(database));

  if (database.status == DatabaseStatus.ready) {
    final statements = SqliteStatementRepository(database.persistenceDatabase);
    final finance = FinanceServices(
      SqliteTransactionRepository(database.persistenceDatabase),
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
      statements: statements,
    );
    services
      ..registerSingleton<FinanceServices>(finance)
      ..registerSingleton<LocalEvidenceStore>(
        LocalEvidenceStore(services<LocalDataManager>(), finance),
      );
  }
}
