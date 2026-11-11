import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_gold_divider.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/desktop/presentation/desktop_primary_shell.dart';
import 'package:butlerly/features/desktop/presentation/desktop_transaction_detail_split_view.dart';
import 'package:butlerly/features/foundation/presentation/statement_capture_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
    theme: AppTheme.dark,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );

  Widget desktop(Widget body) => DesktopPrimaryShell(
    currentIndex: 0,
    onSelected: (_) {},
    onMoreSectionSelected: (_) {},
    body: body,
  );

  testWidgets('desktop AppBars inherit the Home-style divider and Help gaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        desktop(
          Scaffold(
            appBar: AppBar(
              title: const Text('Statements'),
              actions: [
                IconButton(
                  key: const ValueKey('preceding-header-action'),
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                ),
                const ButlerlyContextHelpButton(articleId: 'ch-10'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerTheme = Theme.of(tester.element(find.byType(AppBar).first));
    final divider =
        headerTheme.appBarTheme.shape as ButlerlyDesktopGoldBottomBorder;
    expect(divider.thickness, ButlerlyGoldAccentTokens.thickness);
    expect(ButlerlyGoldAccentTokens.gradient.colors, const [
      Color(0xFFC0974C),
      Color(0xFFF3C670),
    ]);
    final helpPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('page-context-help-padding')),
    );
    expect(
      helpPadding.padding,
      const EdgeInsets.only(
        left: ButlerlySpacing.small,
        right: ButlerlySpacing.small,
      ),
    );
    final action = tester.getRect(
      find.byKey(const ValueKey('preceding-header-action')),
    );
    final help = tester.getRect(
      find.byKey(const ValueKey('page-context-help')),
    );
    expect(help.left - action.right, closeTo(ButlerlySpacing.small, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop split-view headers share height and vertical edges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        desktop(
          DesktopTransactionDetailSplitView(
            results: Scaffold(
              body: ButlerlyPage(
                title: 'Transactions',
                pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
                showContextHelp: false,
                children: [Text('Results')],
              ),
            ),
            detail: Scaffold(
              appBar: AppBar(title: Text('Transaction detail')),
              body: Center(child: Text('Detail')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBars = find.byType(AppBar);
    expect(appBars, findsNWidgets(2));
    final leftHeader = tester.getRect(appBars.first);
    final rightHeader = tester.getRect(appBars.last);
    expect(leftHeader.height, ButlerlySize.pageToolbarHeight);
    expect(rightHeader.height, ButlerlySize.pageToolbarHeight);
    expect(leftHeader.top, closeTo(rightHeader.top, 0.5));
    expect(leftHeader.bottom, closeTo(rightHeader.bottom, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared SliverAppBar pages also inherit the desktop divider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        desktop(
          const Scaffold(
            body: ButlerlyPage(
              title: 'Analysis',
              showContextHelp: false,
              children: [Text('Content')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shape = Theme.of(
      tester.element(find.byType(SliverAppBar)),
    ).appBarTheme.shape;
    expect(shape, isA<ButlerlyDesktopGoldBottomBorder>());
    expect(
      (shape! as ButlerlyDesktopGoldBottomBorder).thickness,
      ButlerlyGoldAccentTokens.thickness,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact headers do not receive desktop-only styling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        Scaffold(
          appBar: AppBar(
            title: const Text('Statements'),
            actions: const [ButlerlyContextHelpButton(articleId: 'ch-10')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerTheme = Theme.of(tester.element(find.byType(AppBar)));
    expect(headerTheme.appBarTheme.shape, isNull);
    expect(
      tester
          .widget<Padding>(
            find.byKey(const ValueKey('page-context-help-padding')),
          )
          .padding,
      const EdgeInsets.only(left: ButlerlySpacing.small),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded X Close is separate from trailing Help', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = false;

    await tester.pumpWidget(
      app(
        desktop(
          Scaffold(
            appBar: AppBar(
              leading: ButlerlyPanelCloseButton(
                buttonKey: const ValueKey('test-panel-close'),
                onPressed: () => closed = true,
              ),
              title: const Text('Review statement import'),
              actions: const [ButlerlyContextHelpButton(articleId: 'ch-10')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final close = find.byKey(const ValueKey('test-panel-close'));
    final help = find.byKey(const ValueKey('page-context-help-visual'));
    expect(close, findsOneWidget);
    expect(help, findsOneWidget);
    expect(tester.getRect(close).right, lessThan(tester.getRect(help).left));
    final closeButton = tester.widget<IconButton>(close);
    expect(closeButton.iconSize, ButlerlyButtonTokens.iconSize);
    expect(
      tester.getSize(close),
      const Size.square(ButlerlySize.minimumTarget),
    );
    final closeCircle = find.descendant(
      of: close,
      matching: find.byKey(const ValueKey('desktop-panel-close-circle')),
    );
    expect(closeCircle, findsOneWidget);
    expect(
      tester.getSize(closeCircle),
      const Size.square(ButlerlyButtonTokens.iconVisualSize),
    );
    expect(
      find.descendant(of: close, matching: find.byIcon(Icons.close_rounded)),
      findsOneWidget,
    );
    await tester.tap(close);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop statement footer pairs Abandon and Import', (
    tester,
  ) async {
    var abandonCount = 0;
    var importCount = 0;

    Widget footer({required bool desktop, required bool canImport}) => app(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 350,
            child: StatementReviewFooterActions(
              desktop: desktop,
              onAbandon: () => abandonCount++,
              onImport: canImport ? () => importCount++ : null,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(footer(desktop: true, canImport: false));
    await tester.pumpAndSettle();
    expect(find.text('Abandon import'), findsOneWidget);
    expect(find.text('Import data'), findsOneWidget);
    final abandon = find.byKey(
      const ValueKey('statement-review-footer-abandon'),
    );
    final import = find.byKey(const ValueKey('statement-review-import-data'));
    expect(
      tester.getRect(abandon).right,
      lessThan(tester.getRect(import).left),
    );
    expect(tester.getRect(import).top, closeTo(tester.getRect(abandon).top, 1));
    expect(tester.widget<FilledButton>(import).onPressed, isNull);
    await tester.tap(abandon);
    expect(abandonCount, 1);

    await tester.pumpWidget(footer(desktop: true, canImport: true));
    await tester.pumpAndSettle();
    await tester.tap(import);
    expect(importCount, 1);

    await tester.pumpWidget(footer(desktop: false, canImport: true));
    await tester.pumpAndSettle();
    expect(abandon, findsNothing);
    expect(import, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
