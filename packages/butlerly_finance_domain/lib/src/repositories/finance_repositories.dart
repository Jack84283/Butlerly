import '../analysis/analysis.dart';
import '../entities/account.dart';
import '../entities/attachment_link.dart';
import '../entities/category.dart';
import '../entities/duplicate_candidate_group.dart';
import '../entities/evidence_item.dart';
import '../entities/exchange_rate.dart';
import '../entities/extraction.dart';
import '../entities/master_translation.dart';
import '../entities/merchant.dart';
import '../entities/reconciliation_candidate.dart';
import '../entities/reconciliation_link.dart';
import '../entities/reference_data.dart';
import '../entities/statement.dart';
import '../entities/suggestion.dart';
import '../entities/tag.dart';
import '../entities/transaction.dart';
import '../entities/user_preference.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/domain_id.dart';

abstract interface class TransactionRepository {
  Future<void> save(Transaction transaction);
  Future<Transaction?> findById(TransactionId id);
  Future<List<Transaction>> listAll();
  Future<List<Transaction>> query(TransactionRepositoryQuery query);
  Future<void> removePermanently(TransactionId id);
}

final class DuplicateTransactionGroupMatch {
  const DuplicateTransactionGroupMatch({
    required this.duplicateKey,
    required this.transactionIds,
  });

  final DuplicateTransactionKey duplicateKey;
  final List<TransactionId> transactionIds;
}

abstract interface class DuplicateCandidateGroupRepository {
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  });

  Future<List<DuplicateTransactionGroupMatch>> findActiveDuplicateGroups();
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  );
  Future<void> save(DuplicateCandidateGroup group);
  Future<void> remove(String id);
}

abstract interface class ExchangeRateRepository {
  Future<void> save(ExchangeRate rate);
  Future<ExchangeRate?> findApplicable({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
    required DateTime financialDate,
  });
}

abstract interface class AnalysisRuleRepository {
  Future<void> install(
    AnalysisRuleDefinition definition, {
    required String sourceType,
    required String canonicalDefinition,
  });
  Future<List<AnalysisRuleDefinition>> listDefinitions();
  Future<void> activate(
    RuleIdentity id,
    RuleVersion version,
    bool enabled,
    DateTime at,
  );
  Future<List<AnalysisRuleDefinition>> listActive();
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id);
}

final class AnalysisRuleActivation {
  const AnalysisRuleActivation({required this.version, required this.enabled});
  final RuleVersion version;
  final bool enabled;
}

abstract interface class AnalysisFindingRepository {
  Future<void> save(AnalysisFinding finding);
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle});
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  );
}

final class TransactionRepositoryQuery {
  const TransactionRepositoryQuery({
    this.text,
    this.from,
    this.to,
    this.categoryId,
    this.paymentSourceId,
    this.currency,
    this.direction,
    this.status,
    this.needsReview,
    this.uncategorized = false,
  });

  final String? text;
  final DateTime? from;
  final DateTime? to;
  final CategoryId? categoryId;
  final PaymentSourceId? paymentSourceId;
  final String? currency;
  final TransactionDirection? direction;
  final TransactionStatus? status;
  final bool? needsReview;
  final bool uncategorized;
}

abstract interface class PaymentSourceRepository {
  Future<void> save(PaymentSource paymentSource);
  Future<PaymentSource?> findById(PaymentSourceId id);
  Future<List<PaymentSource>> listAll();
}

abstract interface class MerchantRepository {
  Future<void> save(Merchant merchant);
  Future<Merchant?> findById(MerchantId id);
  Future<List<Merchant>> listAll();
}

abstract interface class CategoryRepository {
  Future<void> save(Category category);
  Future<Category?> findById(CategoryId id);
  Future<List<Category>> listAll();
}

abstract interface class TagRepository {
  Future<void> save(Tag tag);
  Future<Tag?> findById(TagId id);
  Future<List<Tag>> listAll();
}

abstract interface class MasterTranslationRepository {
  Future<void> saveAll(List<MasterTranslation> translations);
  Future<Map<String, String>> labels({
    required String masterType,
    required String locale,
  });
}

abstract interface class ReferenceDataRepository {
  Future<void> save(ReferenceData value);
  Future<ReferenceData?> findById(ReferenceDataId id);
  Future<List<ReferenceData>> list({
    String? type,
    bool includeArchived = false,
  });
  Future<Map<String, String>> labels({
    required String type,
    required String locale,
    bool includeArchived = false,
  });
  Future<void> saveTranslation({
    required ReferenceDataId id,
    required String locale,
    required String label,
  });
}

abstract interface class EvidenceRepository {
  Future<void> save(EvidenceItem evidence);
  Future<void> saveExtraction(Extraction extraction);
  Future<void> link(AttachmentLink link);
  Future<EvidenceItem?> findById(EvidenceId id);
  Future<List<EvidenceItem>> listForTransaction(TransactionId id);
  Future<void> remove(EvidenceId id);
}

abstract interface class StatementRepository {
  Future<void> saveStatement(FinancialStatement statement);
  Future<void> saveRows(List<StatementRow> rows);
  Future<void> saveStatementWithRows(
    FinancialStatement statement,
    List<StatementRow> rows,
  );
  Future<FinancialStatement?> findStatement(String id);
  Future<List<FinancialStatement>> listStatements({
    bool includeArchived = false,
  });
  Future<List<StatementRow>> listRows(String statementId);
  Future<void> assignPaymentSource(
    String statementId,
    String paymentSourceId,
    DateTime updatedAt,
  );
  Future<void> updateRow(StatementRow row);
  Future<bool> canDeleteStatement(String id);
  Future<void> removeStatement(String id);
}

abstract interface class StatementWorkflowRepository {
  Future<void> saveRowTransaction(StatementRow row, Transaction transaction);
  Future<void> linkRow(StatementRow row);
}

abstract interface class ExtractionLookupRepository {
  Future<Extraction?> findExtractionForEvidence(EvidenceId id);
}

abstract interface class SuggestionRepository {
  Future<void> save(Suggestion suggestion);
  Future<Suggestion?> findById(SuggestionId id);
  Future<List<Suggestion>> listForTransaction(TransactionId id);
}

abstract interface class ReconciliationCandidateRepository {
  Future<void> save(ReconciliationCandidate candidate);
  Future<ReconciliationCandidate?> findById(String id);
  Future<List<ReconciliationCandidate>> listAll();
}

abstract interface class ReconciliationLinkRepository {
  Future<void> save(ReconciliationLink link);
  Future<List<ReconciliationLink>> listAll();
}

abstract interface class ReconciliationWorkflowRepository {
  Future<void> confirm(
    ReconciliationCandidate candidate,
    ReconciliationLink link,
  );

  Future<void> reject(ReconciliationCandidate candidate);
}

abstract interface class UserPreferenceRepository {
  Future<UserPreference?> load();
  Future<void> save(UserPreference preference);
}
