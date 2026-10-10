import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: кольцо-показатель (приём 3 стиля «Д»): кольцо 52 px с числом внутри, справа —
/// подпись заглавными и пояснение.
///
/// ```dart
/// RingStat(value: 0.35, label: '48', title: 'МС ПИНГ', caption: 'обычно 45–60')
/// RingStat(value: 0.4, label: '7', title: 'ОШИБОК', caption: 'за час', color: RescueColors.warn)
/// RingStat.onAccent(value: 0.24, label: '48', title: 'ГБ\nИЗ 200', size: 56)   // на жёлтом
/// RingStat(value: 1, label: '12', size: 40)                                      // только кольцо
/// ```
class RingStat extends StatelessWidget {
  const RingStat({
    super.key,
    required this.value,
    required this.label,
    this.title,
    this.caption,
    this.color = RescueColors.accent,
    this.trackColor = RescueColors.line,
    this.labelColor = RescueColors.text,
    this.titleColor = RescueColors.text,
    this.captionColor = RescueColors.muted,
    this.size = 52,
    this.strokeWidth,
    this.semanticLabel,
  });

  /// На жёлтом фоне: дорожка accentDeep, дуга и текст тёмные.
  const RingStat.onAccent({
    super.key,
    required this.value,
    required this.label,
    this.title,
    this.caption,
    this.size = 56,
    this.strokeWidth,
    this.semanticLabel,
  }) : color = RescueColors.ink,
       trackColor = RescueColors.accentDeep,
       labelColor = RescueColors.onAccent,
       titleColor = RescueColors.onAccent,
       captionColor = RescueColors.onAccentMuted;

  /// Заполнение дуги 0..1 (вне диапазона обрезается); null или 0 — только дорожка.
  final double? value;

  /// Число внутри кольца: «48», «—», «6ч».
  final String label;

  /// Подпись справа заглавными: «МС ПИНГ» (11 / 700 / 0.08em). Можно в две строки через \n.
  final String? title;

  /// Пояснение под подписью: «обычно 45–60» (12, muted).
  final String? caption;
  final Color color;
  final Color trackColor;
  final Color labelColor;
  final Color titleColor;
  final Color captionColor;

  /// Диаметр кольца.
  final double size;

  /// Толщина; null — пропорционально размеру (4.5 при 52).
  final double? strokeWidth;

  /// Для чтеца; null — «label title, caption».
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final caption = this.caption;
    final stroke = strokeWidth ?? size * 4.5 / 52;
    final ring = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: RingPainter(value: value ?? 0, color: color, trackColor: trackColor, strokeWidth: stroke),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(stroke + 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(fontSize: size * 15 / 52, fontWeight: FontWeight.w600, color: labelColor),
              ),
            ),
          ),
        ),
      ),
    );
    final spoken =
        semanticLabel ??
        [
          [label, ?title?.replaceAll('\n', ' ')].join(' '),
          ?caption,
        ].join(', ');
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: title == null && caption == null
            ? ring
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ring,
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null)
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.88,
                              color: titleColor,
                            ),
                          ),
                        if (caption != null)
                          Text(
                            caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: captionColor),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Рисует дорожку и дугу от «12 часов» по часовой, концы скруглены.
class RingPainter extends CustomPainter {
  const RingPainter({required this.value, required this.color, required this.trackColor, required this.strokeWidth});

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, paint..color = trackColor);
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    if (v <= 0) return;
    paint
      ..color = color
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (v >= 1) {
      canvas.drawCircle(center, radius, paint);
    } else {
      canvas.drawArc(rect, -math.pi / 2, v * 2 * math.pi, false, paint);
    }
  }

  @override
  bool shouldRepaint(RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
