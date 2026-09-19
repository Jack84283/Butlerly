import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import 'merchant.dart';

enum ClassificationRuleMatchMode { exact, prefix }

final class ClassificationRule {
  ClassificationRule({
    required this.id,
    required String pattern,
    this.matchMode = ClassificationRuleMatchMode.exact,
    this.enabled = true,
    this.merchantId,
    this.categoryId,
    this.subcategoryId,
    this.tagIds = const [],
    required this.createdAt,
    required this.updatedAt,
  }) : pattern = normalizeMerchantName(pattern) {
    if (this.pattern.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'pattern',
        message: 'A classification rule match pattern is required.',
      );
    }
    if (merchantId == null &&
        categoryId == null &&
        subcategoryId == null &&
        tagIds.isEmpty) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'assignment',
        message: 'A classification rule must assign at least one value.',
      );
    }
    if (subcategoryId != null && categoryId == null) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'subcategoryId',
        message: 'A subcategory assignment requires a parent category.',
      );
    }
  }

  final ClassificationRuleId id;
  final String pattern;
  final ClassificationRuleMatchMode matchMode;
  final bool enabled;
  final MerchantId? merchantId;
  final CategoryId? categoryId;
  final CategoryId? subcategoryId;
  final List<TagId> tagIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool matches(String value) {
    if (!enabled) return false;
    final normalized = normalizeMerchantName(value);
    if (normalized.isEmpty) return false;
    return switch (matchMode) {
      ClassificationRuleMatchMode.exact => normalized == pattern,
      ClassificationRuleMatchMode.prefix =>
        normalized == pattern || normalized.startsWith('$pattern '),
    };
  }

  ClassificationRule copyWith({
    String? pattern,
    ClassificationRuleMatchMode? matchMode,
    bool? enabled,
    MerchantId? merchantId,
    bool clearMerchant = false,
    CategoryId? categoryId,
    bool clearCategory = false,
    CategoryId? subcategoryId,
    bool clearSubcategory = false,
    List<TagId>? tagIds,
    DateTime? updatedAt,
  }) => ClassificationRule(
    id: id,
    pattern: pattern ?? this.pattern,
    matchMode: matchMode ?? this.matchMode,
    enabled: enabled ?? this.enabled,
    merchantId: clearMerchant ? null : merchantId ?? this.merchantId,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    subcategoryId: clearSubcategory
        ? null
        : subcategoryId ?? this.subcategoryId,
    tagIds: tagIds ?? this.tagIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
