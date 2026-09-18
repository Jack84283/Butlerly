import 'dart:async';

import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Branded launch presentation shared by cold-start bootstrap and the in-app
/// launch route used after inactivity resets.
class ButlerlyLaunchSurface extends StatelessWidget {
  const ButlerlyLaunchSurface({
    this.footer,
    this.screenKey = const ValueKey('butlerly-launch-screen'),
    super.key,
  });

  final Widget? footer;
  final Key screenKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: screenKey,
    body: ButlerlyResponsiveBody(
      contentKey: const ValueKey('butlerly-launch-content'),
      child: Semantics(
        label: context.l10n.text('appName'),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: context.colors.brand,
                  borderRadius: BorderRadius.circular(ButlerlyRadius.large),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: ButlerlySpacing.section),
              Text(
                context.l10n.text('appName'),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              if (footer != null) ...[
                const SizedBox(height: ButlerlySpacing.section),
                footer!,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// In-app launch route used when a running Butlerly session is reset after
/// inactivity. Cold application startup uses [ButlerlyLaunchSurface] from the
/// startup gate so initialization and the five-second brand window happen on
/// one surface instead of two sequential launch screens.
class ButlerlyLaunchPage extends StatefulWidget {
  const ButlerlyLaunchPage({
    this.duration = ButlerlySessionConfig.launchDuration,
    this.elapsedNow,
    super.key,
  });

  final Duration duration;

  /// Injectable monotonic elapsed-time source for tests. Production owns a
  /// [Stopwatch], matching the inactivity guard's clock semantics.
  final ButlerlyElapsedNow? elapsedNow;

  @override
  State<ButlerlyLaunchPage> createState() => _ButlerlyLaunchPageState();
}

class _ButlerlyLaunchPageState extends State<ButlerlyLaunchPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  Stopwatch? _ownedElapsedClock;
  late ButlerlyElapsedNow _elapsedNow;
  Duration? _startedAt;
  late Duration _remaining;
  late bool _foreground;

  @override
  void initState() {
    super.initState();
    _installElapsedClock(widget.elapsedNow);
    WidgetsBinding.instance.addObserver(this);
    _remaining = widget.duration;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    if (_foreground) _startCountdown();
  }

  @override
  void didUpdateWidget(covariant ButlerlyLaunchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clockChanged = !identical(oldWidget.elapsedNow, widget.elapsedNow);
    final durationChanged = oldWidget.duration != widget.duration;
    if (!clockChanged && !durationChanged) return;

    if (clockChanged && _foreground) _pauseCountdown();
    if (clockChanged) _installElapsedClock(widget.elapsedNow);
    if (durationChanged) {
      _timer?.cancel();
      _timer = null;
      _startedAt = null;
      _remaining = widget.duration;
    }
    if (_foreground) _startCountdown();
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
        if (_remaining <= Duration.zero) {
          _finish();
        } else {
          _startCountdown();
        }
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!_foreground) return;
        _foreground = false;
        _pauseCountdown();
        return;
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    if (!_foreground || _remaining <= Duration.zero) return;
    _startedAt = _elapsedNow();
    _timer = Timer(_remaining, _finish);
  }

  void _pauseCountdown() {
    _timer?.cancel();
    _timer = null;
    final startedAt = _startedAt;
    _startedAt = null;
    if (startedAt == null) return;
    final rawElapsed = _elapsedNow() - startedAt;
    final elapsed = rawElapsed.isNegative ? Duration.zero : rawElapsed;
    if (elapsed <= Duration.zero) return;
    _remaining = elapsed >= _remaining ? Duration.zero : _remaining - elapsed;
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    _remaining = Duration.zero;
    if (mounted) context.go('/');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ownedElapsedClock?.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ButlerlyLaunchSurface();
}
