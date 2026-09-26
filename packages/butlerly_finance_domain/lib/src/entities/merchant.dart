import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import 'merchant_matching.dart';

enum MerchantStatus { active, archived }

final class Merchant {
  Merchant({
    required this.id,
    required String name,
    this.status = MerchantStatus.active,
    this.rawName,
    String? normalizedName,
    this.defaultCategoryId,
    this.defaultSubcategoryId,
    this.isBuiltIn = false,
    Iterable<MerchantAlias> aliases = const [],
    Iterable<MerchantNormalizationPattern> normalizationPatterns = const [],
  }) : name = _validate(name),
       normalizedName = normalizedName ?? normalizeMerchantName(name),
       aliases = immutableAliases(aliases),
       normalizationPatterns = immutablePatterns(normalizationPatterns);

  final MerchantId id;
  final String name;
  final MerchantStatus status;
  final String? rawName;
  final String normalizedName;
  final CategoryId? defaultCategoryId;
  final CategoryId? defaultSubcategoryId;
  final bool isBuiltIn;
  final List<MerchantAlias> aliases;
  final List<MerchantNormalizationPattern> normalizationPatterns;

  Merchant archive() => Merchant(
    id: id,
    name: name,
    status: MerchantStatus.archived,
    rawName: rawName,
    normalizedName: normalizedName,
    defaultCategoryId: defaultCategoryId,
    defaultSubcategoryId: defaultSubcategoryId,
    isBuiltIn: isBuiltIn,
    aliases: aliases,
    normalizationPatterns: normalizationPatterns,
  );

  static String _validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'name',
        message: 'A normalized merchant name is required.',
      );
    }
    return normalized;
  }
}
