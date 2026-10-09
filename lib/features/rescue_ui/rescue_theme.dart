import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: тёмная тема нового дизайна (Material 3).
///
/// Подключение одной строкой в `MaterialApp.router`:
/// `theme: RescueTheme.dark(), darkTheme: RescueTheme.dark(), themeMode: ThemeMode.dark,`
/// (или просто `theme: RescueTheme.dark()` и убрать `darkTheme`/`themeMode`).
abstract final class RescueTheme {
  /// Системный шрифт Windows; ничего не скачиваем и не вшиваем.
  static const fontFamily = 'Segoe UI';
  static const fontFamilyFallback = ['Segoe UI Variable', 'Segoe UI', 'Tahoma'];

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: RescueColors.accent,
      onPrimary: RescueColors.onAccent,
      primaryContainer: RescueColors.softAccent,
      onPrimaryContainer: RescueColors.softAccentText,
      secondary: RescueColors.teal,
      onSecondary: RescueColors.onAccent,
      secondaryContainer: RescueColors.bypassBg,
      onSecondaryContainer: RescueColors.bypassText,
      tertiary: RescueColors.fair,
      onTertiary: RescueColors.onAccent,
      tertiaryContainer: RescueColors.warningBg,
      onTertiaryContainer: RescueColors.warningText,
      error: RescueColors.poor,
      onError: RescueColors.onAccent,
      errorContainer: RescueColors.importantBg,
      onErrorContainer: RescueColors.importantText,
      surface: RescueColors.card,
      onSurface: RescueColors.text,
      onSurfaceVariant: RescueColors.textSecondary,
      surfaceDim: RescueColors.background,
      surfaceContainerLowest: RescueColors.background,
      surfaceContainerLow: RescueColors.background,
      surfaceContainer: RescueColors.card,
      surfaceContainerHigh: RescueColors.card,
      surfaceContainerHighest: RescueColors.track,
      outline: RescueColors.line,
      outlineVariant: RescueColors.rowLine,
      inverseSurface: RescueColors.text,
      onInverseSurface: RescueColors.background,
      inversePrimary: RescueColors.softAccent,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      scaffoldBackgroundColor: RescueColors.background,
      canvasColor: RescueColors.background,
      cardColor: RescueColors.card,
      dividerColor: RescueColors.line,
      focusColor: RescueColors.accent.withValues(alpha: 0.24),
      hoverColor: RescueColors.text.withValues(alpha: 0.05),
      splashColor: RescueColors.accent.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      // Существующие экраны Hiddify читают это расширение.
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    // Стиль кнопок заменяет labelLarge целиком, поэтому шрифт указываем явно.
    const buttonText = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    const buttonSize = Size(44, 44);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18);

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineSmall: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            bodyLarge: const TextStyle(fontSize: 15),
            bodyMedium: const TextStyle(fontSize: 14),
            bodySmall: const TextStyle(fontSize: 12, color: RescueColors.textSecondary),
            labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            labelSmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          )
          .apply(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            bodyColor: RescueColors.text,
            displayColor: RescueColors.text,
          ),
      cardTheme: CardThemeData(
        color: RescueColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: RescueColors.line),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: RescueColors.background,
        foregroundColor: RescueColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: RescueColors.text),
      ),
      dividerTheme: const DividerThemeData(color: RescueColors.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RescueColors.accent,
          foregroundColor: RescueColors.onAccent,
          disabledBackgroundColor: RescueColors.track,
          disabledForegroundColor: RescueColors.textSecondary,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RescueColors.text,
          disabledForegroundColor: RescueColors.textSecondary,
          side: const BorderSide(color: RescueColors.line),
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RescueColors.accent,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: RescueColors.textSecondary,
          minimumSize: buttonSize,
          shape: buttonShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RescueColors.background,
        hintStyle: const TextStyle(fontSize: 14, color: RescueColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RescueColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RescueColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RescueColors.accent),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? RescueColors.good : RescueColors.track,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: RescueColors.text, borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, color: RescueColors.background),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RescueColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: RescueColors.line),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: RescueColors.text,
        contentTextStyle: TextStyle(fontSize: 14, color: RescueColors.background),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: RescueColors.accent,
        linearTrackColor: RescueColors.track,
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(RescueColors.muted),
        radius: Radius.circular(4),
      ),
    );
  }

  /// Опасная кнопка («Удалить»): контур тёмно-красный, текст розовый.
  static ButtonStyle dangerOutlinedButton() => OutlinedButton.styleFrom(
    foregroundColor: RescueColors.importantText,
    side: const BorderSide(color: RescueColors.dangerBorder),
  );
}
