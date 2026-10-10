import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Пункт легенды: линия «━» или точка «●» нужного цвета.
class ChartLegendItem {
  const ChartLegendItem({required this.color, required this.label, this.line = false});

  final Color color;
  final String label;
  final bool line;
}

/// Шлюпка: легенда под графиком («━ Общая оценка  ● Серьёзный сбой»).
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<ChartLegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: item.line
                    ? Container(
                        width: 14,
                        height: 3,
                        decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(2)),
                      )
                    : Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
                      ),
              ),
              const SizedBox(width: 6),
              Text(item.label, style: const TextStyle(fontSize: 13, color: RescueColors.muted)),
            ],
          ),
      ],
    );
  }
}
