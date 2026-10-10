import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: типографика стиля «Д». Шрифт не задаём — он приходит из темы (Segoe UI).
///
/// Приёмы стиля: заголовки разделов — маленькие заглавные с разрядкой ([screenTitle], [blockLabel]),
/// крупные цифры и названия закладок — тонкие ([tabTitle], [bigLight]). Разрядка в Flutter —
/// в пикселях, поэтому `0.18em` при 13 px = 2.34.
abstract final class RescueText {
  // ── Стиль «Д» ──────────────────────────────────────────────────────────────────────────

  /// Заголовок раздела: «ГЛАВНАЯ» (13 / 700 / 0.18em). Текст передавать заглавными.
  static const screenTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.34,
    color: RescueColors.text,
  );

  /// Подпись блока: «СЕРВЕР», «ОШИБКИ ЗА ЧАС» (12 / 700 / 0.14em).
  static const blockLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.68,
    color: RescueColors.text,
  );

  /// Мелкая подпись заглавными: единицы колец «МС ПИНГ», пинг сервера (11 / 700 / 0.08em).
  static const microLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.88,
    color: RescueColors.text,
  );

  /// Метка-рамка с числом («7», «ВКЛ»): 11 / 700.
  static const tag = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: RescueColors.text);

  /// Название закладки-«папки»: 24 / 300.
  static const tabTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: RescueColors.text);

  /// Крупная тонкая цифра («48 ГБ»): 34 / 300.
  static const bigLight = TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: RescueColors.text);

  /// Крупный тонкий статус («Подключено»): 28 / 300.
  static const statusLight = TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: RescueColors.text);

  /// Кнопка-таблетка и ссылка-действие: 13 / 700.
  static const button = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RescueColors.text);

  /// Заголовок строки списка: 14 / 700.
  static const rowTitle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RescueColors.text);

  // ── Общие (имена прежние, вид стиля «Д») ───────────────────────────────────────────────

  /// Заголовок страницы (h1) обычным регистром — тонкий, как названия закладок.
  static const pageTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: RescueColors.text);

  /// Подзаголовок под заголовком страницы.
  static const pageSubtitle = TextStyle(fontSize: 13, color: RescueColors.muted);

  /// Заголовок карточки (h2) обычным регистром.
  static const cardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RescueColors.text);

  static const body = TextStyle(fontSize: 14, color: RescueColors.text);
  static const bodyStrong = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RescueColors.text);
  static const small = TextStyle(fontSize: 13, color: RescueColors.text);
  static const smallSecondary = TextStyle(fontSize: 13, color: RescueColors.muted);
  static const caption = TextStyle(fontSize: 12, color: RescueColors.muted);

  /// Заголовки колонок таблиц: 11 / 700 / 0.1em.
  static const tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: RescueColors.muted,
  );
  static const axis = TextStyle(fontSize: 11, color: RescueColors.muted);

  /// Ссылка-действие «Все ошибки ›».
  static const link = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RescueColors.text);

  /// Крупное число в плитке — тонкое.
  static const bigNumber = TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: RescueColors.text);
}
