import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Шлюпка: сетка «сколько влезет» — как CSS `repeat(auto-fit, minmax(200px, 1fr))` в макетах.
///
/// Число колонок = сколько элементов шириной не меньше [minItemWidth] помещается; ширина делится поровну.
/// Если колонок больше, чем элементов, элементы растягиваются (auto-fit).
class RescueGrid extends StatelessWidget {
  const RescueGrid({super.key, required this.children, this.minItemWidth = 200, this.spacing = 12, this.runSpacing});

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  /// Промежуток между рядами; null — как [spacing].
  final double? runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + spacing) / (minItemWidth + spacing)).floor();
        final columns = math.max(1, math.min(fit, children.length));
        final itemWidth = math.max(0.0, (width - spacing * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing ?? spacing,
          children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
        );
      },
    );
  }
}
