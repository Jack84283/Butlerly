import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Offline confirmation feedback for a successful transaction save/update and
/// the moment the user enables the sound preference in More.
final class ButlerlySoundFeedback {
  ButlerlySoundFeedback._();

  // Distinct offline sounds for successful create and update operations.
  // AudioPlayer's asset cache prefixes these paths with "assets/".
  static const String createdSoundAssetPath = 'audio/item_created.wav';
  static const String updatedSoundAssetPath = 'audio/item_updated.wav';

  // Kept for callers that previously used the single confirmation sound.
  static const String soundAssetPath = createdSoundAssetPath;

  static final AudioPlayer _player = AudioPlayer();
  static bool _configured = false;

  @visibleForTesting
  static Future<void> Function(String assetPath)? playbackForTesting;

  /// Play Butlerly's own confirmation WAV, not a device ringtone or
  /// notification sound. On mobile, do not interrupt music or podcasts.
  /// iOS also allows this explicitly enabled sound in Silent mode.
  @visibleForTesting
  static AudioContext confirmationAudioContext() => AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
    respectSilence: false,
  ).build();

  static Future<void> playCreated() => _play(createdSoundAssetPath);

  static Future<void> playUpdated() => _play(updatedSoundAssetPath);

  /// Backward-compatible confirmation entrypoint: preview the create sound.
  static Future<void> play() => playCreated();

  static Future<void> _play(String assetPath) async {
    try {
      final override = playbackForTesting;
      if (override != null) {
        await override(assetPath);
        return;
      }
      // Keep the short local sound buffered across interactions. AudioPlayer
      // replaces an active source before starting the next one.
      if (!_configured) {
        // Configure only supported mobile audio sessions. Desktop players
        // use the system's regular output; all platforms play the same WAV.
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android)) {
          await _player.setAudioContext(confirmationAudioContext());
        }
        await _player.setReleaseMode(ReleaseMode.stop);
        _configured = true;
      }
      await _player.play(AssetSource(assetPath), volume: 0.65);
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
