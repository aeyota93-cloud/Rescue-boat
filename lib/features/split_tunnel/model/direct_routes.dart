/// Шлюпка: «Мимо Шлюпки» — адреса, к которым Windows шлёт пакеты сама, не заходя в туннель.
///
/// Программы «мимо VPN» и так не идут в VPN, но их пакеты проходят через ядро: оно ловит весь
/// трафик и само отправляет его напрямую. Когда процессор занят игрой, ядро отвечает с опозданием,
/// и в игре это видно как потери и скачки пинга. Адреса из этого списка ядро убирает из маршрутов
/// туннеля (ядро rb.29+, tun-exclude.txt): Windows шлёт пакеты к ним сразу в сетевую карту.
///
/// Таблица маршрутов Windows знает только адрес, не программу: адрес из списка идёт мимо Шлюпки
/// у всех программ. Поэтому список узкий и под рукой у пользователя:
/// - сети Blizzard (кроме Blizzard, там никого нет), если в «мимо VPN» есть её программы;
/// - адреса, куда игры из «мимо VPN» слали заметный UDP-трафик (запоминаются на лету и один раз
///   берутся из журнала ошибок). Сайты, CDN, DNS и QUIC (TCP, UDP 443, служебные порты) не берутся;
/// - адреса и сети, которые пользователь добавил сам;
/// - минус «никогда мимо Шлюпки» — этот запрет сильнее всего остального, даже сетей Blizzard.
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

/// Запись списка: откуда взялась, какая игра туда ходила, когда в последний раз.
class DirectEntry {
  const DirectEntry({required this.source, this.app = '', required this.lastSeen, this.pinned = false});

  final DirectSource source;
  final String app;
  final DateTime lastSeen;

  /// Не забывать и держать, даже если игру убрали из «мимо VPN».
  final bool pinned;

  DirectEntry copyWith({DirectSource? source, String? app, DateTime? lastSeen, bool? pinned}) => DirectEntry(
    source: source ?? this.source,
    app: app ?? this.app,
    lastSeen: lastSeen ?? this.lastSeen,
    pinned: pinned ?? this.pinned,
  );

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'app': app,
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
      lastSeen: DateTime.fromMillisecondsSinceEpoch(last),
      pinned: json['pinned'] == true,
    );
  }
}

class DirectRoutes {
  const DirectRoutes({this.entries = const {}, this.never = const {}, this.blizzard = true, this.seeded = false});

  /// Сеть → запись.
  final Map<V4Net, DirectEntry> entries;

  /// «Никогда мимо Шлюпки».
  final Set<V4Net> never;

  /// Сети Blizzard (действуют, только если её программа в «мимо VPN»).
  final bool blizzard;

  /// Журнал ошибок уже прочитан (это делается один раз).
  final bool seeded;

  DirectRoutes copyWith({Map<V4Net, DirectEntry>? entries, Set<V4Net>? never, bool? blizzard, bool? seeded}) =>
      DirectRoutes(
        entries: entries ?? this.entries,
        never: never ?? this.never,
        blizzard: blizzard ?? this.blizzard,
        seeded: seeded ?? this.seeded,
      );

  bool isNever(V4Net n) => never.any((x) => x.contains(n) || n.contains(x));

  /// Добавить или освежить запомненные адреса, забыть старые и лишние. Возвращает тот же объект,
  /// если ничего не поменялось по существу (время освежается не чаще раза в час).
  DirectRoutes learn(Iterable<(String ip, String app, DateTime seen)> found, DateTime now) {
    final next = Map.of(entries);
    var changed = false;
    for (final (ip, app, seen) in found) {
      final n = V4Net.tryParse(ip);
      if (n == null || n.bits != 32 || isNever(n)) continue;
      final old = next[n];
      if (old == null) {
        next[n] = DirectEntry(source: DirectSource.learned, app: app, lastSeen: seen);
        changed = true;
      } else if (seen.difference(old.lastSeen) > const Duration(hours: 1)) {
        next[n] = old.copyWith(lastSeen: seen, app: old.app.isEmpty ? app : null);
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

  /// Пользователь добавил адрес или сеть: снимает с неё «никогда мимо».
  DirectRoutes withUser(V4Net n, DateTime now) => copyWith(
    entries: {
      ...entries,
      n: DirectEntry(source: DirectSource.user, lastSeen: now, pinned: true),
    },
    never: never.where((x) => x != n).toSet(),
  );

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

  /// «Никогда мимо Шлюпки»: запись уходит из списка, запомнить её снова нельзя.
  DirectRoutes withNever(V4Net n) => copyWith(entries: Map.of(entries)..remove(n), never: {...never, n});

  DirectRoutes withoutNever(V4Net n) => copyWith(never: never.where((x) => x != n).toSet());

  /// Запись действует: своя или закреплённая — всегда, запомненная — пока игра в «мимо VPN».
  bool isActive(DirectEntry e, SplitTunnel s) => e.source == DirectSource.user || e.pinned || isBypassApp(s, e.app);

  /// Сети Blizzard действуют.
  bool blizzardActive(SplitTunnel s) => blizzard && s.bypass.apps.any((a) => blizzardApps.contains(a.toLowerCase()));

  /// Итоговый список «мимо Шлюпки» (то, что получит ядро). [enabled] false — пусто.
  List<V4Net> effective(SplitTunnel s, {required bool enabled}) {
    if (!enabled) return const [];
    final nets = <V4Net>[
      if (blizzardActive(s)) ...blizzardNets.map((n) => V4Net.tryParse(n)!),
      for (final e in entries.entries)
        if (isActive(e.value, s)) e.key,
    ];
    return subtractNets(nets, never);
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'seeded': seeded,
    'blizzard': blizzard,
    'entries': {for (final e in entries.entries) e.key.toString(): e.value.toJson()},
    'never': [for (final n in never) n.toString()],
  };

  /// Читает и вторую версию, и первую (game-routes.json: только `routes`, запомненные адреса).
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
    return DirectRoutes(
      entries: entries,
      never: never,
      blizzard: json['blizzard'] as bool? ?? true,
      seeded: json['seeded'] == true,
    );
  }
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
