import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: крупная карточка-выбор («Весь компьютер» / «Только браузеры»), как «Способ работы» в макете.
///
/// Выбранная — фон deep, заголовок жёлтый, подпись subOnDeep; невыбранная — фон panel,
/// заголовок светлый, подпись muted. Радиус 22, без рамки. Для чтеца — кнопка с отметкой «выбрано».
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
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
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
          color: selected ? RescueColors.deep : RescueColors.panel,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected ? RescueColors.accent : RescueColors.text,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(fontSize: 12, color: selected ? RescueColors.subOnDeep : RescueColors.muted),
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
