import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/power_button.dart';

/// Шлюпка: карточка статуса внизу меню (слот `RescueShell.footer`): точка, «Подключено»,
/// мелкая подпись и мини-кнопка питания. Фон card, радиус 24, отступ 14.
///
/// ```dart
/// RescueShell(
///   footer: ShellStatusCard(state: PowerState.on, title: 'Подключено', subtitle: 'Нидерланды · 48 мс', onPower: toggle),
///   compactFooter: PowerButton.mini(state: PowerState.on, onPressed: toggle),
///   ...
/// )
/// ```
class ShellStatusCard extends StatelessWidget {
  const ShellStatusCard({
    super.key,
    required this.state,
    required this.title,
    this.subtitle,
    this.onPower,
    this.powerLabel,
  });

  final PowerState state;

  /// «Подключено» / «Отключено».
  final String title;

  /// «Нидерланды · 48 мс» / «нажмите кнопку».
  final String? subtitle;

  /// Нажатие мини-кнопки; null — кнопки нет.
  final VoidCallback? onPower;

  /// Подпись кнопки для чтеца; null — по состоянию.
  final String? powerLabel;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final onPower = this.onPower;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: RescueColors.card, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (state) {
                PowerState.on => RescueColors.accent,
                PowerState.connecting => RescueColors.warn,
                PowerState.off => RescueColors.off,
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: RescueColors.subOnDeep),
                    ),
                ],
              ),
            ),
          ),
          if (onPower != null) ...[
            const SizedBox(width: 6),
            PowerButton.mini(state: state, onPressed: onPower, semanticLabel: powerLabel),
          ],
        ],
      ),
    );
  }
}
