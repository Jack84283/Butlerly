import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Shared outside-content canvas used by every standard Butlerly page surface.
///
/// Page chrome may span the viewport, but body regions outside the readable
/// content surface always use the semantic subtle-surface color.
class ButlerlyContentCanvas extends StatelessWidget {
  const ButlerlyContentCanvas({required this.child, this.canvasKey, super.key});

  final Widget child;
  final Key? canvasKey;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: canvasKey,
    color: context.colors.subtleSurface,
    child: child,
  );
}

/// Shared box-layout content surface for standard Scaffold bodies.
class ButlerlyContentSurface extends StatelessWidget {
  const ButlerlyContentSurface({
    required this.child,
    this.surfaceKey,
    this.contentKey,
    this.maxWidth,
    super.key,
  });

  final Widget child;
  final Key? surfaceKey;
  final Key? contentKey;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final resolvedMaxWidth =
        maxWidth ?? ButlerlyLayout.contentMaxWidth(MediaQuery.sizeOf(context));
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
        child: Material(
          key: surfaceKey,
          color: context.colors.background,
          child: SizedBox(
            key: contentKey,
            width: double.infinity,
            height: double.infinity,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Shared sliver-layout content surface for pages that own a CustomScrollView.
///
/// [surfaceHorizontalPadding] expands the surface around the readable content
/// width so page padding remains inside the background-colored content area.
class ButlerlySliverContentSurface extends StatelessWidget {
  const ButlerlySliverContentSurface({
    required this.sliver,
    this.surfaceKey,
    this.surfaceHorizontalPadding = 0,
    super.key,
  });

  final Widget sliver;
  final Key? surfaceKey;
  final double surfaceHorizontalPadding;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final readableWidth = ButlerlyLayout.contentMaxWidth(
        MediaQuery.sizeOf(context),
      );
      final surfaceMaxWidth = readableWidth + surfaceHorizontalPadding;
      final extraWidth = constraints.crossAxisExtent - surfaceMaxWidth;
      final horizontalInset = extraWidth > 0 ? extraWidth / 2 : 0.0;
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: horizontalInset),
        sliver: DecoratedSliver(
          key: surfaceKey,
          decoration: BoxDecoration(color: context.colors.background),
          sliver: sliver,
        ),
      );
    },
  );
}
