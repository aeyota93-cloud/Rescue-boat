import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Отметка на графике: цветной кружок в точке [index] и необязательная подпись рядом.
class LineChartMarker {
  const LineChartMarker({
    required this.index,
    required this.color,
    this.radius = 7,
    this.label,
    this.labelColor = RescueColors.importantText,
  });

  final int index;
  final Color color;
  final double radius;
  final String? label;
  final Color labelColor;
}

/// Шлюпка: линейный график (оценка по дням) — сетка с подписями слева, подписи дат снизу,
/// отметки сбоев цветными кружками.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.semanticLabel,
    this.minY = 0,
    this.maxY = 100,
    this.yTicks = const [],
    this.xLabels = const [],
    this.markers = const [],
    this.lineColor = RescueColors.accent,
    this.height = 230,
    this.showLastPoint = true,
  });

  /// Значения по порядку слева направо; null — нет данных (линия рвётся).
  final List<double?> values;

  /// Обязательная подпись для экранного чтеца: что видно на графике словами.
  final String semanticLabel;
  final double minY;
  final double maxY;

  /// Значения, на которых рисуются линии сетки с подписями (например, 70, 80, 90, 100).
  final List<double> yTicks;

  /// Подписи снизу, распределяются равномерно: первая слева, последняя справа.
  final List<String> xLabels;
  final List<LineChartMarker> markers;
  final Color lineColor;
  final double height;

  /// Кружок 4 px в последней точке.
  final bool showLastPoint;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: LineChartPainter(
              values: values,
              minY: minY,
              maxY: maxY,
              yTicks: yTicks,
              xLabels: xLabels,
              markers: markers,
              lineColor: lineColor,
              showLastPoint: showLastPoint,
              textStyle: base.merge(const TextStyle(fontSize: 11, color: RescueColors.textSecondary)),
            ),
          ),
        ),
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  LineChartPainter({
    required this.values,
    required this.minY,
    required this.maxY,
    required this.yTicks,
    required this.xLabels,
    required this.markers,
    required this.lineColor,
    required this.showLastPoint,
    required this.textStyle,
  });

  final List<double?> values;
  final double minY;
  final double maxY;
  final List<double> yTicks;
  final List<String> xLabels;
  final List<LineChartMarker> markers;
  final Color lineColor;
  final bool showLastPoint;
  final TextStyle textStyle;

  TextPainter _text(String s, {Color? color}) => TextPainter(
    text: TextSpan(
      text: s,
      style: color == null ? textStyle : textStyle.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void paint(Canvas canvas, Size size) {
    final yLabels = [for (final t in yTicks) _text(_fmt(t))];
    final labelWidth = yLabels.fold<double>(0, (w, p) => math.max(w, p.width));
    final xPainters = [for (final l in xLabels) _text(l)];
    final xLabelHeight = xPainters.isEmpty ? 0.0 : xPainters.first.height + 8;
    final maxMarker = markers.fold<double>(4, (r, m) => math.max(r, m.radius));

    final plot = Rect.fromLTRB(
      labelWidth > 0 ? labelWidth + 10 : maxMarker,
      maxMarker + 2,
      size.width - maxMarker - 2,
      size.height - xLabelHeight - maxMarker,
    );
    if (plot.width <= 0 || plot.height <= 0) return;
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    double yOf(double v) => plot.bottom - ((v.clamp(minY, maxY) - minY) / span) * plot.height;
    double xOf(int i) => values.length <= 1 ? plot.left : plot.left + i / (values.length - 1) * plot.width;

    // Сетка и подписи слева
    final grid = Paint()
      ..color = RescueColors.line
      ..strokeWidth = 1;
    for (final (i, t) in yTicks.indexed) {
      final y = yOf(t);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final p = yLabels[i];
      p.paint(canvas, Offset(labelWidth - p.width, y - p.height / 2));
    }

    // Подписи снизу
    for (final (i, p) in xPainters.indexed) {
      final n = xPainters.length;
      final x = n == 1 ? plot.left : plot.left + i / (n - 1) * plot.width;
      final dx = i == 0
          ? x
          : i == n - 1
          ? x - p.width
          : x - p.width / 2;
      p.paint(canvas, Offset(dx.clamp(0, math.max(0, size.width - p.width)), size.height - p.height));
    }

    // Линия (рвётся на null)
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    var penDown = false;
    for (final (i, v) in values.indexed) {
      if (v == null) {
        penDown = false;
        continue;
      }
      final o = Offset(xOf(i), yOf(v));
      if (penDown) {
        path.lineTo(o.dx, o.dy);
      } else {
        path.moveTo(o.dx, o.dy);
        penDown = true;
      }
    }
    canvas.drawPath(path, line);

    if (showLastPoint && values.isNotEmpty && values.last != null) {
      canvas.drawCircle(Offset(xOf(values.length - 1), yOf(values.last!)), 4, Paint()..color = lineColor);
    }

    // Отметки и подписи к ним
    for (final m in markers) {
      if (m.index < 0 || m.index >= values.length) continue;
      final v = values[m.index];
      if (v == null) continue;
      final c = Offset(xOf(m.index), yOf(v));
      canvas.drawCircle(c, m.radius, Paint()..color = m.color);
      final label = m.label;
      if (label == null) continue;
      final p = _text(label, color: m.labelColor);
      var dx = c.dx + m.radius + 3;
      if (dx + p.width > size.width) dx = c.dx - m.radius - 3 - p.width;
      var dy = c.dy + m.radius + 2;
      if (dy + p.height > plot.bottom + maxMarker) dy = c.dy - m.radius - 2 - p.height;
      p.paint(canvas, Offset(math.max(0, dx), dy));
    }
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.minY != minY ||
      oldDelegate.maxY != maxY ||
      oldDelegate.yTicks != yTicks ||
      oldDelegate.xLabels != xLabels ||
      oldDelegate.markers != markers ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.showLastPoint != showLastPoint ||
      oldDelegate.textStyle != textStyle;
}
