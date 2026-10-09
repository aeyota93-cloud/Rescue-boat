import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: карточка-секция. По умолчанию: фон #1C1C2E, рамка #2C2C44, радиус 20, отступ 20.
///
/// [RescueCard.inset] — вложенная плитка на тёмном фоне без рамки (радиус 14),
/// [RescueCard.dashed] — пунктирная рамка «пустого места» (например, «Запасной» сервер).
class RescueCard extends StatelessWidget {
  const RescueCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.color = RescueColors.card,
    this.borderColor = RescueColors.line,
    this.dashed = false,
    this.semanticLabel,
  });

  const RescueCard.inset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    this.radius = 14,
    this.semanticLabel,
  }) : color = RescueColors.background,
       borderColor = null,
       dashed = false;

  /// Пунктирная рамка #3A3A55 — «здесь пока пусто».
  const RescueCard.dashed({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.semanticLabel,
  }) : color = RescueColors.card,
       borderColor = RescueColors.muted,
       dashed = true;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;

  /// null — без рамки.
  final Color? borderColor;
  final bool dashed;

  /// Название секции для экранного чтеца (как aria-label у section в макете).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final border = borderColor;
    Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: border != null && !dashed ? Border.all(color: border) : null,
      ),
      child: child,
    );
    if (dashed && border != null) {
      card = CustomPaint(
        foregroundPainter: _DashedBorderPainter(color: border, radius: radius),
        child: card,
      );
    }
    final label = semanticLabel;
    if (label == null) return card;
    return Semantics(container: true, explicitChildNodes: true, label: label, child: card);
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gap = 4.0;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
