import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/segmented_control.dart';

/// Куда идёт программа/сайт: решают общие правила, мимо VPN или через VPN.
enum RouteChoice { auto, bypass, vpn }

/// Шлюпка: переключатель «Авто / Мимо / VPN» для строки раздельного туннеля.
///
/// Цвета как в Tunnel.dc.html: Авто — оранжевый, Мимо — бирюзовый, VPN — фиолетовый.
/// Клавиатура: Tab — на переключатель, ←/→ — выбор.
class RouteSwitch extends StatelessWidget {
  const RouteSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel, this.width = 230});

  final RouteChoice value;

  /// null — переключатель неактивен.
  final ValueChanged<RouteChoice>? onChanged;

  /// Например, «Куда идёт Google Chrome».
  final String? semanticLabel;

  /// Ширина целиком; null — по ширине родителя (тогда нужны ограничения сверху).
  final double? width;

  static const segments = [
    RescueSegment(
      value: RouteChoice.auto,
      label: 'Авто',
      semanticLabel: 'Авто, по общим правилам',
      selectedBackground: RescueColors.warningBg,
      selectedForeground: RescueColors.warningText,
    ),
    RescueSegment(
      value: RouteChoice.bypass,
      label: 'Мимо',
      semanticLabel: 'Мимо VPN',
      selectedBackground: RescueColors.bypassBg,
      selectedForeground: RescueColors.bypassText,
    ),
    RescueSegment(
      value: RouteChoice.vpn,
      label: 'VPN',
      semanticLabel: 'Через VPN',
      // Цвета по умолчанию — мягкий акцент.
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: RescueSegmented<RouteChoice>(
        segments: segments,
        value: value,
        onChanged: onChanged,
        semanticLabel: semanticLabel,
        expand: true,
        background: RescueColors.background,
        outerRadius: 10,
        innerRadius: 7,
        fontSize: 12,
      ),
    );
  }
}
