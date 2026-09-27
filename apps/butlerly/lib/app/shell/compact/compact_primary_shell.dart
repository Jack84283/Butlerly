import 'package:butlerly/app/shell/shared/bottom_navigation_primary_shell.dart';
import 'package:flutter/material.dart';

class CompactPrimaryShell extends StatelessWidget {
  const CompactPrimaryShell({
    required this.body,
    required this.destinations,
    required this.visualBranchIndexes,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final Widget body;
  final Map<int, NavigationDestination> destinations;
  final List<int> visualBranchIndexes;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => BottomNavigationPrimaryShell(
    body: body,
    destinations: destinations,
    visualBranchIndexes: visualBranchIndexes,
    currentIndex: currentIndex,
    onSelected: onSelected,
    bodySurfaceKey: const ValueKey('primary-compact-body-surface'),
    navigationKey: const ValueKey('primary-compact-navigation'),
  );
}
