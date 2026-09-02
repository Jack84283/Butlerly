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
    this.semanticLabel,
    this.containerSize = ButlerlySize.categoryIconContainer,
    this.glyphSize = ButlerlySize.categoryIconGlyph,
    super.key,
  });

  final String categoryId;
  final String? semanticLabel;
  final double containerSize;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final identity = ButlerlyCategoryIdentity.forId(categoryId);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: containerSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ButlerlyCategoryColors.color(identity.colorId),
            borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
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
