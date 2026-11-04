import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

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
  }) => _show(
    context,
    message: message,
    status: _ToastStatus.error,
    closeLabel: closeLabel,
    detailsLabel: detailsLabel,
    onDetails: onDetails,
  );

  static void _show(
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
    // Display the most recent operation status, not a queue of stale toasts.
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
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
              TextButton(
                key: const ValueKey('butlerly-toast-details'),
                onPressed: onDetails,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: Text(detailsLabel!),
              ),
              IconButton(
                key: const ValueKey('butlerly-toast-close'),
                onPressed: messenger.hideCurrentSnackBar,
                tooltip: closeLabel,
                icon: Icon(Icons.close_rounded, color: foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ToastStatus { success, error, info }
