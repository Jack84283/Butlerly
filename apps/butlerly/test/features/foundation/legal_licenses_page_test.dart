import 'package:butlerly/design_system/components/butlerly_brand_icon.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app({Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const LegalLicensesPage(),
  );

  testWidgets('desktop Legal keeps documents and reader side by side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('desktop-legal-document-list'));
    final reader = find.byKey(const ValueKey('desktop-legal-reader-0-en'));
    expect(list, findsOneWidget);
    expect(reader, findsOneWidget);
    expect(tester.getRect(list).right, lessThan(tester.getRect(reader).left));
    expect(
      find.byKey(const ValueKey('desktop-legal-document-3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('desktop-legal-document-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-legal-reader-1-en')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Legal retains the existing document navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-legal-document-list')),
      findsNothing,
    );
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.byType(ButlerlyBrandVersionTile), findsOneWidget);
    expect(find.byType(ButlerlyBrandIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('all four legal review documents are bundled in three languages', () async {
    const documents = [
      LegalDocument('termsOfUse', 'assets/legal/terms_of_use.txt'),
      LegalDocument('privacyPolicy', 'assets/legal/privacy_policy.txt'),
      LegalDocument(
        'softwareLicenseThirdPartyNotices',
        'assets/legal/third_party_notices.txt',
      ),
      LegalDocument(
        'aiProfessionalAdviceDisclosures',
        'assets/legal/ai_disclosures.txt',
      ),
    ];
    const ids = ['LEG-0001', 'LEG-0002', 'LEG-0003', 'LEG-0004'];
    for (var i = 0; i < documents.length; i++) {
      for (final locale in AppLocalizations.supportedLocales) {
        final path = documents[i].assetPathFor(locale);
        final text = await rootBundle.loadString(path);
        expect(text, contains(ids[i]), reason: path);
        expect(text, contains('v1.1'), reason: path);
        switch (locale.languageCode) {
          case 'zh':
            expect(text, contains('审阅稿'), reason: path);
          case 'es':
            expect(text, contains('revisión Alpha'), reason: path);
          default:
            expect(text, contains('review edition v1.1'), reason: path);
        }
      }
    }
    expect(
      documents.first.assetPathFor(const Locale('fr')),
      'assets/legal/terms_of_use.txt',
    );
  });

  testWidgets('desktop reader displays the Chinese and Spanish legal text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(locale: const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    final chinese = find.descendant(
      of: find.byKey(const ValueKey('desktop-legal-reader-0-zh')),
      matching: find.byType(SelectableText),
    );
    expect(chinese, findsOneWidget);
    expect(tester.widget<SelectableText>(chinese).data, contains('使用条款'));
    expect(find.textContaining('尚未生效'), findsWidgets);

    await tester.pumpWidget(app(locale: const Locale('es')));
    await tester.pumpAndSettle();
    final spanish = find.descendant(
      of: find.byKey(const ValueKey('desktop-legal-reader-0-es')),
      matching: find.byType(SelectableText),
    );
    expect(spanish, findsOneWidget);
    expect(
      tester.widget<SelectableText>(spanish).data,
      contains('TÉRMINOS DE USO'),
    );
    expect(find.textContaining('No vigentes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop locale switch reloads the open privacy document', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var locale = const Locale('en');
    late StateSetter updateRoot;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateRoot = setState;
          return app(locale: locale);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-legal-document-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byKey(const ValueKey('desktop-legal-reader-1-en')),
              matching: find.byType(SelectableText),
            ),
          )
          .data,
      contains('PRIVACY POLICY'),
    );
    updateRoot(() => locale = const Locale('es'));
    await tester.pumpAndSettle();
    final spanish = find.descendant(
      of: find.byKey(const ValueKey('desktop-legal-reader-1-es')),
      matching: find.byType(SelectableText),
    );
    expect(spanish, findsOneWidget);
    expect(
      tester.widget<SelectableText>(spanish).data,
      contains('POLÍTICA DE PRIVACIDAD'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact reader opens an offline Chinese legal document', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(locale: const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.byType(LegalDocumentPage), findsOneWidget);
    final reader = find.byType(SelectableText);
    expect(reader, findsOneWidget);
    expect(
      tester.widget<SelectableText>(reader).data,
      contains('BUTLERLY — 隐私政策'),
    );
    expect(tester.takeException(), isNull);
  });

}
