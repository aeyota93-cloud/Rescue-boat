import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Шлюпка: столбики по часам («Ошибки по часам»).
///
/// Ноль — чёрточка line 2 px; иначе высота растёт от 10 px до [height]
/// пропорционально максимуму. Цвет: от [highFrom] и выше — [highColor] (warn), ниже — [color] (accent).
class HourBars extends StatelessWidget {
  const HourBars({
    super.key,
    required this.counts,
    this.title,
    this.startLabel,
    this.endLabel,
    this.height = 64,
    this.highFrom = 3,
    this.semanticLabel,
    this.color = RescueColors.accent,
    this.highColor = RescueColors.warn,
  });

  /// Значения по порядку, обычно 24 часа, старые слева.
  final List<int> counts;

  /// Серая подпись сверху («Ошибки по часам»).
  final String? title;

  /// Подписи под осью: слева («вчера 21:00») и справа («сейчас»).
  final String? startLabel;
  final String? endLabel;
  final double height;
  final int highFrom;

  /// Если null — «<title>: всего N, больше всего M за час».
  final String? semanticLabel;

  /// Цвет обычного столбика и столбика от [highFrom].
  final Color color;
  final Color highColor;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final start = startLabel;
    final end = endLabel;
    final maxValue = counts.fold<int>(0, math.max);
    final total = counts.fold<int>(0, (s, v) => s + v);

    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ?? '${title ?? 'По часам'}: всего $total, больше всего $maxValue за час',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(title, style: RescueText.tableHeader.copyWith(color: RescueColors.text)),
              const SizedBox(height: 6),
            ],
            Container(
              height: height,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: RescueColors.line)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final n = math.max(counts.length, 1);
                  // На узком окне промежуток уменьшается, чтобы столбики не схлопнулись.
                  final gap = math.min(4.0, constraints.maxWidth / n * 0.25);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, v) in counts.indexed) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(
                          child: Container(
                            key: ValueKey('hour-bar-$i'),
                            height: _barHeight(v, maxValue),
                            decoration: BoxDecoration(
                              color: v <= 0
                                  ? RescueColors.line
                                  : v >= highFrom
                                  ? highColor
                                  : color,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (start != null || end != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (start != null) Expanded(child: Text(start, style: RescueText.axis)),
                  if (end != null)
                    Expanded(
                      child: Text(end, style: RescueText.axis, textAlign: TextAlign.end),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _barHeight(int v, int maxValue) {
    if (v <= 0 || maxValue <= 0) return 2;
    // Высота без нижней линии 1 px.
    final top = height - 1;
    return math.min(top, 10 + (top - 10) * v / maxValue);
  }
}
