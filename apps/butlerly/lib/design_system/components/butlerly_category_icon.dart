import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders the persistent category identity independently from the active
/// application theme. Flutter owns the colored background; SVG owns the glyph.
class ButlerlyCategoryIcon extends StatelessWidget {
  const ButlerlyCategoryIcon({
    required this.categoryId,
    this.customColorId,
    this.semanticLabel,
    this.containerSize = ButlerlySize.categoryIconContainer,
    this.glyphSize = ButlerlySize.categoryIconGlyph,
    super.key,
  });

  final String categoryId;

  /// The persisted color for a user category. Required for custom IDs.
  final ButlerlyCategoryColorId? customColorId;
  final String? semanticLabel;
  final double containerSize;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final identity =
        ButlerlyCategoryIdentity.forBuiltInId(categoryId) ??
        (customColorId == null
            ? null
            : ButlerlyCategoryIdentity.custom(
                categoryId: categoryId,
                categoryColorId: customColorId!,
              ));
    assert(
      identity != null,
      'Unknown category ID requires a persisted custom color assignment.',
    );
    if (identity == null) {
      return SizedBox.square(dimension: containerSize);
    }
    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: containerSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ButlerlyCategoryColors.color(identity.categoryColorId),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: SvgPicture.asset(
              identity.assetPath,
              width: glyphSize,
              height: glyphSize,
              colorFilter: const ColorFilter.mode(
                ButlerlyCategoryColors.whiteGlyph,
                BlendMode.srcIn,
              ),
              semanticsLabel: null,
            ),
          ),
        ),
      ),
    );
  }
}
