import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

/// Шлюпка: шапка раздела в стиле «Д» — заголовок маленькими заглавными с разрядкой
/// («НАСТРОЙКИ», 13 / 700 / 0.18em) слева, кнопки справа, высота от 44.
/// [title] передаётся обычным регистром: заглавными он станет сам, а чтец прочтёт его как есть.
/// На узком окне кнопки переносятся под заголовок.
class RescuePageHeader extends StatelessWidget {
  const RescuePageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});

  final String title;

  /// Серая подпись под заголовком (12, muted).
  final String? subtitle;
  final List<Widget> actions;

  /// Слева от заголовка, например кнопка «Назад».
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final leading = this.leading;
    final heading = Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 6)],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                label: title,
                child: ExcludeSemantics(child: Text(title.toUpperCase(), style: RescueText.screenTitle)),
              ),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: RescueText.caption)],
            ],
          ),
        ),
      ],
    );
    final buttons = Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: actions);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions.isEmpty) return Align(alignment: Alignment.centerLeft, child: heading);
          if (constraints.maxWidth >= 640) {
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 10),
                buttons,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), buttons],
          );
        },
      ),
    );
  }
}
