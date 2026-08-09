import '../entities/account.dart';
import '../entities/attachment_link.dart';
import '../entities/category.dart';
import '../entities/evidence_item.dart';
import '../entities/extraction.dart';
import '../entities/merchant.dart';
import '../entities/suggestion.dart';
import '../entities/tag.dart';
import '../entities/transaction.dart';
import '../value_objects/domain_id.dart';

abstract interface class TransactionRepository {
  Future<void> save(Transaction transaction);
  Future<Transaction?> findById(TransactionId id);
  Future<List<Transaction>> listAll();
  Future<void> removePermanently(TransactionId id);
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

abstract interface class EvidenceRepository {
  Future<void> save(EvidenceItem evidence);
  Future<void> saveExtraction(Extraction extraction);
  Future<void> link(AttachmentLink link);
  Future<EvidenceItem?> findById(EvidenceId id);
  Future<List<EvidenceItem>> listForTransaction(TransactionId id);
}

abstract interface class SuggestionRepository {
  Future<void> save(Suggestion suggestion);
  Future<Suggestion?> findById(SuggestionId id);
  Future<List<Suggestion>> listForTransaction(TransactionId id);
}
