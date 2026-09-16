import 'package:butlerly/app/shell/desktop/desktop_primary_shell.dart';
import 'package:butlerly/app/shell/ipad/ipad_primary_shell.dart';
import 'package:butlerly/app/shell/iphone/iphone_primary_shell.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

export 'package:butlerly/app/shell/shared/primary_bottom_navigation.dart'
    show phoneNavigationHeightForLabels;

const primaryShellRouteNamePrefix = 'primary-shell:';

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
    this.onPop,
  });

  final int branchIndex;
  final PrimaryShellVisibilityController controller;
  final VoidCallback? onPop;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, previousRoute);
    onPop?.call();
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

  @override
  Widget build(BuildContext context) {
    final secondaryRouteVisible = widget.visibilityController
        .secondaryRouteVisibleFor(navigationShell.currentIndex);

    late final Widget shell;
    if (secondaryRouteVisible) {
      shell = Scaffold(body: navigationShell);
    } else {
      final destinations = _destinations(context);
      final view = View.of(context);
      final display = view.display;
      final deviceDisplaySize = display.size / display.devicePixelRatio;
      final deviceClass = ButlerlyLayout.deviceClass(
        MediaQuery.sizeOf(context),
        deviceDisplaySize: deviceDisplaySize,
      );
      shell = switch (deviceClass) {
        ButlerlyDeviceClass.phone => IPhonePrimaryShell(
          body: navigationShell,
          destinations: destinations,
          visualBranchIndexes: _visualBranchIndexes,
          currentIndex: navigationShell.currentIndex,
          onSelected: _selectDestination,
        ),
        ButlerlyDeviceClass.tablet => IPadPrimaryShell(
          body: navigationShell,
          destinations: destinations,
          visualBranchIndexes: _visualBranchIndexes,
          currentIndex: navigationShell.currentIndex,
          onSelected: _selectDestination,
        ),
        ButlerlyDeviceClass.desktop => DesktopPrimaryShell(
          body: navigationShell,
          destinations: destinations,
          visualBranchIndexes: _visualBranchIndexes,
          currentIndex: navigationShell.currentIndex,
          onSelected: _selectDestination,
        ),
      };
    }

    return PopScope(
      canPop: secondaryRouteVisible || navigationShell.currentIndex != 1,
      onPopInvokedWithResult: _handleSystemBack,
      child: shell,
    );
  }
}
