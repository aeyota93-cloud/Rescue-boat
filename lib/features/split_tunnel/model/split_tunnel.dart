/// Шлюпка: раздельный туннель — два списка, «через VPN» и «мимо VPN», плюс пункты, закреплённые
/// за конкретным сервером подписки (docs/redesign/servers-v2.md), и группы записей
/// (docs/redesign/groups.md) — только для удобства в приложении, ядро их не видит.
///
/// Списки хранятся в split-tunnel.json рядом с настройками и выгружаются в наборы правил
/// sing-box (папка split/), за которыми следит ядро (Rescue-boat-core, split_tunnel.go):
/// изменение действует сразу, без переподключения. Списки важнее всех остальных правил.
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

/// Одна запись списка: что это и как хранится.
typedef SplitRef = ({SplitKind kind, String value});

class SplitList {
  const SplitList({this.apps = const [], this.domains = const [], this.ips = const []});

  final List<String> apps;
  final List<String> domains;
  final List<String> ips;

  bool get isEmpty => apps.isEmpty && domains.isEmpty && ips.isEmpty;

  /// Все записи: программы, сайты, сети.
  List<SplitRef> get items => [
    for (final kind in SplitKind.values)
      for (final value in of(kind)) (kind: kind, value: value),
  ];

  int get length => apps.length + domains.length + ips.length;

  /// Все записи [others] вместе с этими, без повторов (порядок — как встретились).
  SplitList union(Iterable<SplitList> others) {
    var out = this;
    for (final o in others) {
      for (final kind in SplitKind.values) {
        for (final v in o.of(kind)) {
          out = out.withItem(kind, v);
        }
      }
    }
    return out;
  }

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

/// Группа записей с именем («Игры», «Работа и дом»). Путь у каждой записи свой, группа только
/// собирает их в одну строку и меняет путь всем сразу.
class SplitGroup {
  const SplitGroup({required this.name, this.items = const SplitList()});

  final String name;
  final SplitList items;

  Map<String, dynamic> toJson() => {'name': name, ...items.toJson()};

  factory SplitGroup.fromJson(Map<String, dynamic> json) =>
      SplitGroup(name: json['name'] as String? ?? '', items: SplitList.fromJson(json));
}

class SplitTunnel {
  const SplitTunnel({
    this.bypass = const SplitList(),
    this.via = const SplitList(),
    this.servers = const {},
    this.groups = const [],
  });

  final SplitList bypass;

  /// «Через VPN (Авто)»: через выбранный сервер, при сбое — запасные.
  final SplitList via;

  /// Закреплённые за сервером: тег выхода → пункты. Пустых списков здесь не держим.
  final Map<String, SplitList> servers;

  /// Группы по порядку. Запись — не больше чем в одной; пустых групп не держим.
  final List<SplitGroup> groups;

  SplitList list(SplitTarget target) => target == SplitTarget.bypass ? bypass : via;

  /// Куда идёт запись: «через VPN» — и «Авто», и за сервером. Порядок как в ядре: сервер, «Авто», «мимо».
  SplitTarget? targetOf(SplitKind kind, String value) {
    if (serverOf(kind, value) != null) return SplitTarget.via;
    if (via.contains(kind, value)) return SplitTarget.via;
    if (bypass.contains(kind, value)) return SplitTarget.bypass;
    return null;
  }

  /// Тег сервера, за которым закреплена запись; null — не закреплена.
  String? serverOf(SplitKind kind, String value) {
    for (final MapEntry(key: tag, value: list) in servers.entries) {
      if (list.contains(kind, value)) return tag;
    }
    return null;
  }

  /// Всё, что идёт через VPN: «Авто» и все серверные пункты (содержимое via-vpn.json). Если сервер
  /// пропал из подписки, ядро не знает его набора, и его пункты честно идут через «Авто».
  SplitList get viaAll => via.union(servers.values);

  SplitTunnel withList(SplitTarget target, SplitList list) => target == SplitTarget.bypass
      ? SplitTunnel(bypass: list, via: via, servers: servers, groups: groups)
      : SplitTunnel(bypass: bypass, via: list, servers: servers, groups: groups);

  SplitTunnel withServer(String tag, SplitList list) =>
      SplitTunnel(bypass: bypass, via: via, servers: _clean({...servers, tag: list}), groups: groups);

  SplitTunnel withGroups(List<SplitGroup> list) => SplitTunnel(
    bypass: bypass,
    via: via,
    servers: servers,
    groups: List.unmodifiable(list.where((g) => !g.items.isEmpty)),
  );

  /// Убрать запись отовсюду: из обоих списков и со всех серверов. Из группы она не уходит:
  /// в группе остаётся с «Авто».
  SplitTunnel without(SplitKind kind, String value) => SplitTunnel(
    bypass: bypass.without(kind, value),
    via: via.without(kind, value),
    servers: _clean({for (final e in servers.entries) e.key: e.value.without(kind, value)}),
    groups: groups,
  );

  /// Имя группы записи; null — без группы.
  String? groupOf(SplitKind kind, String value) {
    for (final g in groups) {
      if (g.items.contains(kind, value)) return g.name;
    }
    return null;
  }

  /// Группа с этим именем (без учёта регистра); null — нет такой.
  SplitGroup? group(String name) {
    for (final g in groups) {
      if (sameGroupName(g.name, name)) return g;
    }
    return null;
  }

  /// Записи [items] — в группу [name] (нет такой — создаётся в конце). Из других групп уходят.
  SplitTunnel inGroup(String name, Iterable<SplitRef> items) {
    final out = outOfGroups(items);
    final existing = out.group(name);
    var list = existing?.items ?? const SplitList();
    for (final i in items) {
      list = list.withItem(i.kind, i.value);
    }
    final updated = SplitGroup(name: existing?.name ?? name.trim(), items: list);
    return out.withGroups([
      for (final g in out.groups) identical(g, existing) ? updated : g,
      if (existing == null) updated,
    ]);
  }

  /// Записи [items] — из всех групп (пути не меняются).
  SplitTunnel outOfGroups(Iterable<SplitRef> items) => withGroups([
    for (final g in groups) SplitGroup(name: g.name, items: items.fold(g.items, (l, i) => l.without(i.kind, i.value))),
  ]);

  /// Переименовать группу. Если имя занято другой группой — записи сливаются в неё.
  SplitTunnel renameGroup(String from, String to) {
    final g = group(from);
    final name = to.trim();
    if (g == null || name.isEmpty) return this;
    final other = group(name);
    if (other != null && !identical(other, g)) return withoutGroup(from).inGroup(other.name, g.items.items);
    return withGroups([for (final x in groups) identical(x, g) ? SplitGroup(name: name, items: g.items) : x]);
  }

  /// Удалить группу; записи остаются в списках, где были.
  SplitTunnel withoutGroup(String name) => withGroups([
    for (final g in groups)
      if (!sameGroupName(g.name, name)) g,
  ]);

  /// Разложить записи по стандартным группам ([suggestedGroups]): только те, что есть в списках
  /// и ещё не в группе. Для старых файлов без групп и для первого запуска.
  SplitTunnel withSuggestedGroups() {
    var out = this;
    for (final MapEntry(key: name, value: catalog) in suggestedGroups.entries) {
      final items = [
        for (final i in catalog.items)
          if (out.targetOf(i.kind, i.value) != null && out.groupOf(i.kind, i.value) == null)
            (kind: i.kind, value: _stored(i.kind, i.value)),
      ];
      if (items.isNotEmpty) out = out.inGroup(name, items);
    }
    return out;
  }

  /// Как запись записана в списках (регистр имени программы может отличаться от каталога).
  String _stored(SplitKind kind, String value) {
    for (final l in [via, bypass, ...servers.values]) {
      for (final v in l.of(kind)) {
        if (sameItem(kind, v, value)) return v;
      }
    }
    return value;
  }

  /// Поставить запись в одно место: [target] или, если задан [server], за этим сервером
  /// (тогда [target] — «через VPN»). Из остальных мест запись убирается.
  SplitTunnel placed(SplitKind kind, String value, SplitTarget target, {String? server}) {
    final rest = without(kind, value);
    if (server != null) {
      return rest.withServer(server, (rest.servers[server] ?? const SplitList()).withItem(kind, value));
    }
    return rest.withList(target, rest.list(target).withItem(kind, value));
  }

  Map<String, dynamic> toJson() => {
    'bypass': bypass.toJson(),
    'via': via.toJson(),
    'servers': {for (final e in servers.entries) e.key: e.value.toJson()},
    'groups': [for (final g in groups) g.toJson()],
  };

  /// Старый файл без `servers` читается: серверных пунктов просто нет. Без `groups` — записи
  /// раскладываются по стандартным группам (см. [withSuggestedGroups]).
  factory SplitTunnel.fromJson(Map<String, dynamic> json) {
    final raw = json['servers'];
    final rawGroups = json['groups'];
    final lists = SplitTunnel(
      bypass: SplitList.fromJson(json['bypass'] as Map<String, dynamic>? ?? const {}),
      via: SplitList.fromJson(json['via'] as Map<String, dynamic>? ?? const {}),
      servers: raw is Map<String, dynamic>
          ? _clean({
              for (final e in raw.entries)
                if (e.value is Map<String, dynamic>) e.key: SplitList.fromJson(e.value as Map<String, dynamic>),
            })
          : const {},
    );
    if (rawGroups is! List<dynamic>) return lists.withSuggestedGroups();
    return lists.withGroups([
      for (final g in rawGroups)
        if (g is Map<String, dynamic>) SplitGroup.fromJson(g),
    ]);
  }

  static Map<String, SplitList> _clean(Map<String, SplitList> map) => Map.unmodifiable({
    for (final e in map.entries)
      if (!e.value.isEmpty) e.key: e.value,
  });

  /// Первый запуск: игры и лаунчеры мимо VPN (ниже пинг, загрузки не идут через сервер),
  /// разложены по стандартным группам.
  static SplitTunnel get defaults =>
      const SplitTunnel(bypass: SplitList(apps: defaultBypassApps)).withSuggestedGroups();
}

/// Имена групп сравниваем без учёта регистра и пробелов по краям.
bool sameGroupName(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

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
  // «www.» — не отдельный сайт: без него правило накроет и соседние поддомены
  // (www.dns-shop.ru грузит данные с restapi.dns-shop.ru).
  final noWww = host.replaceFirst(RegExp(r'^www\d*\.'), '');
  if (noWww.contains('.')) host = noWww;
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

/// Стандартные группы: имя → что в неё попадает, если запись есть в списках. Порядок — порядок
/// групп на экране. Все игры и лаунчеры из [defaultBypassApps] здесь разложены.
const suggestedGroups = <String, SplitList>{
  'Игры': SplitList(
    apps: [
      'cs2.exe',
      'dota2.exe',
      'destiny2.exe',
      'EscapeFromTarkov.exe',
      'FortniteClient-Win64-Shipping.exe',
      'GTA5.exe',
      'Minecraft.Windows.exe',
      'Overwatch.exe',
      'r5apex.exe',
      'RainbowSix.exe',
      'RustClient.exe',
      'TslGame.exe',
      'VALORANT-Win64-Shipping.exe',
      'WorldOfTanks.exe',
      'WorldOfWarships.exe',
    ],
  ),
  'Marvel Rivals': SplitList(apps: ['Marvel-Win64-Shipping.exe', 'Marvel.exe'], domains: ['gaming-sdk.com']),
  'Античиты': SplitList(apps: ['BEService.exe', 'EasyAntiCheat.exe', 'EasyAntiCheat_EOS.exe', 'vgc.exe']),
  'Лаунчеры и магазины': SplitList(
    apps: [
      'steam.exe',
      'steamservice.exe',
      'steamwebhelper.exe',
      'EpicGamesLauncher.exe',
      'EpicWebHelper.exe',
      'EADesktop.exe',
      'EABackgroundService.exe',
      'Battle.net.exe',
      'GalaxyClient.exe',
      'UbisoftConnect.exe',
      'upc.exe',
      'wgc.exe',
      'lgc.exe',
    ],
    domains: ['store.steampowered.com', 'api.steampowered.com', 'steamcommunity.com'],
  ),
  'League of Legends и Riot': SplitList(
    apps: [
      'League of Legends.exe',
      'LeagueClient.exe',
      'LeagueClientUx.exe',
      'LeagueClientUxRender.exe',
      'Riot Client.exe',
      'RiotClientServices.exe',
      'RiotClientUx.exe',
      'RiotClientCrashHandler.exe',
    ],
  ),
  'Общение': SplitList(apps: ['Discord.exe', 'Telegram.exe'], domains: ['discord.com', 'discord.gg']),
  'Служебное для игр': SplitList(
    apps: [
      'gamingservices.exe',
      'GamingServicesNet.exe',
      'GameInputRedistService.exe',
      'gameoverlayui64.exe',
      'NVIDIA Overlay.exe',
    ],
  ),
};

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
  'Marvel-Win64-Shipping.exe',
  'Marvel.exe',
];
