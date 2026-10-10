import 'package:flutter/widgets.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/segmented_control.dart';

/// Вид [PillSegmented]: цвета дорожки и сегментов.
enum PillSegmentedStyle {
  /// На тёмном (card/deep): дорожка line, выбранный — светлый с тёмным текстом,
  /// остальные — subOnDeep. Как «АВТО / МИМО / VPN» в обычной строке туннеля.
  dark(
    track: RescueColors.line,
    selectedBackground: RescueColors.text,
    selectedForeground: RescueColors.onAccent,
    foreground: RescueColors.subOnDeep,
  ),

  /// На жёлтом: дорожка accentDeep, выбранный — тёмный с жёлтым текстом, остальные — тёмные.
  /// Как переключатель в жёлтой (выделенной) строке туннеля.
  onAccent(
    track: RescueColors.accentDeep,
    selectedBackground: RescueColors.onAccent,
    selectedForeground: RescueColors.accent,
    foreground: RescueColors.onAccent,
  ),

  /// Выбор периода на области: дорожка card, выбранный — жёлтый с тёмным текстом
  /// («Час / Сутки / Неделя» на экране ошибок).
  accent(
    track: RescueColors.card,
    selectedBackground: RescueColors.accent,
    selectedForeground: RescueColors.onAccent,
    foreground: RescueColors.text,
  );

  const PillSegmentedStyle({
    required this.track,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.foreground,
  });

  final Color track;
  final Color selectedBackground;
  final Color selectedForeground;
  final Color foreground;
}

/// Один вариант [PillSegmented].
class PillSegment<T> {
  const PillSegment({required this.value, required this.label, this.semanticLabel});

  final T value;

  /// Подпись на сегменте, например «АВТО». Регистр не меняем — передавайте как надо показать.
  final String label;

  /// Полная подпись для чтеца («МИМО» → «Мимо VPN»).
  final String? semanticLabel;
}

/// Шлюпка: таблетки «одно из нескольких» стиля «Д» (АВТО / МИМО / VPN, Час / Сутки / Неделя).
///
/// ```dart
/// PillSegmented<Route>(
///   segments: const [PillSegment(value: Route.auto, label: 'АВТО', semanticLabel: 'Авто, по общим правилам'), ...],
///   value: route,
///   onChanged: (r) => ...,
///   style: highlighted ? PillSegmentedStyle.onAccent : PillSegmentedStyle.dark,
///   semanticLabel: 'Куда идёт Google Chrome',
/// )
/// ```
/// Клавиатура: одна остановка Tab, ←/→ — соседний вариант, Home/End — крайние.
/// Сегмент 38 px + отступы дорожки = зона нажатия 44 px.
class PillSegmented<T> extends StatelessWidget {
  const PillSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.style = PillSegmentedStyle.dark,
    this.semanticLabel,
    this.expand = false,
    this.fontSize = 11,
    this.letterSpacing = 0.66,
    this.segmentPadding = 14,
  });

  final List<PillSegment<T>> segments;
  final T value;

  /// null — неактивен.
  final ValueChanged<T>? onChanged;
  final PillSegmentedStyle style;

  /// Название группы для чтеца.
  final String? semanticLabel;

  /// Сегменты одинаковой ширины на всю ширину родителя.
  final bool expand;

  /// 11 / 0.06em — как «АВТО» в макете; для «Час / Сутки» — 13 и 0.
  final double fontSize;
  final double letterSpacing;
  final double segmentPadding;

  @override
  Widget build(BuildContext context) {
    return RescueSegmented<T>(
      segments: [
        for (final s in segments) RescueSegment<T>(value: s.value, label: s.label, semanticLabel: s.semanticLabel),
      ],
      value: value,
      onChanged: onChanged,
      semanticLabel: semanticLabel,
      expand: expand,
      background: style.track,
      selectedBackground: style.selectedBackground,
      selectedForeground: style.selectedForeground,
      foreground: style.foreground,
      focusColor: style == PillSegmentedStyle.onAccent ? RescueColors.onAccent : RescueColors.accent,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      segmentPadding: segmentPadding,
    );
  }
}
