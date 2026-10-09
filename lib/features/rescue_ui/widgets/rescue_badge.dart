import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Варианты бейджа: цвета фона и текста с макета.
enum RescueBadgeKind {
  /// Важно: «7 за час», много ошибок.
  important(RescueColors.importantBg, RescueColors.importantText),

  /// Внимание: «Авто», немного ошибок.
  warning(RescueColors.warningBg, RescueColors.warningText),

  /// Мягкий акцент: путь «VPN».
  soft(RescueColors.softAccent, RescueColors.softAccentText),

  /// Нейтральный: «23 за сутки».
  neutral(RescueColors.track, RescueColors.textTertiary),

  /// Мимо VPN: путь «мимо».
  bypass(RescueColors.bypassBg, RescueColors.bypassText),

  /// Успех: «активна».
  success(RescueColors.successBg, RescueColors.successText);

  const RescueBadgeKind(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// Форма бейджа: [pill] — круглая «таблетка» 12/600 (счётчики), [tag] — метка радиус 6 (путь в таблице).
enum RescueBadgeShape { pill, tag }

/// Шлюпка: бейдж-метка.
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
    return Container(
      padding: pill
          ? const EdgeInsets.symmetric(vertical: 3, horizontal: 10)
          : const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      decoration: BoxDecoration(color: kind.background, borderRadius: BorderRadius.circular(pill ? 999 : 6)),
      child: Text(
        label,
        semanticsLabel: semanticLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: pill ? FontWeight.w600 : FontWeight.w400, color: kind.foreground),
      ),
    );
  }
}
