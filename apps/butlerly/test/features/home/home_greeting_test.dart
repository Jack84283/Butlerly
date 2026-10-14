import 'package:butlerly/app/locale/home_greeting.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('time-of-day greeting boundaries match across layouts', () {
    expect(greetingKeyForTime(DateTime(2026, 10, 13, 11)), 'greetingMorning');
    expect(greetingKeyForTime(DateTime(2026, 10, 13, 12)), 'greetingAfternoon');
    expect(greetingKeyForTime(DateTime(2026, 10, 13, 18)), 'greetingEvening');
  });

  for (final scenario in [
    (const Locale('en'), 'Good morning, Mia', 'Good morning'),
    (const Locale('es'), 'Buenos días, Mia', 'Buenos días'),
    (const Locale('zh', 'CN'), '早上好，Mia', '早上好'),
  ]) {
    testWidgets('localized named greeting for ${scenario.$1}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: scenario.$1,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Builder(
            builder: (context) => Column(
              children: [
                Text(homeGreetingWithName(context, 'greetingMorning', 'Mia')),
                Text(homeGreetingWithName(context, 'greetingMorning', null)),
              ],
            ),
          ),
        ),
      );

      expect(find.text(scenario.$2), findsOneWidget);
      expect(find.text(scenario.$3), findsOneWidget);
    });
  }
}
