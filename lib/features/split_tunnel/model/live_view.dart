/// Шлюпка: вкладка «Сейчас в сети» раздельного туннеля (docs/redesign/tunnel-v3.md) — соединения
/// по программам: куда ушло каждое (реальный выход из ядра) и почему (какая запись сработала).
/// Без виджетов, чтобы проверять тестами.
library;

import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';

/// Запись списков, которая отправила соединение.
class RuleHit {
  const RuleHit({required this.item, required this.target, this.server, this.group});

  final SplitRef item;
  final SplitTarget target;

  /// Сервер, за которым закреплена запись; null — «Авто» или мимо.
  final String? server;
  final String? group;
}

/// Подходит ли запись к соединению — так же, как наборы правил в ядре.
bool connectionMatches(SplitRef item, NetConnection c) => switch (item.kind) {
  SplitKind.app => c.exe.isNotEmpty && c.exe.toLowerCase() == item.value.toLowerCase(),
  SplitKind.domain => c.host.isNotEmpty && hostMatches(c.host, item.value),
  SplitKind.ip => ipInCidr(c.ip, item.value),
};

/// Какая запись сработала. Порядок как в ядре (Rescue-boat-core, split_tunnel.go): записи за
/// серверами (если серверов два и больше), потом «через VPN», потом «мимо». null — ни одна:
/// решают общие правила («Авто»).
RuleHit? ruleFor(SplitTunnel split, NetConnection c, {required bool severalServers}) {
  RuleHit? find(SplitList list, SplitTarget target, String? server) {
    for (final kind in SplitKind.values) {
      for (final value in list.of(kind)) {
        final item = (kind: kind, value: value);
        if (connectionMatches(item, c)) {
          return RuleHit(item: item, target: target, server: server, group: split.groupOf(kind, value));
        }
      }
    }
    return null;
  }

  if (severalServers) {
    for (final MapEntry(key: tag, value: list) in split.servers.entries) {
      if (find(list, SplitTarget.via, tag) case final hit?) return hit;
    }
  }
  // При одном сервере его записи ядро держит в общем «через VPN» (viaAll).
  return find(split.via, SplitTarget.via, null) ??
      (severalServers ? null : _firstServerHit(split, find)) ??
      find(split.bypass, SplitTarget.bypass, null);
}

RuleHit? _firstServerHit(SplitTunnel split, RuleHit? Function(SplitList, SplitTarget, String?) find) {
  for (final MapEntry(key: tag, value: list) in split.servers.entries) {
    if (find(list, SplitTarget.via, tag) case final hit?) return hit;
  }
  return null;
}

/// Куда соединение ушло на самом деле: мимо VPN, через сервер или через VPN (сервер не узнали).
sealed class LiveDest {
  const LiveDest();

  /// Ключ для сводки и цвета.
  String get key;
}

class DirectDest extends LiveDest {
  const DirectDest();
  @override
  String get key => 'direct';
}

class ServerDest extends LiveDest {
  const ServerDest(this.server);
  final RescueServer server;
  @override
  String get key => 'server:${server.tag}';
}

class VpnDest extends LiveDest {
  const VpnDest();
  @override
  String get key => 'vpn';
}

LiveDest destOf(NetConnection c, RescueServers? servers) {
  if (!c.viaVpn) return const DirectDest();
  final s = servers?.serverOfChain(c.chains);
  return s == null ? const VpnDest() : ServerDest(s);
}

String destLabel(LiveDest d) => switch (d) {
  DirectDest() => 'Мимо VPN',
  ServerDest(:final server) => server.name,
  VpnDest() => 'Через VPN',
};

/// Одно соединение строки программы.
class LiveConn {
  const LiveConn({required this.connection, required this.hit, required this.dest});

  final NetConnection connection;
  final RuleHit? hit;
  final LiveDest dest;

  /// Без записи в списках — решили общие правила.
  bool get auto => hit == null;

  /// Сайт (или IP), куда идёт.
  String get address => connection.host.isNotEmpty ? connection.host : connection.ip;

  int get bytes => connection.upload + connection.download;
}

/// Программа и её соединения сейчас. [exe] пустой — ядро не узнало программу.
class LiveApp {
  const LiveApp({required this.exe, required this.conns, required this.group});

  final String exe;
  final List<LiveConn> conns;

  /// Группа записи программы; null — без группы или программы нет в списках.
  final String? group;

  int get open => conns.where((c) => !c.connection.closed).length;
  int get bytes => conns.fold(0, (s, c) => s + c.bytes);
  List<LiveDest> get dests {
    final seen = <String>{};
    return [
      for (final c in conns)
        if (seen.add(c.dest.key)) c.dest,
    ];
  }
}

/// Фильтр «Сейчас в сети».
enum LiveFilter { all, vpn, direct, auto }

bool liveFilterPasses(LiveFilter f, LiveConn c) => switch (f) {
  LiveFilter.all => true,
  LiveFilter.vpn => c.dest is! DirectDest,
  LiveFilter.direct => c.dest is DirectDest,
  LiveFilter.auto => c.auto,
};

/// Программы с соединениями: сначала те, у кого больше открытых соединений, потом больше трафика.
/// [query] — по программе (имени файла или названию [titleOf]), сайту или IP.
List<LiveApp> buildLiveApps(
  SplitTunnel split,
  List<NetConnection> connections,
  RescueServers? servers, {
  LiveFilter filter = LiveFilter.all,
  String query = '',
  String Function(String exe)? titleOf,
}) {
  final several = servers != null && servers.several;
  final q = query.trim().toLowerCase();
  final byExe = <String, List<LiveConn>>{};
  final names = <String, String>{};
  for (final c in connections) {
    final conn = LiveConn(
      connection: c,
      hit: ruleFor(split, c, severalServers: several),
      dest: destOf(c, servers),
    );
    if (!liveFilterPasses(filter, conn)) continue;
    if (q.isNotEmpty) {
      final title = c.exe.isEmpty ? '' : (titleOf?.call(c.exe) ?? c.exe);
      if (![c.exe, title, c.host, c.ip].any((v) => v.toLowerCase().contains(q))) continue;
    }
    final key = c.exe.toLowerCase();
    names.putIfAbsent(key, () => c.exe);
    (byExe[key] ??= []).add(conn);
  }
  final apps = [
    for (final MapEntry(key: key, value: list) in byExe.entries)
      LiveApp(
        exe: names[key]!,
        conns: list..sort((a, b) => b.bytes.compareTo(a.bytes)),
        group: key.isEmpty ? null : split.groupOf(SplitKind.app, names[key]!),
      ),
  ];
  apps.sort((a, b) {
    if (a.exe.isEmpty != b.exe.isEmpty) return a.exe.isEmpty ? 1 : -1;
    final byOpen = b.open.compareTo(a.open);
    return byOpen != 0 ? byOpen : b.bytes.compareTo(a.bytes);
  });
  return apps;
}

/// Сводка над списком: сколько открытых соединений ушло каждым путём, по порядку
/// «основной, запасные, через VPN, мимо».
List<(LiveDest, int)> liveSummary(List<NetConnection> connections, RescueServers? servers) {
  final counts = <String, (LiveDest, int)>{};
  for (final c in connections.where((c) => !c.closed)) {
    final d = destOf(c, servers);
    final prev = counts[d.key];
    counts[d.key] = (d, (prev?.$2 ?? 0) + 1);
  }
  int rank(LiveDest d) => switch (d) {
    ServerDest(:final server) => server.index,
    VpnDest() => 1000,
    DirectDest() => 1001,
  };
  return counts.values.toList()..sort((a, b) => rank(a.$1).compareTo(rank(b.$1)));
}

/// «12,4 МБ», «830 КБ», «0 КБ».
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${_one(bytes / (1024 * 1024 * 1024))} ГБ';
  if (bytes >= 1024 * 1024) return '${_one(bytes / (1024 * 1024))} МБ';
  return '${(bytes / 1024).round()} КБ';
}

String _one(double v) => v >= 100 ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
