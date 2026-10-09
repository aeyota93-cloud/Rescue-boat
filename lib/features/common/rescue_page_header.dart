import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

/// Шлюпка: шапка страницы нового интерфейса — заголовок (и подпись) слева, кнопки справа.
/// На узком окне кнопки переносятся под заголовок.
class RescuePageHeader extends StatelessWidget {
  const RescuePageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(header: true, child: Text(title, style: RescueText.pageTitle)),
        if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: RescueText.pageSubtitle)],
      ],
    );
    final buttons = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions.isEmpty) return Align(alignment: Alignment.centerLeft, child: heading);
          if (constraints.maxWidth >= 640) {
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
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
