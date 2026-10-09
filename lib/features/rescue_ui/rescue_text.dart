import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: размеры текста с макета. Шрифт не задаём — он приходит из темы (Segoe UI).
abstract final class RescueText {
  /// Заголовок страницы (h1).
  static const pageTitle = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: RescueColors.text);

  /// Подзаголовок под заголовком страницы.
  static const pageSubtitle = TextStyle(fontSize: 13, color: RescueColors.textSecondary);

  /// Заголовок карточки (h2).
  static const cardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RescueColors.text);

  static const body = TextStyle(fontSize: 14, color: RescueColors.text);
  static const bodyStrong = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RescueColors.text);
  static const small = TextStyle(fontSize: 13, color: RescueColors.text);
  static const smallSecondary = TextStyle(fontSize: 13, color: RescueColors.textSecondary);
  static const caption = TextStyle(fontSize: 12, color: RescueColors.textSecondary);
  static const tableHeader = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RescueColors.textSecondary);
  static const axis = TextStyle(fontSize: 11, color: RescueColors.textSecondary);
  static const link = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.accent);

  /// Крупное число в плитке.
  static const bigNumber = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: RescueColors.text);
}
