/// Шлюпка: игровые серверы мимо туннеля.
///
/// Программы «мимо VPN» и так не идут в VPN, но их пакеты проходят через ядро: оно ловит весь
/// трафик и само отправляет его напрямую. Когда процессор занят игрой, ядро отвечает с опозданием,
/// и в игре это видно как потери и скачки пинга. Адреса игровых серверов можно убрать из маршрутов
/// туннеля (ядро rb.29+, tun-exclude.txt): тогда Windows шлёт пакеты к ним сразу в сетевую карту.
///
/// Таблица маршрутов знает только адрес, не программу, поэтому список узкий:
/// - сети Blizzard целиком (кроме Blizzard, там никого нет), если в «мимо VPN» есть её программы;
/// - адреса, куда игры из «мимо VPN» сами слали заметный UDP-трафик (запоминаются на лету и один
///   раз берутся из журнала ошибок). Сайты, CDN, DNS и QUIC (TCP, UDP 443 и служебные порты) сюда
///   не попадают: через те же адреса работают чужие сайты, а на задержку в матче они не влияют.
/// Ядро читает список при подключении, новые адреса действуют со следующего.
library;

import 'dart:io';

import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

/// Файл для ядра в папке раздельного туннеля (Rescue-boat-core, tun_exclude.go).
const tunExcludeFileName = 'tun-exclude.txt';

/// Запомненные адреса (рядом, в той же папке).
const gameRoutesFileName = 'game-routes.json';

/// Сколько адресов помнить: каждый дробит маршрут туннеля примерно на 30 маршрутов Windows.
const gameRoutesMax = 256;

/// Адрес, где давно не играли, забывается.
const gameRoutesTtl = Duration(days: 30);

/// Меньше этого за соединение — проверка пинга до серверов разных стран, а не матч.
const gameFlowMinDownload = 64 * 1024;

/// UDP-порты, которые не игра: DNS, время, QUIC (браузеры, сайты), STUN, поиск в домашней сети.
const nonGameUdpPorts = {53, 67, 68, 123, 137, 138, 443, 853, 1900, 3478, 3479, 5353, 5355};

/// Программы Blizzard: если хоть одна в «мимо VPN», её сети идут мимо туннеля целиком.
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

/// Один запомненный адрес: какая игра туда ходила и когда в последний раз.
class GameRoute {
  const GameRoute({required this.app, required this.lastSeen});

  final String app;
  final DateTime lastSeen;

  Map<String, dynamic> toJson() => {'app': app, 'last': lastSeen.millisecondsSinceEpoch};

  static GameRoute? tryParse(Object? json) {
    if (json is! Map) return null;
    final last = json['last'];
    if (last is! int) return null;
    return GameRoute(app: json['app'] as String? ?? '', lastSeen: DateTime.fromMillisecondsSinceEpoch(last));
  }
}

class GameRoutes {
  const GameRoutes({this.routes = const {}, this.seeded = false});

  /// Адрес IPv4 → запись.
  final Map<String, GameRoute> routes;

  /// Журнал ошибок уже прочитан (это делается один раз).
  final bool seeded;

  GameRoutes copyWith({Map<String, GameRoute>? routes, bool? seeded}) =>
      GameRoutes(routes: routes ?? this.routes, seeded: seeded ?? this.seeded);

  /// Добавить или освежить адреса, убрать старые и лишние. Возвращает тот же объект, если ничего
  /// не поменялось по существу (время освежается не чаще раза в час, чтобы не писать файл зря).
  GameRoutes learn(Iterable<(String ip, String app, DateTime seen)> found, DateTime now) {
    final next = Map.of(routes);
    var changed = false;
    for (final (ip, app, seen) in found) {
      final old = next[ip];
      if (old == null || seen.difference(old.lastSeen) > const Duration(hours: 1)) {
        next[ip] = GameRoute(app: app, lastSeen: seen);
        changed = true;
      }
    }
    final before = next.length;
    next.removeWhere((_, r) => now.difference(r.lastSeen) > gameRoutesTtl);
    if (next.length > gameRoutesMax) {
      final keep = (next.entries.toList()..sort((a, b) => b.value.lastSeen.compareTo(a.value.lastSeen))).take(
        gameRoutesMax,
      );
      next
        ..clear()
        ..addEntries(keep);
    }
    if (!changed && next.length == before && before == routes.length) return this;
    return copyWith(routes: next);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'seeded': seeded,
    'routes': {for (final e in routes.entries) e.key: e.value.toJson()},
  };

  factory GameRoutes.fromJson(Map<String, dynamic> json) {
    final raw = json['routes'];
    final routes = <String, GameRoute>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final r = GameRoute.tryParse(e.value);
        if (r != null && e.key is String && isPublicIPv4(e.key as String)) routes[e.key as String] = r;
      }
    }
    return GameRoutes(routes: routes, seeded: json['seeded'] == true);
  }
}

/// Обычный адрес в интернете (не локальный, не служебный).
bool isPublicIPv4(String ip) {
  final a = InternetAddress.tryParse(ip);
  if (a == null || a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  if (b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224) return false;
  if (b[0] == 100 && b[1] >= 64 && b[1] < 128) return false; // CGNAT провайдера
  if (b[0] == 169 && b[1] == 254) return false;
  if (b[0] == 172 && b[1] >= 16 && b[1] < 32) return false;
  if (b[0] == 192 && b[1] == 168) return false;
  return true;
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

/// Текст tun-exclude.txt. [enabled] false — пустой файл (ядро ничего не убирает из туннеля).
String tunExcludeText(GameRoutes routes, SplitTunnel s, {required bool enabled}) {
  final out = StringBuffer('# Шлюпка: адреса мимо туннеля, файл пишет приложение (game_routes.dart)\n');
  if (!enabled) return out.toString();
  if (s.bypass.apps.any((a) => blizzardApps.contains(a.toLowerCase()))) {
    out.writeln('# Blizzard');
    blizzardNets.forEach(out.writeln);
  }
  final learned = routes.routes.entries.where((e) => isBypassApp(s, e.value.app)).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if (learned.isNotEmpty) out.writeln('# игровые серверы');
  for (final e in learned) {
    out.writeln('${e.key} # ${e.value.app}');
  }
  return out.toString();
}
