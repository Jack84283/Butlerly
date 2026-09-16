import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Centers page body content inside Butlerly's readable-width policy while
/// leaving surrounding screen chrome, such as an AppBar or bottom navigation,
/// free to span the full viewport.
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
    final maxWidth = ButlerlySize.pageContentMaxWidthFor(
      MediaQuery.sizeOf(context),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          key: contentKey,
          width: double.infinity,
          height: double.infinity,
          child: child,
        ),
      ),
    );
  }
}
