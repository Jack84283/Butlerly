import 'package:butlerly/design_system/components/butlerly_content_surface.dart';
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
  Widget build(BuildContext context) => ButlerlyContentCanvas(
    canvasKey: const ValueKey('butlerly-responsive-body-canvas'),
    child: ButlerlyContentSurface(
      surfaceKey: const ValueKey('butlerly-responsive-body-content-surface'),
      contentKey: contentKey,
      child: child,
    ),
  );
}
