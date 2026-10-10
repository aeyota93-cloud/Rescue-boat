import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/rescue_toggle.dart';

/// Шлюпка: «таблетка» подключения — точка, текст статуса и переключатель (фон card, без рамки).
///
/// Нажимается целиком (мышь, Enter/Пробел). Для чтеца — переключатель с подписью [label].
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({
    super.key,
    required this.connected,
    required this.label,
    required this.onChanged,
    this.busy = false,
  });

  /// Включён ли VPN (положение переключателя).
  final bool connected;

  /// Текст статуса: «Подключено · Нидерланды · 48 мс», «Отключено».
  final String label;

  /// Вызывается с новым желаемым состоянием. null — неактивна.
  final ValueChanged<bool>? onChanged;

  /// Идёт подключение/отключение: точка оранжевая.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final dot = busy
        ? RescueColors.warn
        : connected
        ? RescueColors.accent
        : RescueColors.off;
    const shape = StadiumBorder();
    return Semantics(
      toggled: connected,
      enabled: onChanged != null,
      label: label,
      onTap: onChanged == null ? null : () => onChanged(!connected),
      child: ExcludeSemantics(
        child: Material(
          color: RescueColors.card,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onChanged == null ? null : () => onChanged(!connected),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.only(left: 18, right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RescueColors.text),
                      ),
                    ),
                    const SizedBox(width: 12),
                    RescueToggle(value: connected),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
