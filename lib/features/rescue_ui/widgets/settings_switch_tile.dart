import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';
import 'package:hiddify/features/rescue_ui/widgets/rescue_toggle.dart';

/// Шлюпка: строка настроек — заголовок, серая подпись и переключатель справа.
///
/// Нажимается вся строка (высота от 64). [divider] — линия снизу, как между строками в макете.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.divider = true,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// null — строка неактивна.
  final ValueChanged<bool>? onChanged;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final subtitle = this.subtitle;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: title,
      hint: subtitle,
      onTap: enabled ? () => onChanged(!value) : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: divider ? const Border(bottom: BorderSide(color: RescueColors.rowLine)) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: enabled ? RescueColors.text : RescueColors.textSecondary,
                        ),
                      ),
                      if (subtitle != null) Text(subtitle, style: RescueText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                RescueToggle(value: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
