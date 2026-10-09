import 'package:flutter/painting.dart';

/// Шлюпка: цвета тёмной темы (вариант Г), строго с макета. См. docs/redesign/contract.md, раздел 3.
abstract final class RescueColors {
  // Поверхности
  static const background = Color(0xFF121220);
  static const card = Color(0xFF1C1C2E);
  static const line = Color(0xFF2C2C44);

  /// Разделитель строк в таблицах и списках (чуть темнее [line]).
  static const rowLine = Color(0xFF24243A);

  /// Выбранная строка или карточка-выбор.
  static const selected = Color(0xFF24243F);

  /// Пунктир «пустой» карточки, неактивная точка «не в сети».
  static const muted = Color(0xFF3A3A55);

  // Текст
  static const text = Color(0xFFF1F1F8);
  static const textSecondary = Color(0xFFA9A8C2);

  /// Третичный текст: описания в таблицах, нейтральный бейдж.
  static const textTertiary = Color(0xFFC9C8DA);

  /// Текст на заливке акцентом (кнопка «+ Добавить»).
  static const onAccent = Color(0xFF121220);

  // Акценты
  static const softAccent = Color(0xFF2E2C5C);
  static const softAccentText = Color(0xFFD3D1FF);
  static const track = Color(0xFF2A2A40);
  static const accent = Color(0xFF8B88F0);
  static const accentHover = Color(0xFFB5B3FF);
  static const teal = Color(0xFF3BBFA8);

  // Оценки
  static const good = Color(0xFF3CC47C);
  static const fair = Color(0xFFF08C1A);
  static const poor = Color(0xFFFF7A6B);

  /// Точка «отключено».
  static const off = Color(0xFF8A8AA0);

  // Бейджи: фон / текст
  static const importantBg = Color(0xFF4A1D1A);
  static const importantText = Color(0xFFFFB4A9);
  static const warningBg = Color(0xFF45300F);
  static const warningText = Color(0xFFFFCB85);
  static const bypassBg = Color(0xFF123B35);
  static const bypassText = Color(0xFF7FE0CF);
  static const successBg = Color(0xFF123B2A);
  static const successText = Color(0xFF8FE6B5);

  /// Рамка опасной кнопки («Удалить»).
  static const dangerBorder = Color(0xFF5A2A26);

  // Логотип-спасательный круг
  static const logoWhite = Color(0xFFDCE3EB);
  static const logoRed = Color(0xFFD93A2B);
}
