import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const primaryShellRouteNamePrefix = 'primary-shell:';
const _phoneNavigationAddIconSize = 52.0;

/// Computes phone navigation height from each destination's actual geometry.
///
/// This supports nonlinear [TextScaler] implementations and labels that wrap
/// at large accessibility sizes without imposing a fixed maximum growth cap.
/// The established 78 px baseline already includes its own vertical slack, so
/// the bar only grows when a real destination's icon + gap + scaled label
/// geometry exceeds it.
double phoneNavigationHeightForLabels({
  required TextScaler textScaler,
  required double itemWidth,
  required Iterable<String> standardLabels,
  required String addLabel,
  required TextStyle labelStyle,
  required TextDirection textDirection,
}) {
  final availableWidth = itemWidth > 0 ? itemWidth : 1.0;

  double labelHeight(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textScaler: textScaler,
      textDirection: textDirection,
      textAlign: TextAlign.center,
    )..layout(maxWidth: availableWidth);
    return painter.height;
  }

  var requiredHeight =
      _phoneNavigationAddIconSize +
      ButlerlySpacing.micro +
      labelHeight(addLabel);

  for (final label in standardLabels) {
    final destinationHeight =
        ButlerlySize.standardIcon +
        ButlerlySize.navigationLabelGap +
        labelHeight(label);
    if (destinationHeight > requiredHeight) {
      requiredHeight = destinationHeight;
    }
  }

  return requiredHeight < ButlerlySize.navigationBarHeight
      ? ButlerlySize.navigationBarHeight
      : requiredHeight;
}

class PrimaryShellVisibilityController extends ChangeNotifier {
  final Map<int, bool> _secondaryRouteVisible = <int, bool>{};
  bool _notificationScheduled = false;

  bool secondaryRouteVisibleFor(int branchIndex) =>
      _secondaryRouteVisible[branchIndex] ?? false;

  void updateTopRoute(int branchIndex, Route<dynamic>? route) {
    final isPrimaryShellRoute =
        route?.settings.name?.startsWith(primaryShellRouteNamePrefix) ?? false;
    final next = route != null && !isPrimaryShellRoute;
    if (_secondaryRouteVisible[branchIndex] == next) return;
    _secondaryRouteVisible[branchIndex] = next;
    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      notifyListeners();
    });
  }
}

class PrimaryShellNavigatorObserver extends NavigatorObserver {
  PrimaryShellNavigatorObserver({
    required this.branchIndex,
    required this.controller,
  });

  final int branchIndex;
  final PrimaryShellVisibilityController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    controller.updateTopRoute(branchIndex, newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, previousRoute);
  }
}

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    required this.navigationShell,
    required this.visibilityController,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final PrimaryShellVisibilityController visibilityController;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  static const _visualBranchIndexes = <int>[0, 2, 1, 3, 4];

  int _previousPrimaryIndex = 0;
  int _lastPrimaryIndex = 0;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    widget.visibilityController.addListener(_handleVisibilityChanged);
  }

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibilityController != widget.visibilityController) {
      oldWidget.visibilityController.removeListener(_handleVisibilityChanged);
      widget.visibilityController.addListener(_handleVisibilityChanged);
    }
    final current = navigationShell.currentIndex;
    if (current == _lastPrimaryIndex) return;
    if (current == 1 && _lastPrimaryIndex != 1) {
      _previousPrimaryIndex = _lastPrimaryIndex;
    }
    _lastPrimaryIndex = current;
  }

  @override
  void dispose() {
    widget.visibilityController.removeListener(_handleVisibilityChanged);
    super.dispose();
  }

  void _handleVisibilityChanged() {
    if (mounted) setState(() {});
  }

  void _selectDestination(int branchIndex) {
    final current = navigationShell.currentIndex;
    if (branchIndex != current) {
      _previousPrimaryIndex = current;
      _lastPrimaryIndex = branchIndex;
    }
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == current,
    );
  }

  void _handleSystemBack(bool didPop, Object? result) {
    if (!didPop && navigationShell.currentIndex == 1) {
      navigationShell.goBranch(_previousPrimaryIndex);
    }
  }

  Map<int, NavigationDestination> _destinations(BuildContext context) => {
    0: NavigationDestination(
      icon: const Icon(Icons.home_outlined),
      selectedIcon: const Icon(Icons.home_rounded),
      label: context.l10n.text('home'),
    ),
    1: NavigationDestination(
      icon: const Icon(Icons.add_rounded),
      selectedIcon: const Icon(Icons.add_rounded),
      label: context.l10n.text('add'),
    ),
    2: NavigationDestination(
      icon: const Icon(Icons.format_list_bulleted_rounded),
      selectedIcon: const Icon(Icons.format_list_bulleted_rounded),
      label: context.l10n.text('transactions'),
    ),
    3: NavigationDestination(
      icon: const Icon(Icons.bar_chart_rounded),
      selectedIcon: const Icon(Icons.bar_chart_rounded),
      label: context.l10n.text('tools'),
    ),
    4: NavigationDestination(
      icon: const Icon(Icons.more_horiz_rounded),
      selectedIcon: const Icon(Icons.more_horiz_rounded),
      label: context.l10n.text('more'),
    ),
  };

  Widget _destination(
    BuildContext context,
    NavigationDestination destination,
    int branchIndex,
  ) {
    final selected = navigationShell.currentIndex == branchIndex;
    final add = branchIndex == 1;
    final labelStyle = ButlerlyTypography.navigationLabel(
      Theme.of(context).textTheme.labelSmall!,
      color: selected
          ? context.colors.interactive
          : context.colors.secondaryText,
      selected: selected,
    );
    final baseIcon = selected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    final icon = add
        ? Container(
            width: _phoneNavigationAddIconSize,
            height: _phoneNavigationAddIconSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? context.colors.brandStrong
                  : context.colors.selection,
              border: Border.all(
                color: context.colors.interactive.withValues(alpha: 0.55),
              ),
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 28,
                color: selected ? Colors.white : context.colors.interactive,
              ),
              child: baseIcon,
            ),
          )
        : IconTheme(
            data: IconThemeData(
              size: ButlerlySize.standardIcon,
              color: selected
                  ? context.colors.interactive
                  : context.colors.secondaryText,
            ),
            child: baseIcon,
          );
    return Semantics(
      button: true,
      selected: selected,
      label: add
          ? context.l10n.text('addTransactionAction')
          : destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _selectDestination(branchIndex),
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              SizedBox(
                height: add
                    ? ButlerlySpacing.micro
                    : ButlerlySize.navigationLabelGap,
              ),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                softWrap: true,
                style: labelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _phoneNavigationHeight(
    BuildContext context,
    Map<int, NavigationDestination> destinations,
    double availableWidth,
  ) {
    final labelStyle = ButlerlyTypography.navigationLabel(
      Theme.of(context).textTheme.labelSmall!,
      color: context.colors.secondaryText,
      selected: true,
    );
    return phoneNavigationHeightForLabels(
      textScaler: MediaQuery.textScalerOf(context),
      itemWidth: availableWidth / _visualBranchIndexes.length,
      standardLabels: [
        for (final branchIndex in _visualBranchIndexes)
          if (branchIndex != 1) destinations[branchIndex]!.label,
      ],
      addLabel: destinations[1]!.label,
      labelStyle: labelStyle,
      textDirection: Directionality.of(context),
    );
  }

  Widget _phoneNavigation(BuildContext context) {
    final destinations = _destinations(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).navigationBarTheme.backgroundColor,
        border: Border(top: BorderSide(color: context.colors.cardDivider)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: _phoneNavigationHeight(
                context,
                destinations,
                constraints.maxWidth,
              ),
              child: Row(
                children: [
                  for (final branchIndex in _visualBranchIndexes)
                    Expanded(
                      child: _destination(
                        context,
                        destinations[branchIndex]!,
                        branchIndex,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondaryRouteVisible = widget.visibilityController
        .secondaryRouteVisibleFor(navigationShell.currentIndex);
    return PopScope(
      canPop: secondaryRouteVisible || navigationShell.currentIndex != 1,
      onPopInvokedWithResult: _handleSystemBack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (secondaryRouteVisible) {
            return Scaffold(body: navigationShell);
          }

          if (constraints.maxWidth < ButlerlySize.phoneBreakpoint) {
            return Scaffold(
              body: SafeArea(bottom: false, child: navigationShell),
              bottomNavigationBar: _phoneNavigation(context),
            );
          }

          final extended =
              constraints.maxWidth >= ButlerlySize.desktopBreakpoint;
          final destinations = _destinations(context);
          final selectedVisualIndex = _visualBranchIndexes.indexOf(
            navigationShell.currentIndex,
          );
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    extended: extended,
                    selectedIndex: selectedVisualIndex,
                    onDestinationSelected: (visualIndex) => _selectDestination(
                      _visualBranchIndexes[visualIndex],
                    ),
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ButlerlySpacing.section,
                      ),
                      child: extended
                          ? Text(
                              context.l10n.text('appName'),
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(color: context.colors.primaryText),
                            )
                          : Icon(
                              Icons.circle,
                              size: 14,
                              color: context.colors.interactive,
                            ),
                    ),
                    destinations: [
                      for (final branchIndex in _visualBranchIndexes)
                        NavigationRailDestination(
                          icon: destinations[branchIndex]!.icon,
                          selectedIcon:
                              destinations[branchIndex]!.selectedIcon,
                          label: Text(destinations[branchIndex]!.label),
                        ),
                    ],
                  ),
                  VerticalDivider(width: 1, color: context.colors.cardDivider),
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
