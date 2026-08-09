import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.navigationShell, super.key});

  static const tabletBreakpoint = 600.0;
  static const desktopBreakpoint = 1200.0;

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      label: 'Activity',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      label: 'Settings',
    ),
  ];

  void _selectDestination(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < tabletBreakpoint) {
          return Scaffold(
            body: SafeArea(child: navigationShell),
            bottomNavigationBar: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectDestination,
              destinations: _destinations,
            ),
          );
        }

        final extended = constraints.maxWidth >= desktopBreakpoint;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _selectDestination,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: extended
                        ? Text(
                            'Butlerly',
                            style: Theme.of(context).textTheme.titleLarge,
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                  ),
                  destinations: _destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: destination.icon,
                          label: Text(destination.label),
                        ),
                      )
                      .toList(growable: false),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        );
      },
    );
  }
}
