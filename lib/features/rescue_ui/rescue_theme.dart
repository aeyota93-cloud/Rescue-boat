import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: тёмная тема стиля «Д» (Material 3).
///
/// Подключение одной строкой в `MaterialApp.router`:
/// `theme: RescueTheme.dark(), darkTheme: RescueTheme.dark(), themeMode: ThemeMode.dark,`.
///
/// Material-виджеты (кнопки, переключатели, поля, диалоги, меню) перекрашены так, чтобы старые
/// экраны Hiddify внутри «Для опытных» выглядели в том же стиле: фон экрана — [RescueColors.panel]
/// (область каркаса), карточки — [RescueColors.card], действие — жёлтая таблетка.
abstract final class RescueTheme {
  /// Системный шрифт Windows; ничего не скачиваем и не вшиваем.
  static const fontFamily = 'Segoe UI';
  static const fontFamilyFallback = ['Segoe UI Variable', 'Segoe UI', 'Tahoma'];

  /// Текст кнопок-таблеток: 13 / 700. Стиль кнопок заменяет labelLarge целиком, поэтому шрифт явно.
  static const buttonText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const _buttonSize = Size(44, 44);
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: 18);
  static const _pill = StadiumBorder();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: RescueColors.accent,
      onPrimary: RescueColors.onAccent,
      primaryContainer: RescueColors.deep,
      onPrimaryContainer: RescueColors.accent,
      secondary: RescueColors.accentDeep,
      onSecondary: RescueColors.onAccent,
      secondaryContainer: RescueColors.line,
      onSecondaryContainer: RescueColors.text,
      tertiary: RescueColors.warn,
      onTertiary: RescueColors.onAccent,
      tertiaryContainer: RescueColors.deep,
      onTertiaryContainer: RescueColors.warn,
      error: RescueColors.warn,
      onError: RescueColors.onAccent,
      errorContainer: RescueColors.deep,
      onErrorContainer: RescueColors.warn,
      surface: RescueColors.panel,
      onSurface: RescueColors.text,
      onSurfaceVariant: RescueColors.muted,
      surfaceDim: RescueColors.page,
      surfaceBright: RescueColors.line,
      surfaceContainerLowest: RescueColors.deep,
      surfaceContainerLow: RescueColors.panel,
      surfaceContainer: RescueColors.card,
      surfaceContainerHigh: RescueColors.card,
      surfaceContainerHighest: RescueColors.line,
      outline: RescueColors.muted,
      outlineVariant: RescueColors.line,
      inverseSurface: RescueColors.text,
      onInverseSurface: RescueColors.onAccent,
      inversePrimary: RescueColors.accentDeep,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      scaffoldBackgroundColor: RescueColors.panel,
      canvasColor: RescueColors.panel,
      cardColor: RescueColors.card,
      dividerColor: RescueColors.line,
      focusColor: RescueColors.accent.withValues(alpha: 0.22),
      hoverColor: RescueColors.text.withValues(alpha: 0.06),
      splashColor: RescueColors.accent.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      // Существующие экраны Hiddify читают это расширение.
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );

    OutlineInputBorder field(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
    final menuShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    const menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(RescueColors.card),
      surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      elevation: WidgetStatePropertyAll(6),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18)))),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300),
            headlineMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
            headlineSmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
            titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            bodyLarge: const TextStyle(fontSize: 15),
            bodyMedium: const TextStyle(fontSize: 14),
            bodySmall: const TextStyle(fontSize: 12, color: RescueColors.muted),
            labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          )
          .apply(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            bodyColor: RescueColors.text,
            displayColor: RescueColors.text,
          ),
      iconTheme: const IconThemeData(color: RescueColors.text, size: 20),
      cardTheme: CardThemeData(
        color: RescueColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: RescueColors.panel,
        foregroundColor: RescueColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w300,
          color: RescueColors.text,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),
      dividerTheme: const DividerThemeData(color: RescueColors.line, thickness: 1, space: 1),
      // Действие — жёлтая таблетка с тёмным текстом.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RescueColors.accent,
          foregroundColor: RescueColors.onAccent,
          disabledBackgroundColor: RescueColors.line,
          disabledForegroundColor: RescueColors.muted,
          minimumSize: _buttonSize,
          padding: _buttonPadding,
          shape: _pill,
          textStyle: buttonText,
        ),
      ),
      // Второстепенная — таблетка с рамкой muted 1.5.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: RescueColors.text,
              disabledForegroundColor: RescueColors.muted,
              minimumSize: _buttonSize,
              padding: _buttonPadding,
              shape: _pill,
              textStyle: buttonText,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (s) => BorderSide(
                  color: s.contains(WidgetState.disabled)
                      ? RescueColors.line
                      : s.contains(WidgetState.focused)
                      ? RescueColors.accent
                      : RescueColors.muted,
                  width: 1.5,
                ),
              ),
            ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: RescueColors.line,
          foregroundColor: RescueColors.text,
          disabledBackgroundColor: RescueColors.card,
          disabledForegroundColor: RescueColors.muted,
          elevation: 0,
          minimumSize: _buttonSize,
          padding: _buttonPadding,
          shape: _pill,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RescueColors.accent,
          disabledForegroundColor: RescueColors.muted,
          minimumSize: _buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: _pill,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: RescueColors.muted,
          disabledForegroundColor: RescueColors.line2,
          minimumSize: _buttonSize,
          shape: const CircleBorder(),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: RescueColors.accent,
        foregroundColor: RescueColors.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: RescueColors.text,
          selectedBackgroundColor: RescueColors.text,
          selectedForegroundColor: RescueColors.onAccent,
          side: const BorderSide(color: RescueColors.line2, width: 1.5),
          minimumSize: _buttonSize,
          shape: _pill,
          textStyle: buttonText,
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: RescueColors.card,
        selectedColor: RescueColors.text,
        disabledColor: RescueColors.panel,
        checkmarkColor: RescueColors.onAccent,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.text),
        secondaryLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.onAccent),
        side: BorderSide(color: RescueColors.line2),
        shape: StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RescueColors.deep,
        hintStyle: const TextStyle(fontSize: 14, color: RescueColors.muted),
        labelStyle: const TextStyle(fontSize: 14, color: RescueColors.muted),
        floatingLabelStyle: const TextStyle(fontSize: 14, color: RescueColors.accent),
        helperStyle: const TextStyle(fontSize: 12, color: RescueColors.muted),
        errorStyle: const TextStyle(fontSize: 12, color: RescueColors.warn),
        prefixIconColor: RescueColors.muted,
        suffixIconColor: RescueColors.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: field(RescueColors.line),
        enabledBorder: field(RescueColors.line),
        disabledBorder: field(RescueColors.panel),
        focusedBorder: field(RescueColors.accent, 1.5),
        errorBorder: field(RescueColors.warn),
        focusedErrorBorder: field(RescueColors.warn, 1.5),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: RescueColors.accent,
        selectionColor: RescueColors.accent.withValues(alpha: 0.35),
        selectionHandleColor: RescueColors.accent,
      ),
      // Переключатель как в макете: включено — жёлтая дорожка с тёмным кружком,
      // выключено — дорожка line с кружком muted.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? RescueColors.onAccent : RescueColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? RescueColors.card
              : s.contains(WidgetState.selected)
              ? RescueColors.accent
              : RescueColors.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? RescueColors.accent : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(RescueColors.onAccent),
        side: const BorderSide(color: RescueColors.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? RescueColors.accent : RescueColors.muted,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: RescueColors.accent,
        inactiveTrackColor: RescueColors.line,
        thumbColor: RescueColors.accent,
        overlayColor: RescueColors.accent.withValues(alpha: 0.16),
        valueIndicatorColor: RescueColors.text,
        valueIndicatorTextStyle: const TextStyle(color: RescueColors.onAccent, fontWeight: FontWeight.w700),
        activeTickMarkColor: RescueColors.onAccent,
        inactiveTickMarkColor: RescueColors.muted,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: RescueColors.muted,
        textColor: RescueColors.text,
        selectedColor: RescueColors.accent,
        selectedTileColor: RescueColors.deep,
        // Шрифт явно: стиль из темы заменяет стиль подписи целиком, без него — шрифт по умолчанию.
        subtitleTextStyle: const TextStyle(
          fontSize: 12,
          color: RescueColors.muted,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minTileHeight: 52,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: RescueColors.muted,
        collapsedIconColor: RescueColors.muted,
        textColor: RescueColors.text,
        collapsedTextColor: RescueColors.text,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: RescueColors.text,
        unselectedLabelColor: RescueColors.muted,
        indicatorColor: RescueColors.accent,
        dividerColor: RescueColors.line,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: RescueColors.text, borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, color: RescueColors.onAccent),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RescueColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        titleTextStyle: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w300,
          color: RescueColors.text,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: RescueColors.text,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: RescueColors.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: RescueColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RescueColors.text,
        contentTextStyle: const TextStyle(fontSize: 14, color: RescueColors.onAccent),
        actionTextColor: RescueColors.onAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: RescueColors.card,
        surfaceTintColor: Colors.transparent,
        shape: menuShape,
        textStyle: const TextStyle(fontSize: 14, color: RescueColors.text),
      ),
      menuTheme: const MenuThemeData(style: menuStyle),
      menuBarTheme: const MenuBarThemeData(style: menuStyle),
      dropdownMenuTheme: const DropdownMenuThemeData(menuStyle: menuStyle),
      badgeTheme: const BadgeThemeData(backgroundColor: RescueColors.warn, textColor: RescueColors.onAccent),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: RescueColors.accent,
        linearTrackColor: RescueColors.line,
        circularTrackColor: Colors.transparent,
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(RescueColors.line2),
        radius: Radius.circular(4),
      ),
    );
  }

  /// Опасная кнопка на тёмном фоне («Удалить»): рамка и текст [RescueColors.warn].
  static ButtonStyle dangerOutlinedButton() => OutlinedButton.styleFrom(
    foregroundColor: RescueColors.warn,
    side: const BorderSide(color: RescueColors.warn, width: 1.5),
  );

  /// Опасная кнопка на жёлтом: рамка и текст [RescueColors.danger].
  static ButtonStyle dangerOnAccentButton() => OutlinedButton.styleFrom(
    foregroundColor: RescueColors.danger,
    side: const BorderSide(color: RescueColors.danger, width: 1.5),
  );

  /// Второстепенная кнопка на жёлтом («Переименовать»): рамка [RescueColors.ink], тёмный текст.
  static ButtonStyle outlinedOnAccentButton() => OutlinedButton.styleFrom(
    foregroundColor: RescueColors.onAccent,
    side: const BorderSide(color: RescueColors.ink, width: 1.5),
  );

  /// Тёмная кнопка-таблетка («Обновить» на жёлтом, «Открыть туннель» на карточке).
  static ButtonStyle deepFilledButton() =>
      FilledButton.styleFrom(backgroundColor: RescueColors.deep, foregroundColor: RescueColors.textOnDeep);
}
