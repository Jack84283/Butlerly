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
    this.tagNames = const {},
  });

  final Map<String, String> merchantNames;
  final Map<String, String> categoryNames;
  final Map<String, String> tagNames;

  String? merchantName(String? id) => id == null ? null : merchantNames[id];

  String? categoryName(String? id) => id == null ? null : categoryNames[id];

  String? tagName(String id) => tagNames[id];

  String? summary(TransactionDto transaction) {
    final labels = <String>[
      ?merchantName(transaction.merchantId),
      ?categoryName(transaction.categoryId),
      ...transaction.tagIds.map(tagName).whereType<String>(),
    ];
    return labels.isEmpty ? null : labels.join(' • ');
  }

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
              categoryLabels[value.id.value] ?? categoryDisplayLabel(value, languageCode),
      },
      tagNames: {
        for (final value in tags)
          value.id.value: tagLabels[value.id.value] ?? tagDisplayLabel(value, languageCode),
      },
    );
  }
}
