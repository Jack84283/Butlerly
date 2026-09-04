import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/core/database/reference_data_seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds the exact MD-0001 system category and tag IDs', () {
    final data = buildInitialMasterData();

    expect(data.merchants.map((value) => value.name), containsAll([
      'Safeway',
      'Costco',
      'Walmart',
      'Amazon',
      'Starbucks',
      'Target',
      'Whole Foods',
      "Trader Joe's",
      'Walgreens',
      'CVS',
      'Home Depot',
      'Shell',
      'Chevron',
      'Uber',
      'Lyft',
    ]));
    expect(
      data.categories.map((value) => value.id.value),
      contains('category.food'),
    );
    expect(
      data.categories.map((value) => value.id.value),
      contains('category.food.coffee'),
    );
    expect(
      data.tags.map((value) => value.id.value),
      contains('tag.tax_related'),
    );
    expect(
      data.referenceData.map((value) => value.id.value),
      containsAll([
        'transaction.direction.expense',
        'payment_source.type.credit_card',
        'card_network.visa',
        'evidence.type.receipt',
        'review.status.needs_review',
        'reconciliation.status.candidate',
        'analysis.finding.data_quality',
      ]),
    );
    expect(
      data.referenceTranslations
          .where((value) => value.locale == 'zh-Hans')
          .map((value) => value.label),
      contains('信用卡'),
    );
  });

  test('matches every MD-0001 simple reference ID and translation', () {
    final data = buildInitialMasterData();
    final seeded = {
      for (final value in data.referenceData) value.id.value: value,
    };
    final translations = {
      for (final value in data.referenceTranslations)
        '${value.masterId}|${value.locale}': value.label,
    };

    expect(seeded.keys, {for (final row in md0001ReferenceData) row.id});
    for (final row in md0001ReferenceData) {
      expect(translations['${row.id}|en'], row.english);
      expect(translations['${row.id}|zh-Hans'], row.chinese);
    }
  });
}
