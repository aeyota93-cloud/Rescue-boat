import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/direct_routes_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: вкладка «Мимо Шлюпки» в «Туннелировании» (model/direct_routes.dart).
///
/// Адреса, к которым Windows шлёт пакеты сама. Список виден целиком: что запомнено во время игр,
/// что добавлено вручную, что запрещено («никогда мимо»). Изменения сохраняются сразу и действуют
/// с подключения VPN; при включённом VPN их можно применить сразу — с подтверждением, потому что
/// соединения к этим адресам прервутся.
class TunnelDirectView extends HookConsumerWidget {
  const TunnelDirectView({super.key, this.now});

  /// Текущее время; в тестах подменяется.
  final DateTime Function()? now;

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

    final rows = routes.entries.entries.toList()
      ..sort((a, b) {
        int rank(DirectEntry e) => e.source == DirectSource.user ? 0 : (e.pinned ? 1 : 2);
        final r = rank(a.value).compareTo(rank(b.value));
        return r != 0 ? r : b.value.lastSeen.compareTo(a.value.lastSeen);
      });
    final never = routes.never.toList()..sort();

    final status = !enabled
        ? 'Выключено. Адреса не запоминаются, всё идёт через Шлюпку.'
        : applied == null
        ? 'Список применится при подключении VPN.'
        : directPending(applied, effective)
        ? 'Есть изменения: они применятся при переподключении VPN или сейчас.'
        : 'Всё применено.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RescueCard(
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
                    onPressed: () => _showAddDialog(context, ref, never: false),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Добавить адрес или сеть…'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showAddDialog(context, ref, never: true),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Никогда мимо…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        RescueCard.deep(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Label('МИМО ШЛЮПКИ'),
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
              for (final e in rows)
                _Row(
                  key: ValueKey('direct-${e.key}'),
                  icon: e.value.source == DirectSource.user ? Icons.person_rounded : Icons.history_rounded,
                  title: e.key.label,
                  detail: _detail(e.value, routes.isActive(e.value, split), clock()),
                  muted: !routes.isActive(e.value, split),
                  trailing: _EntryMenu(net: e.key, entry: e.value),
                ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Своих адресов пока нет: они появятся, когда вы поиграете в игры из «мимо VPN», '
                    'или добавьте их сами.',
                    style: TextStyle(fontSize: 12, color: RescueColors.muted),
                  ),
                ),
            ],
          ),
        ),
        if (never.isNotEmpty) ...[
          const SizedBox(height: 16),
          RescueCard.deep(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Label('НИКОГДА МИМО ШЛЮПКИ'),
                for (final n in never)
                  _Row(
                    key: ValueKey('never-$n'),
                    icon: Icons.block_rounded,
                    title: n.label,
                    detail: 'всегда через Шлюпку, даже внутри сетей Blizzard',
                    trailing: TextButton(onPressed: () => notifier.removeNever(n), child: const Text('Разрешить')),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// «запомнено · Overwatch.exe · закреплён · 3 дня назад» и почему не действует.
String _detail(DirectEntry e, bool active, DateTime now) {
  final days = now.difference(e.lastSeen).inDays;
  return [
    if (e.source == DirectSource.user) 'добавлено вами' else 'запомнено',
    if (e.app.isNotEmpty) e.app,
    if (e.source == DirectSource.learned && e.pinned) 'закреплён',
    if (e.source == DirectSource.learned)
      days <= 0 ? 'сегодня' : (days == 1 ? 'вчера' : '$days ${pluralRu(days, 'день', 'дня', 'дней')} назад'),
    if (!active) 'не действует: игра не в «мимо VPN»',
  ].join(' · ');
}

Future<void> _showAddDialog(BuildContext context, WidgetRef ref, {required bool never}) => showDialog<void>(
  context: context,
  builder: (_) => _AddDialog(never: never),
);

class _AddDialog extends HookConsumerWidget {
  const _AddDialog({required this.never});

  final bool never;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final error = useState<String?>(null);
    void submit() {
      final notifier = ref.read(directRoutesProvider.notifier);
      final e = never ? notifier.addNever(controller.text) : notifier.add(controller.text);
      if (e == null) {
        Navigator.pop(context);
      } else {
        error.value = e;
      }
    }

    return AlertDialog(
      title: Text(never ? 'Никогда мимо Шлюпки' : 'Мимо Шлюпки'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              never
                  ? 'Адрес или сеть всегда будут идти через Шлюпку, даже если игра туда ходила.'
                  : 'Пакеты к адресу или сети пойдут напрямую через Windows у всех программ, мимо VPN.',
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

class _EntryMenu extends ConsumerWidget {
  const _EntryMenu({required this.net, required this.entry});

  final V4Net net;
  final DirectEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(directRoutesProvider.notifier);
    return PopupMenuButton<void>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_horiz_rounded, color: RescueColors.muted),
      itemBuilder: (_) => [
        if (entry.source == DirectSource.learned)
          PopupMenuItem(
            onTap: () => notifier.setPinned(net, !entry.pinned),
            child: Text(entry.pinned ? 'Открепить' : 'Закрепить — не забывать'),
          ),
        PopupMenuItem(onTap: () => notifier.never(net), child: const Text('Вернуть в Шлюпку навсегда')),
        PopupMenuItem(onTap: () => notifier.remove(net), child: const Text('Убрать из списка')),
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

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.trailing,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: RescueColors.line)),
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
