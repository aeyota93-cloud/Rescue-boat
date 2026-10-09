import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Шлюпка: тонкая полоска заполнения (расход подписки, пинг сервера).
class RescueProgressBar extends StatelessWidget {
  const RescueProgressBar({super.key, required this.value, this.color = RescueColors.good, this.height = 6});

  /// Доля заполнения 0..1 (вне диапазона обрезается).
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    final fraction = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(color: RescueColors.track, borderRadius: radius),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: Container(
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: radius),
          ),
        ),
      ),
    );
  }
}
