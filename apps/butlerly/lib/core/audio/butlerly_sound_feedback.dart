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

  /// Explicitly enabled confirmation feedback should be audible on iPhone
  /// even when the Ring/Silent switch is on, without interrupting other audio.
  @visibleForTesting
  static AudioContext confirmationAudioContext() => AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
    respectSilence: false,
  ).build();

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
        // iOS otherwise silences the confirmation tone in Silent mode.
        // Other platforms keep their default audio routing.
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          await _player.setAudioContext(confirmationAudioContext());
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
