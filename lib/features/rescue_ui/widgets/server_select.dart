import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Вариант в списке [ServerSelect].
class ServerOption<T> {
  const ServerOption({required this.value, required this.code, required this.name, this.subtitle, this.ping});

  final T value;

  /// Код страны или буква в плитке: «NL», «A».
  final String code;

  /// Название: «Нидерланды», «Автовыбор».
  final String name;

  /// Подпись: «first.gym-notes.ru · Основная».
  final String? subtitle;

  /// Пинг или режим справа: «48 МС», «АВТО».
  final String? ping;
}

/// Шлюпка: выбор сервера (приём 4 стиля «Д»): тёмная кнопка-строка (deep, радиус 22, высота 64)
/// с плиткой-кодом, названием жёлтым, подписью, пингом и стрелкой. По нажатию под ней
/// раскрывается тёмный список вариантов и строка «+ Добавить подписку или сервер».
///
/// ```dart
/// ServerSelect<String>(
///   options: const [ServerOption(value: 'nl', code: 'NL', name: 'Нидерланды', subtitle: 'first.gym-notes.ru', ping: '48 МС')],
///   value: selectedId,
///   onChanged: (id) => ...,          // список сам закроется
///   onAdd: () => context.go('/servers'),
/// )
/// ```
/// Раскрытием можно управлять снаружи ([expanded] + [onExpandedChanged]); если [expanded] = null —
/// состояние хранится внутри. Клавиатура: Enter/Пробел раскрывает, Tab — по вариантам, Esc — закрыть.
class ServerSelect<T> extends StatefulWidget {
  const ServerSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.onAdd,
    this.addLabel = '+ Добавить подписку или сервер',
    this.placeholder = 'Сервер не выбран',
    this.expanded,
    this.onExpandedChanged,
    this.semanticLabel = 'Сервер',
  });

  final List<ServerOption<T>> options;

  /// Выбранный вариант; null или нет в списке — показываем [placeholder].
  final T? value;

  /// null — выбор недоступен (кнопка всё равно раскрывает список для просмотра).
  final ValueChanged<T>? onChanged;

  /// Действие внизу списка; null — строки нет.
  final VoidCallback? onAdd;
  final String addLabel;
  final String placeholder;
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;

  /// Название для чтеца: «Сервер, Нидерланды».
  final String semanticLabel;

  @override
  State<ServerSelect<T>> createState() => _ServerSelectState<T>();
}

class _ServerSelectState<T> extends State<ServerSelect<T>> {
  bool _open = false;

  bool get _expanded => widget.expanded ?? _open;

  void _setExpanded(bool v) {
    if (widget.expanded == null) setState(() => _open = v);
    widget.onExpandedChanged?.call(v);
  }

  void _pick(T value) {
    widget.onChanged?.call(value);
    _setExpanded(false);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.options.where((o) => o.value == widget.value).firstOrNull;
    final expanded = _expanded;
    final onAdd = widget.onAdd;

    final button = Semantics(
      button: true,
      expanded: expanded,
      label: '${widget.semanticLabel}, ${current?.name ?? widget.placeholder}',
      hint: [?current?.subtitle, ?current?.ping].join(', '),
      onTap: () => _setExpanded(!expanded),
      child: ExcludeSemantics(
        child: Material(
          color: RescueColors.deep,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            key: const ValueKey('server-select-button'),
            onTap: () => _setExpanded(!expanded),
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _CodeTile(code: current?.code ?? '?', size: 40, radius: 12, color: RescueColors.line),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            current?.name ?? widget.placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: current != null ? RescueColors.accent : RescueColors.textOnDeep,
                            ),
                          ),
                          if (current?.subtitle case final sub?)
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
                            ),
                        ],
                      ),
                    ),
                    if (current?.ping case final ping?) ...[
                      const SizedBox(width: 8),
                      Text(
                        ping,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.88,
                          color: RescueColors.textOnDeep,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: RescueColors.subOnDeep),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final list = Container(
      key: const ValueKey('server-select-list'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: RescueColors.panel, borderRadius: BorderRadius.circular(22)),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Выбор сервера',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in widget.options)
              _OptionRow<T>(
                option: o,
                selected: o.value == widget.value,
                onTap: widget.onChanged == null ? null : () => _pick(o.value),
              ),
            if (onAdd != null)
              Semantics(
                button: true,
                label: widget.addLabel,
                onTap: onAdd,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        widget.addLabel,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RescueColors.text),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {if (expanded) const SingleActivator(LogicalKeyboardKey.escape): () => _setExpanded(false)},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [button, if (expanded) list],
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({required this.option, required this.selected, required this.onTap});

  final ServerOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = option.subtitle;
    final ping = option.ping;
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: onTap != null,
      label: [option.name, ?sub, ?ping].join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? RescueColors.card : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    _CodeTile(code: option.code, size: 32, radius: 10, color: RescueColors.card),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RescueColors.text),
                          ),
                          if (sub != null)
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: RescueColors.muted),
                            ),
                        ],
                      ),
                    ),
                    if (ping != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        ping,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RescueColors.text),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeTile extends StatelessWidget {
  const _CodeTile({required this.code, required this.size, required this.radius, required this.color});

  final String code;
  final double size;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: Text(
        code,
        maxLines: 1,
        style: TextStyle(fontSize: size >= 40 ? 13 : 12, fontWeight: FontWeight.w700, color: RescueColors.text),
      ),
    );
  }
}
