import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/data/running_apps.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: экран «Раздельный туннель». Изменения действуют сразу, без переподключения.
class SplitTunnelPage extends HookConsumerWidget {
  const SplitTunnelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Раздельный туннель'),
          actions: [
            PopupMenuButton<void>(
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () => _confirmReset(context, ref),
                  child: const Text('Вернуть списки по умолчанию'),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.alt_route_rounded), text: 'Мимо VPN'),
              Tab(icon: Icon(Icons.shield_rounded), text: 'Через VPN'),
              Tab(icon: Icon(Icons.lan_rounded), text: 'Сейчас в сети'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ListTab(SplitTarget.bypass), _ListTab(SplitTarget.via), _ConnectionsTab()],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вернуть списки по умолчанию?'),
        content: const Text('Оба списка очистятся, в «Мимо VPN» вернутся игры и лаунчеры.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Вернуть')),
        ],
      ),
    );
    if (ok ?? false) ref.read(splitTunnelProvider.notifier).resetToDefaults();
  }
}

// ---------- списки ----------

class _ListTab extends HookConsumerWidget {
  const _ListTab(this.target);

  final SplitTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(splitTunnelProvider.select((s) => s.list(target)));
    final notifier = ref.read(splitTunnelProvider.notifier);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          target == SplitTarget.bypass
              ? 'Идёт напрямую, мимо VPN. Важнее остальных правил, работает сразу.'
              : 'Всегда идёт через VPN, даже российское. Важнее остальных правил, работает сразу.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.apps_rounded),
              label: const Text('Выбрать из запущенных'),
              onPressed: () => _pickRunning(context, ref),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Файл .exe'),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  dialogTitle: 'Программа для списка «${target.title}»',
                  type: FileType.custom,
                  allowedExtensions: ['exe'],
                  allowMultiple: true,
                );
                for (final f in result?.files ?? const <PlatformFile>[]) {
                  notifier.add(target, SplitKind.app, f.name);
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Сайты, IP, программы списком'),
              onPressed: () => _pasteMany(context, ref),
            ),
          ],
        ),
        for (final kind in SplitKind.values) ...[
          const SizedBox(height: 20),
          Text('${kind.title} · ${list.of(kind).length}', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (list.of(kind).isEmpty)
            Text('Пусто', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in list.of(kind))
                  InputChip(
                    label: Text(value),
                    onDeleted: () => notifier.remove(target, kind, value),
                    deleteButtonTooltipMessage: 'Убрать',
                  ),
              ],
            ),
        ],
      ],
    );
  }

  Future<void> _pickRunning(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<List<String>>(context: context, builder: (_) => _RunningAppsDialog(target));
    final notifier = ref.read(splitTunnelProvider.notifier);
    for (final exe in picked ?? const <String>[]) {
      notifier.add(target, SplitKind.app, exe);
    }
  }

  Future<void> _pasteMany(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Добавить в «${target.title}»'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'По одному на строку:\nyoutube.com\nhttps://example.com/page\n8.8.8.8\n10.0.0.0/8\ngame.exe',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final result = ref.read(splitTunnelProvider.notifier).addMany(target, text);
    if (!context.mounted) return;
    final skipped = result.skipped.isEmpty ? '' : '. Не понял: ${result.skipped.take(5).join(', ')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено: ${result.added}$skipped')));
  }
}

class _RunningAppsDialog extends HookWidget {
  const _RunningAppsDialog(this.target);

  final SplitTarget target;

  @override
  Widget build(BuildContext context) {
    final apps = useFuture(useMemoized(listRunningApps));
    final query = useState('');
    final selected = useState(<String>{});
    final filtered = (apps.data ?? const <RunningApp>[])
        .where(
          (a) =>
              query.value.isEmpty ||
              a.title.toLowerCase().contains(query.value.toLowerCase()) ||
              a.exe.toLowerCase().contains(query.value.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: Text('Программы → «${target.title}»'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Поиск'),
              onChanged: (v) => query.value = v,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (apps.connectionState) {
                ConnectionState.done when filtered.isEmpty => const Center(child: Text('Ничего не нашлось')),
                ConnectionState.done => ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final app = filtered[i];
                    final key = app.exe.toLowerCase();
                    return CheckboxListTile(
                      dense: true,
                      value: selected.value.contains(key),
                      title: Text(app.title),
                      subtitle: Text(app.exe),
                      onChanged: (v) => selected.value = v ?? false
                          ? {...selected.value, key}
                          : ({...selected.value}..remove(key)),
                    );
                  },
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (apps.data ?? const <RunningApp>[])
                .where((a) => selected.value.contains(a.exe.toLowerCase()))
                .map((a) => a.exe)
                .toList(),
          ),
          child: Text('Добавить (${selected.value.length})'),
        ),
      ],
    );
  }
}

// ---------- сейчас в сети ----------

class _Seen {
  _Seen(this.connection, this.lastSeen);

  NetConnection connection;
  DateTime lastSeen;
}

class _ConnectionsTab extends HookConsumerWidget {
  const _ConnectionsTab();

  // Сколько держать в списке закрывшееся соединение: короткие запросы иначе не успеть увидеть.
  static const _keep = Duration(seconds: 60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final port = ref.watch(ConfigOptions.clashApiPort);
    final seen = useRef(<String, _Seen>{});
    final available = useState<bool?>(null);
    final tick = useState(0);

    useEffect(() {
      var active = true;
      Future<void> poll() async {
        final list = await fetchConnections(port);
        if (!active) return;
        final now = DateTime.now();
        if (list != null) {
          for (final c in list) {
            final key = '${c.exe}|${c.host.isNotEmpty ? c.host : c.ip}|${c.port}';
            seen.value[key] = _Seen(c, now);
          }
        }
        seen.value.removeWhere((_, s) => now.difference(s.lastSeen) > _keep);
        available.value = list != null;
        tick.value++;
      }

      unawaited(poll());
      final timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      return () {
        active = false;
        timer.cancel();
      };
    }, [port]);

    final split = ref.watch(splitTunnelProvider);
    final theme = Theme.of(context);

    if (available.value == false && seen.value.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Соединения появятся, когда VPN подключён.', textAlign: TextAlign.center),
        ),
      );
    }
    if (available.value == null) return const Center(child: CircularProgressIndicator());

    final byApp = <String, List<NetConnection>>{};
    for (final s in seen.value.values) {
      byApp.putIfAbsent(s.connection.exe, () => []).add(s.connection);
    }
    final apps = byApp.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Что сейчас выходит в сеть и куда. Нажмите на программу, чтобы увидеть сайты. '
            'В режиме прокси видны только программы, которые используют системный прокси.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        for (final exe in apps)
          _AppConnections(exe: exe, connections: byApp[exe]!, membership: exe.isEmpty ? null : split.targetOf(SplitKind.app, exe)),
      ],
    );
  }
}

class _AppConnections extends ConsumerWidget {
  const _AppConnections({required this.exe, required this.connections, required this.membership});

  final String exe;
  final List<NetConnection> connections;
  final SplitTarget? membership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(splitTunnelProvider.notifier);
    final viaVpn = connections.where((c) => c.viaVpn).length;
    final route = switch (viaVpn) {
      0 => 'напрямую',
      _ when viaVpn == connections.length => 'через VPN',
      _ => 'частично через VPN',
    };
    final hosts = <String, NetConnection>{};
    for (final c in connections) {
      hosts.putIfAbsent(c.host.isNotEmpty ? c.host : c.ip, () => c);
    }
    return ExpansionTile(
      leading: Icon(viaVpn > 0 ? Icons.shield_rounded : Icons.alt_route_rounded),
      title: Text(exe.isEmpty ? 'Программа не определена' : exe),
      subtitle: Text(
        '${connections.length} соед. · $route'
        '${membership == null ? '' : ' · в списке «${membership!.title}»'}',
      ),
      trailing: exe.isEmpty ? null : _MoveButtons(kind: SplitKind.app, value: exe, membership: membership),
      children: [
        for (final entry in hosts.entries)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(entry.key),
            subtitle: Text('${entry.value.viaVpn ? 'через VPN' : 'напрямую'} · ${entry.value.network}:${entry.value.port}'),
            trailing: PopupMenuButton<VoidCallback>(
              tooltip: 'В список',
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                if (entry.value.host.isNotEmpty) ...[
                  PopupMenuItem(
                    value: () => notifier.add(SplitTarget.bypass, SplitKind.domain, _siteOf(entry.value.host)),
                    child: Text('Сайт ${_siteOf(entry.value.host)} → мимо VPN'),
                  ),
                  PopupMenuItem(
                    value: () => notifier.add(SplitTarget.via, SplitKind.domain, _siteOf(entry.value.host)),
                    child: Text('Сайт ${_siteOf(entry.value.host)} → через VPN'),
                  ),
                ],
                if (entry.value.ip.isNotEmpty) ...[
                  PopupMenuItem(
                    value: () => notifier.add(SplitTarget.bypass, SplitKind.ip, _cidrOf(entry.value.ip)),
                    child: Text('IP ${entry.value.ip} → мимо VPN'),
                  ),
                  PopupMenuItem(
                    value: () => notifier.add(SplitTarget.via, SplitKind.ip, _cidrOf(entry.value.ip)),
                    child: Text('IP ${entry.value.ip} → через VPN'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// «r3---sn-abc.googlevideo.com» → «googlevideo.com»: правило по сайту ловит и поддомены.
  static String _siteOf(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    const twoLevel = {'co.uk', 'com.ru', 'org.ru', 'net.ru', 'msk.ru', 'spb.ru', 'com.tr', 'com.br'};
    final lastTwo = parts.sublist(parts.length - 2).join('.');
    final take = twoLevel.contains(lastTwo) ? 3 : 2;
    return parts.sublist(parts.length - take).join('.');
  }

  static String _cidrOf(String ip) => ip.contains(':') ? '$ip/128' : '$ip/32';
}

class _MoveButtons extends ConsumerWidget {
  const _MoveButtons({required this.kind, required this.value, required this.membership});

  final SplitKind kind;
  final String value;
  final SplitTarget? membership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(splitTunnelProvider.notifier);
    return SegmentedButton<SplitTarget?>(
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      segments: const [
        ButtonSegment(value: SplitTarget.bypass, label: Text('Мимо')),
        ButtonSegment(value: SplitTarget.via, label: Text('VPN')),
      ],
      selected: {if (membership != null) membership},
      onSelectionChanged: (selection) {
        final target = selection.isEmpty ? null : selection.first;
        if (target == null) {
          notifier.remove(membership!, kind, value);
        } else {
          notifier.add(target, kind, value);
        }
      },
    );
  }
}
