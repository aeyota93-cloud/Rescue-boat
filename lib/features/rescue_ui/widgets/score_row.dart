import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Полоска «хорошо / средне / плохо» из трёх долей, промежуток 3 px, высота 6.
///
/// Доли в любых единицах (проценты или 0..1) — нормируются по сумме. Нулевые доли не рисуются;
/// если все нули — серая дорожка.
class ScoreBar extends StatelessWidget {
  const ScoreBar({
    super.key,
    required this.good,
    required this.fair,
    required this.poor,
    this.height = 6,
    this.gap = 3,
  });

  final double good;
  final double fair;
  final double poor;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final parts = <(String, double, Color)>[
      ('good', good, RescueColors.good),
      ('fair', fair, RescueColors.fair),
      ('poor', poor, RescueColors.poor),
    ].where((p) => p.$2.isFinite && p.$2 > 0).toList();
    final sum = parts.fold<double>(0, (s, p) => s + p.$2);
    final radius = BorderRadius.circular(height / 2);

    if (parts.isEmpty || sum <= 0) {
      return ExcludeSemantics(
        child: Container(
          key: const ValueKey('score-bar-empty'),
          height: height,
          decoration: BoxDecoration(color: RescueColors.track, borderRadius: radius),
        ),
      );
    }

    final children = <Widget>[];
    for (final (name, value, color) in parts) {
      if (children.isNotEmpty) children.add(SizedBox(width: gap));
      children.add(
        Expanded(
          key: ValueKey('score-bar-$name'),
          // Точность до 0,1 %: flex — целое.
          flex: (value / sum * 1000).round().clamp(1, 1000),
          child: Container(
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: radius),
          ),
        ),
      );
    }
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Row(children: children),
      ),
    );
  }
}

/// Шлюпка: строка «Здоровья подключения» — название, тренд, значение, полоска и подпись-факт.
class ScoreRow extends StatelessWidget {
  const ScoreRow({
    super.key,
    required this.name,
    required this.value,
    required this.good,
    required this.fair,
    required this.poor,
    this.trend,
    this.caption,
    this.emphasized = false,
  });

  final String name;

  /// Значение, обычно «92»; «—», если нет данных.
  final String value;

  /// Изменение к прошлому периоду: >0 — «↗ 3» зелёным, <0 — «↘ 4» красным, 0 — «→ 0». null — не показывать.
  final int? trend;

  /// Доли минут «хорошо / средне / плохо» (см. [ScoreBar]).
  final double good;
  final double fair;
  final double poor;

  /// Подпись под полоской: факт, а не совет («48 мс, обычно 45–60»).
  final String? caption;

  /// Жирное название (для «Общей оценки»).
  final bool emphasized;

  static String trendText(int trend) => switch (trend) {
    > 0 => '↗ $trend',
    < 0 => '↘ ${-trend}',
    _ => '→ 0',
  };

  @override
  Widget build(BuildContext context) {
    final trend = this.trend;
    final caption = this.caption;
    final total = good + fair + poor;
    String pct(double v) => total > 0 ? '${(v / total * 100).round()}%' : '0%';
    final trendSpoken = trend == null
        ? ''
        : trend > 0
        ? ', выросло на $trend'
        : trend < 0
        ? ', упало на ${-trend}'
        : ', без изменений';

    return Semantics(
      container: true,
      label:
          '$name: $value$trendSpoken. Хорошо ${pct(good)}, средне ${pct(fair)}, плохо ${pct(poor)}'
          '${caption != null ? '. $caption' : ''}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                      color: RescueColors.text,
                    ),
                  ),
                ),
                if (trend != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    trendText(trend),
                    style: TextStyle(fontSize: 12, color: trend < 0 ? RescueColors.poor : RescueColors.good),
                  ),
                ],
                const SizedBox(width: 6),
                Text(value, style: RescueText.bodyStrong),
              ],
            ),
            const SizedBox(height: 8),
            ScoreBar(good: good, fair: fair, poor: poor),
            if (caption != null) ...[const SizedBox(height: 8), Text(caption, style: RescueText.caption)],
          ],
        ),
      ),
    );
  }
}
