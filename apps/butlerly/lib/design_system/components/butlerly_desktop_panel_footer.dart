import 'package:butlerly/design_system/components/butlerly_desktop_gold_divider.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Fixed action footer for desktop split-view editors and details.
///
/// Use as Scaffold.bottomNavigationBar so the panel body can scroll without
/// moving or obscuring its primary actions. Mobile pages retain their own
/// established action placement.
class ButlerlyDesktopPanelFooter extends StatelessWidget {
  const ButlerlyDesktopPanelFooter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.background,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ButlerlyDesktopGoldDivider(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(ButlerlySpacing.small),
            child: child,
          ),
        ),
      ],
    ),
  );
}
