/// Шлюпка: «Мимо Шлюпки» — адреса, к которым Windows шлёт пакеты сама, не заходя в туннель.
///
/// Программы «мимо VPN» и так не идут в VPN, но их пакеты проходят через ядро: оно ловит весь
/// трафик и само отправляет его напрямую. Когда процессор занят игрой, ядро отвечает с опозданием,
/// и в игре это видно как потери и скачки пинга. Адреса из этого списка ядро убирает из маршрутов
/// туннеля (ядро rb.29+, tun-exclude.txt): Windows шлёт пакеты к ним сразу в сетевую карту.
///
/// Таблица маршрутов Windows знает только адрес, не программу: адрес из списка идёт мимо Шлюпки
/// у всех программ. Поэтому список узкий и под рукой у пользователя:
/// - сети игровых компаний ([knownNets]: Blizzard, Valve), если в «мимо VPN» есть их программы;
/// - адреса, куда игры из «мимо VPN» слали заметный UDP-трафик (запоминаются на лету и один раз
///   берутся из журнала ошибок). Сайты, CDN, DNS и QUIC (TCP, UDP 443, служебные порты) не берутся;
/// - адреса и сети, которые пользователь добавил сам — вручную или из меню («Мимо Шлюпки»
///   у программы, соединения, ошибки; [directCandidates]);
/// - адреса сайтов, за которыми пользователь попросил следить («Сайт и поддомены» → «Мимо
///   Шлюпки»): запоминаются на лету, как адреса игр, и так же забываются;
/// - минус «только через Шлюпку» ([DirectRoutes.never]) — этот запрет сильнее всего остального.
/// Ядро читает список при подключении; «Применить сейчас» перестраивает маршруты туннеля так же,
/// как ядро ([tunRouteRanges]), не дожидаясь переподключения.
library;

import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

/// Файл для ядра в папке раздельного туннеля (Rescue-boat-core, tun_exclude.go).
const tunExcludeFileName = 'tun-exclude.txt';

/// Список «Мимо Шлюпки» (рядом, в той же папке).
const directRoutesFileName = 'direct-routes.json';

/// Файл первой версии (только запомненные адреса), читается при переходе.
const legacyGameRoutesFileName = 'game-routes.json';

/// Сколько запомненных адресов помнить: каждый дробит маршрут туннеля примерно на 30 маршрутов.
const learnedRoutesMax = 256;

/// Запомненный адрес, где давно не играли, забывается (закреплённый — нет).
const learnedRoutesTtl = Duration(days: 30);

/// Меньше этого за соединение — проверка пинга до серверов разных стран, а не матч.
const gameFlowMinDownload = 64 * 1024;

/// UDP-порты, которые не игра: DNS, время, QUIC (браузеры, сайты), STUN, поиск в домашней сети.
const nonGameUdpPorts = {53, 67, 68, 123, 137, 138, 443, 853, 1900, 3478, 3479, 5353, 5355};

/// Программы Blizzard: если хоть одна в «мимо VPN», её сети идут мимо Шлюпки.
const blizzardApps = {'overwatch.exe', 'battle.net.exe', 'agent.exe', 'hearthstone.exe', 'diablo iv.exe', 'wow.exe'};

/// Сети Blizzard Entertainment (AS57976, IPv4, ip2asn 2026-11).
const blizzardNets = [
  '5.42.160.0/20',
  '5.42.176.0/22',
  '24.105.0.0/22',
  '24.105.16.0/22',
  '24.105.25.0/24',
  '24.105.27.0/24',
  '24.105.28.0/22',
  '24.105.40.0/21',
  '24.105.50.0/23',
  '24.105.52.0/22',
  '24.105.56.0/21',
  '37.244.0.0/24',
  '37.244.2.0/23',
  '37.244.4.0/22',
  '37.244.8.0/23',
  '37.244.10.0/24',
  '37.244.13.0/24',
  '37.244.14.0/23',
  '37.244.16.0/23',
  '37.244.19.0/24',
  '37.244.20.0/24',
  '37.244.23.0/24',
  '37.244.24.0/21',
  '37.244.32.0/22',
  '37.244.36.0/23',
  '37.244.38.0/24',
  '37.244.40.0/22',
  '37.244.44.0/24',
  '37.244.50.0/24',
  '37.244.52.0/22',
  '37.244.60.0/22',
  '59.153.40.0/22',
  '64.224.0.0/21',
  '64.224.24.0/21',
  '66.40.176.0/20',
  '103.4.114.0/23',
  '103.198.32.0/23',
  '117.52.6.0/24',
  '117.52.26.0/23',
  '117.52.33.0/24',
  '117.52.34.0/23',
  '117.52.36.0/23',
  '121.254.137.0/24',
  '121.254.206.0/23',
  '121.254.218.0/24',
  '137.221.64.0/19',
  '137.221.104.0/22',
  '137.221.108.0/23',
  '137.221.111.0/24',
  '137.221.112.0/24',
  '150.116.9.0/24',
  '158.115.192.0/20',
  '158.115.216.0/21',
  '182.162.31.0/24',
  '185.60.112.0/22',
  '198.74.32.0/22',
  '198.74.36.0/23',
  '202.9.66.0/23',
];

/// Программы Valve и Steam: если хоть одна в «мимо VPN», сети Valve идут мимо Шлюпки.
const steamApps = {'steam.exe', 'cs2.exe', 'dota2.exe', 'project8.exe', 'tf_win64.exe'};

/// Сети Valve (AS32590, IPv4, RIPEstat announced-prefixes 2026-11-27, объединены). Через них идут
/// матчи игр Valve (Steam Datagram Relay). Магазин и загрузки Steam — на чужих CDN, их здесь нет.
const steamNets = [
  '45.121.184.0/24',
  '103.10.124.0/23',
  '103.28.54.0/24',
  '146.66.152.0/24',
  '146.66.155.0/24',
  '155.133.224.0/21',
  '155.133.236.0/22',
  '155.133.240.0/23',
  '155.133.244.0/24',
  '155.133.246.0/24',
  '155.133.248.0/22',
  '155.133.252.0/24',
  '155.133.254.0/23',
  '162.254.192.0/21',
  '185.25.180.0/24',
  '185.25.182.0/23',
  '192.69.96.0/22',
  '205.196.6.0/24',
  '208.64.200.0/22',
  '208.78.164.0/22',
];

/// Набор сетей игровой компании: действует, если в «мимо VPN» есть её программа.
class KnownNets {
  const KnownNets({
    required this.id,
    required this.title,
    required this.appsTitle,
    required this.apps,
    required this.nets,
  });

  /// Ключ в файле списка.
  final String id;

  /// «Сети Blizzard».
  final String title;

  /// Для подсказки «не действует: Overwatch и Battle.net не в «мимо VPN»».
  final String appsTitle;

  /// Имена exe в нижнем регистре.
  final Set<String> apps;
  final List<String> nets;
}

const knownNets = [
  KnownNets(
    id: 'blizzard',
    title: 'Сети Blizzard',
    appsTitle: 'Overwatch и Battle.net',
    apps: blizzardApps,
    nets: blizzardNets,
  ),
  KnownNets(id: 'steam', title: 'Сети Steam', appsTitle: 'Steam и игры Valve', apps: steamApps, nets: steamNets),
];

/// Сколько адресов можно добавить за одно действие из меню: каждый дробит маршрут туннеля
/// примерно на 30 маршрутов Windows.
const directAddMax = 64;

// ---------- Сети IPv4 ----------

/// Сеть IPv4: адрес (32 бита) и длина префикса. Адрес всегда «обрезан» по префиксу.
class V4Net implements Comparable<V4Net> {
  V4Net(int addr, this.bits) : addr = bits == 0 ? 0 : addr & (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;

  final int addr;
  final int bits;

  int get first => addr;
  int get last => addr + (1 << (32 - bits)) - 1;

  /// «1.2.3.4» или «1.2.3.0/24»; null — не IPv4.
  static V4Net? tryParse(String raw) {
    final s = raw.trim();
    final slash = s.indexOf('/');
    final ip = slash < 0 ? s : s.substring(0, slash);
    final bits = slash < 0 ? 32 : int.tryParse(s.substring(slash + 1));
    if (bits == null || bits < 0 || bits > 32) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    var addr = 0;
    for (final p in parts) {
      final b = int.tryParse(p);
      if (b == null || b < 0 || b > 255 || p.isEmpty || p.length > 3) return null;
      addr = (addr << 8) | b;
    }
    return V4Net(addr, bits);
  }

  bool contains(V4Net other) => other.first >= first && other.last <= last;

  String get ip => [24, 16, 8, 0].map((s) => (addr >> s) & 0xFF).join('.');

  /// Как пишем пользователю: один адрес — без «/32».
  String get label => bits == 32 ? ip : toString();

  @override
  String toString() => '$ip/$bits';

  @override
  int compareTo(V4Net other) => addr != other.addr ? addr.compareTo(other.addr) : bits.compareTo(other.bits);

  @override
  bool operator ==(Object other) => other is V4Net && other.addr == addr && other.bits == bits;

  @override
  int get hashCode => Object.hash(addr, bits);
}

/// Обычный адрес в интернете (не локальный, не служебный).
bool isPublicV4(V4Net n) {
  final a = n.addr >> 24;
  final b = (n.addr >> 16) & 0xFF;
  if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
  if (a == 100 && b >= 64 && b < 128) return false; // CGNAT провайдера
  if (a == 169 && b == 254) return false;
  if (a == 172 && b >= 16 && b < 32) return false;
  if (a == 192 && b == 168) return false;
  return true;
}

bool isPublicIPv4(String ip) {
  final n = V4Net.tryParse(ip);
  return n != null && n.bits == 32 && !ip.contains('/') && isPublicV4(n);
}

/// Отрезки адресов → наименьший набор сетей (тот же разбор, что у ядра: netipx IPSet.Prefixes).
List<V4Net> _rangesToNets(List<(int, int)> ranges) {
  final out = <V4Net>[];
  for (var (start, end) in ranges) {
    while (start <= end) {
      var bits = 32;
      // Самая большая сеть, которая начинается в start и не вылезает за end.
      while (bits > 0) {
        final size = 1 << (32 - (bits - 1));
        if (start % size != 0 || start + size - 1 > end) break;
        bits--;
      }
      final net = V4Net(start, bits);
      out.add(net);
      start = net.last + 1;
    }
  }
  return out;
}

List<(int, int)> _mergedRanges(Iterable<V4Net> nets) {
  final sorted = nets.map((n) => (n.first, n.last)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(int, int)>[];
  for (final r in sorted) {
    if (out.isNotEmpty && r.$1 <= out.last.$2 + 1) {
      if (r.$2 > out.last.$2) out[out.length - 1] = (out.last.$1, r.$2);
    } else {
      out.add(r);
    }
  }
  return out;
}

/// Объединить сети в наименьший набор.
List<V4Net> collapseNets(Iterable<V4Net> nets) => _rangesToNets(_mergedRanges(nets));

/// [from] без [remove].
List<V4Net> subtractNets(Iterable<V4Net> from, Iterable<V4Net> remove) {
  final cut = _mergedRanges(remove);
  final out = <(int, int)>[];
  for (var (start, end) in _mergedRanges(from)) {
    for (final (cs, ce) in cut) {
      if (ce < start || cs > end) continue;
      if (cs > start) out.add((start, cs - 1));
      start = ce + 1;
      if (start > end) break;
    }
    if (start <= end) out.add((start, end));
  }
  return _rangesToNets(out);
}

/// Маршруты туннеля при этом списке «мимо Шлюпки»: весь IPv4 без него — как строит ядро (sing-tun
/// BuildAutoRouteRanges с route_exclude_address).
List<V4Net> tunRouteRanges(Iterable<V4Net> direct) => subtractNets([V4Net(0, 0)], direct);

/// Что добавить и что убрать в таблице маршрутов туннеля, чтобы получить [target].
({List<V4Net> add, List<V4Net> remove}) tunRouteDiff(Iterable<V4Net> current, Iterable<V4Net> target) {
  final cur = current.toSet();
  final tgt = target.toSet();
  return (add: (tgt.difference(cur).toList()..sort()), remove: (cur.difference(tgt).toList()..sort()));
}

/// Разбор того, что ввёл пользователь: адрес или сеть в интернете, не шире /8 (как в ядре).
({V4Net? net, String? error}) parseDirectInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return (net: null, error: null);
  final net = V4Net.tryParse(s);
  if (net == null) return (net: null, error: 'Нужен адрес IPv4 или сеть, например 35.228.147.76 или 137.221.64.0/19');
  if (net.bits < 8) return (net: null, error: 'Слишком большая сеть: можно не шире /8');
  if (!isPublicV4(net)) return (net: null, error: 'Это домашний или служебный адрес — он и так идёт мимо VPN');
  return (net: net, error: null);
}

// ---------- Список ----------

enum DirectSource { learned, user }

/// Запись списка: откуда взялась, какая программа или какой сайт туда ходили, когда в последний раз.
class DirectEntry {
  const DirectEntry({required this.source, this.app = '', this.site = '', required this.lastSeen, this.pinned = false});

  final DirectSource source;
  final String app;

  /// Сайт, за которым следим («discord.gg»); пусто — адрес не от сайта.
  final String site;
  final DateTime lastSeen;

  /// Не забывать и держать, даже если игру убрали из «мимо VPN».
  final bool pinned;

  DirectEntry copyWith({DirectSource? source, String? app, String? site, DateTime? lastSeen, bool? pinned}) =>
      DirectEntry(
        source: source ?? this.source,
        app: app ?? this.app,
        site: site ?? this.site,
        lastSeen: lastSeen ?? this.lastSeen,
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'app': app,
    if (site.isNotEmpty) 'site': site,
    'last': lastSeen.millisecondsSinceEpoch,
    if (pinned) 'pinned': true,
  };

  static DirectEntry? tryParse(Object? json, {DirectSource fallback = DirectSource.learned}) {
    if (json is! Map) return null;
    final last = json['last'];
    if (last is! int) return null;
    return DirectEntry(
      source: DirectSource.values.asNameMap()[json['source']] ?? fallback,
      app: json['app'] as String? ?? '',
      site: json['site'] as String? ?? '',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(last),
      pinned: json['pinned'] == true,
    );
  }
}

/// Что запомнить: адрес, программа, сайт (пусто — не от сайта), когда видели.
typedef DirectHit = ({String ip, String app, String site, DateTime seen});

class DirectRoutes {
  const DirectRoutes({
    this.entries = const {},
    this.never = const {},
    this.netsOff = const {},
    this.sites = const {},
    this.seeded = false,
  });

  /// Сеть → запись.
  final Map<V4Net, DirectEntry> entries;

  /// «Только через Шлюпку» (в файле и коде — never: «никогда мимо»).
  final Set<V4Net> never;

  /// Выключенные наборы сетей ([KnownNets.id]); остальные включены.
  final Set<String> netsOff;

  /// Сайты, за чьими адресами следим (в нижнем регистре).
  final Set<String> sites;

  /// Журнал ошибок уже прочитан (это делается один раз).
  final bool seeded;

  DirectRoutes copyWith({
    Map<V4Net, DirectEntry>? entries,
    Set<V4Net>? never,
    Set<String>? netsOff,
    Set<String>? sites,
    bool? seeded,
  }) => DirectRoutes(
    entries: entries ?? this.entries,
    never: never ?? this.never,
    netsOff: netsOff ?? this.netsOff,
    sites: sites ?? this.sites,
    seeded: seeded ?? this.seeded,
  );

  bool isNever(V4Net n) => never.any((x) => x.contains(n) || n.contains(x));

  /// Адрес уже действует или лежит в списке (своей записью или внутри сети из списка).
  bool covers(V4Net n) => entries.keys.any((x) => x.contains(n));

  /// Добавить или освежить запомненные адреса игр, забыть старые и лишние. Возвращает тот же объект,
  /// если ничего не поменялось по существу (время освежается не чаще раза в час).
  DirectRoutes learn(Iterable<(String ip, String app, DateTime seen)> found, DateTime now) =>
      learnHits([for (final (ip, app, seen) in found) (ip: ip, app: app, site: '', seen: seen)], now);

  /// То же для адресов сайтов, за которыми следим, и для игр: общий разбор.
  DirectRoutes learnHits(Iterable<DirectHit> found, DateTime now) {
    final next = Map.of(entries);
    var changed = false;
    for (final h in found) {
      final n = V4Net.tryParse(h.ip);
      if (n == null || n.bits != 32 || isNever(n)) continue;
      final old = next[n];
      if (old == null) {
        next[n] = DirectEntry(source: DirectSource.learned, app: h.app, site: h.site, lastSeen: h.seen);
        changed = true;
      } else if (h.seen.difference(old.lastSeen) > const Duration(hours: 1)) {
        next[n] = old.copyWith(
          lastSeen: h.seen,
          app: old.app.isEmpty ? h.app : null,
          site: old.site.isEmpty ? h.site : null,
        );
        changed = true;
      }
    }
    final before = next.length;
    next.removeWhere(
      (_, e) => e.source == DirectSource.learned && !e.pinned && now.difference(e.lastSeen) > learnedRoutesTtl,
    );
    final learned = next.entries.where((e) => e.value.source == DirectSource.learned && !e.value.pinned).toList();
    if (learned.length > learnedRoutesMax) {
      learned.sort((a, b) => b.value.lastSeen.compareTo(a.value.lastSeen));
      for (final e in learned.skip(learnedRoutesMax)) {
        next.remove(e.key);
      }
    }
    if (!changed && next.length == before && before == entries.length) return this;
    return copyWith(entries: next);
  }

  /// Пользователь добавил адрес или сеть: снимает с неё «только через Шлюпку».
  DirectRoutes withUser(V4Net n, DateTime now, {String app = ''}) => withPicks([(net: n, app: app, site: '')], now);

  /// Добавить выбранное в меню ([directCandidates]). Адреса программ и отдельные IP — свои
  /// (держатся, пока их не уберут). Адреса сайтов — запомненные с сайтом: сайт попадает в [sites],
  /// его новые адреса запоминаются на лету, старые забываются, как у игр.
  DirectRoutes withPicks(Iterable<DirectPick> picks, DateTime now) {
    final next = Map.of(entries);
    final cut = <V4Net>{};
    final watch = <String>{};
    for (final p in picks) {
      cut.add(p.net);
      if (p.site.isNotEmpty) {
        watch.add(p.site);
        final old = next[p.net];
        // Свою запись не понижаем до запомненной.
        if (old == null || old.source == DirectSource.learned) {
          next[p.net] = DirectEntry(source: DirectSource.learned, app: p.app, site: p.site, lastSeen: now);
        }
      } else {
        next[p.net] = DirectEntry(source: DirectSource.user, app: p.app, lastSeen: now, pinned: true);
      }
    }
    return copyWith(
      entries: next,
      never: never.where((x) => !cut.contains(x)).toSet(),
      sites: watch.isEmpty ? null : {...sites, ...watch},
    );
  }

  /// Следить за сайтом (без адресов: они появятся при первом соединении).
  DirectRoutes withSite(String site) => copyWith(sites: {...sites, site.toLowerCase()});

  /// Перестать следить за сайтом и убрать его запомненные адреса.
  DirectRoutes withoutSite(String site) {
    final s = site.toLowerCase();
    return copyWith(
      sites: sites.where((x) => x != s).toSet(),
      entries: Map.of(entries)..removeWhere((_, e) => e.site == s && e.source == DirectSource.learned),
    );
  }

  DirectRoutes without(V4Net n) => copyWith(entries: Map.of(entries)..remove(n));

  DirectRoutes withPinned(V4Net n, bool pinned) {
    final e = entries[n];
    if (e == null) return this;
    return copyWith(
      entries: {
        ...entries,
        n: e.copyWith(pinned: pinned),
      },
    );
  }

  /// «Убрать и больше не добавлять»: запись уходит в «только через Шлюпку».
  DirectRoutes withNever(V4Net n) => copyWith(entries: Map.of(entries)..remove(n), never: {...never, n});

  DirectRoutes withoutNever(V4Net n) => copyWith(never: never.where((x) => x != n).toSet());

  /// Из «только через Шлюпку» обратно в список: своей записью.
  DirectRoutes withNeverBack(V4Net n, DateTime now) => withoutNever(n).withUser(n, now);

  /// Запись действует: своя или закреплённая — всегда, адрес сайта — пока следим за сайтом,
  /// запомненная игра — пока игра в «мимо VPN».
  bool isActive(DirectEntry e, SplitTunnel s) =>
      e.source == DirectSource.user ||
      e.pinned ||
      (e.site.isNotEmpty && sites.contains(e.site)) ||
      isBypassApp(s, e.app);

  bool netsOn(KnownNets k) => !netsOff.contains(k.id);

  /// Набор сетей включён и его программа в «мимо VPN».
  bool netsActive(KnownNets k, SplitTunnel s) =>
      netsOn(k) && s.bypass.apps.any((a) => k.apps.contains(a.toLowerCase()));

  DirectRoutes withNets(String id, bool on) =>
      copyWith(netsOff: on ? (netsOff.where((x) => x != id).toSet()) : {...netsOff, id});

  /// Итоговый список «мимо Шлюпки» (то, что получит ядро). [enabled] false — пусто.
  List<V4Net> effective(SplitTunnel s, {required bool enabled}) {
    if (!enabled) return const [];
    final nets = <V4Net>[
      for (final k in knownNets)
        if (netsActive(k, s)) ...k.nets.map((n) => V4Net.tryParse(n)!),
      for (final e in entries.entries)
        if (isActive(e.value, s)) e.key,
    ];
    return subtractNets(nets, never);
  }

  Map<String, dynamic> toJson() => {
    'version': 3,
    'seeded': seeded,
    'netsOff': (netsOff.toList()..sort()),
    'sites': (sites.toList()..sort()),
    'entries': {for (final e in entries.entries) e.key.toString(): e.value.toJson()},
    'never': [for (final n in never) n.toString()],
  };

  /// Читает третью версию, вторую (`blizzard: bool`) и первую (game-routes.json: только `routes`).
  factory DirectRoutes.fromJson(Map<String, dynamic> json) {
    final entries = <V4Net, DirectEntry>{};
    for (final key in ['entries', 'routes']) {
      final raw = json[key];
      if (raw is! Map) continue;
      for (final e in raw.entries) {
        final n = e.key is String ? V4Net.tryParse(e.key as String) : null;
        final entry = DirectEntry.tryParse(e.value);
        if (n != null && entry != null && isPublicV4(n) && n.bits >= 8) entries[n] = entry;
      }
    }
    final never = <V4Net>{
      for (final s in (json['never'] as List<dynamic>? ?? const []).whereType<String>())
        if (V4Net.tryParse(s) case final n?) n,
    };
    final netsOff = <String>{
      ...(json['netsOff'] as List<dynamic>? ?? const []).whereType<String>(),
      if (json['blizzard'] == false) 'blizzard',
    };
    return DirectRoutes(
      entries: entries,
      never: never,
      netsOff: netsOff,
      sites: {...(json['sites'] as List<dynamic>? ?? const []).whereType<String>().map((s) => s.toLowerCase())},
      seeded: json['seeded'] == true,
    );
  }
}

/// Группа записи на вкладке: сайт, программа или «добавлено вами».
String directGroupOf(DirectEntry e) => e.site.isNotEmpty
    ? e.site
    : e.app.isNotEmpty
    ? e.app
    : '';

enum DirectGroupKind { user, site, app }

/// Группа вкладки «Мимо Шлюпки»: свои адреса без программы, сайт или программа.
class DirectGroup {
  const DirectGroup({required this.key, required this.kind, required this.entries});

  /// Сайт («discord.gg»), exe программы или пусто — «добавлено вами».
  final String key;
  final DirectGroupKind kind;

  /// Свои и закреплённые — первыми, дальше по свежести.
  final List<MapEntry<V4Net, DirectEntry>> entries;
}

/// Группы для вкладки: «добавлено вами», потом сайты (и те, за которыми следим, но адресов ещё нет),
/// потом программы — по последней игре.
List<DirectGroup> directGroups(DirectRoutes r) {
  final by = <String, List<MapEntry<V4Net, DirectEntry>>>{};
  for (final e in r.entries.entries) {
    (by[directGroupOf(e.value)] ??= []).add(e);
  }
  for (final s in r.sites) {
    by.putIfAbsent(s, () => []);
  }
  int rank(DirectEntry e) => e.source == DirectSource.user ? 0 : (e.pinned ? 1 : 2);
  DateTime last(List<MapEntry<V4Net, DirectEntry>> l) =>
      l.fold(DateTime(0), (m, e) => e.value.lastSeen.isAfter(m) ? e.value.lastSeen : m);
  final groups = [
    for (final MapEntry(:key, :value) in by.entries)
      DirectGroup(
        key: key,
        kind: key.isEmpty
            ? DirectGroupKind.user
            : (r.sites.contains(key) || value.any((e) => e.value.site == key)
                  ? DirectGroupKind.site
                  : DirectGroupKind.app),
        entries: value
          ..sort((a, b) {
            final x = rank(a.value).compareTo(rank(b.value));
            return x != 0 ? x : b.value.lastSeen.compareTo(a.value.lastSeen);
          }),
      ),
  ];
  return groups..sort((a, b) {
    final k = a.kind.index.compareTo(b.kind.index);
    if (k != 0) return k;
    return a.kind == DirectGroupKind.app ? last(b.entries).compareTo(last(a.entries)) : a.key.compareTo(b.key);
  });
}

// ---------- Отбор адресов из меню ----------

/// Что видели: соединение или ошибка. [direct] — шло напрямую (не через VPN и не заблокировано).
typedef DirectSeen = ({String ip, String app, String host, bool direct});

/// Выбранный адрес: [site] не пусто — адрес сайта, за которым будем следить.
typedef DirectPick = ({V4Net net, String app, String site});

/// Что можно добавить и почему остальное нельзя — для пункта меню и диалога.
class DirectCandidates {
  const DirectCandidates({
    this.picks = const [],
    this.viaVpn = 0,
    this.shared = 0,
    this.already = 0,
    this.never = 0,
    this.over = 0,
  });

  final List<DirectPick> picks;

  /// Адреса, к которым ходят через VPN: мимо Шлюпки они ушли бы мимо VPN у всех программ.
  final int viaVpn;

  /// Адреса, на которые ходят и другие сайты (общие сети доставки) или кто-то через VPN.
  final int shared;

  /// Уже в списке.
  final int already;

  /// В «только через Шлюпку».
  final int never;

  /// Не влезли в [directAddMax].
  final int over;

  bool get isEmpty => picks.isEmpty;
}

/// Отбор адресов для «Мимо Шлюпки» из того, что видели у выбранного ([matched]), на фоне всего, что
/// видели сейчас ([all]). Берутся только публичные IPv4, к которым шли напрямую: адрес в списке идёт
/// мимо VPN у всех программ, поэтому то, что идёт через VPN, брать нельзя. Адрес отбрасывается и
/// тогда, когда к нему же сейчас ходят через VPN или (если [sites] не пусто) ходят другие сайты:
/// это общая сеть доставки, на ней бывают и заблокированные сайты. [sites] — сайты, за чьими
/// адресами будем следить; адрес достаётся сайту, к которому шло соединение.
DirectCandidates directCandidates(
  Iterable<DirectSeen> matched,
  Iterable<DirectSeen> all,
  DirectRoutes routes, {
  Set<String> sites = const {},
}) {
  String siteOf(String host) {
    if (host.isEmpty) return '';
    for (final s in sites) {
      if (_hostUnder(host, s)) return s;
    }
    return '';
  }

  final vpnIps = {
    for (final s in all)
      if (!s.direct) s.ip,
  };
  final hostsByIp = <String, Set<String>>{};
  for (final s in all) {
    if (s.host.isNotEmpty) (hostsByIp[s.ip] ??= {}).add(s.host.toLowerCase());
  }

  final picked = <V4Net, DirectPick>{};
  final viaVpn = <String>{};
  final shared = <String>{};
  final already = <String>{};
  final never = <String>{};
  for (final s in matched) {
    if (!isPublicIPv4(s.ip)) continue;
    final n = V4Net.tryParse(s.ip)!;
    if (picked.containsKey(n)) continue;
    if (!s.direct) {
      viaVpn.add(s.ip);
      continue;
    }
    if (routes.isNever(n)) {
      never.add(s.ip);
      continue;
    }
    if (routes.covers(n)) {
      already.add(s.ip);
      continue;
    }
    final site = siteOf(s.host);
    final foreign = sites.isNotEmpty && (hostsByIp[s.ip] ?? const {}).any((h) => siteOf(h).isEmpty);
    if (vpnIps.contains(s.ip) || foreign) {
      shared.add(s.ip);
      continue;
    }
    picked[n] = (net: n, app: s.app, site: site);
  }
  // Адрес, который не вышел подходящим в одном соединении, но подошёл в другом, — не берём.
  final bad = {...viaVpn, ...shared};
  final list = [
    for (final p in picked.values)
      if (!bad.contains(p.net.ip)) p,
  ]..sort((a, b) => a.net.compareTo(b.net));
  return DirectCandidates(
    picks: list.take(directAddMax).toList(),
    viaVpn: viaVpn.length,
    shared: shared.difference(viaVpn).length,
    already: already.length,
    never: never.length,
    over: list.length > directAddMax ? list.length - directAddMax : 0,
  );
}

bool _hostUnder(String host, String site) {
  final h = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return h == site || h.endsWith('.$site');
}

DirectSeen seenOfConnection(NetConnection c) =>
    (ip: c.ip, app: c.exe, host: c.host, direct: c.chains.isNotEmpty && c.chains.first.startsWith('direct'));

DirectSeen seenOfError(ErrorEvent e) => (ip: e.ip, app: e.app, host: e.host, direct: e.route == ErrorRoute.direct);

/// Адреса сайтов, за которыми следим, из текущих соединений — для запоминания на лету.
/// Те же проверки, что в меню: только напрямую, без общих адресов.
List<DirectHit> siteHits(List<NetConnection> list, DirectRoutes routes, DateTime now) {
  if (routes.sites.isEmpty) return const [];
  final all = list.map(seenOfConnection).toList();
  final mine = [
    for (final s in all)
      if (s.host.isNotEmpty && routes.sites.any((site) => _hostUnder(s.host, site))) s,
  ];
  if (mine.isEmpty) return const [];
  // Без проверки «уже в списке»: там освежается время.
  final c = directCandidates(mine, all, routes.copyWith(entries: const {}), sites: routes.sites);
  return [for (final p in c.picks) (ip: p.net.ip, app: p.app, site: p.site, seen: now)];
}

/// Программа в «мимо VPN» (сама или в составе группы — группы пишут в тот же список).
bool isBypassApp(SplitTunnel s, String exe) => exe.isNotEmpty && s.targetOf(SplitKind.app, exe) == SplitTarget.bypass;

/// Соединение — это игра с сервером: программа из «мимо VPN», UDP напрямую, не служебный порт
/// и заметный объём (матч, а не проверка пинга).
bool isGameFlow(NetConnection c, SplitTunnel s) {
  if (c.network != 'udp' || c.viaVpn) return false;
  if (c.chains.isEmpty || !c.chains.first.startsWith('direct')) return false;
  if (nonGameUdpPorts.contains(int.tryParse(c.port))) return false;
  if (c.download < gameFlowMinDownload) return false;
  return isPublicIPv4(c.ip) && isBypassApp(s, c.exe);
}

/// То же для журнала ошибок: зависший или оборванный UDP игры напрямую — значит, шёл матч.
bool isGameError(ErrorEvent e, SplitTunnel s) {
  if (e.network != 'udp' || e.route != ErrorRoute.direct) return false;
  if (nonGameUdpPorts.contains(e.port)) return false;
  return isPublicIPv4(e.ip) && isBypassApp(s, e.app);
}

/// Текст tun-exclude.txt для ядра.
String tunExcludeText(List<V4Net> nets) {
  final out = StringBuffer('# Шлюпка: адреса мимо туннеля, файл пишет приложение (direct_routes.dart)\n');
  for (final n in nets) {
    out.writeln(n);
  }
  return out.toString();
}

/// Сколько действующих адресов программы [exe] в списке: её трафик к ним Шлюпка не видит.
int directHiddenCount(DirectRoutes r, SplitTunnel s, String exe) {
  final x = exe.toLowerCase();
  return r.entries.values.where((e) => e.app.toLowerCase() == x && r.isActive(e, s)).length;
}
