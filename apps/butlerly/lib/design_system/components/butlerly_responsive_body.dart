import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Centers page body content inside Butlerly's readable-width policy while
/// leaving surrounding screen chrome, such as an AppBar or bottom navigation,
/// free to span the full viewport.
///
/// The readable body is the content surface. Any horizontal area outside that
/// surface uses the shared out-of-content canvas color.
class ButlerlyResponsiveBody extends StatelessWidget {
  const ButlerlyResponsiveBody({
    required this.child,
    this.contentKey,
    super.key,
  });

  final Widget child;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final maxWidth = ButlerlyLayout.contentMaxWidth(MediaQuery.sizeOf(context));
    return ColoredBox(
      key: const ValueKey('butlerly-responsive-body-canvas'),
      color: context.colors.subtleSurface,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            key: const ValueKey('butlerly-responsive-body-content-surface'),
            color: context.colors.background,
            child: SizedBox(
              key: contentKey,
              width: double.infinity,
              height: double.infinity,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
