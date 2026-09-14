import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light => lightFor(ButlerlyColorTheme.butlerRed);

  static ThemeData lightFor(ButlerlyColorTheme theme) => _build(
    brightness: Brightness.light,
    colors: ButlerlySemanticColors.palette(Brightness.light, theme),
  );

  static ThemeData get dark => darkFor(ButlerlyColorTheme.butlerRed);

  static ThemeData darkFor(ButlerlyColorTheme theme) => _build(
    brightness: Brightness.dark,
    colors: ButlerlySemanticColors.palette(Brightness.dark, theme),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ButlerlySemanticColors colors,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: null,
    );
    final textTheme = ButlerlyTypography.apply(
      base.textTheme,
      primaryText: colors.primaryText,
      secondaryText: colors.secondaryText,
      tertiaryText: colors.tertiaryText,
    );

    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.controlPrimary,
      onPrimary: Colors.white,
      primaryContainer: colors.selection,
      onPrimaryContainer: colors.primaryText,
      secondary: colors.brand,
      onSecondary: _onColor(colors.brand),
      secondaryContainer: colors.brand.withValues(alpha: 0.16),
      onSecondaryContainer: colors.primaryText,
      tertiary: colors.info,
      onTertiary: _onColor(colors.info),
      error: colors.error,
      onError: _onColor(colors.error),
      surface: colors.surface,
      onSurface: colors.primaryText,
      surfaceContainerHighest: colors.elevatedSurface,
      outline: colors.border,
      outlineVariant: colors.cardDivider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: colors.primaryText,
      onInverseSurface: colors.background,
      inversePrimary: colors.interactiveStrong,
    );

    final standardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      extensions: [colors],
      visualDensity: VisualDensity.standard,
      dividerColor: colors.cardDivider,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colors.background,
        foregroundColor: colors.primaryText,
        titleSpacing: ButlerlySize.phoneGutter,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          side: BorderSide(color: colors.border.withValues(alpha: 0.8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.subtleSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.standard,
          vertical: ButlerlySpacing.standard,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          borderSide: BorderSide(color: colors.interactive, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          borderSide: BorderSide(color: colors.error),
        ),
        labelStyle: TextStyle(color: colors.secondaryText),
        hintStyle: TextStyle(color: colors.secondaryText),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(colors.subtleSurface),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(color: colors.secondaryText),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: colors.interactive,
        unselectedLabelColor: colors.secondaryText,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: colors.selection,
          borderRadius: BorderRadius.circular(ButlerlyRadius.full),
          border: Border.all(color: colors.interactive.withValues(alpha: 0.28)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlyButtonTokens.horizontalPadding,
            vertical: ButlerlyButtonTokens.verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ButlerlyButtonTokens.radius),
          ),
          minimumSize: const Size(
            ButlerlyButtonTokens.compactHeight,
            ButlerlyButtonTokens.height,
          ),
          elevation: 0,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            ButlerlyButtonTokens.compactHeight,
            ButlerlyButtonTokens.height,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlyButtonTokens.horizontalPadding,
            vertical: ButlerlyButtonTokens.verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ButlerlyButtonTokens.radius),
          ),
          side: BorderSide(color: colors.border),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            ButlerlyButtonTokens.compactHeight,
            ButlerlyButtonTokens.height,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlyButtonTokens.horizontalPadding,
            vertical: ButlerlyButtonTokens.verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ButlerlyButtonTokens.radius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(ButlerlySize.minimumTarget),
          iconSize: ButlerlyButtonTokens.iconSize,
          padding: const EdgeInsets.all(ButlerlySpacing.compact),
          foregroundColor: colors.primaryText,
          disabledForegroundColor: colors.tertiaryText,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.large),
          side: BorderSide(color: colors.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.elevatedSurface,
        modalBackgroundColor: colors.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ButlerlyRadius.large),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: ButlerlySize.navigationBarHeight,
        backgroundColor: colors.background,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => ButlerlyTypography.navigationLabel(
            textTheme.labelSmall!,
            color: states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.secondaryText,
            selected: states.contains(WidgetState.selected),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.secondaryText,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.selection,
        selectedIconTheme: IconThemeData(color: colors.interactive),
        unselectedIconTheme: IconThemeData(color: colors.secondaryText),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.elevatedSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
        ),
        shape: standardShape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.subtleSurface,
        selectedColor: colors.selection,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.full),
        ),
      ),
    );
  }
}

Color _onColor(Color background) {
  final whiteContrast = _contrast(background, Colors.white);
  return whiteContrast >= 4.5 ? Colors.white : Colors.black;
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}
