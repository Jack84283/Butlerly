import 'package:butlerly/features/foundation/presentation/time_zone_catalog.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

void main() {
  test('shortlist is unique, limited and localized in every UI language', () {
    expect(timeZoneCatalog, hasLength(10));
    expect(
      timeZoneCatalog.map((zone) => zone.id).toSet().length,
      timeZoneCatalog.length,
    );
    for (final locale in const [Locale('en'), Locale('zh'), Locale('es')]) {
      final labels = timeZoneCatalog.map((zone) => zone.label(locale)).toList();
      expect(labels.every((label) => label.trim().isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length);
    }
    expect(timeZoneLabelFor('America/Los_Angeles', const Locale('en')),
        'Pacific Time (Los Angeles)');
  });

  test('previously selected IANA zone remains available without rewriting it', () {
    final choices = timeZoneChoicesFor('Asia/Kolkata');
    expect(choices.where((entry) => entry.id == 'Asia/Kolkata'), hasLength(1));
    expect(choices.where((entry) => entry.id == 'UTC'), hasLength(1));
    expect(
      timeZoneLabelFor('Asia/Kolkata', const Locale('en')),
      'Kolkata (Asia/Kolkata)',
    );
    expect(
      timeZoneChoicesFor('America/Los_Angeles').length,
      timeZoneCatalog.length,
    );
  });

  test('search deduplicates IDs, not distinct cities or daylight-saving rules',
      () {
    final available = [
      TimezoneInfo(identifier: 'America/Los_Angeles'),
      TimezoneInfo(identifier: 'America/Vancouver'),
      TimezoneInfo(identifier: 'America/Vancouver'),
      TimezoneInfo(identifier: 'US/Pacific'),
    ];
    final results = searchButlerlyTimeZones(
      available,
      'America',
      locale: const Locale('en'),
    );
    expect(
      results.where((entry) => entry.id == 'America/Vancouver'),
      hasLength(1),
    );
    expect(
      results.map((entry) => entry.id),
      containsAll(['America/Vancouver', 'America/Los_Angeles']),
    );
    expect(
      searchButlerlyTimeZones(
        available,
        'Los Angeles',
        locale: const Locale('en'),
      ).map((entry) => entry.id),
      contains('America/Los_Angeles'),
    );
  });

  testWidgets('common picker offers Other and searches distinct IANA cities', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showButlerlyTimeZonePicker(
                  context,
                  selectedId: 'America/Los_Angeles',
                  loadTimeZones: (_) async => [
                    TimezoneInfo(identifier: 'Asia/Kolkata'),
                    TimezoneInfo(identifier: 'Asia/Shanghai'),
                    TimezoneInfo(identifier: 'Asia/Kolkata'),
                  ],
                );
              },
              child: const Text('Select time zone'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select time zone'));
    await tester.pumpAndSettle();
    expect(find.text('Pacific Time (Los Angeles)'), findsOneWidget);
    expect(find.text('Eastern Time (New York)'), findsOneWidget);
    expect(find.text('America/Vancouver'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Other time zones…'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Other time zones…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Kolkata');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('time-zone-result-Asia/Kolkata')),
    );
    await tester.pumpAndSettle();
    expect(selected, 'Asia/Kolkata');
    expect(tester.takeException(), isNull);
  });
}
