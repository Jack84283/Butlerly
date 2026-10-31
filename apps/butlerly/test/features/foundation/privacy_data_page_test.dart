import 'dart:io';

import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart'
    as share_platform;

void main() {
  setUpAll(() async {
    await Future.wait([
      initializeDateFormatting('en'),
      initializeDateFormatting('es'),
      initializeDateFormatting('zh'),
    ]);
  });

  Widget app({
    share_plus.SharePlus? shareClient,
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PrivacyDataPage(shareClient: shareClient),
    ),
  );

  testWidgets(
    'Privacy and data uses Cupertino symbols for native iOS actions',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byIcon(CupertinoIcons.archivebox), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.arrow_counterclockwise),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.arrow_down_doc), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);
      expect(find.byIcon(Icons.backup_outlined), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'wide Privacy & Data shows real actions in a two-column dashboard',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      for (final key in const [
        'desktop-privacy-local-banner',
        'desktop-privacy-backup',
        'desktop-privacy-export',
        'desktop-privacy-management',
        'desktop-privacy-danger',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.text('Backup & Recovery'), findsOneWidget);
      expect(find.text('Data Export'), findsOneWidget);
      expect(find.text('Data Management'), findsOneWidget);
      expect(find.text('Danger Zone'), findsOneWidget);

      final backup = tester.getRect(
        find.byKey(const ValueKey('desktop-privacy-backup')),
      );
      final export = tester.getRect(
        find.byKey(const ValueKey('desktop-privacy-export')),
      );
      final management = tester.getRect(
        find.byKey(const ValueKey('desktop-privacy-management')),
      );
      expect(backup.left, lessThan(export.left));
      expect(backup.top, closeTo(export.top, 1));
      expect(management.top, greaterThan(backup.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact Privacy & Data preserves its original action list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-privacy-local-banner')),
      findsNothing,
    );
    expect(find.text('Local data controls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile backup shares and then removes its temporary file', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-share-test-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    root.createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root);
    final platform = _SharePlatform();
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      app(shareClient: share_plus.SharePlus.custom(platform)),
    );
    await tester.pump();
    await tester.tap(find.text('Back up Butlerly'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'correct horse battery staple');
    await tester.enterText(fields.at(1), 'correct horse battery staple');
    await tester.tap(find.text('Create encrypted backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(platform.params, isNotNull);
    expect(platform.sawFileDuringShare, isTrue);
    debugDefaultTargetPlatformOverride = null;
    expect(gateway.discardedPath, isNotNull);
    expect(File(gateway.discardedPath!).existsSync(), isFalse);
  });

  testWidgets('restore preview formats its creation date for each locale', (
    tester,
  ) async {
    final date = DateTime(2026, 10, 31, 13, 45);
    for (final locale in const [
      Locale('en'),
      Locale('es'),
      Locale('zh', 'CN'),
    ]) {
      await tester.pumpWidget(app(locale: locale));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(PrivacyDataPage));
      final formatted = formatBackupInspectionDate(context, date);

      expect(formatted, contains('2026'));
      expect(formatted, isNot(contains('T13:45:00')));
    }
  });
}

final class _SharePlatform extends share_platform.SharePlatform {
  share_plus.ShareParams? params;
  bool sawFileDuringShare = false;

  @override
  Future<share_plus.ShareResult> share(share_plus.ShareParams value) async {
    params = value;
    final file = value.files!.single;
    sawFileDuringShare = File(file.path).existsSync();
    return const share_plus.ShareResult(
      'shared',
      share_plus.ShareResultStatus.success,
    );
  }
}

final class _ShareGateway implements LocalDataGateway {
  _ShareGateway(this.root);

  final Directory root;
  String? discardedPath;

  @override
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  }) async {
    final file = File(path.join(root.path, fileName));
    file.writeAsBytesSync(const [1, 2, 3]);
    return file.path;
  }

  @override
  Future<void> discardTemporaryBackup(String filePath) async {
    discardedPath = filePath;
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
