import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: переключатель как в макете — дорожка 48×28, белый кружок 22.
///
/// Зона нажатия 48×44. Если [onChanged] = null — только отображение
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
      width: 48,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? RescueColors.good : RescueColors.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: const SizedBox.square(
          dimension: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
        child: SizedBox(width: 48, height: 44, child: Center(child: track)),
      ),
    );
  }
}
