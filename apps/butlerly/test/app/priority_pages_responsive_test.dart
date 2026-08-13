import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sizes = [Size(320, 568), Size(390, 844), Size(430, 932)];
  final pages = <String, Widget>{
    'Settings': const SettingsPage(),
    'Import and export': const ImportExportPage(),
    'Privacy and data': const PrivacyDataPage(),
  };

  for (final entry in pages.entries) {
    for (final size in sizes) {
      testWidgets('${entry.key} reflows at ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: entry.value,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final exception = tester.takeException();
        if (exception is FlutterError) fail(exception.toStringDeep());
        expect(exception, isNull);
      });
    }
  }
}
