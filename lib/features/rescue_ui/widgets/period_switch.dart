import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/widgets/segmented_control.dart';

/// Шлюпка: «Час / Сутки / Неделя» — сегментированный выбор периода.
///
/// Тип значения любой (например, InsightsPeriod из insights):
/// ```dart
/// PeriodSwitch<InsightsPeriod>(
///   options: const [(InsightsPeriod.hour, 'Час'), (InsightsPeriod.day, 'Сутки'), (InsightsPeriod.week, 'Неделя')],
///   value: period,
///   onChanged: (p) => ...,
/// )
/// ```
class PeriodSwitch<T> extends StatelessWidget {
  const PeriodSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticLabel = 'Период',
  });

  /// Пары «значение — подпись» по порядку.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return RescueSegmented<T>(
      segments: [for (final (v, label) in options) RescueSegment<T>(value: v, label: label)],
      value: value,
      onChanged: onChanged,
      semanticLabel: semanticLabel,
    );
  }
}
