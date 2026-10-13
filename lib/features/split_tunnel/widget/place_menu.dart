import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/model/live_view.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: общие кнопки туннеля (docs/redesign/tunnel-v3.md) — плашка пути «Запасной 2 ▾» с меню
/// «Авто / Мимо VPN / Через VPN / серверы», кнопка группы «Общение» / «+ В группу» и метка
/// реального выхода соединения.

/// Как место называется на плашке: «Авто», «Мимо VPN», «VPN», «Запасной 2». null — разные.
String placeLabel(SplitPlace? place, RescueServers? servers) => switch (place) {
  null => 'Разные',
  (target: null, server: _) => 'Авто',
  (target: SplitTarget.bypass, server: _) => 'Мимо VPN',
  (target: SplitTarget.via, server: null) => 'VPN',
  (target: SplitTarget.via, server: final String tag) => servers?.byTag(tag)?.name ?? 'VPN',
};

/// «2 мимо, 1 через запасной 2» — у группы с разными путями.
String describePlaces(SplitTunnel split, List<SplitRef> items, RescueServers? servers) {
  final counts = <String, int>{};
  for (final i in items) {
    final p = split.placeOf(i.kind, i.value);
    final label = switch (p) {
      (target: null, server: _) => 'авто',
      (target: SplitTarget.bypass, server: _) => 'мимо',
      (target: SplitTarget.via, server: null) => 'через VPN',
      (target: SplitTarget.via, server: final String tag) => serverPlaceLabel(tag, servers),
    };
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return [for (final e in counts.entries) '${e.value} ${e.key}'].join(', ');
}

/// Пункты меню «куда направить» [items]: галочка у места, общего для всех.
List<Widget> placeMenuItems({
  required WidgetRef ref,
  required SplitTunnel split,
  required RescueServers? servers,
  required List<SplitRef> items,
  VoidCallback? onCompare,
}) {
  final notifier = ref.read(splitTunnelProvider.notifier);
  final current = split.commonPlace(items);
  final several = servers != null && servers.several;
  final pinned = current?.server;
  final lost = pinned != null && servers != null && servers.byTag(pinned) == null;
  void set(SplitPlace p) => notifier.setPlace(items, p);

  return [
    MenuItemButton(
      leadingIcon: _Check(current == autoPlace),
      onPressed: () => set(autoPlace),
      child: const _TwoLines('Авто', 'общие правила: российское мимо, остальное через VPN'),
    ),
    MenuItemButton(
      leadingIcon: _Check(current == bypassPlace),
      onPressed: () => set(bypassPlace),
      child: const _TwoLines('Мимо VPN', 'напрямую, с домашнего IP'),
    ),
    const Divider(height: 8),
    MenuItemButton(
      leadingIcon: _Check(current == viaPlace),
      onPressed: () => set(viaPlace),
      child: _TwoLines(
        'Через VPN',
        several ? 'сервер выберет Шлюпка: основной, при сбое запасные' : 'всегда через сервер',
      ),
    ),
    if (several)
      for (final s in servers.servers)
        MenuItemButton(
          key: ValueKey('place-server-${s.tag}'),
          leadingIcon: _Check(current?.server == s.tag),
          onPressed: () => set((target: SplitTarget.via, server: s.tag)),
          child: _TwoLines(s.name, [?s.hint, s.title].join(' · ')),
        ),
    if (lost)
      MenuItemButton(
        leadingIcon: const _Check(true),
        child: Text('«${serverTitle(pinned)}» — сервера нет, идёт через Авто'),
      ),
    if (onCompare != null) ...[
      const Divider(height: 8),
      MenuItemButton(leadingIcon: const _Check(false), onPressed: onCompare, child: const Text('Сравнить пути…')),
    ],
  ];
}

/// Плашка пути «Запасной 2 ▾»: показывает, куда идут [items], по нажатию — меню [placeMenuItems].
class PlaceButton extends ConsumerWidget {
  const PlaceButton({super.key, required this.items, required this.label, this.onCompare, this.compact = false});

  final List<SplitRef> items;

  /// Что направляем — для подсказки и чтеца: «Google Chrome», «группа Общение».
  final String label;
  final VoidCallback? onCompare;

  /// Ниже и уже — для строк соединений.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final place = split.commonPlace(items);
    final text = placeLabel(place, servers);
    final (bg, fg, border) = switch (place) {
      null => (Colors.transparent, RescueColors.warn, RescueColors.warn),
      (target: null, server: _) => (Colors.transparent, RescueColors.subOnDeep, RescueColors.line2),
      (target: SplitTarget.bypass, server: _) => (RescueColors.card, RescueColors.textOnDeep, RescueColors.line2),
      (target: SplitTarget.via, server: null) => (
        RescueColors.accent.withValues(alpha: 0.14),
        RescueColors.accent,
        RescueColors.accent.withValues(alpha: 0.45),
      ),
      (target: SplitTarget.via, server: _) => (RescueColors.accent, RescueColors.onAccent, RescueColors.accent),
    };
    return MenuAnchor(
      menuChildren: placeMenuItems(ref: ref, split: split, servers: servers, items: items, onCompare: onCompare),
      builder: (context, controller, _) => Tooltip(
        message: 'Куда направить: $label',
        child: Semantics(
          button: true,
          label: 'Куда направить: $label. Сейчас: $text',
          child: ExcludeSemantics(
            child: Material(
              color: bg,
              shape: StadiumBorder(side: BorderSide(color: border)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => controller.isOpen ? controller.close() : controller.open(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: compact ? 32 : 40, minWidth: 44),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more_rounded, size: 16, color: fg),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка группы записи: имя группы или «+ В группу». Меню: группы, «Новая группа…», «Убрать из
/// группы», «Открыть группу».
class GroupButton extends ConsumerWidget {
  const GroupButton({
    super.key,
    required this.items,
    required this.label,
    this.onOpenGroup,
    this.maxWidth = 160,
    this.short = false,
  });

  /// Одна запись или несколько отмеченных.
  final List<SplitRef> items;
  final String label;

  /// «Открыть группу «…»» — перейти к ней на вкладке «Группы»; null — пункта нет.
  final ValueChanged<String>? onOpenGroup;
  final double maxWidth;

  /// Внутри открытой группы её имя у каждой записи лишнее: «Перенести» вместо имени.
  final bool short;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final notifier = ref.read(splitTunnelProvider.notifier);
    final current = {for (final i in items) split.groupOf(i.kind, i.value)};
    final only = current.length == 1 ? current.single : null;
    final grouped = current.any((g) => g != null);
    final text = items.length > 1 ? 'В группу' : (only == null ? '+ В группу' : (short ? 'Перенести' : only));
    final color = only == null || items.length > 1 ? RescueColors.accent : RescueColors.subOnDeep;
    return MenuAnchor(
      menuChildren: [
        for (final g in split.groups)
          MenuItemButton(
            leadingIcon: _Check(only != null && sameGroupName(g.name, only)),
            onPressed: only != null && sameGroupName(g.name, only) ? null : () => notifier.moveToGroup(g.name, items),
            child: Text('${g.name} · ${g.items.length}'),
          ),
        MenuItemButton(
          leadingIcon: const _Check(false),
          onPressed: () async {
            final name = await showGroupNameDialog(context, title: 'Новая группа');
            if (name != null) notifier.moveToGroup(name, items);
          },
          child: const Text('Новая группа…'),
        ),
        if (grouped) ...[
          const Divider(height: 8),
          MenuItemButton(
            leadingIcon: const _Check(false),
            onPressed: () => notifier.removeFromGroup(items),
            child: const _TwoLines('Убрать из группы', 'путь записи не изменится'),
          ),
          if (only != null && onOpenGroup != null)
            MenuItemButton(
              leadingIcon: const _Check(false),
              onPressed: () => onOpenGroup!(only),
              child: Text('Открыть группу «$only»', style: const TextStyle(color: RescueColors.accent)),
            ),
        ],
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Группа: $label',
        child: Semantics(
          button: true,
          label: only == null ? 'Положить в группу: $label' : 'Группа $only: $label',
          child: ExcludeSemantics(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: 32, maxWidth: maxWidth),
                child: CustomPaint(
                  painter: _DashedPainter(
                    color: only == null ? RescueColors.accent.withValues(alpha: 0.6) : RescueColors.line2,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Цвет реального выхода: основной — жёлтый, запасные — темнее, «мимо» — серый.
Color destColor(LiveDest d) => switch (d) {
  DirectDest() => const Color(0xFF8C8378),
  VpnDest() => RescueColors.accentDeep,
  ServerDest(:final server) => const [
    RescueColors.accent,
    Color(0xFFE7A93C),
    Color(0xFFC9B27A),
    Color(0xFFD98F5C),
    Color(0xFFB8A27A),
  ][server.index % 5],
};

/// Метка «куда ушло на самом деле»: цветной квадрат и имя пути.
class DestPill extends StatelessWidget {
  const DestPill(this.dest, {super.key});

  final LiveDest dest;

  @override
  Widget build(BuildContext context) {
    final c = destColor(dest);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              destLabel(dest),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// «не удалось 76» — соединений с ошибкой за сутки; при нуле ничего. В строке ставить во [Flexible].
class FailBadge extends StatelessWidget {
  const FailBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Tooltip(
      message: 'Соединений, которые не удались за сутки',
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: RescueColors.warn.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'не удалось $count',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: RescueColors.warn),
        ),
      ),
    );
  }
}

/// Окно с именем группы; null — отмена или пустое имя.
Future<String?> showGroupNameDialog(BuildContext context, {required String title, String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(title: title, initial: initial),
    );

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('group-name'),
      controller: _controller,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(hintText: 'Например, «Работа и дом»'),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
      FilledButton(onPressed: _done, child: const Text('Готово')),
    ],
  );
}

/// Галочка у текущего места; у остальных — пустое место той же ширины, чтобы текст стоял ровно.
class _Check extends StatelessWidget {
  const _Check(this.on);

  final bool on;

  @override
  Widget build(BuildContext context) => on
      ? const Icon(Icons.check_rounded, size: 18, color: RescueColors.accent, semanticLabel: 'выбрано')
      : const SizedBox(width: 18);
}

/// Пункт меню: название и мелкая подсказка под ним.
class _TwoLines extends StatelessWidget {
  const _TwoLines(this.title, this.hint);

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title),
      Text(hint, style: const TextStyle(fontSize: 12, color: RescueColors.muted)),
    ],
  );
}

/// Пунктирная рамка кнопки группы.
class _DashedPainter extends CustomPainter {
  const _DashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)).deflate(0.5));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}
