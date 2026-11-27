import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/model/live_view.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/direct_routes_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/place_menu.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Мимо Шлюпки» из меню — общий диалог и пункт меню (model/direct_routes.dart,
/// docs/redesign/direct-routes-v2.md). Все точки входа (программа, группа, запись, соединение,
/// ошибки) отбирают адреса одной функцией [directCandidates] и показывают один диалог.

/// «12 адресов».
String addressesRu(int n) => '$n ${pluralRu(n, 'адрес', 'адреса', 'адресов')}';

/// Почему часть адресов не взята — одной строкой; пусто — всё взято.
String directSkippedText(DirectCandidates c) => [
  if (c.viaVpn > 0) '${addressesRu(c.viaVpn)} — через VPN',
  if (c.shared > 0) '${c.shared} общие с другими сайтами или программами',
  if (c.already > 0) '${c.already} уже в списке',
  if (c.never > 0) '${c.never} в «Только через Шлюпку»',
  if (c.over > 0) '${c.over} не влезли: за раз не больше $directAddMax',
].join('; ');

/// Диалог «Мимо Шлюпки»: что добавится, что нет и почему; «Добавить» или «Добавить и применить
/// сейчас» (только при включённом VPN). [what] — «программы Overwatch», «сайта discord.gg».
Future<void> showDirectAddDialog(BuildContext context, {required DirectCandidates candidates, required String what}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _DirectAddDialog(candidates: candidates, what: what),
    );

class _DirectAddDialog extends ConsumerStatefulWidget {
  const _DirectAddDialog({required this.candidates, required this.what});

  final DirectCandidates candidates;
  final String what;

  @override
  ConsumerState<_DirectAddDialog> createState() => _DirectAddDialogState();
}

class _DirectAddDialogState extends ConsumerState<_DirectAddDialog> {
  bool _busy = false;

  Future<void> _add({required bool now}) async {
    // ref.read до первого await.
    final notifier = ref.read(directRoutesProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picks = widget.candidates.picks;
    notifier.addPicks(picks);
    var text = 'Добавлено в «Мимо Шлюпки»: ${addressesRu(picks.length)}';
    if (now) {
      setState(() => _busy = true);
      final error = await notifier.applyNow();
      text = error ?? '$text. Применено: маршруты Windows обновлены';
    }
    if (mounted) Navigator.pop(context);
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidates;
    final connected = ref.watch(connectionNotifierProvider.select((s) => s.valueOrNull is Connected));
    final enabled = ref.watch(directRoutesEnabledProvider);
    final sites = {
      for (final p in c.picks)
        if (p.site.isNotEmpty) p.site,
    };
    final skipped = directSkippedText(c);
    final shown = c.picks.take(6).map((p) => p.net.label).join(', ') + (c.picks.length > 6 ? ' …' : '');
    return AlertDialog(
      title: const Text('Мимо Шлюпки'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${addressesRu(c.picks.length)} ${widget.what} пойдут напрямую: пакеты к ним Windows '
              'отправит сама, без Шлюпки и без VPN — у всех программ.',
              style: RescueText.body,
            ),
            const SizedBox(height: 8),
            Text(shown, key: const ValueKey('direct-add-list'), style: RescueText.smallSecondary),
            if (sites.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Новые адреса ${sites.join(', ')} Шлюпка будет добавлять сама, старые — забывать через 30 дней.',
                style: RescueText.smallSecondary,
              ),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Не взяты: $skipped.', key: const ValueKey('direct-add-skipped'), style: RescueText.smallSecondary),
            ],
            if (!enabled) ...[
              const SizedBox(height: 8),
              const Text(
                '«Мимо Шлюпки» сейчас выключено: адреса сохранятся и заработают, когда вы его включите.',
                style: RescueText.smallSecondary,
              ),
            ] else if (connected) ...[
              const SizedBox(height: 8),
              const Text(
                '«Применить сейчас» прервёт соединения к этим адресам. Если вы в матче, игра может вылететь — '
                'тогда зайдите снова.',
                style: RescueText.smallSecondary,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        if (enabled && connected)
          OutlinedButton(onPressed: _busy ? null : () => _add(now: false), child: const Text('Добавить'))
        else
          FilledButton(onPressed: _busy ? null : () => _add(now: false), child: const Text('Добавить')),
        if (enabled && connected)
          FilledButton.icon(
            key: const ValueKey('direct-add-now'),
            onPressed: _busy ? null : () => _add(now: true),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt_rounded, size: 18),
            label: const Text('Добавить и применить сейчас'),
          ),
      ],
    );
  }
}

/// Отбор адресов для записей [items] из текущих соединений.
DirectCandidates candidatesForItems(List<SplitRef> items, List<NetConnection> all, DirectRoutes routes) {
  final seenAll = all.map(seenOfConnection).toList();
  final matched = [
    for (final c in all)
      if (items.any((i) => connectionMatches(i, c))) seenOfConnection(c),
  ];
  final sites = {
    for (final i in items)
      if (i.kind == SplitKind.domain) i.value.toLowerCase(),
  };
  return directCandidates(matched, seenAll, routes, sites: sites);
}

/// Подпись и доступность пункта «Мимо Шлюпки» — без виджетов, для тестов.
({String title, String hint, bool enabled}) directMenuState(DirectCandidates? c, {required bool online}) {
  if (c == null) return (title: 'Мимо Шлюпки', hint: 'смотрю соединения…', enabled: false);
  if (c.picks.isNotEmpty) {
    return (
      title: 'Мимо Шлюпки: ${addressesRu(c.picks.length)}',
      hint: 'адреса сейчас — напрямую через Windows, у всех программ',
      enabled: true,
    );
  }
  if (!online) return (title: 'Мимо Шлюпки', hint: 'сейчас не в сети — адресов нет', enabled: false);
  if (c.viaVpn > 0) return (title: 'Мимо Шлюпки', hint: 'сначала выберите «Мимо VPN»', enabled: false);
  if (c.already > 0) return (title: 'Мимо Шлюпки ✓', hint: 'адреса уже в списке', enabled: false);
  return (title: 'Мимо Шлюпки', hint: 'нечего добавить: ${directSkippedText(c)}', enabled: false);
}

/// Пункт меню «Мимо Шлюпки: 12 адресов» для записей [items]. Соединения читает, только пока
/// меню открыто (пункт построен) — опрос ядра не идёт зря.
class DirectMenuItem extends ConsumerWidget {
  const DirectMenuItem({super.key, required this.items, required this.what});

  final List<SplitRef> items;

  /// «программы Overwatch» — для диалога.
  final String what;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Маршруты туннеля — таблица Windows: на других системах «Мимо Шлюпки» нет.
    if (!PlatformUtils.isWindows) return const SizedBox.shrink();
    final live = ref.watch(liveConnectionsProvider);
    final routes = ref.watch(directRoutesProvider);
    final all = live.valueOrNull;
    final c = live.isLoading && all == null ? null : candidatesForItems(items, all ?? const [], routes);
    final online = all != null && all.any((x) => items.any((i) => connectionMatches(i, x)));
    final s = directMenuState(c, online: online);
    // Меню закрывается раньше, чем сработает нажатие, и этот пункт исчезает: диалог открываем
    // от навигатора — он живёт дальше.
    final host = Navigator.of(context).context;
    return MenuItemButton(
      key: const ValueKey('direct-menu-item'),
      leadingIcon: const Icon(Icons.call_split_rounded, size: 18, color: RescueColors.muted),
      onPressed: s.enabled ? () => showDirectAddDialog(host, candidates: c!, what: what) : null,
      child: MenuTwoLines(s.title, s.hint),
    );
  }
}

/// «программы Overwatch», «сайта discord.gg», «сети 1.2.3.0/24» — для диалога «Мимо Шлюпки».
String directWhatOf(SplitRef i, String title) => switch (i.kind) {
  SplitKind.app => 'программы $title',
  SplitKind.domain => 'сайта ${i.value}',
  SplitKind.ip => 'IP ${i.value.replaceFirst(RegExp(r'/(32|128)$'), '')}',
};

// ---------- «Ошибки» ----------

/// Отбор адресов из ошибок: сами ошибки — и выборка, и фон (общие адреса видны внутри них).
DirectCandidates candidatesForErrors(List<ErrorEvent> events, DirectRoutes routes) {
  final seen = events.map(seenOfError).toList();
  return directCandidates(seen, seen, routes);
}

/// Кнопка «IP (n) мимо Шлюпки» у группы ошибок; n — адреса, которые можно добавить.
class DirectErrorsButton extends ConsumerWidget {
  const DirectErrorsButton({super.key, required this.events});

  final List<ErrorEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!PlatformUtils.isWindows) return const SizedBox.shrink();
    final c = candidatesForErrors(events, ref.watch(directRoutesProvider));
    final s = directMenuState(c, online: true);
    final n = c.picks.length;
    return Tooltip(
      message: s.enabled ? 'Пакеты к этим адресам Windows отправит сама, без Шлюпки' : s.hint,
      child: OutlinedButton.icon(
        key: const ValueKey('direct-group-ips'),
        onPressed: s.enabled ? () => showDirectAddDialog(context, candidates: c, what: 'из этих ошибок') : null,
        icon: const Icon(Icons.call_split_rounded, size: 16),
        label: Text(n > 1 ? 'IP ($n) мимо Шлюпки' : 'IP мимо Шлюпки'),
      ),
    );
  }
}

/// Значок «мимо Шлюпки» у IP в строке ошибки.
class DirectEventIcon extends ConsumerWidget {
  const DirectEventIcon({super.key, required this.event});

  final ErrorEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!PlatformUtils.isWindows || !isPublicIPv4(event.ip)) return const SizedBox.shrink();
    final c = candidatesForErrors([event], ref.watch(directRoutesProvider));
    final s = directMenuState(c, online: true);
    return IconButton(
      key: ValueKey('direct-ip-${event.ip}'),
      tooltip: s.enabled ? 'Мимо Шлюпки' : 'Мимо Шлюпки: ${s.hint}',
      // Без запаса до 48×48: иначе каждая строка ошибок становится выше.
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: s.title.endsWith('✓') ? RescueColors.accent : RescueColors.muted,
      onPressed: s.enabled ? () => showDirectAddDialog(context, candidates: c, what: 'IP ${event.ip}') : null,
      icon: Icon(s.title.endsWith('✓') ? Icons.check_rounded : Icons.call_split_rounded),
    );
  }
}
