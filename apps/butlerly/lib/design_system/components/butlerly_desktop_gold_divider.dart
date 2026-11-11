import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Paint-only bottom border for every desktop AppBar and SliverAppBar.
///
/// Material's shape renderer paints this gold gradient across the full width
/// of the header. Device layouts do not receive the desktop AppBar theme.
class ButlerlyDesktopGoldBottomBorder extends ShapeBorder {
  const ButlerlyDesktopGoldBottomBorder({
    this.thickness = ButlerlyGoldAccentTokens.thickness,
  });

  final double thickness;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(bottom: thickness);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty || thickness <= 0) return;
    final line = Rect.fromLTWH(
      rect.left,
      rect.bottom - thickness,
      rect.width,
      thickness,
    );
    final paint = Paint()
      ..shader = ButlerlyGoldAccentTokens.gradient.createShader(line);
    canvas.drawRect(line, paint);
  }

  @override
  ShapeBorder scale(double t) =>
      ButlerlyDesktopGoldBottomBorder(thickness: thickness * t);
}

/// Full-width gold separator above the pinned action footer in desktop panels.
class ButlerlyDesktopGoldDivider extends StatelessWidget {
  const ButlerlyDesktopGoldDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: ButlerlyGoldAccentTokens.thickness,
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: ButlerlyGoldAccentTokens.gradient),
    ),
  );
}
