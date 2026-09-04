import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';

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
  }) : name = _validate(name),
       normalizedName = normalizedName ?? normalizeMerchantName(name);

  final MerchantId id;
  final String name;
  final MerchantStatus status;
  final String? rawName;
  final String normalizedName;
  final CategoryId? defaultCategoryId;
  final CategoryId? defaultSubcategoryId;
  final bool isBuiltIn;

  Merchant archive() => Merchant(
    id: id,
    name: name,
    status: MerchantStatus.archived,
    rawName: rawName,
    normalizedName: normalizedName,
    defaultCategoryId: defaultCategoryId,
    defaultSubcategoryId: defaultSubcategoryId,
    isBuiltIn: isBuiltIn,
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

/// Conservative, deterministic merchant matching representation.
String normalizeMerchantName(String value) {
  var normalized = value.toLowerCase().trim();
  normalized = normalized.replaceAll(RegExp(r"[^a-z0-9]+"), ' ');
  normalized = normalized.replaceAll(
    RegExp(r'\b(store|location|#)?\s*\d{2,}\b'),
    ' ',
  );
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}
