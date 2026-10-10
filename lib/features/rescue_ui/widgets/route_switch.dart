import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/widgets/pill_segmented.dart';
import 'package:hiddify/features/rescue_ui/widgets/segmented_control.dart';

/// Куда идёт программа/сайт: решают общие правила, мимо VPN или через VPN.
enum RouteChoice { auto, bypass, vpn }

/// Шлюпка: переключатель «Авто / Мимо / VPN» для строки раздельного туннеля.
///
/// Вид стиля «Д»: таблетка, выбранный сегмент светлый с тёмным текстом ([PillSegmentedStyle.dark]);
/// в жёлтой (выделенной) строке — [onAccent] = true: выбранный тёмный с жёлтым текстом.
/// Клавиатура: Tab — на переключатель, ←/→ — выбор.
class RouteSwitch extends StatelessWidget {
  const RouteSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.width = 230,
    this.onAccent = false,
  });

  final RouteChoice value;

  /// null — переключатель неактивен.
  final ValueChanged<RouteChoice>? onChanged;

  /// Например, «Куда идёт Google Chrome».
  final String? semanticLabel;

  /// Ширина целиком; null — по ширине родителя (тогда нужны ограничения сверху).
  final double? width;

  /// Переключатель стоит на жёлтом фоне (выделенная строка).
  final bool onAccent;

  static const segments = [
    RescueSegment(value: RouteChoice.auto, label: 'Авто', semanticLabel: 'Авто, по общим правилам'),
    RescueSegment(value: RouteChoice.bypass, label: 'Мимо', semanticLabel: 'Мимо VPN'),
    RescueSegment(value: RouteChoice.vpn, label: 'VPN', semanticLabel: 'Через VPN'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: PillSegmented<RouteChoice>(
        segments: [
          for (final s in segments) PillSegment(value: s.value, label: s.label, semanticLabel: s.semanticLabel),
        ],
        value: value,
        onChanged: onChanged,
        semanticLabel: semanticLabel,
        expand: true,
        style: onAccent ? PillSegmentedStyle.onAccent : PillSegmentedStyle.dark,
        fontSize: 12,
        letterSpacing: 0.4,
      ),
    );
  }
}
