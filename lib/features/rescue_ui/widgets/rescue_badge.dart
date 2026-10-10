import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Варианты бейджа стиля «Д»: фон, текст и рамка (метка-рамка — прозрачный фон с рамкой цвета текста).
enum RescueBadgeKind {
  /// Важно: счётчик ошибок — оранжевая плашка с тёмным текстом (6.3:1).
  important(RescueColors.warn, RescueColors.onAccent),

  /// Внимание: метка-рамка жёлтая («7» у «ОШИБКИ ЗА ЧАС»).
  warning(Colors.transparent, RescueColors.accent, RescueColors.accent),

  /// Мягкий акцент: тёмная плашка с жёлтым текстом («АКТИВНА», путь «VPN»).
  soft(RescueColors.deep, RescueColors.accent),

  /// Нейтральный: плашка line со светлым текстом («ДО 9 НОЯБРЯ», «23 за сутки»).
  neutral(RescueColors.line, RescueColors.text),

  /// Мимо VPN: метка-рамка line2 со светлым текстом.
  bypass(Colors.transparent, RescueColors.text, RescueColors.line2),

  /// Успех: жёлтая плашка с тёмным текстом.
  success(RescueColors.accent, RescueColors.onAccent);

  const RescueBadgeKind(this.background, this.foreground, [this.border]);

  final Color background;
  final Color foreground;

  /// Рамка 1.5 px; null — без рамки.
  final Color? border;
}

/// Форма бейджа: [pill] — «таблетка» (счётчики), [tag] — метка радиус 6 (путь в таблице).
enum RescueBadgeShape { pill, tag }

/// Шлюпка: бейдж-метка, 11 / 700.
class RescueBadge extends StatelessWidget {
  const RescueBadge({
    super.key,
    required this.label,
    this.kind = RescueBadgeKind.neutral,
    this.shape = RescueBadgeShape.pill,
    this.semanticLabel,
  });

  /// Метка пути в таблицах: «VPN» / «мимо».
  const RescueBadge.tag({super.key, required this.label, this.kind = RescueBadgeKind.neutral, this.semanticLabel})
    : shape = RescueBadgeShape.tag;

  final String label;
  final RescueBadgeKind kind;
  final RescueBadgeShape shape;

  /// Если короткая надпись непонятна на слух («мимо» → «мимо VPN»).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pill = shape == RescueBadgeShape.pill;
    final border = kind.border;
    return Container(
      padding: pill
          ? const EdgeInsets.symmetric(vertical: 3, horizontal: 9)
          : const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
      decoration: BoxDecoration(
        color: kind.background,
        borderRadius: BorderRadius.circular(pill ? 999 : 6),
        border: border != null ? Border.all(color: border, width: 1.5) : null,
      ),
      child: Text(
        label,
        semanticsLabel: semanticLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kind.foreground),
      ),
    );
  }
}
