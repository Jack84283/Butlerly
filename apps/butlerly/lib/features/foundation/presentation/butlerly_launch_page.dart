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
    super.key,
  });

  final Duration duration;

  @override
  State<ButlerlyLaunchPage> createState() => _ButlerlyLaunchPageState();
}

class _ButlerlyLaunchPageState extends State<ButlerlyLaunchPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleHome();
  }

  @override
  void didUpdateWidget(covariant ButlerlyLaunchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) _scheduleHome();
  }

  void _scheduleHome() {
    _timer?.cancel();
    _timer = Timer(widget.duration, () {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
