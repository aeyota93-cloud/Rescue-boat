/// Шлюпка: раздельный туннель — два списка, «через VPN» и «мимо VPN».
///
/// Списки хранятся в split-tunnel.json рядом с настройками и выгружаются в наборы правил
/// sing-box (папка split/), за которыми следит ядро (Rescue-boat-core, split_tunnel.go):
/// изменение действует сразу, без переподключения. Оба списка важнее всех остальных правил.
library;

enum SplitTarget {
  bypass('Мимо VPN'),
  via('Через VPN');

  const SplitTarget(this.title);
  final String title;

  SplitTarget get other => this == bypass ? via : bypass;
}

enum SplitKind {
  app('Программы'),
  domain('Сайты'),
  ip('IP и сети');

  const SplitKind(this.title);
  final String title;
}

class SplitList {
  const SplitList({this.apps = const [], this.domains = const [], this.ips = const []});

  final List<String> apps;
  final List<String> domains;
  final List<String> ips;

  bool get isEmpty => apps.isEmpty && domains.isEmpty && ips.isEmpty;

  List<String> of(SplitKind kind) => switch (kind) {
    SplitKind.app => apps,
    SplitKind.domain => domains,
    SplitKind.ip => ips,
  };

  bool contains(SplitKind kind, String value) => of(kind).any((e) => sameItem(kind, e, value));

  SplitList withItem(SplitKind kind, String value) {
    if (contains(kind, value)) return this;
    return _with(kind, [...of(kind), value]);
  }

  SplitList without(SplitKind kind, String value) =>
      _with(kind, of(kind).where((e) => !sameItem(kind, e, value)).toList());

  SplitList _with(SplitKind kind, List<String> items) => SplitList(
    apps: kind == SplitKind.app ? items : apps,
    domains: kind == SplitKind.domain ? items : domains,
    ips: kind == SplitKind.ip ? items : ips,
  );

  Map<String, dynamic> toJson() => {'apps': apps, 'domains': domains, 'ips': ips};

  factory SplitList.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) => (json[key] as List<dynamic>? ?? const []).cast<String>().toList();
    return SplitList(apps: list('apps'), domains: list('domains'), ips: list('ips'));
  }

  /// Набор правил sing-box (формат source, версия 3). Внутри одного правила условия разных
  /// видов складываются через «И», поэтому программы, сайты и сети — отдельные правила.
  Map<String, dynamic> toRuleSet() => {
    'version': 3,
    'rules': [
      if (apps.isNotEmpty) {'process_path_regex': apps.map(processPathRegex).toList()},
      if (domains.isNotEmpty) {'domain_suffix': domains},
      if (ips.isNotEmpty) {'ip_cidr': ips},
    ],
  };

  /// Только сайты: их DNS-запросы тоже идут мимо VPN.
  Map<String, dynamic> toDomainsRuleSet() => {
    'version': 3,
    'rules': [
      if (domains.isNotEmpty) {'domain_suffix': domains},
    ],
  };
}

class SplitTunnel {
  const SplitTunnel({this.bypass = const SplitList(), this.via = const SplitList()});

  final SplitList bypass;
  final SplitList via;

  SplitList list(SplitTarget target) => target == SplitTarget.bypass ? bypass : via;

  SplitTarget? targetOf(SplitKind kind, String value) {
    if (via.contains(kind, value)) return SplitTarget.via;
    if (bypass.contains(kind, value)) return SplitTarget.bypass;
    return null;
  }

  SplitTunnel withList(SplitTarget target, SplitList list) =>
      target == SplitTarget.bypass ? SplitTunnel(bypass: list, via: via) : SplitTunnel(bypass: bypass, via: list);

  Map<String, dynamic> toJson() => {'bypass': bypass.toJson(), 'via': via.toJson()};

  factory SplitTunnel.fromJson(Map<String, dynamic> json) => SplitTunnel(
    bypass: SplitList.fromJson(json['bypass'] as Map<String, dynamic>? ?? const {}),
    via: SplitList.fromJson(json['via'] as Map<String, dynamic>? ?? const {}),
  );

  /// Первый запуск: игры и лаунчеры мимо VPN (ниже пинг, загрузки не идут через сервер).
  static SplitTunnel get defaults => const SplitTunnel(bypass: SplitList(apps: defaultBypassApps));
}

/// Совпадает с processMatchers в ядре: имя без учёта регистра, после «\» или «/» или с начала.
String processPathRegex(String name) => r'(?i)(^|[\\/])' + RegExp.escape(name) + r'$';

bool sameItem(SplitKind kind, String a, String b) =>
    kind == SplitKind.ip ? a == b : a.toLowerCase() == b.toLowerCase();

/// Разбор строки, которую вставил пользователь: что это и в каком виде хранить.
/// Возвращает null, если строку не удалось понять.
({SplitKind kind, String value})? parseSplitItem(String raw) {
  var s = raw.trim();
  if (s.isEmpty || s.startsWith('#') || s.startsWith('//')) return null;
  s = s.replaceAll('"', '').replaceAll("'", '');

  // Программа: путь к .exe или имя файла.
  if (s.toLowerCase().endsWith('.exe')) {
    final name = s.split(RegExp(r'[\\/]')).last.trim();
    return name.isEmpty ? null : (kind: SplitKind.app, value: name);
  }

  // IPv4 или сеть IPv4.
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:/(\d{1,2}))?$').firstMatch(s);
  if (v4 != null) {
    final octets = [1, 2, 3, 4].map((i) => int.parse(v4.group(i)!));
    final mask = v4.group(5) == null ? 32 : int.parse(v4.group(5)!);
    if (octets.any((o) => o > 255) || mask > 32) return null;
    return (kind: SplitKind.ip, value: '${octets.join('.')}/$mask');
  }

  // IPv6 или сеть IPv6 (грубо: шестнадцатеричные группы через двоеточие).
  final v6 = RegExp(r'^([0-9a-fA-F:]+:[0-9a-fA-F:]*)(?:/(\d{1,3}))?$').firstMatch(s);
  if (v6 != null && v6.group(1)!.contains(':')) {
    final mask = v6.group(2) == null ? 128 : int.parse(v6.group(2)!);
    if (mask > 128) return null;
    return (kind: SplitKind.ip, value: '${v6.group(1)!.toLowerCase()}/$mask');
  }

  // Сайт: ссылка, «*.example.com», «.example.com» или просто домен. Хост берём вручную:
  // Uri кодирует кириллицу процентами, а ядру нужен punycode (госуслуги.рф → xn--…).
  var host = s.toLowerCase();
  host = host.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
  host = host.split(RegExp(r'[/?#]')).first;
  host = host.replaceFirst(RegExp(r'^[^@]*@'), '').replaceFirst(RegExp(r':\d+$'), '');
  host = host.replaceFirst(RegExp(r'^\*?\.'), '');
  final labels = host.split('.');
  if (labels.length < 2 || labels.any((l) => l.isEmpty)) return null;
  final ascii = <String>[];
  for (final label in labels) {
    if (RegExp(r'^[a-z0-9-]+$').hasMatch(label)) {
      ascii.add(label);
    } else if (RegExp('^[a-z0-9À-￿-]+\$').hasMatch(label)) {
      ascii.add('xn--${punycodeEncode(label)}');
    } else {
      return null;
    }
  }
  return (kind: SplitKind.domain, value: ascii.join('.'));
}

/// Punycode (RFC 3492) для одной части домена, без префикса «xn--».
String punycodeEncode(String input) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  final codes = input.runes.toList();
  final output = StringBuffer()..writeAll(codes.where((c) => c < 0x80).map(String.fromCharCode));
  final basic = output.length;
  var handled = basic;
  if (basic > 0) output.write('-');

  String digit(int d) => String.fromCharCode(d < 26 ? 97 + d : 22 + d);
  int adapt(int value, int points, bool first) {
    var d = first ? value ~/ damp : value ~/ 2;
    d += d ~/ points;
    var k = 0;
    while (d > ((base - tMin) * tMax) ~/ 2) {
      d ~/= base - tMin;
      k += base;
    }
    return k + (base - tMin + 1) * d ~/ (d + skew);
  }

  var n = 128, delta = 0, bias = 72;
  while (handled < codes.length) {
    final m = codes.where((c) => c >= n).reduce((a, b) => a < b ? a : b);
    delta += (m - n) * (handled + 1);
    n = m;
    for (final c in codes) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = base; ; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          output.write(digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        output.write(digit(q));
        bias = adapt(delta, handled + 1, handled == basic);
        delta = 0;
        handled++;
      }
    }
    delta++;
    n++;
  }
  return output.toString();
}

/// Лаунчеры, античиты и популярные сетевые игры (имена как в Диспетчере задач → «Подробности»).
const defaultBypassApps = [
  // Лаунчеры
  'steam.exe',
  'steamwebhelper.exe',
  'steamservice.exe',
  'EpicGamesLauncher.exe',
  'EpicWebHelper.exe',
  'Battle.net.exe',
  'EADesktop.exe',
  'EABackgroundService.exe',
  'upc.exe',
  'UbisoftConnect.exe',
  'RiotClientServices.exe',
  'RiotClientUx.exe',
  'GalaxyClient.exe',
  'wgc.exe',
  'lgc.exe',
  // Античиты (держат соединение с серверами игр)
  'EasyAntiCheat.exe',
  'EasyAntiCheat_EOS.exe',
  'BEService.exe',
  'vgc.exe',
  // Игры
  'cs2.exe',
  'dota2.exe',
  'VALORANT-Win64-Shipping.exe',
  'League of Legends.exe',
  'FortniteClient-Win64-Shipping.exe',
  'r5apex.exe',
  'TslGame.exe',
  'Overwatch.exe',
  'RustClient.exe',
  'destiny2.exe',
  'GTA5.exe',
  'RainbowSix.exe',
  'WorldOfTanks.exe',
  'WorldOfWarships.exe',
  'EscapeFromTarkov.exe',
  'Minecraft.Windows.exe',
];
