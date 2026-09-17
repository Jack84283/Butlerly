import 'package:butlerly/app/shell/shared/primary_bottom_navigation.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

class IPhonePrimaryShell extends StatelessWidget {
  const IPhonePrimaryShell({
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
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: SafeArea(
      bottom: false,
      child: ColoredBox(
        key: const ValueKey('primary-phone-body-surface'),
        color: context.colors.background,
        child: body,
      ),
    ),
    bottomNavigationBar: PrimaryBottomNavigation(
      navigationKey: const ValueKey('primary-phone-navigation'),
      destinations: destinations,
      visualBranchIndexes: visualBranchIndexes,
      currentIndex: currentIndex,
      onSelected: onSelected,
    ),
  );
}
