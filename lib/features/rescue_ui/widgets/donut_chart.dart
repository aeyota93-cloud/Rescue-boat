import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Сегмент [DonutChart].
class DonutSegment {
  const DonutSegment({required this.value, required this.color, this.label});

  final double value;
  final Color color;

  /// Название для экранного чтеца («через VPN»).
  final String? label;
}

/// Шлюпка: кольцевая диаграмма (как «71 правило» на Обзоре): сегменты с зазором 3 px, число в центре.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    this.size = 170,
    this.thickness = 22,
    this.centerValue,
    this.centerLabel,
    this.semanticLabel,
  });

  final List<DonutSegment> segments;
  final double size;
  final double thickness;

  /// Крупное число в центре («71»).
  final String? centerValue;

  /// Подпись под числом («правило»).
  final String? centerLabel;

  /// Если null — собирается из подписей сегментов.
  final String? semanticLabel;

  String _defaultLabel() {
    final parts = [
      for (final s in segments)
        if (s.label != null) '${s.label}: ${_fmt(s.value)}',
    ];
    return [?centerValue, ?centerLabel, ...parts].join(', ');
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final value = centerValue;
    final label = centerLabel;
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ?? _defaultLabel(),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: DonutPainter(segments: segments, thickness: thickness),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value != null)
                    Text(
                      value,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: RescueColors.text),
                    ),
                  if (label != null)
                    Text(label, style: const TextStyle(fontSize: 12, color: RescueColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Рисует кольцо; пустое (все нули) — серая дорожка.
class DonutPainter extends CustomPainter {
  const DonutPainter({required this.segments, required this.thickness, this.gap = 3});

  final List<DonutSegment> segments;
  final double thickness;

  /// Зазор между сегментами по дуге, px.
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - thickness) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    final visible = segments.where((s) => s.value.isFinite && s.value > 0).toList();
    final total = visible.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) {
      canvas.drawCircle(rect.center, radius, paint..color = RescueColors.track);
      return;
    }

    final gapAngle = visible.length > 1 ? gap / radius : 0.0;
    var start = -math.pi / 2; // от «12 часов» по часовой
    for (final s in visible) {
      final sweep = s.value / total * 2 * math.pi;
      final drawn = sweep - gapAngle;
      if (drawn > 0) canvas.drawArc(rect, start, drawn, false, paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.thickness != thickness || oldDelegate.gap != gap;
}
