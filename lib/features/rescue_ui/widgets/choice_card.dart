import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: крупная карточка-выбор («Весь компьютер (VPN)» / «Только браузеры (прокси)»).
///
/// Выбранная — рамка 2 px акцентом и фон #24243F. Для чтеца — кнопка с отметкой «выбрано».
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.title, required this.selected, required this.onTap, this.description});

  final String title;
  final String? description;
  final bool selected;

  /// null — неактивна.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final description = this.description;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: selected
          ? const BorderSide(color: RescueColors.accent, width: 2)
          : const BorderSide(color: RescueColors.line),
    );
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      selected: selected,
      enabled: onTap != null,
      label: title,
      hint: description,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? RescueColors.selected : Colors.transparent,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: Padding(
              // Рамка 2 px у выбранной — на 1 px меньше отступ, чтобы текст не прыгал.
              padding: EdgeInsets.all(selected ? 15 : 16),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: RescueColors.text),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? RescueColors.textTertiary : RescueColors.textSecondary,
                        ),
                      ),
                    ],
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
