import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Шлюпка: метка-рамка — короткий текст в рамке 1.5 px радиус 6 («7», «ВКЛ», «92»).
///
/// Цвет рамки = цвет текста. По умолчанию берёт цвет текста вокруг (DefaultTextStyle),
/// поэтому на жёлтом фоне сама станет тёмной, если фон задан через `RescueCard.accent`.
class FrameTag extends StatelessWidget {
  const FrameTag(this.text, {super.key, this.color, this.filled = false, this.semanticLabel});

  final String text;

  /// null — цвет текста вокруг.
  final Color? color;

  /// true — сплошная плашка цвета [color] с тёмным текстом (счётчик в меню).
  final bool filled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? RescueColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? c : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Text(
        text,
        semanticsLabel: semanticLabel,
        maxLines: 1,
        style: RescueText.tag.copyWith(color: filled ? RescueColors.onAccent : c, height: 1.4),
      ),
    );
  }
}

/// Шлюпка: подпись блока заглавными с разрядкой и необязательной меткой-рамкой с числом:
/// «ОШИБКИ ЗА ЧАС [7]», «СЕРВЕРЫ [2]», «РЕЖИМ».
///
/// ```dart
/// SectionLabel('Ошибки за час', count: '7', color: RescueColors.accent)
/// SectionLabel.screen('Главная', trailing: Text('замеры раз в минуту', style: RescueText.caption))
/// ```
/// Текст переводится в заглавные сам ([uppercase]). Для чтеца — заголовок.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.count,
    this.color,
    this.trailing,
    this.uppercase = true,
    this.style = RescueText.blockLabel,
  });

  /// Заголовок раздела (h1): «ГЛАВНАЯ», 13 / 700 / 0.18em, высота строки не меньше 44.
  const SectionLabel.screen(this.text, {super.key, this.trailing, this.count, this.color, this.uppercase = true})
    : style = RescueText.screenTitle;

  final String text;

  /// Число или короткое слово в метке-рамке справа от подписи.
  final String? count;

  /// Цвет подписи и метки; null — цвет текста вокруг (на жёлтом — тёмный, на тёмном — светлый).
  final Color? color;

  /// Справа: подпись, кнопка или ссылка.
  final Widget? trailing;
  final bool uppercase;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? RescueColors.text;
    final count = this.count;
    final trailing = this.trailing;
    final screen = identical(style, RescueText.screenTitle);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Semantics(
            header: true,
            child: Text(uppercase ? text.toUpperCase() : text, style: style.copyWith(color: c)),
          ),
        ),
        if (count != null) ...[const SizedBox(width: 8), FrameTag(count, color: c)],
      ],
    );
    final row = Row(
      children: [
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerStart, child: label),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), Flexible(child: trailing)],
      ],
    );
    return screen ? ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: row) : row;
  }
}
