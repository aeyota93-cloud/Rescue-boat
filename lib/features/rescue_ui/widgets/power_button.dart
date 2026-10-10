import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Состояние [PowerButton].
enum PowerState { off, connecting, on }

/// Шлюпка: круглая кнопка подключения (приём 4 стиля «Д»).
///
/// Большая (по умолчанию, 184 px) стоит на жёлтом блоке: подключено — тёмный круг с жёлтым
/// значком; выключено — светлый круг с тёмным значком; рамка 12 px accentDeep. Во время
/// подключения по рамке бежит тёмная дуга.
///
/// [PowerButton.mini] (40 px в зоне 44) — для карточки статуса в меню на тёмном фоне:
/// подключено — жёлтый круг с тёмным значком, выключено — круг line со светлым значком.
///
/// Для чтеца — кнопка «Подключить VPN» / «Отключить VPN» / «Подключение…» (или [semanticLabel]).
class PowerButton extends StatefulWidget {
  const PowerButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.size = 184,
    this.semanticLabel,
    this.onAccent = true,
  });

  /// Маленькая кнопка на тёмном фоне (карточка статуса в меню).
  const PowerButton.mini({super.key, required this.state, required this.onPressed, this.size = 40, this.semanticLabel})
    : onAccent = false;

  final PowerState state;

  /// null — кнопка неактивна.
  final VoidCallback? onPressed;

  /// Диаметр круга. Зона нажатия — не меньше 44.
  final double size;
  final String? semanticLabel;

  /// true — кнопка стоит на жёлтом блоке (большой вариант), false — на тёмном.
  final bool onAccent;

  static String defaultLabel(PowerState state) => switch (state) {
    PowerState.off => 'Подключить VPN',
    PowerState.connecting => 'Подключение…',
    PowerState.on => 'Отключить VPN',
  };

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  void _syncSpin() {
    if (widget.state == PowerState.connecting) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  ({Color bg, Color fg, Color ring}) get _colors {
    final on = widget.state != PowerState.off;
    if (widget.onAccent) {
      return on
          ? (bg: RescueColors.ink, fg: RescueColors.accent, ring: RescueColors.accentDeep)
          : (bg: RescueColors.textOnDeep, fg: RescueColors.onAccent, ring: RescueColors.accentDeep);
    }
    return switch (widget.state) {
      PowerState.on => (bg: RescueColors.accent, fg: RescueColors.onAccent, ring: RescueColors.accent),
      PowerState.connecting => (bg: RescueColors.line, fg: RescueColors.accent, ring: RescueColors.line),
      PowerState.off => (bg: RescueColors.line, fg: RescueColors.textOnDeep, ring: RescueColors.line),
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final c = _colors;
    final ringWidth = widget.onAccent ? math.max(2.0, size * 12 / 184) : 0.0;
    final iconSize = widget.onAccent ? size * 56 / 184 : size * 18 / 40;
    final onPressed = widget.onPressed;
    final hit = math.max(size, 44.0);

    // Ink, а не Container: подсветка наведения и нажатия видна поверх заливки.
    final circle = Ink(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.bg,
        shape: BoxShape.circle,
        border: ringWidth > 0 ? Border.all(color: c.ring, width: ringWidth) : null,
      ),
      child: Center(
        child: Icon(Icons.power_settings_new_rounded, size: iconSize, color: c.fg),
      ),
    );

    final spinner = widget.state == PowerState.connecting
        ? Positioned.fill(
            child: IgnorePointer(
              child: RotationTransition(
                turns: _spin,
                child: CustomPaint(
                  painter: _ArcPainter(
                    color: widget.onAccent ? RescueColors.ink : RescueColors.accent,
                    strokeWidth: widget.onAccent ? ringWidth : 3,
                  ),
                ),
              ),
            ),
          )
        : null;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: widget.semanticLabel ?? PowerButton.defaultLabel(widget.state),
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: hit,
          child: Center(
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                children: [
                  Material(
                    type: MaterialType.circle,
                    color: Colors.transparent,
                    child: InkWell(onTap: onPressed, customBorder: const CircleBorder(), child: circle),
                  ),
                  ?spinner,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi / 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
