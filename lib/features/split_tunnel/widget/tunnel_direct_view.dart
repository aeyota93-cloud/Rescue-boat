import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/app_names.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/direct_routes_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/direct_add.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: вкладка «Мимо Шлюпки» в «Туннелировании» (model/direct_routes.dart).
///
/// Адреса, к которым Windows шлёт пакеты сама. Две колонки: «Мимо Шлюпки» — сети игровых компаний
/// и адреса по группам (добавлено вами, сайты, программы) и «Только через Шлюпку» — запрет. Изменения
/// сохраняются сразу и действуют с подключения VPN; при включённом VPN их можно применить сразу — с
/// подтверждением, потому что соединения к этим адресам прервутся.
class TunnelDirectView extends HookConsumerWidget {
  const TunnelDirectView({super.key, this.now, this.focus});

  /// Текущее время; в тестах подменяется.
  final DateTime Function()? now;

  /// Группа, к которой перешли из «Сейчас в сети» (exe программы или сайт): выделена рамкой.
  final String? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(directRoutesProvider);
    final split = ref.watch(splitTunnelProvider);
    final enabled = ref.watch(directRoutesEnabledProvider);
    final effective = ref.watch(directEffectiveProvider);
    final applied = ref.watch(directAppliedProvider);
    final notifier = ref.read(directRoutesProvider.notifier);
    final applying = useState(false);
    final clock = now ?? DateTime.now;

    Future<void> applyNow() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Применить сейчас?'),
          content: const Text(
            'Соединения к адресам, которые меняются, прервутся. Если вы сейчас в матче, игра может '
            'вылететь — тогда просто зайдите в матч снова. Остальные программы и VPN не пострадают.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Применить')),
          ],
        ),
      );
      if (!(ok ?? false)) return;
      applying.value = true;
      final error = await notifier.applyNow();
      applying.value = false;
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error ?? 'Применено: маршруты Windows обновлены')));
    }

    final groups = directGroups(routes);
    final never = routes.never.toList()..sort();

    final status = !enabled
        ? 'Выключено. Адреса не запоминаются, всё идёт через Шлюпку.'
        : applied == null
        ? 'Список применится при подключении VPN.'
        : directPending(applied, effective)
        ? 'Есть изменения: они применятся при переподключении VPN или сейчас.'
        : 'Всё применено.';

    final top = RescueCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Пакеты к этим адресам Windows отправляет сама — без Шлюпки и без VPN, у всех программ. '
            'Так игры не ждут Шлюпку, когда компьютер загружен.',
            style: RescueText.body,
          ),
          const SizedBox(height: 12),
          Text(
            status,
            key: const ValueKey('direct-status'),
            style: RescueText.smallSecondary.copyWith(
              color: directPending(applied, effective) && enabled ? RescueColors.accent : null,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!enabled)
                FilledButton(
                  onPressed: () => ref.read(DirectRoutesPreferences.enabled.notifier).update(true),
                  child: const Text('Включить'),
                ),
              if (enabled && directPending(applied, effective))
                FilledButton.icon(
                  onPressed: applying.value ? null : applyNow,
                  icon: applying.value
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('Применить сейчас'),
                ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _AddDialog()),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Добавить адрес или сеть…'),
              ),
            ],
          ),
        ],
      ),
    );

    final direct = RescueCard.deep(
      key: const ValueKey('direct-column'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('МИМО ШЛЮПКИ'),
          const _SubLabel('Сети игровых компаний'),
          for (final k in knownNets)
            _Row(
              icon: Icons.sports_esports_rounded,
              title: k.title,
              detail: [
                '${k.nets.length} сетей',
                if (!routes.netsOn(k))
                  'выключено'
                else if (!routes.netsActive(k, split))
                  'не действует: ${k.appsTitle} не в «мимо VPN»',
              ].join(' · '),
              muted: !routes.netsActive(k, split),
              trailing: RescueToggle(
                value: routes.netsOn(k),
                onChanged: (on) => notifier.setNets(k.id, on),
                semanticLabel: '${k.title} мимо Шлюпки',
              ),
            ),
          for (final g in groups)
            _Group(
              group: g,
              routes: routes,
              split: split,
              now: clock(),
              focused: focus != null && g.key.toLowerCase() == focus!.toLowerCase(),
            ),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Своих адресов пока нет: они появятся, когда вы поиграете в игры из «мимо VPN», '
                'или добавьте их сами — здесь или в меню программы, соединения и ошибки.',
                style: TextStyle(fontSize: 12, color: RescueColors.muted),
              ),
            ),
        ],
      ),
    );

    final only = RescueCard.deep(
      key: const ValueKey('never-column'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('ТОЛЬКО ЧЕРЕЗ ШЛЮПКУ'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Эти адреса всегда идут через Шлюпку — даже внутри сетей игровых компаний, и сами сюда '
              'больше не попадут. Сюда ведёт «Убрать и больше не добавлять».',
              style: TextStyle(fontSize: 12, color: RescueColors.muted),
            ),
          ),
          for (final n in never)
            _Row(
              key: ValueKey('never-$n'),
              icon: Icons.block_rounded,
              title: n.label,
              detail: 'всегда через Шлюпку',
              trailing: _NeverMenu(net: n),
            ),
          if (never.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Пусто.', style: TextStyle(fontSize: 12, color: RescueColors.muted)),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= twoColumnsFrom;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            const SizedBox(height: 16),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: direct),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: only),
                ],
              )
            else ...[
              direct,
              const SizedBox(height: 16),
              only,
            ],
          ],
        );
      },
    );
  }

  /// С этой ширины «Мимо Шлюпки» и «Только через Шлюпку» стоят рядом.
  static const twoColumnsFrom = 820.0;
}

/// «запомнено · закреплён · 3 дня назад» и почему не действует.
String _detail(DirectEntry e, bool active, DateTime now) {
  final days = now.difference(e.lastSeen).inDays;
  return [
    if (e.source == DirectSource.user) 'добавлено вами' else 'запомнено',
    if (e.source == DirectSource.learned && e.pinned) 'закреплён',
    if (e.source == DirectSource.learned)
      days <= 0 ? 'сегодня' : (days == 1 ? 'вчера' : '$days ${pluralRu(days, 'день', 'дня', 'дней')} назад'),
    if (!active) 'не действует: игра не в «мимо VPN»',
  ].join(' · ');
}

/// Группа: заголовок (сайт, программа, «добавлено вами») и её адреса.
class _Group extends ConsumerWidget {
  const _Group({
    required this.group,
    required this.routes,
    required this.split,
    required this.now,
    this.focused = false,
  });

  final DirectGroup group;
  final DirectRoutes routes;
  final SplitTunnel split;
  final DateTime now;
  final bool focused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(directRoutesProvider.notifier);
    final g = group;
    final n = g.entries.length;
    final active = g.entries.where((e) => routes.isActive(e.value, split)).length;
    final (icon, title) = switch (g.kind) {
      DirectGroupKind.user => (Icons.person_rounded, 'Добавлено вами'),
      DirectGroupKind.site => (Icons.public_rounded, 'Сайт ${g.key}'),
      DirectGroupKind.app => (Icons.apps_rounded, appTitle(g.key)),
    };
    final detail = [
      if (n == 0) 'адреса появятся при первом соединении' else addressesRu(n),
      if (g.kind == DirectGroupKind.site) 'новые адреса добавляются сами',
      if (g.kind == DirectGroupKind.app) g.key,
      if (n > 0 && active == 0) 'не действует: не в «мимо VPN»',
    ].join(' · ');
    return Container(
      key: ValueKey('direct-group-${g.key}'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: focused ? RescueColors.accent : RescueColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            icon: icon,
            title: title,
            detail: detail,
            muted: n > 0 && active == 0,
            first: true,
            trailing: PopupMenuButton<void>(
              tooltip: 'Действия с группой',
              icon: const Icon(Icons.more_horiz_rounded, color: RescueColors.muted),
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () {
                    if (g.kind == DirectGroupKind.site) {
                      notifier.removeSite(g.key);
                    }
                    for (final e in g.entries) {
                      notifier.remove(e.key);
                    }
                  },
                  child: _MenuText(
                    g.kind == DirectGroupKind.site ? 'Не следить за сайтом' : 'Убрать все адреса',
                    g.kind == DirectGroupKind.site
                        ? 'адреса сайта уйдут из списка'
                        : 'запомненные могут вернуться, если игра снова туда пойдёт',
                  ),
                ),
              ],
            ),
          ),
          for (final e in g.entries)
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: _Row(
                key: ValueKey('direct-${e.key}'),
                icon: e.value.source == DirectSource.user ? Icons.push_pin_outlined : Icons.history_rounded,
                title: e.key.label,
                detail: _detail(e.value, routes.isActive(e.value, split), now),
                muted: !routes.isActive(e.value, split),
                trailing: _EntryMenu(net: e.key, entry: e.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddDialog extends HookConsumerWidget {
  const _AddDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final error = useState<String?>(null);
    void submit() {
      final e = ref.read(directRoutesProvider.notifier).add(controller.text);
      if (e == null) {
        Navigator.pop(context);
      } else {
        error.value = e;
      }
    }

    return AlertDialog(
      title: const Text('Мимо Шлюпки'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Пакеты к адресу или сети пойдут напрямую через Windows у всех программ, мимо VPN.',
              style: RescueText.smallSecondary,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => submit(),
              onChanged: (_) => error.value = null,
              decoration: InputDecoration(hintText: '35.228.147.76 или 137.221.64.0/19', errorText: error.value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: submit, child: const Text('Добавить')),
      ],
    );
  }
}

/// Пункт меню с подсказкой мелким шрифтом.
class _MenuText extends StatelessWidget {
  const _MenuText(this.title, this.hint);

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

class _EntryMenu extends ConsumerWidget {
  const _EntryMenu({required this.net, required this.entry});

  final V4Net net;
  final DirectEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(directRoutesProvider.notifier);
    final learned = entry.source == DirectSource.learned;
    return PopupMenuButton<void>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_horiz_rounded, color: RescueColors.muted),
      itemBuilder: (_) => [
        if (learned)
          PopupMenuItem(
            onTap: () => notifier.setPinned(net, !entry.pinned),
            child: Text(entry.pinned ? 'Открепить' : 'Закрепить — не забывать'),
          ),
        PopupMenuItem(
          onTap: () => notifier.remove(net),
          child: learned
              ? const _MenuText('Убрать', 'может вернуться, если игра или сайт снова туда пойдут')
              : const Text('Убрать'),
        ),
        PopupMenuItem(
          onTap: () => notifier.never(net),
          child: const _MenuText('Убрать и больше не добавлять', 'адрес уйдёт в «Только через Шлюпку»'),
        ),
      ],
    );
  }
}

class _NeverMenu extends ConsumerWidget {
  const _NeverMenu({required this.net});

  final V4Net net;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(directRoutesProvider.notifier);
    return PopupMenuButton<void>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_horiz_rounded, color: RescueColors.muted),
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () => notifier.neverBack(net),
          child: const _MenuText('Вернуть в «Мимо Шлюпки»', 'адрес снова пойдёт напрямую'),
        ),
        PopupMenuItem(
          onTap: () => notifier.removeNever(net),
          child: const _MenuText('Удалить из списка', 'обычный адрес: игра может запомнить его снова'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: RescueText.microLabel.copyWith(color: RescueColors.subOnDeep)),
  );
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RescueColors.muted),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.trailing,
    this.muted = false,
    this.first = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget trailing;
  final bool muted;

  /// Первая строка группы: без черты сверху.
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: first ? null : const Border(top: BorderSide(color: RescueColors.line)),
    ),
    child: Opacity(
      opacity: muted ? 0.55 : 1,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: RescueColors.line, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: RescueColors.textOnDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.textOnDeep),
                ),
                Text(detail, style: const TextStyle(fontSize: 11, color: RescueColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    ),
  );
}
