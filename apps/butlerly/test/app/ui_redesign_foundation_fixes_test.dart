import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  test('quiet-premium readable small text meets the contrast target', () {
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;

    expect(
      _contrastRatio(colors.secondaryText, colors.background),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
    expect(
      _contrastRatio(colors.secondaryText, colors.subtleSurface),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
  });

  test('editorial placeholder keeps cross-platform serif fallbacks', () {
    expect(ButlerlyTypography.editorialFontFamily, 'Georgia');
    expect(
      ButlerlyTypography.editorialFontFallback,
      containsAll(const ['Times New Roman', 'Noto Serif', 'serif']),
    );
  });

  testWidgets('transaction metadata uses the readable small-text color', (
    tester,
  ) async {
    late TextStyle metadataStyle;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            metadataStyle = context.transactionItemMetadata;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      metadataStyle.color,
      AppTheme.light.extension<ButlerlySemanticColors>()!.secondaryText,
    );
  });

  testWidgets('Add and Tools share the action-group primitive', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyActionGroup), findsNWidgets(2));
    expect(find.byType(ButlerlyActionRow), findsNWidgets(5));
    final addSubtitle = tester.widget<Text>(
      find.text('Enter transaction details yourself'),
    );
    expect(
      addSubtitle.style?.color,
      AppTheme.light.extension<ButlerlySemanticColors>()!.secondaryText,
    );

    appRouter.go('/tools');
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyActionGroup), findsOneWidget);
    expect(find.byType(ButlerlyActionRow), findsNWidgets(4));
  });

  for (final textScale in const [1.3, 1.5, 2.0]) {
    testWidgets(
      'phone navigation has no overflow at ${textScale}x text scale',
      (tester) async {
        _setPhoneViewport(tester);
        tester.view.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(
          tester.view.platformDispatcher.clearTextScaleFactorTestValue,
        );

        await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
        await tester.pumpAndSettle();

        final exception = tester.takeException();
        if (exception is FlutterError) {
          fail(exception.toStringDeep());
        }
        expect(exception, isNull);
        expect(find.text('Home'), findsAtLeastNWidgets(1));
        expect(find.text('Transactions'), findsOneWidget);
        expect(find.bySemanticsLabel('Add transaction'), findsOneWidget);
        expect(find.text('Tools'), findsOneWidget);
        expect(find.text('More'), findsAtLeastNWidgets(1));
      },
    );
  }
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
