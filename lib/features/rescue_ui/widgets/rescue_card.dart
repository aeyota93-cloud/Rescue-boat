import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: карточка-секция: графитовая поверхность, тонкая рамка, радиус 16, отступ 20.
///
/// Варианты:
/// - [RescueCard.inset] — вложенная плитка цвета panel внутри карточки (радиус 14);
/// - [RescueCard.dashed] — пунктирная рамка line2 «пустого места» («Запасной», радиус 16);
/// - [RescueCard.deep] — тёмный блок deep (радиус 16, отступ 18), текст светлый;
/// - [RescueCard.accent] — жёлтый блок (радиус 16, отступ 28), текст и значки тёмные.
class RescueCard extends StatelessWidget {
  const RescueCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 16,
    this.color = RescueColors.card,
    this.borderColor = RescueColors.line,
    this.dashed = false,
    this.semanticLabel,
    this.foreground,
    this.borderRadius,
  });

  const RescueCard.inset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    this.radius = 14,
    this.semanticLabel,
  }) : color = RescueColors.panel,
       borderColor = RescueColors.line,
       dashed = false,
       foreground = null,
       borderRadius = null;

  /// Пунктирная рамка line2 — «здесь пока пусто».
  const RescueCard.dashed({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 16,
    this.semanticLabel,
  }) : color = Colors.transparent,
       borderColor = RescueColors.line2,
       dashed = true,
       foreground = null,
       borderRadius = null;

  /// Тёмный блок-список (ошибки, таблица туннеля, «Для опытных»).
  const RescueCard.deep({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 16,
    this.semanticLabel,
  }) : color = RescueColors.deep,
       borderColor = RescueColors.line,
       dashed = false,
       foreground = RescueColors.textOnDeep,
       borderRadius = null;

  /// Жёлтый блок (подключение, активная подписка). Текст по умолчанию — [RescueColors.onAccent].
  const RescueCard.accent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.radius = 16,
    this.semanticLabel,
  }) : color = RescueColors.accent,
       borderColor = RescueColors.line,
       dashed = false,
       foreground = RescueColors.onAccent,
       borderRadius = null;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;

  /// null — без рамки; по умолчанию тонкая линия поверхности.
  final Color? borderColor;
  final bool dashed;

  /// Название секции для экранного чтеца (как aria-label у section в макете).
  final String? semanticLabel;

  /// Цвет текста и значков внутри; null — не менять.
  final Color? foreground;

  /// Свои скругления по углам (например, без верхнего левого под закладкой); null — [radius] везде.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final shape = borderRadius ?? BorderRadius.circular(radius);
    final border = borderColor;
    Widget content = child;
    final fg = foreground;
    if (fg != null) {
      content = IconTheme.merge(
        data: IconThemeData(color: fg),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: content,
        ),
      );
    }
    Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: shape,
        border: border != null && !dashed ? Border.all(color: border) : null,
      ),
      child: content,
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
    const width = 1.5;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);
    final hatch = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hatch);
    }
    canvas.restore();
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 5.0;
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
