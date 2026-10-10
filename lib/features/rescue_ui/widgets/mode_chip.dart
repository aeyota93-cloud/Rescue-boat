import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: таблетка-переключатель режима для жёлтого фона («Весь компьютер», «Игры мимо VPN»).
///
/// Рамка 1.5 px [RescueColors.ink], высота 44, точка 8 px слева от подписи.
/// Включено — тёмная заливка с жёлтым текстом и точкой; выключено — прозрачно, тёмный текст.
/// Для чтеца — переключатель (toggled) с подписью [label] и подсказкой [hint].
class ModeChip extends StatelessWidget {
  const ModeChip({super.key, required this.label, required this.selected, required this.onChanged, this.hint});

  final String label;
  final bool selected;

  /// Вызывается с новым состоянием; null — неактивна.
  final ValueChanged<bool>? onChanged;

  /// Что значит текущее положение: «Все программы и игры». Показывается всплывающей подсказкой.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final fg = selected ? RescueColors.accent : RescueColors.onAccent;
    const shape = StadiumBorder(side: BorderSide(color: RescueColors.ink, width: 1.5));
    final tap = onChanged == null ? null : () => onChanged(!selected);
    Widget chip = Material(
      color: selected ? RescueColors.ink : Colors.transparent,
      shape: shape,
      child: InkWell(
        onTap: tap,
        customBorder: shape,
        hoverColor: RescueColors.ink.withValues(alpha: 0.08),
        focusColor: RescueColors.ink.withValues(alpha: 0.16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final hint = this.hint;
    if (hint != null) chip = Tooltip(message: hint, excludeFromSemantics: true, child: chip);
    return Semantics(
      button: true,
      toggled: selected,
      enabled: onChanged != null,
      label: label,
      hint: hint,
      onTap: tap,
      child: ExcludeSemantics(child: chip),
    );
  }
}
