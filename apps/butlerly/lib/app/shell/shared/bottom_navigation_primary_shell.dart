import 'package:butlerly/app/shell/shared/primary_bottom_navigation.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Shared shell implementation for the width-driven Compact and Medium
/// presentations. Both presentations intentionally keep the same interaction
/// model and primary bottom navigation.
class BottomNavigationPrimaryShell extends StatelessWidget {
  const BottomNavigationPrimaryShell({
    required this.body,
    required this.destinations,
    required this.visualBranchIndexes,
    required this.currentIndex,
    required this.onSelected,
    required this.bodySurfaceKey,
    required this.navigationKey,
    super.key,
  });

  final Widget body;
  final Map<int, NavigationDestination> destinations;
  final List<int> visualBranchIndexes;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Key bodySurfaceKey;
  final Key navigationKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: ColoredBox(
        key: bodySurfaceKey,
        color: context.colors.subtleSurface,
        child: body,
      ),
    ),
    bottomNavigationBar: PrimaryBottomNavigation(
      navigationKey: navigationKey,
      destinations: destinations,
      visualBranchIndexes: visualBranchIndexes,
      currentIndex: currentIndex,
      onSelected: onSelected,
    ),
  );
}
