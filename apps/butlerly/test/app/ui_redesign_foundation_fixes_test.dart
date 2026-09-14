import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
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

  test('quiet-premium bodySmall meets the normal-text contrast target', () {
    final theme = AppTheme.light;
    final colors = theme.extension<ButlerlySemanticColors>()!;
    final bodySmallColor = theme.textTheme.bodySmall!.color!;

    expect(bodySmallColor, colors.secondaryText);
    expect(
      _contrastRatio(bodySmallColor, colors.background),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
    expect(
      _contrastRatio(bodySmallColor, colors.subtleSurface),
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

  test('phone navigation measures the actual label under nonlinear scaling', () {
    const scaler = _NavigationNonlinearTextScaler();
    final height = phoneNavigationHeightForTextScaler(scaler);

    // The test scaler barely scales a 1 px probe but doubles the real 10.5 px
    // navigation label. This catches regressions back to scale(1).
    expect(scaler.scale(1), 1.1);
    expect(
      scaler.scale(ButlerlyTypography.navigationLabelFontSize),
      ButlerlyTypography.navigationLabelFontSize * 2,
    );
    expect(
      height,
      ButlerlySize.navigationBarHeight +
          ButlerlySize.navigationBarMaxAccessibilityGrowth,
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

        _expectNoFlutterException(tester);
        expect(find.text('Home'), findsAtLeastNWidgets(1));
        expect(find.text('Transactions'), findsOneWidget);
        expect(find.bySemanticsLabel('Add transaction'), findsOneWidget);
        expect(find.text('Tools'), findsOneWidget);
        expect(find.text('More'), findsAtLeastNWidgets(1));
      },
    );
  }

  testWidgets('Spanish phone navigation has no overflow at 2x text scale', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();
    await _switchLanguage(tester, 'Spanish');

    tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    _expectNoFlutterException(tester);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Transacciones'), findsOneWidget);
    expect(find.text('Herramientas'), findsOneWidget);
    expect(find.text('Más'), findsAtLeastNWidgets(1));
  });

  testWidgets('Chinese phone navigation has no overflow at 2x text scale', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();
    await _switchLanguage(tester, 'Chinese (Simplified)');

    tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    _expectNoFlutterException(tester);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('交易'), findsAtLeastNWidgets(1));
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('更多'), findsAtLeastNWidgets(1));
  });
}

Future<void> _switchLanguage(WidgetTester tester, String language) async {
  await tester.tap(find.text('More').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('English'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(language).last);
  await tester.pumpAndSettle();
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectNoFlutterException(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception is FlutterError) {
    fail(exception.toStringDeep());
  }
  expect(exception, isNull);
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class _NavigationNonlinearTextScaler extends TextScaler {
  const _NavigationNonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize < 2 ? fontSize * 1.1 : fontSize * 2;

  @override
  double get textScaleFactor => 2;
}
