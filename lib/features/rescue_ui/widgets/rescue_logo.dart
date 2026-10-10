import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: логотип — спасательный круг (белое кольцо с четырьмя красными вставками).
class RescueLogo extends StatelessWidget {
  const RescueLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: const _LifebuoyPainter()),
    );
  }
}

class _LifebuoyPainter extends CustomPainter {
  const _LifebuoyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Как в макете: viewBox 40, r = 14, толщина 8, пунктир 11/11.
    final scale = size.shortestSide / 40;
    final center = size.center(Offset.zero);
    final radius = 14 * scale;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * scale
      ..color = RescueColors.logoWhite;
    canvas.drawCircle(center, radius, paint);

    paint.color = RescueColors.logoRed;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const sweep = 11 / 14; // длина дуги 11 при радиусе 14
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(rect, i * math.pi / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_LifebuoyPainter oldDelegate) => false;
}
