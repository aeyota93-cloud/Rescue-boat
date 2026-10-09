/// Шлюпка: строки таблицы раздельного туннеля — записи обоих списков плюс программы,
/// которые сейчас в сети, с числом соединений и ошибок за сутки. Без виджетов, чтобы проверять тестами.
library;

import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

class TunnelEntry {
  const TunnelEntry({
    required this.kind,
    required this.value,
    required this.target,
    required this.isDefaultGame,
    required this.connections,
    required this.errors,
  });

  final SplitKind kind;

  /// Как хранится в списке: «steam.exe», «youtube.com», «192.168.0.0/16».
  final String value;

  /// null — ни в одном списке («Авто», решают общие правила).
  final SplitTarget? target;

  /// Из списка игр и лаунчеров по умолчанию.
  final bool isDefaultGame;

  /// Сколько соединений сейчас; null — неизвестно (ядро не запущено).
  final int? connections;

  /// Ошибок за сутки.
  final int errors;

  bool get online => (connections ?? 0) > 0;
}

class TunnelSummary {
  const TunnelSummary({required this.via, required this.bypass, required this.auto, required this.online});

  /// Записей в списке «через VPN».
  final int via;

  /// Записей в списке «мимо VPN».
  final int bypass;

  /// Программ в сети, которых нет в списках; null — неизвестно.
  final int? auto;

  /// Программ в сети; null — неизвестно.
  final int? online;
}

final _defaultGames = {for (final a in defaultBypassApps) a.toLowerCase()};

bool isDefaultGame(String exe) => _defaultGames.contains(exe.toLowerCase());

/// Сайт совпадает с правилом: сам домен или любой его поддомен (как domain_suffix в ядре).
bool hostMatches(String host, String domain) {
  final h = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final d = domain.toLowerCase();
  return h == d || h.endsWith('.$d');
}

/// Адрес внутри сети «a.b.c.d/m» (IPv4) или совпадает с адресом IPv6 /128.
bool ipInCidr(String ip, String cidr) {
  if (ip.isEmpty) return false;
  final slash = cidr.indexOf('/');
  final base = slash < 0 ? cidr : cidr.substring(0, slash);
  final bits = slash < 0 ? null : int.tryParse(cidr.substring(slash + 1));
  final a = _ipv4(ip);
  final b = _ipv4(base);
  if (a == null || b == null) {
    // IPv6: только точное совпадение адреса.
    return (bits == null || bits == 128) && ip.toLowerCase() == base.toLowerCase();
  }
  final m = (bits ?? 32).clamp(0, 32);
  if (m == 0) return true;
  final mask = (0xFFFFFFFF << (32 - m)) & 0xFFFFFFFF;
  return (a & mask) == (b & mask);
}

int? _ipv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return null;
  var v = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    v = (v << 8) | n;
  }
  return v;
}

/// Частные сети: роутер, принтер, телевизор.
bool isHomeNetwork(String cidr) {
  final base = cidr.split('/').first;
  if (base.contains(':')) {
    final l = base.toLowerCase();
    return l.startsWith('fc') || l.startsWith('fd') || l.startsWith('fe80');
  }
  return ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16'].any((n) => ipInCidr(base, n));
}

bool _connMatches(SplitKind kind, String value, NetConnection c) => switch (kind) {
  SplitKind.app => c.exe.toLowerCase() == value.toLowerCase(),
  SplitKind.domain => c.host.isNotEmpty && hostMatches(c.host, value),
  SplitKind.ip => ipInCidr(c.ip, value),
};

/// Ошибки за сутки для записи: сайт — по группам ошибок с этим сайтом и его поддоменами,
/// программа — по событиям с этим exe, сеть — по адресам внутри неё.
int errorsFor(SplitKind kind, String value, List<ErrorGroup> groups) {
  var sum = 0;
  for (final g in groups) {
    switch (kind) {
      case SplitKind.domain:
        if (!g.key.startsWith('app:') && g.key.isNotEmpty && hostMatches(g.key, value)) sum += g.count;
      case SplitKind.app:
        for (final e in g.events) {
          if (e.app.toLowerCase() == value.toLowerCase()) sum += e.count;
        }
      case SplitKind.ip:
        for (final e in g.events) {
          if (ipInCidr(e.ip, value)) sum += e.count;
        }
    }
  }
  return sum;
}

/// Строки и плитки. [connections] = null — ядро не запущено, «сейчас» неизвестно.
({List<TunnelEntry> entries, TunnelSummary summary}) buildTunnelRows(
  SplitTunnel split,
  List<NetConnection>? connections,
  List<ErrorGroup> errors,
) {
  int? count(SplitKind kind, String value) =>
      connections?.where((c) => _connMatches(kind, value, c)).length;

  final entries = <TunnelEntry>[];
  void addEntry(SplitKind kind, String value, SplitTarget? target) => entries.add(
    TunnelEntry(
      kind: kind,
      value: value,
      target: target,
      isDefaultGame: kind == SplitKind.app && isDefaultGame(value),
      connections: count(kind, value),
      errors: errorsFor(kind, value, errors),
    ),
  );

  for (final target in [SplitTarget.via, SplitTarget.bypass]) {
    final list = split.list(target);
    for (final kind in SplitKind.values) {
      for (final value in list.of(kind)) {
        // Запись в обоих списках быть не должна, но если есть — побеждает «через VPN», как в ядре.
        if (target == SplitTarget.bypass && split.via.contains(kind, value)) continue;
        addEntry(kind, value, target);
      }
    }
  }

  // Программы в сети, которых нет в списках.
  final onlineApps = <String, String>{};
  for (final c in connections ?? const <NetConnection>[]) {
    if (c.exe.isNotEmpty) onlineApps.putIfAbsent(c.exe.toLowerCase(), () => c.exe);
  }
  var auto = 0;
  for (final exe in onlineApps.values) {
    if (split.targetOf(SplitKind.app, exe) != null) continue;
    auto++;
    addEntry(SplitKind.app, exe, null);
  }

  entries.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.value.toLowerCase().compareTo(b.value.toLowerCase());
  });

  int total(SplitList l) => l.apps.length + l.domains.length + l.ips.length;
  return (
    entries: entries,
    summary: TunnelSummary(
      via: total(split.via),
      bypass: total(split.bypass),
      auto: connections == null ? null : auto,
      online: connections == null ? null : onlineApps.length,
    ),
  );
}

/// «1 соединение», «3 соединения», «14 соединений».
String pluralRu(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

/// «r3---sn-abc.googlevideo.com» → «googlevideo.com»: правило по сайту ловит и поддомены.
String siteOf(String host) {
  final parts = host.split('.');
  if (parts.length <= 2) return host;
  const twoLevel = {'co.uk', 'com.ru', 'org.ru', 'net.ru', 'msk.ru', 'spb.ru', 'com.tr', 'com.br'};
  final lastTwo = parts.sublist(parts.length - 2).join('.');
  final take = twoLevel.contains(lastTwo) ? 3 : 2;
  return parts.sublist(parts.length - take).join('.');
}

String cidrOf(String ip) => ip.contains(':') ? '$ip/128' : '$ip/32';
