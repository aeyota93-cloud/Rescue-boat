import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Шлюпка: строка-переход «Для опытных» — заголовок, подпись и «›» справа (высота от 52, линия снизу).
///
/// [onDeep] = true — строка в тёмном блоке (подпись subOnDeep, как в макете).
class SettingsLinkTile extends StatelessWidget {
  const SettingsLinkTile({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.divider = true,
    this.onDeep = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Линия line снизу, как между строками в макете.
  final bool divider;
  final bool onDeep;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              border: divider ? const Border(bottom: BorderSide(color: RescueColors.line)) : null,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: onDeep ? RescueColors.textOnDeep : RescueColors.text,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: RescueText.caption.copyWith(color: onDeep ? RescueColors.subOnDeep : null),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('›', style: TextStyle(fontSize: 16, color: onDeep ? RescueColors.subOnDeep : RescueColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
