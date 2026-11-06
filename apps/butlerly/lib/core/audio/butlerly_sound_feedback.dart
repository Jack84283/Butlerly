import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Offline confirmation feedback for a successful transaction save/update and
/// the moment the user enables the sound preference in More.
final class ButlerlySoundFeedback {
  ButlerlySoundFeedback._();

  static final AudioPlayer _player = AudioPlayer();

  @visibleForTesting
  static Future<void> Function()? playbackForTesting;

  static Future<void> play() async {
    final override = playbackForTesting;
    if (override != null) {
      await override();
      return;
    }
    try {
      // Reuse one player so rapid interactions do not overlap multiple chimes.
      await _player.stop();
      await _player.play(
        AssetSource('audio/transaction_confirmation.wav'),
        volume: 0.65,
      );
    } catch (_) {
      // Sound is optional feedback. Never fail an already-committed save or
      // setting change because the device cannot play audio.
    }
  }
}
