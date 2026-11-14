import 'package:audioplayers/audioplayers.dart';
import 'package:butlerly/core/audio/butlerly_sound_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('save feedback uses a bundled Butlerly WAV on all platforms', (
    tester,
  ) async {
    final data = await rootBundle.load(
      'assets/${ButlerlySoundFeedback.soundAssetPath}',
    );
    expect(data.lengthInBytes, greaterThan(44));
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
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
