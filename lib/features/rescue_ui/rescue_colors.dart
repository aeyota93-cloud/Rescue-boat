import 'package:flutter/painting.dart';

/// Шлюпка: цвета стиля «Д» (тёмный). Источник — docs/redesign/style-d.md и макет
/// docs/redesign/mockup/style-d-dark.html.
///
/// Новые экраны берут токены из первого блока (page, panel, card, deep, text, muted …).
/// Второй блок — старые имена варианта «Г», оставлены алиасами на новые значения, чтобы
/// старые экраны собирались и выглядели прилично; в новом коде их не использовать.
abstract final class RescueColors {
  // ── Стиль «Д»: поверхности ─────────────────────────────────────────────────────────────

  /// Фон окна вокруг меню.
  static const page = Color(0xFF141311);

  /// Область выбранного раздела и сам выбранный пункт меню.
  static const panel = Color(0xFF1F1E1B);

  /// Карточки внутри области, неактивные закладки-«папки».
  static const card = Color(0xFF2A2825);

  /// Тёмные блоки-списки (ошибки, таблица туннеля), кнопка сервера.
  static const deep = Color(0xFF121110);

  // ── Стиль «Д»: текст и линии ───────────────────────────────────────────────────────────

  /// Основной текст.
  static const text = Color(0xFFF3EFE9);

  /// Вторичный текст (контраст 5.4:1 на card, 6.1:1 на panel, 6.9:1 на deep).
  static const muted = Color(0xFFA39B91);

  /// Основной текст на deep (чуть светлее [text], как в макете).
  static const textOnDeep = Color(0xFFFAF8F5);

  /// Вторичный текст в тёмных списках (deep).
  static const subOnDeep = Color(0xFFBDB5AB);

  /// Линии, дорожки колец и полосок, плитки-значки в тёмных списках.
  static const line = Color(0xFF3A3835);

  /// Пунктир, рамки меток.
  static const line2 = Color(0xFF4A4642);

  /// Точка «выключено / не в сети» (только графика, не текст).
  static const off = Color(0xFF6E675F);

  // ── Стиль «Д»: акцент (жёлтый) ─────────────────────────────────────────────────────────

  /// Жёлтый: блок подключения, выделенная строка, кнопки действия.
  static const accent = Color(0xFFF4CC56);

  /// Текст на жёлтом (10.9:1). На жёлтом — только тёмный текст.
  static const onAccent = Color(0xFF1F1D1A);

  /// Вторичный текст на жёлтом (6.4:1).
  static const onAccentMuted = Color(0xFF4A4232);

  /// Дорожки колец и сегменты на жёлтом.
  static const accentDeep = Color(0xFFE8BD3F);

  /// Плитка-значок в жёлтой строке.
  static const accentTile = Color(0xFFF8DE8C);

  /// Тёмная заливка и рамки на жёлтом (включённая таблетка режима, кнопка питания).
  static const ink = Color(0xFF232220);

  // ── Стиль «Д»: сигналы ─────────────────────────────────────────────────────────────────

  /// Счётчик ошибок, точки-уведомления; «опасно» на тёмном фоне. Текст на нём — [onAccent].
  static const warn = Color(0xFFE9853A);

  /// «Удалить» на жёлтом (5.5:1). На тёмном не использовать — там [warn].
  static const danger = Color(0xFF8A2E1E);

  // ── Логотип-спасательный круг ──────────────────────────────────────────────────────────
  static const logoWhite = Color(0xFFFFFFFF);
  static const logoRed = Color(0xFFD93A2B);

  // ── Старые имена (вариант «Г») → значения стиля «Д». Только для совместимости. ───────────

  /// Было: фон окна. Теперь экраны лежат на области [panel], поэтому алиас на неё.
  static const background = panel;

  /// Разделитель строк.
  static const rowLine = line;

  /// Выбранная строка или карточка-выбор.
  static const selected = deep;

  /// Вторичный текст.
  static const textSecondary = muted;

  /// Третичный текст.
  static const textTertiary = subOnDeep;

  /// Мягкий акцент: тёмная плашка с жёлтым текстом.
  static const softAccent = deep;
  static const softAccentText = accent;

  /// Дорожка полосок и колец.
  static const track = line;
  static const accentHover = accentTile;

  /// Было: бирюзовый «мимо VPN». В стиле «Д» — светлый, чтобы отличался от жёлтого.
  static const teal = text;

  /// Оценки: хорошо — жёлтый, средне — приглушённый, плохо — оранжевый.
  static const good = accent;
  static const fair = muted;
  static const poor = warn;

  // Бейджи (фон / текст): тёмная плашка с цветным текстом.
  static const importantBg = deep;
  static const importantText = warn;
  static const warningBg = deep;
  static const warningText = accent;
  static const bypassBg = deep;
  static const bypassText = text;
  static const successBg = deep;
  static const successText = accent;

  /// Рамка опасной кнопки на тёмном фоне.
  static const dangerBorder = warn;
}
