import 'package:audioplayers/audioplayers.dart';
import 'package:butlerly/core/audio/butlerly_sound_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enabled confirmation sound remains audible in iPhone Silent mode', () {
    final ios = ButlerlySoundFeedback.confirmationAudioContext().iOS;

    // Ambient audio is muted by the Ring/Silent switch. Playback is not.
    expect(ios.category, AVAudioSessionCategory.playback);
    // A short confirmation chime must not interrupt music or podcasts.
    expect(ios.options, contains(AVAudioSessionOptions.mixWithOthers));
  });
}
