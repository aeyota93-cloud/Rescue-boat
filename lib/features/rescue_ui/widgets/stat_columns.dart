import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Одна колонка [StatColumns].
class StatColumn {
  const StatColumn({required this.label, required this.value, this.lineColor = RescueColors.line2});

  /// Подпись заглавными: «МИМО VPN».
  final String label;

  /// Число: «38».
  final String value;

  /// Цветная линия слева (line2 по умолчанию, accent — для выделенной колонки «В СЕТИ»).
  final Color lineColor;
}

/// Шлюпка: колонки-счётчики с цветной левой линией 2 px — «МИМО VPN 38 · ЧЕРЕЗ VPN 12 · В СЕТИ 4».
///
/// Подпись 11 / 600 muted, число 20 / 700. Колонки распределяются по ширине (space-between);
/// если не влезают — переносятся.
class StatColumns extends StatelessWidget {
  const StatColumns({super.key, required this.columns, this.labelColor = RescueColors.muted, this.valueColor});

  final List<StatColumn> columns;
  final Color labelColor;

  /// null — цвет текста вокруг.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final c in columns)
        Semantics(
          container: true,
          label: '${c.label}: ${c.value}',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.lineColor, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.label,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: labelColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.value,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: valueColor),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
    return Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 12, children: cells);
  }
}
