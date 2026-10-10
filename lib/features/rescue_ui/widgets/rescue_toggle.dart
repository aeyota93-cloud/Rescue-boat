import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: переключатель стиля «Д» — дорожка 46×28, кружок 22.
///
/// Включено — жёлтая дорожка с тёмным кружком, выключено — дорожка line с кружком muted.
/// Зона нажатия 46×44. Если [onChanged] = null — только отображение
/// (так его используют внутри SettingsSwitchTile и ConnectionPill, где нажимается вся строка).
class RescueToggle extends StatelessWidget {
  const RescueToggle({super.key, required this.value, this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? RescueColors.accent : RescueColors.line,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: value ? RescueColors.onAccent : RescueColors.muted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );

    final onChanged = this.onChanged;
    if (onChanged == null) return ExcludeSemantics(child: track);

    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(999),
        excludeFromSemantics: true,
        child: SizedBox(width: 46, height: 44, child: Center(child: track)),
      ),
    );
  }
}
