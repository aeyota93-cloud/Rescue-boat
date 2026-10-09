import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';
import 'package:hiddify/features/rescue_ui/widgets/rescue_card.dart';
import 'package:hiddify/features/rescue_ui/widgets/rescue_progress_bar.dart';

/// Шлюпка: плитка-счётчик — подпись сверху и крупное число.
///
/// Обычная: карточка с рамкой, радиус 16, число 28 px («Через VPN 12»).
/// [inset] = true: тёмная плитка внутри карточки, число 20 px («Израсходовано 48 из 200 ГБ»).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.markerColor,
    this.valueColor = RescueColors.text,
    this.caption,
    this.progress,
    this.progressColor = RescueColors.good,
    this.inset = false,
  });

  final String label;
  final String value;

  /// Цветной квадратик 10×10 перед подписью (как легенда диаграммы).
  final Color? markerColor;
  final Color valueColor;

  /// Серая строка под числом («ещё 31 день»).
  final String? caption;

  /// Полоска заполнения 0..1 под числом.
  final double? progress;
  final Color progressColor;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final marker = markerColor;
    final caption = this.caption;
    final progress = this.progress;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (marker != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: marker, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(label, style: inset ? RescueText.caption : RescueText.smallSecondary)),
          ],
        ),
        SizedBox(height: inset ? 4 : 6),
        Text(
          value,
          style: TextStyle(fontSize: inset ? 20 : 28, fontWeight: FontWeight.w700, color: valueColor),
        ),
        if (caption != null) ...[const SizedBox(height: 2), Text(caption, style: RescueText.caption)],
        if (progress != null) ...[const SizedBox(height: 8), RescueProgressBar(value: progress, color: progressColor)],
      ],
    );

    final tile = inset
        ? RescueCard.inset(child: content)
        : RescueCard(radius: 16, padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18), child: content);
    return Semantics(
      container: true,
      label: [label, value, ?caption].join(', '),
      child: ExcludeSemantics(child: tile),
    );
  }
}
