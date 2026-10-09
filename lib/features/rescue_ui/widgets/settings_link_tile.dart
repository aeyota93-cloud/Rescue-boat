import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Шлюпка: строка-переход «Для опытных» — заголовок, подпись и «›» справа (высота от 56).
class SettingsLinkTile extends StatelessWidget {
  const SettingsLinkTile({super.key, required this.title, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

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
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: RescueColors.text),
                      ),
                      if (subtitle != null) Text(subtitle, style: RescueText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Text('›', style: TextStyle(fontSize: 14, color: RescueColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
