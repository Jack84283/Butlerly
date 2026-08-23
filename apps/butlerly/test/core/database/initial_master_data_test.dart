import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds the exact MD-0001 system category and tag IDs', () {
    final data = buildInitialMasterData();

    expect(data.merchants, isEmpty);
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
        'transaction_direction.expense',
        'payment_source_type.card',
        'card_network.visa',
        'evidence_type.receipt_image',
        'review_status.needs_review',
        'reconciliation_status.proposed',
        'analysis_finding_type.conflict',
      ]),
    );
    expect(
      data.referenceTranslations
          .where((value) => value.locale == 'zh-Hans')
          .map((value) => value.label),
      contains('信用卡'),
    );
  });
}
