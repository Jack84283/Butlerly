import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Home header remains readable when a tablet rail narrows the page',
    (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

      HomePage.debugCurrentDate = DateTime(2026, 9, 14, 13);
      addTearDown(() => HomePage.debugCurrentDate = null);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Row(
            children: [
              const SizedBox(width: 73),
              const Expanded(child: Scaffold(body: HomePage())),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Butlerly'), findsOneWidget);
      expect(find.text('Buenas tardes'), findsOneWidget);
      expect(find.text('septiembre de 2026'), findsOneWidget);
      expect(
        find.text('UNA FORMA MÁS TRANQUILA DE VIVIR EL DINERO'),
        findsOneWidget,
      );

      for (final finder in [
        find.text('Butlerly'),
        find.text('Buenas tardes'),
        find.text('septiembre de 2026'),
        find.text('UNA FORMA MÁS TRANQUILA DE VIVIR EL DINERO'),
      ]) {
        final text = tester.widget<Text>(finder);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }

      final exception = tester.takeException();
      if (exception is FlutterError) fail(exception.toStringDeep());
      expect(exception, isNull);
    },
  );
}
