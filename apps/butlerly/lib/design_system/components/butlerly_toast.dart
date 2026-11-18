import 'dart:async';

import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// An owned toast can only dismiss the same notification it created.
///
/// Disposing a route must never dismiss a newer toast posted by another route.
final class ButlerlyToastHandle {
  ButlerlyToastHandle._(this._messenger, this._token);

  final ScaffoldMessengerState _messenger;
  final Object _token;

  void dismissAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messenger.mounted ||
          !identical(ButlerlyToast._activeToast[_messenger], _token)) {
        return;
      }
      ButlerlyToast._activeToast[_messenger] = null;
      _messenger.removeCurrentSnackBar();
    });
    // Registering a post-frame callback alone does not schedule a frame.
    // Ensure cleanup also completes when navigation leaves the app idle.
    WidgetsBinding.instance.scheduleFrame();
  }
}

/// Shared visual and dismissal rules for status notifications.
///
/// Success: semantic green; dismissed after five seconds.
/// Error: semantic red; retained until explicitly closed, with an optional
/// Details action that does not dismiss the notification.
///
/// Flutter's Snackbar API requires a duration even for a manually dismissed
/// message. The deliberately very long error duration is a compatibility
/// fallback; the visible Close control is the intended dismissal path.
abstract final class ButlerlyToast {
  static const successDuration = Duration(seconds: 5);
  static const _manualDismissDuration = Duration(days: 36500);
  static final Expando<Object> _activeToast = Expando<Object>('active-toast');

  static void success(BuildContext context, String message) =>
      _show(context, message: message, status: _ToastStatus.success);

  static void info(BuildContext context, String message) =>
      _show(context, message: message, status: _ToastStatus.info);

  static void error(
    BuildContext context,
    String message, {
    required String closeLabel,
    required String detailsLabel,
    required VoidCallback onDetails,
  }) {
    _show(
      context,
      message: message,
      status: _ToastStatus.error,
      closeLabel: closeLabel,
      detailsLabel: detailsLabel,
      onDetails: onDetails,
    );
  }

  /// Returns an ownership handle for errors tied to a particular route.
  static ButlerlyToastHandle ownedError(
    BuildContext context,
    String message, {
    required String closeLabel,
    required String detailsLabel,
    required VoidCallback onDetails,
  }) => _show(
    context,
    message: message,
    status: _ToastStatus.error,
    closeLabel: closeLabel,
    detailsLabel: detailsLabel,
    onDetails: onDetails,
  );

  static ButlerlyToastHandle _show(
    BuildContext context, {
    required String message,
    required _ToastStatus status,
    String? closeLabel,
    String? detailsLabel,
    VoidCallback? onDetails,
  }) {
    final colors = context.colors;
    final background = switch (status) {
      _ToastStatus.success => colors.success,
      _ToastStatus.error => colors.error,
      _ToastStatus.info => colors.info,
    };
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final messenger = ScaffoldMessenger.of(context);
    // Every Butlerly toast invalidates earlier route-owned dismissals.
    final token = Object();
    _activeToast[messenger] = token;
    // Display the most recent operation status, not a queue of stale toasts.
    messenger.removeCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        key: ValueKey('butlerly-${status.name}-toast'),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        duration: status == _ToastStatus.error
            ? _manualDismissDuration
            : successDuration,
        content: Row(
          children: [
            Icon(switch (status) {
              _ToastStatus.success => Icons.check_circle_outline_rounded,
              _ToastStatus.error => Icons.error_outline_rounded,
              _ToastStatus.info => Icons.info_outline_rounded,
            }, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
            if (status == _ToastStatus.error) ...[
              // The app-wide TextButton/IconButton themes can supply a white
              // background. Explicitly pair the error actions' white surface
              // with dark labels/icons instead of white-on-white controls.
              TextButton(
                key: const ValueKey('butlerly-toast-details'),
                onPressed: onDetails,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF202020),
                  side: BorderSide.none,
                ),
                child: Text(detailsLabel!),
              ),
              IconButton(
                key: const ValueKey('butlerly-toast-close'),
                onPressed: messenger.hideCurrentSnackBar,
                tooltip: closeLabel,
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF202020),
                  side: BorderSide.none,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    unawaited(
      controller.closed.then((_) {
        if (identical(_activeToast[messenger], token)) {
          _activeToast[messenger] = null;
        }
      }),
    );
    return ButlerlyToastHandle._(messenger, token);
  }
}

enum _ToastStatus { success, error, info }
