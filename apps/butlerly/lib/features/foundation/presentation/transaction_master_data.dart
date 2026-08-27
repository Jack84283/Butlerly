import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'master_data_labels.dart';

/// Presentation-only lookup data for transaction master-data references.
///
/// Transaction DTOs intentionally carry stable foreign keys. Screens use this
/// model to resolve those keys without bypassing the application layer.
final class TransactionMasterData {
  const TransactionMasterData({
    this.merchantNames = const {},
    this.categoryNames = const {},
    this.categoryParentIds = const {},
    this.tagNames = const {},
  });

  final Map<String, String> merchantNames;
  final Map<String, String> categoryNames;
  final Map<String, String?> categoryParentIds;
  final Map<String, String> tagNames;

  String? merchantName(String? id) => id == null ? null : merchantNames[id];

  String? categoryName(String? id) => id == null ? null : categoryNames[id];

  String? categoryParentId(String? id) =>
      id == null ? null : categoryParentIds[id];

  String? tagName(String id) => tagNames[id];

  String? summary(TransactionDto transaction) {
    final labels = <String>[
      ?merchantName(transaction.merchantId),
      if (categoryParentId(transaction.categoryId) case final parentId?)
        ?categoryName(parentId),
      if (categoryName(transaction.categoryId) case final categoryName?
          when categoryName != categoryNameForParent(transaction.categoryId))
        categoryName,
      ...transaction.tagIds.map(tagName).whereType<String>(),
    ];
    return labels.isEmpty ? null : labels.join(' • ');
  }

  String? categoryNameForParent(String? id) =>
      categoryName(categoryParentId(id));

  static Future<TransactionMasterData> load(
    FinanceServices finance, {
    String languageCode = 'en',
  }) async {
    final merchantsResult = await finance.listMerchants();
    final categoriesResult = await finance.listCategories();
    final tagsResult = await finance.listTags();

    final merchants = switch (merchantsResult) {
      ApplicationSuccess<List<Merchant>>(:final value) => value,
      _ => const <Merchant>[],
    };
    final categories = switch (categoriesResult) {
      ApplicationSuccess<List<Category>>(:final value) => value,
      _ => const <Category>[],
    };
    final tags = switch (tagsResult) {
      ApplicationSuccess<List<Tag>>(:final value) => value,
      _ => const <Tag>[],
    };
    final categoryLabels = switch (await finance.loadMasterTranslations(
      masterType: 'category',
      locale: languageCode == 'zh' ? 'zh-Hans' : languageCode,
    )) {
      ApplicationSuccess<Map<String, String>>(:final value) => value,
      _ => const <String, String>{},
    };
    final tagLabels = switch (await finance.loadMasterTranslations(
      masterType: 'tag',
      locale: languageCode == 'zh' ? 'zh-Hans' : languageCode,
    )) {
      ApplicationSuccess<Map<String, String>>(:final value) => value,
      _ => const <String, String>{},
    };

    return TransactionMasterData(
      merchantNames: {
        for (final value in merchants) value.id.value: value.name,
      },
      categoryNames: {
        for (final value in categories)
          value.id.value:
              categoryLabels[value.id.value] ??
              categoryDisplayLabel(value, languageCode),
      },
      categoryParentIds: {
        for (final value in categories) value.id.value: value.parentId?.value,
      },
      tagNames: {
        for (final value in tags)
          value.id.value:
              tagLabels[value.id.value] ?? tagDisplayLabel(value, languageCode),
      },
    );
  }
}

/// Canonical presentation snapshot shared by transaction workflows.
/// It contains retrieval results and localized labels, while selection state
/// remains owned by the consuming page.
final class TransactionMasterDataSnapshot {
  const TransactionMasterDataSnapshot({
    required this.presentation,
    required this.merchants,
    required this.categories,
    required this.tags,
    required this.paymentSources,
  });

  final TransactionMasterData presentation;
  final List<Merchant> merchants;
  final List<Category> categories;
  final List<Tag> tags;
  final List<PaymentSource> paymentSources;
}

final class TransactionMasterDataProvider {
  const TransactionMasterDataProvider(this.finance);

  final FinanceServices finance;

  Future<TransactionMasterDataSnapshot> load({
    String languageCode = 'en',
  }) async {
    final results = await Future.wait([
      finance.listMerchants(),
      finance.listCategories(),
      finance.listTags(),
      finance.listPaymentSources(),
      TransactionMasterData.load(finance, languageCode: languageCode),
    ]);
    List<T> valueOf<T>(int index) => switch (results[index]) {
      ApplicationSuccess<List<T>>(:final value) => value,
      _ => const <Never>[] as List<T>,
    };
    return TransactionMasterDataSnapshot(
      presentation: results[4] as TransactionMasterData,
      merchants: valueOf<Merchant>(0),
      categories: valueOf<Category>(1),
      tags: valueOf<Tag>(2),
      paymentSources: valueOf<PaymentSource>(3),
    );
  }
}
