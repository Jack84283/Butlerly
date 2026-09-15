import 'dart:async';

import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Branded in-app launch surface shown after the native platform splash.
///
/// It is used for both a cold application start and a fresh session after the
/// inactivity timeout. The operating-system process is never force-terminated.
class ButlerlyLaunchPage extends StatefulWidget {
  const ButlerlyLaunchPage({
    this.duration = ButlerlySessionConfig.launchDuration,
    this.now = DateTime.now,
    super.key,
  });

  final Duration duration;
  final DateTime Function() now;

  @override
  State<ButlerlyLaunchPage> createState() => _ButlerlyLaunchPageState();
}

class _ButlerlyLaunchPageState extends State<ButlerlyLaunchPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _startedAt;
  late Duration _remaining;
  late bool _foreground;

  @override
  void initState() {
    super.initState();
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
    if (oldWidget.duration == widget.duration) return;
    _timer?.cancel();
    _startedAt = null;
    _remaining = widget.duration;
    if (_foreground) _startCountdown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
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
        _foreground = false;
        _pauseCountdown();
        return;
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    if (!_foreground || _remaining <= Duration.zero) return;
    _startedAt = widget.now();
    _timer = Timer(_remaining, _finish);
  }

  void _pauseCountdown() {
    _timer?.cancel();
    _timer = null;
    final startedAt = _startedAt;
    _startedAt = null;
    if (startedAt == null) return;
    final elapsed = widget.now().difference(startedAt);
    if (elapsed <= Duration.zero) return;
    _remaining = elapsed >= _remaining
        ? Duration.zero
        : _remaining - elapsed;
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('butlerly-launch-screen'),
    body: Semantics(
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
          ],
        ),
      ),
    ),
  );
}
