import 'package:audioplayers/audioplayers.dart';
import 'package:butlerly/core/audio/butlerly_sound_feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('create and update use distinct bundled PCM WAV assets', (
    tester,
  ) async {
    for (final sound in [
      (asset: ButlerlySoundFeedback.createdSoundAssetPath, duration: 1.30),
      (asset: ButlerlySoundFeedback.updatedSoundAssetPath, duration: 1.10),
    ]) {
      final data = await rootBundle.load('assets/${sound.asset}');
      expect(data.lengthInBytes, greaterThan(44));
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(20, Endian.little), 1); // PCM
      expect(data.getUint16(22, Endian.little), 1); // mono
      expect(data.getUint16(34, Endian.little), 16); // bits per sample
      final sampleRate = data.getUint32(24, Endian.little);
      expect(sampleRate, 44100);
      final sampleBytes = data.getUint32(40, Endian.little);
      expect(sampleBytes, data.lengthInBytes - 44);
      final seconds = sampleBytes / (sampleRate * 2);
      expect((seconds - sound.duration).abs(), lessThan(0.02));
    }
    expect(
      ButlerlySoundFeedback.createdSoundAssetPath,
      isNot(ButlerlySoundFeedback.updatedSoundAssetPath),
    );
  });

  test('Android confirmation mixes without taking over audio focus', () {
    final android = ButlerlySoundFeedback.confirmationAudioContext().android;
    expect(android.audioFocus, AndroidAudioFocus.none);
  });

  testWidgets(
    'enabled confirmation sound remains audible in iPhone Silent mode',
    (tester) async {
      final ios = ButlerlySoundFeedback.confirmationAudioContext().iOS;

      // Ambient audio is muted by the Ring/Silent switch. Playback is not.
      expect(ios.category, AVAudioSessionCategory.playback);
      // A short confirmation chime must not interrupt music or podcasts.
      expect(ios.options, contains(AVAudioSessionOptions.mixWithOthers));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
