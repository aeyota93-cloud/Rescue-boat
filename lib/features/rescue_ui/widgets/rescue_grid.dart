import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Шлюпка: сетка «сколько влезет» — как CSS `repeat(auto-fit, minmax(200px, 1fr))` в макетах.
///
/// Число колонок = сколько элементов шириной не меньше [minItemWidth] помещается; ширина делится поровну.
/// Если колонок больше, чем элементов, элементы растягиваются (auto-fit).
///
/// [masonry] — «кладка» для карточек разной высоты (Настройки): элемент i всегда в колонке
/// i % колонок, каждая колонка складывается сверху вниз сама по себе. Нет дыр под короткими
/// карточками, а развёрнутая карточка сдвигает только те, что под ней в своей колонке.
class RescueGrid extends StatelessWidget {
  const RescueGrid({
    super.key,
    required this.children,
    this.minItemWidth = 200,
    this.spacing = 12,
    this.runSpacing,
    this.masonry = false,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  /// Промежуток между рядами; null — как [spacing].
  final double? runSpacing;
  final bool masonry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + spacing) / (minItemWidth + spacing)).floor();
        final columns = math.max(1, math.min(fit, children.length));
        final itemWidth = math.max(0.0, (width - spacing * (columns - 1)) / columns).floorToDouble();
        if (masonry) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: spacing),
                SizedBox(
                  width: itemWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = c; i < children.length; i += columns) ...[
                        if (i >= columns) SizedBox(height: runSpacing ?? spacing),
                        children[i],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        }
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing ?? spacing,
          children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
        );
      },
    );
  }
}
