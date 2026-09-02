import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category colors are stable and use the predefined palette', () {
    final first = ButlerlyChartColors.category('food');

    expect(ButlerlyChartColors.category('food'), first);
    expect(ButlerlyChartColors.category('food'), isA<Color>());
    expect(ButlerlyChartColors.categoryPalette, contains(first));
  });

  test('categories beyond the palette have a deterministic fallback', () {
    expect(
      ButlerlyChartColors.category('category-9'),
      ButlerlyChartColors.category('category-9'),
    );
    expect(
      ButlerlyChartColors.category('category-9'),
      isIn(ButlerlyChartColors.categoryPalette),
    );
  });

  test('visible categories receive unique colors up to the palette size', () {
    final ids = List<String>.generate(32, (index) => 'category-$index');
    final colors = ButlerlyChartColors.forCategories(ids).values.toSet();

    expect(ButlerlyChartColors.categoryPalette, hasLength(32));
    expect(colors, hasLength(32));
    expect(
      ButlerlyChartColors.forCategories(ids),
      ButlerlyChartColors.forCategories(ids),
    );
  });
}
