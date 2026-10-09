import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Шлюпка: заголовок карточки. Слева название (и бейджи), справа — серая подпись
/// («за 24 часа») или ссылка («Все ошибки ›»).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailingText,
    this.actionLabel,
    this.onAction,
    this.badges = const [],
    this.titleStyle = RescueText.cardTitle,
  });

  final String title;

  /// Серая подпись справа.
  final String? trailingText;

  /// Текст ссылки без «›» — стрелку дорисуем сами.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Бейджи сразу после заголовка («7 за час», «23 за сутки»).
  final List<Widget> badges;
  final TextStyle titleStyle;

  @override
  Widget build(BuildContext context) {
    final trailing = trailingText;
    final action = actionLabel;
    // На узком окне бейджи переносятся под заголовок, как flex-wrap в макете.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(header: true, child: Text(title, style: titleStyle)),
                ...badges,
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            // Подпись прижата вправо и занимает не больше половины строки.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: Text(trailing, style: RescueText.smallSecondary, textAlign: TextAlign.end),
            ),
          ],
          if (action != null) ...[const SizedBox(width: 12), RescueLink(label: action, onTap: onAction)],
        ],
      ),
    );
  }
}

/// Ссылка-действие «Текст ›» с зоной нажатия не меньше 44 px.
class RescueLink extends StatelessWidget {
  const RescueLink({super.key, required this.label, this.onTap, this.style = RescueText.link});

  final String label;
  final VoidCallback? onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: RescueColors.softAccent.withValues(alpha: 0.4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(widthFactor: 1, child: Text('$label ›', style: style)),
            ),
          ),
        ),
      ),
    );
  }
}
