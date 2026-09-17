import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Application-level timing for Butlerly's fresh-session behavior.
abstract final class ButlerlySessionConfig {
  static const inactivityTimeout = Duration(minutes: 5);
  static const launchDuration = Duration(seconds: 5);
}

typedef ButlerlyPlatformExit = Future<void> Function();
typedef ButlerlyElapsedNow = Duration Function();
typedef ButlerlyWallNow = DateTime Function();

/// Tracks inactivity and turns an expired session into a fresh Butlerly launch.
///
/// Foreground inactivity is measured with a monotonic clock rather than
/// wall-clock time so device clock and timezone changes cannot shorten or
/// extend the active privacy timeout. While Butlerly is backgrounded, a UTC
/// wall-clock snapshot supplements the monotonic clock because some platform
/// monotonic clocks pause during deep device sleep. A backward wall-clock jump
/// while backgrounded fails closed into a fresh session instead of risking an
/// indefinitely extended timeout.
///
/// On Android, a timeout reached while Butlerly is in the foreground first
/// switches to `/launch` and then asks the platform navigator to close the
/// Flutter activity. Reopening the application therefore resumes from the
/// branded launch route (or cold-starts there if the process was reclaimed).
/// If the timeout elapses while Butlerly is already backgrounded, the next
/// resume goes directly to the fresh launch route instead of immediately
/// closing the activity again.
///
/// iOS intentionally does not receive a programmatic-exit request because iOS
/// does not support apps terminating themselves; on iOS the same expiration
/// clears the active UI/navigation session and presents the fresh launch flow.
/// Repository data and persisted user preferences are intentionally untouched.
class ButlerlySessionGuard extends StatefulWidget {
  const ButlerlySessionGuard({
    required this.router,
    required this.child,
    this.inactivityTimeout = ButlerlySessionConfig.inactivityTimeout,
    this.elapsedNow,
    this.wallNow = DateTime.now,
    this.targetPlatform,
    this.onPlatformExit,
    super.key,
  });

  final GoRouter router;
  final Widget child;
  final Duration inactivityTimeout;

  /// Injectable monotonic elapsed-time source for tests. Production owns a
  /// [Stopwatch], which is unaffected by ordinary wall-clock/timezone changes.
  final ButlerlyElapsedNow? elapsedNow;

  /// Used only to account for time spent backgrounded/suspended. Foreground
  /// inactivity never depends on this wall clock.
  final ButlerlyWallNow wallNow;

  /// Injectable for tests. Production falls back to [defaultTargetPlatform].
  final TargetPlatform? targetPlatform;

  /// Injectable for tests. Production uses [SystemNavigator.pop] on Android.
  final ButlerlyPlatformExit? onPlatformExit;

  @override
  State<ButlerlySessionGuard> createState() => _ButlerlySessionGuardState();
}

class _ButlerlySessionGuardState extends State<ButlerlySessionGuard>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  Stopwatch? _ownedElapsedClock;
  late ButlerlyElapsedNow _elapsedNow;
  TextEditingController? _activeEditingController;
  late Duration _lastActivityAt;
  DateTime? _backgroundedAtWall;
  Duration? _backgroundedAtElapsed;
  late bool _launchActive;
  late bool _foreground;

  @override
  void initState() {
    super.initState();
    _installElapsedClock(widget.elapsedNow);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addSemanticsActionListener(_handleSemanticsAction);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    FocusManager.instance.addListener(_handleFocusChanged);
    widget.router.routeInformationProvider.addListener(_handleRouteChanged);
    _lastActivityAt = _elapsedNow();
    _launchActive = _isLaunchRoute;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncEditingController();
    });
    if (_foreground && !_launchActive) _scheduleTimeout();
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
    if (!identical(oldWidget.elapsedNow, widget.elapsedNow)) {
      final elapsed = _elapsedSinceActivity;
      _installElapsedClock(widget.elapsedNow);
      _lastActivityAt = _elapsedNow() - elapsed;
    }
    // Keep the original activity point across rebuilds. Rebuilding the app
    // shell is not evidence of user activity.
    _scheduleTimeout();
  }

  void _installElapsedClock(ButlerlyElapsedNow? injected) {
    _ownedElapsedClock?.stop();
    _ownedElapsedClock = null;
    if (injected != null) {
      _elapsedNow = injected;
      return;
    }
    final stopwatch = Stopwatch()..start();
    _ownedElapsedClock = stopwatch;
    _elapsedNow = () => stopwatch.elapsed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_foreground) return;
        _foreground = true;
        _syncEditingController();
        final expiredWhileAway = _backgroundCouldHaveExpired();
        _clearBackgroundSnapshot();
        if (_launchActive) return;
        if (expiredWhileAway ||
            _elapsedSinceActivity >= widget.inactivityTimeout) {
          // The app was already away when the timeout elapsed. Present the
          // fresh launch now; do not immediately close the activity the user
          // just reopened.
          _expireSession(requestPlatformExit: false);
        } else {
          // Returning to Butlerly before the privacy timeout is itself user
          // activity. Give the resumed session a full inactivity window rather
          // than carrying a nearly-expired foreground timer across the resume.
          _recordActivity();
        }
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!_foreground) return;
        _foreground = false;
        _inactivityTimer?.cancel();
        _backgroundedAtElapsed = _elapsedNow();
        _backgroundedAtWall = widget.wallNow().toUtc();
        return;
    }
  }

  bool get _isLaunchRoute =>
      widget.router.routeInformationProvider.value.uri.path == '/launch';

  Duration get _elapsedSinceActivity {
    final elapsed = _elapsedNow() - _lastActivityAt;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  bool _backgroundCouldHaveExpired() {
    final backgroundedAtElapsed = _backgroundedAtElapsed;
    final backgroundedAtWall = _backgroundedAtWall;
    if (backgroundedAtElapsed == null || backgroundedAtWall == null) {
      return false;
    }

    final rawIdleAtBackground = backgroundedAtElapsed - _lastActivityAt;
    final idleAtBackground = rawIdleAtBackground.isNegative
        ? Duration.zero
        : rawIdleAtBackground;
    final remaining = widget.inactivityTimeout - idleAtBackground;
    if (remaining <= Duration.zero) return true;

    final wallAway = widget.wallNow().toUtc().difference(backgroundedAtWall);
    if (wallAway.isNegative) {
      // The system clock moved backward while Butlerly was away. There is no
      // trustworthy suspend-inclusive duration, so protect privacy by requiring
      // a fresh session instead of potentially extending the timeout.
      return true;
    }
    return wallAway >= remaining;
  }

  void _clearBackgroundSnapshot() {
    _backgroundedAtElapsed = null;
    _backgroundedAtWall = null;
  }

  TargetPlatform get _targetPlatform =>
      widget.targetPlatform ?? defaultTargetPlatform;

  void _handleRouteChanged() {
    final launchActive = _isLaunchRoute;
    if (launchActive == _launchActive) return;
    _launchActive = launchActive;
    if (_launchActive) {
      _inactivityTimer?.cancel();
      _setEditingController(null);
      return;
    }

    // The launch flow has completed. Start the inactivity clock from the fresh
    // Home session rather than carrying pre-launch idle time forward.
    _lastActivityAt = _elapsedNow();
    _clearBackgroundSnapshot();
    _syncEditingController();
    _scheduleTimeout();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _recordActivity();
    return false;
  }

  void _handleSemanticsAction(ui.SemanticsActionEvent _) {
    // VoiceOver and TalkBack navigation and activation are delivered as
    // semantics actions, including accessibility-focus movement. Counting the
    // platform action itself avoids treating framework-only focus changes as
    // user activity.
    _recordActivity();
  }

  void _handleFocusChanged() {
    // Focus changes can also be caused by lifecycle or route transitions, so
    // they are not themselves evidence of user activity. Pointer/key events
    // already account for user-driven focus changes; this listener only keeps
    // the active EditableText controller subscription current.
    _syncEditingController();
  }

  void _handleEditingChanged() {
    // Software keyboards deliver text through the text-input channel rather
    // than HardwareKeyboard. Listening to the focused EditableText controller
    // ensures mobile typing counts as activity without requiring every form to
    // wire an inactivity callback manually.
    _recordActivity();
  }

  void _syncEditingController() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    EditableText? editable;
    final widgetAtFocus = focusContext?.widget;
    if (widgetAtFocus is EditableText) {
      editable = widgetAtFocus;
    } else {
      editable = focusContext?.findAncestorWidgetOfExactType<EditableText>();
    }
    _setEditingController(editable?.controller);
  }

  void _setEditingController(TextEditingController? controller) {
    if (identical(_activeEditingController, controller)) return;
    _activeEditingController?.removeListener(_handleEditingChanged);
    _activeEditingController = controller;
    _activeEditingController?.addListener(_handleEditingChanged);
  }

  void _recordActivity() {
    if (!_foreground || _launchActive) return;
    _lastActivityAt = _elapsedNow();
    _scheduleTimeout();
  }

  void _scheduleTimeout() {
    _inactivityTimer?.cancel();
    if (!_foreground || _launchActive) return;

    final remaining = widget.inactivityTimeout - _elapsedSinceActivity;
    if (remaining <= Duration.zero) {
      _expireSession();
      return;
    }
    _inactivityTimer = Timer(remaining, _handleTimeout);
  }

  void _handleTimeout() {
    if (!_foreground || _launchActive) return;
    if (_elapsedSinceActivity < widget.inactivityTimeout) {
      _scheduleTimeout();
      return;
    }
    _expireSession();
  }

  void _expireSession({bool requestPlatformExit = true}) {
    _inactivityTimer?.cancel();
    if (!_foreground || _launchActive || !mounted) return;

    // Set the fresh-launch route before requesting Android activity closure so
    // a warm reopen cannot expose the prior route even if the process survives.
    widget.router.go('/launch');

    if (requestPlatformExit && _targetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isLaunchRoute) return;
        unawaited(_requestPlatformExit());
      });
    }
  }

  Future<void> _requestPlatformExit() async {
    final exit = widget.onPlatformExit;
    if (exit != null) {
      await exit();
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _ownedElapsedClock?.stop();
    _clearBackgroundSnapshot();
    _setEditingController(null);
    widget.router.routeInformationProvider.removeListener(_handleRouteChanged);
    FocusManager.instance.removeListener(_handleFocusChanged);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeSemanticsActionListener(
      _handleSemanticsAction,
    );
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
