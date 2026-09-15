import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Application-level timing for Butlerly's fresh-session behavior.
abstract final class ButlerlySessionConfig {
  static const inactivityTimeout = Duration(minutes: 5);
  static const launchDuration = Duration(seconds: 5);
}

/// Tracks foreground inactivity without terminating the operating-system
/// process.
///
/// Once the timeout is reached Butlerly navigates to `/launch`, which removes
/// the active route stack from view. The launch flow then returns to Home as a
/// fresh UI session. Repository data and user preferences are intentionally
/// untouched.
class ButlerlySessionGuard extends StatefulWidget {
  const ButlerlySessionGuard({
    required this.router,
    required this.child,
    this.inactivityTimeout = ButlerlySessionConfig.inactivityTimeout,
    this.now = DateTime.now,
    super.key,
  });

  final GoRouter router;
  final Widget child;
  final Duration inactivityTimeout;
  final DateTime Function() now;

  @override
  State<ButlerlySessionGuard> createState() => _ButlerlySessionGuardState();
}

class _ButlerlySessionGuardState extends State<ButlerlySessionGuard>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  late DateTime _lastActivityAt;
  late bool _launchActive;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.router.routeInformationProvider.addListener(_handleRouteChanged);
    _lastActivityAt = widget.now();
    _launchActive = _isLaunchRoute;
    if (!_launchActive) _scheduleTimeout();
  }

  @override
  void didUpdateWidget(covariant ButlerlySessionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routeInformationProvider.removeListener(
        _handleRouteChanged,
      );
      widget.router.routeInformationProvider.addListener(_handleRouteChanged);
      _launchActive = _isLaunchRoute;
    }
    if (oldWidget.inactivityTimeout != widget.inactivityTimeout ||
        oldWidget.now != widget.now) {
      _lastActivityAt = widget.now();
    }
    _scheduleTimeout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (_launchActive) return;
        _scheduleTimeout();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        _inactivityTimer?.cancel();
    }
  }

  bool get _isLaunchRoute =>
      widget.router.routeInformationProvider.value.uri.path == '/launch';

  void _handleRouteChanged() {
    final launchActive = _isLaunchRoute;
    if (launchActive == _launchActive) return;
    _launchActive = launchActive;
    if (_launchActive) {
      _inactivityTimer?.cancel();
      return;
    }

    // The launch flow has completed. Start the inactivity clock from the fresh
    // Home session rather than carrying pre-launch idle time forward.
    _lastActivityAt = widget.now();
    _scheduleTimeout();
  }

  void _recordActivity() {
    if (!_foreground || _launchActive) return;
    _lastActivityAt = widget.now();
    _scheduleTimeout();
  }

  void _scheduleTimeout() {
    _inactivityTimer?.cancel();
    if (!_foreground || _launchActive) return;

    final elapsed = widget.now().difference(_lastActivityAt);
    final remaining = widget.inactivityTimeout - elapsed;
    if (remaining <= Duration.zero) {
      _expireSession();
      return;
    }
    _inactivityTimer = Timer(remaining, _handleTimeout);
  }

  void _handleTimeout() {
    if (!_foreground || _launchActive) return;
    final elapsed = widget.now().difference(_lastActivityAt);
    if (elapsed < widget.inactivityTimeout) {
      _scheduleTimeout();
      return;
    }
    _expireSession();
  }

  void _expireSession() {
    _inactivityTimer?.cancel();
    if (!_foreground || _launchActive || !mounted) return;
    widget.router.go('/launch');
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    widget.router.routeInformationProvider.removeListener(_handleRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _recordActivity(),
    onPointerSignal: (PointerSignalEvent _) => _recordActivity(),
    child: widget.child,
  );
}
