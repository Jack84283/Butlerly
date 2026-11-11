import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/desktop/presentation/desktop_home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home breakdown header actions align to the right edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: DesktopHomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trendCard = find.byKey(const ValueKey('desktop-home-trend-card'));
    final categoryCard = find.byKey(
      const ValueKey('desktop-home-category-card'),
    );
    final month = find.byKey(const ValueKey('desktop-home-trend-months'));
    final viewAll = find.byKey(
      const ValueKey('desktop-home-category-view-all'),
    );
    expect(trendCard, findsOneWidget);
    expect(categoryCard, findsOneWidget);
    expect(month, findsOneWidget);
    expect(viewAll, findsOneWidget);

    expect(
      tester.widget<DropdownButton<int>>(month).alignment,
      AlignmentDirectional.centerEnd,
    );
    final buttonStyle = tester.widget<TextButton>(viewAll).style!;
    expect(
      buttonStyle.minimumSize?.resolve({}),
      const Size(
        ButlerlyButtonTokens.minimumWidth,
        ButlerlyButtonTokens.height,
      ),
    );
    expect(
      buttonStyle.padding?.resolve({}),
      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );

    final trendRight = tester.getRect(trendCard).right;
    final categoryRight = tester.getRect(categoryCard).right;
    expect(
      trendRight - tester.getRect(month).right,
      closeTo(ButlerlyDesktopInnerCard.outerGutter, 1),
    );
    expect(
      categoryRight - tester.getRect(viewAll).right,
      closeTo(ButlerlyDesktopInnerCard.outerGutter, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Home Help matches standard header edge and Add gap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget app(Widget body) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ButlerlyDesktopHeaderScope(child: Scaffold(body: body)),
      ),
    );

    await tester.pumpWidget(app(const DesktopHomePage()));
    await tester.pumpAndSettle();
    final homeHeader = find.byKey(const ValueKey('desktop-home-header'));
    final homeAdd = find.byKey(const ValueKey('desktop-home-header-add'));
    final homeHelp = find.byKey(const ValueKey('page-context-help-visual'));
    expect(homeHeader, findsOneWidget);
    expect(homeAdd, findsOneWidget);
    expect(homeHelp, findsOneWidget);
    final homeRightInset =
        tester.getRect(homeHeader).right - tester.getRect(homeHelp).right;
    final homeAddGap =
        tester.getRect(homeHelp).left - tester.getRect(homeAdd).right;

    // Mount a shared ButlerlyPage AppBar at the identical width to compare
    // the visible Help circle against the actual border, not just padding.
    await tester.pumpWidget(
      app(
        const ButlerlyPage(
          title: 'Rules',
          showContextHelp: false,
          actions: [
            ButlerlyHeaderAddButton(
              label: 'Add',
              onPressed: null,
              closeToHelp: true,
            ),
            ButlerlyContextHelpButton(
              articleId: 'ch-16',
              visualGapAfterAdd: ButlerlySpacing.small,
            ),
          ],
          children: [SizedBox(height: 40)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sharedHelp = find.byKey(const ValueKey('page-context-help-visual'));
    expect(find.byType(SliverAppBar), findsOneWidget);
    expect(sharedHelp, findsOneWidget);
    final sharedRightInset =
        tester.getRect(find.byType(Scaffold).first).right -
        tester.getRect(sharedHelp).right;

    expect(homeAddGap, closeTo(ButlerlySpacing.small, 0.5));
    expect(homeRightInset, closeTo(sharedRightInset, 0.5));
    expect(tester.takeException(), isNull);
  });
}
