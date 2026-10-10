import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/section_label.dart';

/// Цвета строки [DeepListTile]: обычной (на deep) и выделенной (жёлтой).
/// Пригодятся, чтобы раскрасить свой хвост строки (кольцо, переключатель) в тон.
enum DeepTileColors {
  normal(
    background: Colors.transparent,
    border: RescueColors.line,
    tile: RescueColors.line,
    title: RescueColors.accent,
    subtitle: RescueColors.subOnDeep,
    foreground: RescueColors.textOnDeep,
    ring: RescueColors.accent,
    ringTrack: RescueColors.line,
  ),
  highlighted(
    background: RescueColors.accent,
    border: RescueColors.accent,
    tile: RescueColors.accentTile,
    title: RescueColors.onAccent,
    subtitle: RescueColors.onAccentMuted,
    foreground: RescueColors.onAccent,
    ring: RescueColors.onAccent,
    ringTrack: RescueColors.accentDeep,
  );

  const DeepTileColors({
    required this.background,
    required this.border,
    required this.tile,
    required this.title,
    required this.subtitle,
    required this.foreground,
    required this.ring,
    required this.ringTrack,
  });

  static DeepTileColors of({required bool highlighted}) => highlighted ? DeepTileColors.highlighted : normal;

  final Color background;
  final Color border;

  /// Плитка-значок слева.
  final Color tile;
  final Color title;
  final Color subtitle;

  /// Текст и значки хвоста.
  final Color foreground;

  /// Дуга и дорожка кольца в хвосте (RingStat).
  final Color ring;
  final Color ringTrack;
}

/// Шлюпка: тёмный блок-список (приём 5 стиля «Д»): фон deep, радиус 32, отступ 18, строки через 10.
///
/// ```dart
/// DeepList(
///   title: 'Ошибки за час', count: '7',
///   actionLabel: 'Все ошибки', onAction: () => context.go('/errors'),
///   children: [
///     DeepListTile(leading: 'K', title: 'kinopoisk.ru', subtitle: 'Chrome · сброс · VPN', trailingText: '5', highlighted: true),
///     DeepListTile(leading: 'D', title: 'gateway.discord.gg', subtitle: 'Discord · обрыв · VPN', trailingText: '1'),
///   ],
/// )
/// ```
class DeepList extends StatelessWidget {
  const DeepList({
    super.key,
    required this.children,
    this.title,
    this.count,
    this.actionLabel,
    this.onAction,
    this.radius = 32,
    this.padding = const EdgeInsets.all(18),
    this.spacing = 10,
    this.semanticLabel,
  });

  final List<Widget> children;

  /// Подпись блока заглавными жёлтым: «ОШИБКИ ЗА ЧАС».
  final String? title;

  /// Метка-рамка с числом справа от подписи.
  final String? count;

  /// Ссылка внизу справа: «Все ошибки ›» (стрелку дорисуем).
  final String? actionLabel;
  final VoidCallback? onAction;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double spacing;

  /// Название блока для чтеца; null — [title].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final action = actionLabel;
    final items = <Widget>[
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
          child: SectionLabel(title, count: count, color: RescueColors.accent),
        ),
      ...children,
      if (action != null)
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            button: true,
            link: true,
            label: action,
            onTap: onAction,
            child: ExcludeSemantics(
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(999),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        '$action ›',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: RescueColors.textOnDeep,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
    final spaced = <Widget>[
      for (final (i, w) in items.indexed) ...[if (i > 0) SizedBox(height: spacing), w],
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel ?? title,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(color: RescueColors.deep, borderRadius: BorderRadius.circular(radius)),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: RescueColors.textOnDeep),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: spaced,
          ),
        ),
      ),
    );
  }
}

/// Шлюпка: строка тёмного списка: плитка-значок (буква или значок), заголовок, подпись и хвост.
///
/// Обычная строка — прозрачная с рамкой line, заголовок жёлтый; [highlighted] — жёлтая строка
/// с тёмным текстом (первая/выбранная). Высота от 60, радиус 20, плитка 36 радиус 10.
/// Если задан [onTap] — строка-кнопка (для чтеца — с отметкой [selected]).
class DeepListTile extends StatelessWidget {
  const DeepListTile({
    super.key,
    required this.title,
    this.leading,
    this.leadingIcon,
    this.subtitle,
    this.trailing,
    this.trailingText,
    this.highlighted = false,
    this.selected,
    this.onTap,
    this.minHeight = 60,
    this.tileSize = 36,
    this.radius = 20,
    this.semanticLabel,
  });

  final String title;

  /// Буква или код в плитке: «K», «NL».
  final String? leading;

  /// Значок в плитке вместо буквы.
  final IconData? leadingIcon;
  final String? subtitle;

  /// Свой хвост (кольцо, переключатель). Цвета — из [DeepTileColors.of].
  final Widget? trailing;

  /// Тонкое число справа (18 / 300): счётчик ошибок.
  final String? trailingText;

  /// Жёлтая строка.
  final bool highlighted;

  /// Отметка «выбрано» для чтеца у строки-кнопки; null — как [highlighted].
  final bool? selected;
  final VoidCallback? onTap;
  final double minHeight;
  final double tileSize;
  final double radius;

  /// Как прочитать строку; null — «заголовок, подпись, хвост-текст».
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = DeepTileColors.of(highlighted: highlighted);
    final leading = this.leading;
    final icon = leadingIcon;
    final sub = subtitle;
    final tailText = trailingText;
    final tail = trailing;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: c.border),
    );

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (leading != null || icon != null) ...[
              ExcludeSemantics(
                child: Container(
                  width: tileSize,
                  height: tileSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.tile, borderRadius: BorderRadius.circular(tileSize * 10 / 36)),
                  child: icon != null
                      ? Icon(icon, size: tileSize / 2, color: c.foreground)
                      : Text(
                          leading!,
                          maxLines: 1,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.foreground),
                        ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.title),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.subtitle),
                      ),
                  ],
                ),
              ),
            ),
            if (tailText != null) ...[
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Text(
                  tailText,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: c.foreground),
                ),
              ),
            ],
            if (tail != null) ...[
              const SizedBox(width: 12),
              IconTheme.merge(
                data: IconThemeData(color: c.foreground),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: c.foreground),
                  child: tail,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final onTap = this.onTap;
    final spoken = semanticLabel ?? [title, ?sub, ?tailText].join(', ');
    final material = Material(
      color: c.background,
      shape: shape,
      child: onTap == null ? row : InkWell(onTap: onTap, customBorder: shape, excludeFromSemantics: true, child: row),
    );
    // Тексты строки скрыты от чтеца и читаются одной подписью; кнопки и переключатели
    // в хвосте ([trailing]) остаются доступны.
    return Semantics(
      container: true,
      explicitChildNodes: tail != null,
      button: onTap != null,
      selected: onTap != null ? (selected ?? highlighted) : null,
      label: spoken,
      onTap: onTap,
      child: material,
    );
  }
}
