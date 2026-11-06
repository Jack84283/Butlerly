import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Offline confirmation feedback for a successful transaction save/update and
/// the moment the user enables the sound preference in More.
final class ButlerlySoundFeedback {
  ButlerlySoundFeedback._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _configured = false;

  @visibleForTesting
  static Future<void> Function()? playbackForTesting;

  static Future<void> play() async {
    final override = playbackForTesting;
    if (override != null) {
      await override();
      return;
    }
    try {
      // Keep the short local sound buffered across interactions. AudioPlayer
      // replaces an active source before starting the next one.
      if (!_configured) {
        // Only iOS needs an explicit ambient audio session so feedback
        // honors the Ring/Silent switch. Other platforms keep their default
        // routing and do not depend on session APIs being implemented.
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          await _player.setAudioContext(
            AudioContextConfig(respectSilence: true).build(),
          );
        }
        await _player.setReleaseMode(ReleaseMode.stop);
        _configured = true;
      }
      await _player.play(
        AssetSource('audio/transaction_confirmation.wav'),
        volume: 0.65,
      );
    } catch (error, stackTrace) {
      // Sound is optional feedback. Never fail an already-committed save or
      // setting change because the device cannot play audio.
      if (kDebugMode) {
        debugPrint('Butlerly sound feedback failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }
}
