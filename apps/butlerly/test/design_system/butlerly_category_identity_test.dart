import 'dart:io';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final builtInIds = buildInitialMasterData().categories
      .map((category) => category.id.value)
      .toList(growable: false);

  test('defines exactly eight persistent category colors', () {
    expect(ButlerlyCategoryColors.palette, hasLength(8));
    expect(ButlerlyCategoryColors.palette.values.toSet(), hasLength(8));
  });

  test('maps every built-in category to an asset and color', () {
    expect(
      ButlerlyCategoryIdentity.builtInCategoryIds.toSet(),
      equals(builtInIds.toSet()),
    );

    for (final categoryId in builtInIds) {
      final identity = ButlerlyCategoryIdentity.forId(categoryId);
      expect(identity.categoryId, categoryId);
      expect(identity.localizationKey, categoryId);
      expect(
        File(identity.assetPath).existsSync(),
        isTrue,
        reason: 'Missing category asset for $categoryId',
      );
      expect(ButlerlyCategoryColors.palette, contains(identity.colorId));
    }
  });

  test('custom categories use the canonical custom asset and stable color', () {
    final first = ButlerlyCategoryIdentity.forId('custom-category');
    final second = ButlerlyCategoryIdentity.forId('custom-category');

    expect(first.assetName, 'custom');
    expect(first.assetPath, endsWith('assets/icons/categories/custom.svg'));
    expect(first.colorId, second.colorId);
    expect(ButlerlyCategoryColors.palette, contains(first.colorId));
  });

  test('category identity is independent of application theme', () {
    final identity = ButlerlyCategoryIdentity.forId('category.food.groceries');
    final categoryColor = ButlerlyCategoryColors.color(identity.colorId);

    for (final theme in [
      AppTheme.light,
      AppTheme.dark,
      AppTheme.lightFor(ButlerlyColorTheme.skyBlue),
      AppTheme.darkFor(ButlerlyColorTheme.green),
    ]) {
      expect(theme.brightness, isNotNull);
      expect(categoryColor, ButlerlyCategoryColors.color(identity.colorId));
    }
    expect(categoryColor, isNot(AppTheme.light.colorScheme.surface));
  });

  test(
    'standard category icon dimensions are 40 dp container and 24 dp glyph',
    () {
      expect(ButlerlySize.categoryIconContainer, 40);
      expect(ButlerlySize.categoryIconGlyph, 24);
    },
  );
}
