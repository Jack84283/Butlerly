import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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
    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 32,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        color: colors.primaryText,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
        color: colors.secondaryText,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
        color: colors.primaryText,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 17 / 12,
        color: colors.tertiaryText,
      ),
    );

    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.interactive,
      onPrimary: Colors.white,
      primaryContainer: colors.selection,
      onPrimaryContainer: colors.primaryText,
      secondary: colors.brand,
      onSecondary: Colors.white,
      secondaryContainer: colors.brand.withValues(alpha: 0.18),
      onSecondaryContainer: colors.primaryText,
      tertiary: colors.info,
      onTertiary: Colors.white,
      error: colors.error,
      onError: Colors.white,
      surface: colors.surface,
      onSurface: colors.primaryText,
      surfaceContainerHighest: colors.elevatedSurface,
      outline: colors.border,
      outlineVariant: colors.border,
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
      dividerColor: colors.border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: colors.background,
        foregroundColor: colors.primaryText,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: ButlerlyElevation.raised,
        margin: EdgeInsets.zero,
        color: brightness == Brightness.dark
            ? colors.surface
            : colors.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          side: BorderSide(
            color: colors.border,
            width: brightness == Brightness.light ? 0 : 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
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
          borderSide: BorderSide(color: colors.interactive, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          borderSide: BorderSide(color: colors.error),
        ),
        labelStyle: TextStyle(color: colors.secondaryText),
        hintStyle: TextStyle(color: colors.tertiaryText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            ButlerlySize.minimumTarget,
            ButlerlySize.preferredTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlySpacing.section,
            vertical: ButlerlySpacing.small,
          ),
          shape: standardShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            ButlerlySize.minimumTarget,
            ButlerlySize.preferredTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlySpacing.section,
            vertical: ButlerlySpacing.small,
          ),
          shape: standardShape,
          side: BorderSide(color: colors.border),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            ButlerlySize.minimumTarget,
            ButlerlySize.minimumTarget,
          ),
          shape: standardShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(ButlerlySize.minimumTarget),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.elevatedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.large),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.elevatedSurface,
        modalBackgroundColor: colors.elevatedSurface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ButlerlyRadius.large),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colors.surface,
        indicatorColor: colors.selection,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            color: states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.secondaryText,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
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
        backgroundColor: colors.surface,
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
        backgroundColor: colors.surface,
        selectedColor: colors.selection,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ButlerlyRadius.full),
        ),
      ),
    );
  }
}
