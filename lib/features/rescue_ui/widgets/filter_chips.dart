import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: фильтры-таблетки «Всё / Программы / Сайты / IP» (выбран один).
///
/// Выбранный — светлая таблетка с тёмным текстом, остальные — рамка line2 со светлым текстом.
///
/// Каждый фильтр — отдельная кнопка (Tab, Enter/Пробел), высота 44.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.selected, required this.onSelected});

  /// Пары «значение — подпись» по порядку.
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          _Chip(label: label, selected: value == selected, onTap: onSelected == null ? null : () => onSelected!(value)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? RescueColors.text : RescueColors.line2, width: 1.5));
    return Semantics(
      button: true,
      selected: selected,
      toggled: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? RescueColors.text : Colors.transparent,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? RescueColors.onAccent : RescueColors.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
