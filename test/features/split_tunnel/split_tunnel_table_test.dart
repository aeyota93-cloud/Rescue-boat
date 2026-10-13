import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/notifier/compare_notifier.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/data/running_apps.dart';
import 'package:hiddify/features/split_tunnel/model/app_names.dart';
import 'package:hiddify/features/split_tunnel/model/live_view.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/split_tunnel_table_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../compare/fake_core.dart';
import '../screens_test_helpers.dart';
import '../servers/servers_fixtures.dart';
import '../shell_frame_helper.dart';

const nl = ['NL', 'select'];
const games = ['NL игры', 'select'];
const direct = ['direct'];

NetConnection conn(
  String exe, {
  String host = '',
  String ip = '1.2.3.4',
  List<String> chains = nl,
  int bytes = 0,
  bool closed = false,
}) => NetConnection(
  id: '$exe$host$ip',
  exe: exe,
  host: host,
  ip: ip,
  port: '443',
  network: 'tcp',
  viaVpn: chains.first != 'direct',
  upload: 0,
  download: bytes,
  chains: chains,
  closed: closed,
);

ErrorEvent event({String app = '', String host = '', String ip = '', int n = 1}) => ErrorEvent(
  time: DateTime(2026, 10, 10, 12),
  kind: ErrorKind.reset,
  app: app,
  host: host,
  ip: ip,
  port: 443,
  network: 'tcp',
  count: n,
);

ErrorGroup errGroup(String key, List<ErrorEvent> events) => ErrorGroup(
  key: key,
  target: key,
  app: '',
  route: ErrorRoute.vpn,
  count: events.fold(0, (s, e) => s + e.count),
  last: DateTime(2026, 10, 10, 12),
  events: events,
);

void main() {
  late Directory dir;
  final three = rescueServersOf(threeServers(), threeServersOrder)!;

  setUp(() => dir = Directory.systemTemp.createTempSync('split_table_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void writeState(SplitTunnel state) =>
      File('${dir.path}/split-tunnel.json').writeAsStringSync(jsonEncode(state.toJson()));

  final errors = [
    errGroup('rr1.kinopoisk.ru', [event(host: 'rr1.kinopoisk.ru', app: 'msedge.exe', n: 5)]),
    errGroup('notkinopoisk.ru', [event(host: 'notkinopoisk.ru', n: 7)]),
    errGroup('app:discord.exe', [event(app: 'Discord.exe', n: 2)]),
  ];

  Future<ProviderContainer> start(
    WidgetTester tester, {
    List<NetConnection>? connections,
    List<ErrorGroup> groups = const [],
    RescueServers? servers,
    List<RunningApp> running = const [],
    List<Override> extra = const [],
  }) async {
    final container = await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          liveConnectionsProvider.overrideWith((ref) => Stream.value(connections)),
          errorGroupsProvider.overrideWith((ref, period) => AsyncData(groups)),
          runningAppsProvider.overrideWith((ref) async => running),
          rescueServersProvider.overrideWith((ref) => servers ?? three),
          ...extra,
        ],
      ),
    );
    return container!;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text).last);

  /// Пункт открытого меню (тот же текст бывает и на кнопках страницы).
  Future<void> tapMenu(WidgetTester tester, String text) => tap(tester, find.widgetWithText(MenuItemButton, text).last);

  Future<void> openTab(WidgetTester tester, int i) => tap(tester, find.byKey(ValueKey('folder-tab-$i')));

  Future<void> nameGroup(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const ValueKey('group-name')), name);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
  }

  group('строки и модель', () {
    test('ошибки сайта считаются вместе с поддоменами, но не с похожими доменами', () {
      expect(hostMatches('rr1.kinopoisk.ru', 'kinopoisk.ru'), isTrue);
      expect(hostMatches('KINOPOISK.RU', 'kinopoisk.ru'), isTrue);
      expect(hostMatches('notkinopoisk.ru', 'kinopoisk.ru'), isFalse);
      expect(errorsFor(SplitKind.domain, 'kinopoisk.ru', errors), 5);
      expect(errorsFor(SplitKind.app, 'discord.exe', errors), 2);
    });

    test('сети: адрес внутри, домашняя сеть', () {
      expect(ipInCidr('192.168.1.10', '192.168.0.0/16'), isTrue);
      expect(ipInCidr('192.169.1.10', '192.168.0.0/16'), isFalse);
      expect(isHomeNetwork('192.168.0.0/16'), isTrue);
      expect(isHomeNetwork('8.8.8.8/32'), isFalse);
    });

    test('«1 соединение», «3 соединения», «14 соединений»', () {
      String f(int n) => pluralRu(n, 'соединение', 'соединения', 'соединений');
      expect(
        [f(1), f(3), f(14), f(21), f(112)],
        ['соединение', 'соединения', 'соединений', 'соединение', 'соединений'],
      );
    });

    test('какое правило сработало — порядок как в ядре: серверы, «через VPN», «мимо»', () {
      const split = SplitTunnel(
        via: SplitList(apps: ['steam.exe']),
        bypass: SplitList(domains: ['api.steampowered.com']),
        servers: {
          'NL игры': SplitList(domains: ['store.steampowered.com']),
        },
        groups: [
          SplitGroup(
            name: 'Лаунчеры',
            items: SplitList(apps: ['steam.exe']),
          ),
        ],
      );
      // Программа «через VPN» важнее сайта «мимо».
      final api = ruleFor(split, conn('steam.exe', host: 'api.steampowered.com'), severalServers: true)!;
      expect(api.item, (kind: SplitKind.app, value: 'steam.exe'));
      expect(api.target, SplitTarget.via);
      expect(api.group, 'Лаунчеры');
      // Сайт за сервером важнее всего.
      final store = ruleFor(split, conn('steam.exe', host: 'store.steampowered.com'), severalServers: true)!;
      expect(store.server, 'NL игры');
      // Один сервер: его записи ядро держит в общем «через VPN» — первой сработает программа.
      expect(
        ruleFor(split, conn('steam.exe', host: 'store.steampowered.com'), severalServers: false)!.item.kind,
        SplitKind.app,
      );
      // Сайт «мимо» у другой программы.
      expect(
        ruleFor(split, conn('chrome.exe', host: 'x.api.steampowered.com'), severalServers: true)!.target,
        SplitTarget.bypass,
      );
      expect(ruleFor(split, conn('chrome.exe', host: 'ya.ru'), severalServers: true), isNull);
    });

    test('программы в сети: порядок, куда ушли, фильтры, поиск, закрытые', () {
      const split = SplitTunnel(
        servers: {
          'NL игры': SplitList(apps: ['Discord.exe']),
        },
        groups: [
          SplitGroup(
            name: 'Общение',
            items: SplitList(apps: ['Discord.exe']),
          ),
        ],
      );
      final all = [
        conn('chrome.exe', host: 'youtube.com', bytes: 5 << 20),
        conn('chrome.exe', host: 'ya.ru', chains: direct, bytes: 1024),
        conn('Discord.exe', host: 'discord.com', chains: games),
        conn('Discord.exe', host: 'cdn.discordapp.com', chains: games),
        conn('Discord.exe', host: 'old.discord.com', chains: games, closed: true),
        conn('', host: 'settings-win.data.microsoft.com'),
      ];
      // Открытых поровну (закрытое у Discord не считается) — первым тот, у кого больше трафика.
      final apps = buildLiveApps(split, all, three);
      expect([for (final a in apps) a.exe], ['chrome.exe', 'Discord.exe', '']);
      expect(apps[1].open, 2);
      expect(apps[1].group, 'Общение');
      expect([for (final d in apps.first.dests) destLabel(d)], ['Основной', 'Мимо VPN']);
      expect(apps.first.conns.first.auto, isTrue);

      expect([for (final a in buildLiveApps(split, all, three, filter: LiveFilter.direct)) a.exe], ['chrome.exe']);
      expect(buildLiveApps(split, all, three, filter: LiveFilter.auto).map((a) => a.exe), ['chrome.exe', '']);
      expect(
        buildLiveApps(split, all, three, query: 'хром', titleOf: (e) => e == 'chrome.exe' ? 'Хром' : e).single.exe,
        'chrome.exe',
      );
      expect(buildLiveApps(split, all, three, query: 'ytimg'), isEmpty);

      // Сводка — только открытые, по порядку серверов, «мимо» в конце.
      expect(
        [for (final (d, n) in liveSummary(all, three)) '${destLabel(d)} $n'],
        ['Основной 2', 'Запасной 2 2', 'Мимо VPN 1'],
      );
    });

    test('размер трафика и названия программ', () {
      expect(formatBytes(830 * 1024), '830 КБ');
      expect(formatBytes(12 * 1024 * 1024 + 400 * 1024), '12,4 МБ');
      expect(appTitle('TslGame.exe'), 'PUBG');
      expect(appTitle('obs64.exe', {'obs64.exe': 'OBS Studio'}), 'OBS Studio');
      expect(appTitle('tool.exe'), 'tool');
      expect(appTitle(''), 'Неизвестная программа');
    });

    test('место записей: общее, разные; «Авто» у игры по умолчанию — мимо', () {
      const split = SplitTunnel(
        bypass: SplitList(apps: ['ssh.exe']),
        servers: {
          'NL игры': SplitList(domains: ['mwlogin.net']),
        },
      );
      expect(split.placeOf(SplitKind.domain, 'mwlogin.net'), (target: SplitTarget.via, server: 'NL игры'));
      expect(split.commonPlace([(kind: SplitKind.app, value: 'ssh.exe')]), bypassPlace);
      expect(
        split.commonPlace([(kind: SplitKind.app, value: 'ssh.exe'), (kind: SplitKind.domain, value: 'mwlogin.net')]),
        isNull,
      );
    });
  });

  final shellConns = [
    conn('chrome.exe', host: 'www.google.com'),
    conn('chrome.exe', host: 'ya.ru', chains: direct),
    conn('Discord.exe', host: 'discord.com', chains: games),
  ];
  const shellState = SplitTunnel(
    via: SplitList(apps: ['Telegram.exe'], domains: ['youtube.com']),
    bypass: SplitList(apps: defaultBypassApps, domains: ['kinopoisk.ru'], ips: ['192.168.0.0/16']),
    servers: {
      'NL игры': SplitList(apps: ['Discord.exe']),
    },
    groups: [
      SplitGroup(
        name: 'Игры и лаунчеры',
        items: SplitList(apps: defaultBypassApps),
      ),
      SplitGroup(
        name: 'Общение',
        items: SplitList(apps: ['Discord.exe', 'Telegram.exe']),
      ),
    ],
  );

  for (final size in shellSizes) {
    testWidgets('окно ${size.width.toInt()} px: «Сейчас в сети» и «Группы» без переполнений', (tester) async {
      writeState(shellState);
      final container = await start(tester, connections: shellConns, groups: errors);
      await pumpInShell(tester, container, const SplitTunnelTablePage(), size: size, selected: 1);
      expectNoLayoutErrors(tester);

      expect(find.text('РАЗДЕЛЬНЫЙ ТУННЕЛЬ'), findsOneWidget);
      expect(find.text('3 соединения'), findsOneWidget);
      expect(find.text('Google Chrome'), findsOneWidget);
      expect(find.text('Discord'), findsOneWidget);
      // У Discord видно группу и сервер.
      expect(
        find.descendant(of: find.byKey(const ValueKey('live-app-Discord.exe')), matching: find.text('Общение')),
        findsOneWidget,
      );
      // Ошибки за сутки — не про «сейчас»: здесь их нет, они на «Группах».
      expect(find.byTooltip('Соединений, которые не удались за сутки'), findsNothing);

      await tap(tester, find.text('Google Chrome'));
      expect(find.textContaining('общие правила → мимо', findRichText: true), findsOneWidget);
      expectNoLayoutErrors(tester);

      await openTab(tester, 1);
      expect(find.byKey(const ValueKey('group-card-Игры и лаунчеры')), findsOneWidget);
      expect(find.byTooltip('Соединений, которые не удались за сутки'), findsWidgets, reason: 'у «Общения» и «Без группы»');
      expect(find.byKey(const ValueKey('group-card-')), findsOneWidget, reason: 'карточка «Без группы»');
      await tap(tester, find.byKey(const ValueKey('group-open-Общение')));
      expect(find.text('Группа «Общение»'), findsOneWidget);
      expect(find.text('Discord'), findsWidgets);
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });
  }

  testWidgets('«Сейчас в сети»: путь программы, правило для сайта, группа, вид по группам, фильтр', (tester) async {
    writeState(
      const SplitTunnel(
        servers: {
          'NL игры': SplitList(apps: ['Discord.exe']),
        },
        groups: [
          SplitGroup(
            name: 'Общение',
            items: SplitList(apps: ['Discord.exe']),
          ),
        ],
      ),
    );
    final container = await start(
      tester,
      connections: [
        conn('Discord.exe', host: 'gateway.discord.gg', chains: games),
        conn('chrome.exe', host: 'www.youtube.com', bytes: 3 << 20),
        conn('chrome.exe', host: 'ya.ru', chains: direct),
      ],
    );
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    SplitTunnel state() => container.read(splitTunnelProvider);

    // Почему так: у Discord — программа в группе, у Chrome — общие правила.
    await tap(tester, find.text('Discord'));
    expect(find.textContaining('программа Discord · группа «Общение»', findRichText: true), findsOneWidget);
    await tap(tester, find.text('Google Chrome'));
    expect(find.textContaining('общие правила → через VPN', findRichText: true), findsOneWidget);

    // Плашка пути программы.
    await tap(tester, find.byTooltip('Куда направить: Google Chrome'));
    await tapMenu(tester, 'Мимо VPN');
    expect(state().bypass.apps, ['chrome.exe']);

    // «⋯» у соединения: сайт целиком — за «Запасной 1».
    await tap(tester, find.byTooltip('Направить: youtube.com'));
    await tapText(tester, 'Сайт youtube.com и поддомены');
    await tap(tester, find.byKey(const ValueKey('place-server-NL запасной')));
    expect(state().serverOf(SplitKind.domain, 'youtube.com'), 'NL запасной');
    expect(find.textContaining('сайт youtube.com', findRichText: true), findsOneWidget);

    // Группа программы: новая.
    await tap(tester, find.byKey(const ValueKey('group-btn-chrome.exe')));
    await tapMenu(tester, 'Новая группа…');
    await nameGroup(tester, 'Браузеры');
    expect(state().groupOf(SplitKind.app, 'chrome.exe'), 'Браузеры');

    // По группам и переход к группе.
    await tapText(tester, 'По группам');
    expect(find.text('ОБЩЕНИЕ'), findsOneWidget);
    expect(find.text('БРАУЗЕРЫ'), findsOneWidget);
    await tap(tester, find.text('открыть группу').first);
    expect(find.text('Группа «Общение»'), findsOneWidget);

    // Фильтр «Мимо» — только Chrome (у него ya.ru напрямую).
    await openTab(tester, 0);
    await tapText(tester, 'Мимо');
    expect(find.text('Google Chrome'), findsOneWidget);
    expect(find.text('Discord'), findsNothing);
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('VPN выключен: подсказка и переход к группам', (tester) async {
    writeState(const SplitTunnel(bypass: SplitList(apps: ['ssh.exe'])));
    final container = await start(tester);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    expect(find.textContaining('VPN выключен'), findsOneWidget);
    await tapText(tester, 'Открыть группы');
    expect(find.byKey(const ValueKey('group-card-')), findsOneWidget);
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('«Группы»: путь всей группе и сервер, «Выровнять», записи по одной, перенос, отметки', (tester) async {
    writeState(
      const SplitTunnel(
        bypass: SplitList(apps: ['ssh.exe'], domains: ['mwlogin.net']),
        servers: {
          'NL игры': SplitList(apps: ['Discord.exe']),
        },
        groups: [
          SplitGroup(
            name: 'Работа и дом',
            items: SplitList(apps: ['ssh.exe'], domains: ['mwlogin.net']),
          ),
          SplitGroup(
            name: 'Общение',
            items: SplitList(apps: ['Discord.exe']),
          ),
        ],
      ),
    );
    final container = await start(tester, connections: const []);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    SplitTunnel state() => container.read(splitTunnelProvider);
    await openTab(tester, 1);

    final card = find.byKey(const ValueKey('group-card-Работа и дом'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);

    // «VPN» у группы — всем; строка «Сервер» — за «Запасной 2».
    await tap(tester, inCard(find.text('VPN')));
    expect(state().via.items, hasLength(2));
    await tap(tester, find.byKey(const ValueKey('group-server-Работа и дом')));
    await tapMenu(tester, 'Запасной 2');
    expect(state().servers['NL игры']!.items, hasLength(3));

    // Запись по одной: SSH мимо — у группы «Разные пути», «Выровнять» ставит всем.
    await tap(tester, find.byKey(const ValueKey('group-open-Работа и дом')));
    await tap(tester, find.byTooltip('Куда направить: SSH'));
    await tapMenu(tester, 'Мимо VPN');
    expect(inCard(find.textContaining('Разные пути')), findsOneWidget);
    expect(find.textContaining('не как у группы'), findsOneWidget);
    await tap(tester, inCard(find.text('Выровнять')));
    await tapMenu(tester, 'Мимо VPN');
    expect(state().bypass.items, hasLength(2));

    // Перенос одной записи в другую группу.
    await tap(tester, find.byKey(const ValueKey('group-btn-mwlogin.net')));
    await tapMenu(tester, 'Общение · 1');
    expect(state().groupOf(SplitKind.domain, 'mwlogin.net'), 'Общение');

    // Отметить все (остался SSH) → в новую группу. Старая исчезла, панель закрылась.
    await tap(tester, find.byKey(const ValueKey('select-all')));
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('selection-group')));
    await tapMenu(tester, 'Новая группа…');
    await nameGroup(tester, 'Дом');
    expect([for (final g in state().groups) g.name], ['Общение', 'Дом']);
    expect(find.text('Группа «Работа и дом»'), findsNothing);

    // «⋯» карточки: переименовать, удалить — запись остаётся в списках, уходит в «Без группы».
    await tap(tester, find.byTooltip('Группа Дом: ещё'));
    await tapMenu(tester, 'Переименовать…');
    await nameGroup(tester, 'Мой дом');
    expect(state().group('Мой дом'), isNotNull);
    await tap(tester, find.byTooltip('Группа Мой дом: ещё'));
    await tapMenu(tester, 'Удалить группу (записи останутся)');
    expect(state().groupOf(SplitKind.app, 'ssh.exe'), isNull);
    expect(state().bypass.apps, ['ssh.exe']);
    expect(find.byKey(const ValueKey('group-card-')), findsOneWidget);
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('файлы правил для ядра: каждое действие на экране меняет правила у каждой записи', (tester) async {
    writeState(
      const SplitTunnel(
        bypass: SplitList(apps: ['ssh.exe'], domains: ['mwlogin.net'], ips: ['8.8.8.8/32']),
        groups: [
          SplitGroup(
            name: 'Работа и дом',
            items: SplitList(apps: ['ssh.exe'], domains: ['mwlogin.net'], ips: ['8.8.8.8/32']),
          ),
        ],
      ),
    );
    final container = await start(tester, connections: [conn('chrome.exe', host: 'www.youtube.com')]);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));

    // Что лежит в наборе правил [file] (папка split/, за ней следит ядро): программы, сайты, сети.
    Set<String> rules(String file) {
      final f = File('${dir.path}/split/$file');
      if (!f.existsSync()) return const {};
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final r in (json['rules'] as List).cast<Map<String, dynamic>>())
          for (final e in r.entries) ...[for (final v in (e.value as List).cast<String>()) '${e.key}:$v'],
      };
    }

    final app = 'process_path_regex:${processPathRegex('ssh.exe')}';
    const site = 'domain_suffix:mwlogin.net';
    const ip = 'ip_cidr:8.8.8.8/32';
    final games = viaServerFile(serverKey('NL игры'));

    expect(rules('bypass-vpn.json'), {app, site, ip});
    expect(rules('bypass-domains.json'), {site}, reason: 'DNS сайтов «мимо» — тоже мимо');
    expect(rules('via-vpn.json'), isEmpty);

    // «VPN» у группы — все три записи «через VPN».
    await openTab(tester, 1);
    final card = find.byKey(const ValueKey('group-card-Работа и дом'));
    await tap(tester, find.descendant(of: card, matching: find.text('VPN')));
    expect(rules('via-vpn.json'), {app, site, ip});
    expect(rules('via-domains.json'), {site});
    expect(rules('bypass-vpn.json'), isEmpty);

    // Сервер группы — «Запасной 2»: свой набор у сервера (и общий «через VPN» на случай, если
    // сервер пропадёт из подписки).
    await tap(tester, find.byKey(const ValueKey('group-server-Работа и дом')));
    await tapMenu(tester, 'Запасной 2');
    expect(rules(games), {app, site, ip});
    expect(rules('via-vpn.json'), {app, site, ip});

    // По одной: программа — мимо, сайт — «Авто» (ни в одном наборе), IP остаётся за сервером.
    await tap(tester, find.byKey(const ValueKey('group-open-Работа и дом')));
    await tap(tester, find.byTooltip('Куда направить: SSH'));
    await tapMenu(tester, 'Мимо VPN');
    await tap(tester, find.byTooltip('Куда направить: mwlogin.net'));
    await tapMenu(tester, 'Авто');
    expect(rules('bypass-vpn.json'), {app});
    expect(rules(games), {ip});
    expect(rules('via-vpn.json'), {ip});
    expect([rules('via-domains.json'), rules('bypass-domains.json')], [isEmpty, isEmpty]);

    // «Сейчас в сети»: сайт из соединения — сразу в набор сервера.
    await openTab(tester, 0);
    await tap(tester, find.text('Google Chrome'));
    await tap(tester, find.byTooltip('Направить: youtube.com'));
    await tapText(tester, 'Сайт youtube.com и поддомены');
    await tap(tester, find.byKey(const ValueKey('place-server-NL запасной')));
    expect(rules(viaServerFile(serverKey('NL запасной'))), {'domain_suffix:youtube.com'});
    expect(rules('via-domains.json'), {'domain_suffix:youtube.com'});
    await closePage(tester, container);
  });

  testWidgets('«Добавить»: несколько записей сразу в группу с путём как у группы; новая группа; бессмысленно', (
    tester,
  ) async {
    writeState(
      const SplitTunnel(
        servers: {
          'NL игры': SplitList(apps: ['Discord.exe']),
        },
        groups: [
          SplitGroup(
            name: 'Общение',
            items: SplitList(apps: ['Discord.exe']),
          ),
        ],
      ),
    );
    final container = await start(tester, connections: const []);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    SplitTunnel state() => container.read(splitTunnelProvider);

    await tapText(tester, '+ Добавить');
    await tester.enterText(find.byKey(const ValueKey('add-text')), 'youtube.com\nTelegram.exe');
    await tester.pumpAndSettle();
    expect(find.text('2 записи'), findsOneWidget);
    await tapText(tester, 'Общение');
    expect(find.text('Как у группы: Запасной 2'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('add-submit')));
    expect(state().servers['NL игры']!.domains, ['youtube.com']);
    expect(state().groupOf(SplitKind.app, 'Telegram.exe'), 'Общение');

    await tapText(tester, '+ Добавить');
    await tester.enterText(find.byKey(const ValueKey('add-text')), 'https://example.org/page');
    await tester.pumpAndSettle();
    await tapText(tester, '+ Новая…');
    await tester.enterText(find.byKey(const ValueKey('add-new-group')), 'Сайты');
    await tapText(tester, 'Мимо VPN');
    await tap(tester, find.byKey(const ValueKey('add-submit')));
    expect(state().bypass.domains, ['example.org']);
    expect(state().groupOf(SplitKind.domain, 'example.org'), 'Сайты');

    // Без группы и с «Авто» — ничего не изменится: кнопка неактивна.
    await tapText(tester, '+ Добавить');
    await tester.enterText(find.byKey(const ValueKey('add-text')), 'abc.com');
    await tester.pumpAndSettle();
    expect(find.textContaining('ничего не изменит'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('add-submit'))).onPressed, isNull);
    await tapText(tester, 'Отмена');
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('«Из запущенных» — в группу; «Новая группа» — из записей других групп', (tester) async {
    writeState(
      const SplitTunnel(
        bypass: SplitList(apps: ['ssh.exe', 'vpnagent.exe']),
        groups: [
          SplitGroup(
            name: 'Служебное',
            items: SplitList(apps: ['vpnagent.exe']),
          ),
        ],
      ),
    );
    final container = await start(
      tester,
      connections: const [],
      running: const [RunningApp(exe: 'obs64.exe', path: r'C:\obs\obs64.exe', title: 'OBS Studio')],
    );
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    SplitTunnel state() => container.read(splitTunnelProvider);

    await tapText(tester, 'Из запущенных');
    await tapText(tester, 'OBS Studio');
    await tapText(tester, 'Служебное');
    await tap(tester, find.byKey(const ValueKey('add-submit')));
    expect(state().groupOf(SplitKind.app, 'obs64.exe'), 'Служебное');
    expect(state().bypass.apps, contains('obs64.exe'), reason: 'как у группы — мимо');

    await tapText(tester, 'Новая группа');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('new-group-create'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('new-group-name')), 'Работа и дом');
    await tap(tester, find.byKey(const ValueKey('new-group-pick-ssh.exe')));
    await tap(tester, find.byKey(const ValueKey('new-group-pick-vpnagent.exe')));
    expect(find.textContaining('сейчас в «Служебное», перенесётся'), findsNWidgets(2), reason: 'vpnagent и obs64');
    await tap(tester, find.byKey(const ValueKey('new-group-create')));
    expect(state().group('Работа и дом')!.items.apps, ['ssh.exe', 'vpnagent.exe']);
    expect(state().groupOf(SplitKind.app, 'vpnagent.exe'), 'Работа и дом');
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('поиск на «Группах»: записи одним списком', (tester) async {
    writeState(
      const SplitTunnel(
        via: SplitList(domains: ['youtube.com']),
        bypass: SplitList(domains: ['kinopoisk.ru']),
        groups: [
          SplitGroup(
            name: 'Видео',
            items: SplitList(domains: ['youtube.com']),
          ),
        ],
      ),
    );
    final container = await start(tester, connections: const []);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    await openTab(tester, 1);
    await tester.enterText(find.byType(TextField), 'KINO');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('entry-kinopoisk.ru')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-youtube.com')), findsNothing);
    expect(find.byKey(const ValueKey('group-card-Видео')), findsNothing);
    await tester.enterText(find.byType(TextField), 'нет такого');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не нашлось.'), findsOneWidget);
    await closePage(tester, container);
  });

  testWidgets('200 записей без группы: панель строится лениво, шапка на месте', (tester) async {
    writeState(SplitTunnel(via: SplitList(domains: [for (var i = 0; i < 200; i++) 'site-$i.example.com'])));
    final container = await start(tester, connections: const []);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    await openTab(tester, 1);
    await tap(tester, find.byKey(const ValueKey('group-open-')));
    expect(find.text('Без группы'), findsWidgets);
    expect(find.byKey(const ValueKey('entry-site-0.example.com')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-site-199.example.com')), findsNothing);
    expect(find.text('РАЗДЕЛЬНЫЙ ТУННЕЛЬ'), findsOneWidget);
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('один сервер: в меню пути нет серверов', (tester) async {
    writeState(const SplitTunnel(bypass: SplitList(domains: ['youtube.com'])));
    final container = await start(
      tester,
      connections: const [],
      servers: RescueServers(servers: [three.main]),
    );
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    await openTab(tester, 1);
    await tap(tester, find.byKey(const ValueKey('group-open-')));
    await tap(tester, find.byTooltip('Куда направить: youtube.com'));
    expect(find.text('Основной'), findsNothing);
    await tapMenu(tester, 'Через VPN');
    expect(container.read(splitTunnelProvider).via.domains, ['youtube.com']);
    await closePage(tester, container);
  });

  testWidgets('меню «Ещё»: «Сравнить пути…» с вводом адреса', (tester) async {
    writeState(const SplitTunnel());
    final container = await start(
      tester,
      extra: [
        vpnStatusProvider.overrideWith(
          (ref) => const VpnStatus(connected: true, busy: false, label: 'Подключено', canToggle: true),
        ),
        compareEnvProvider.overrideWithValue(CompareEnv(newId: () => 'tableid00001')),
      ],
    );
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 900));
    final core = FakeCore(dir);
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сравнить пути…'));
    await tester.pumpAndSettle();
    expect(core.allFiles, isEmpty, reason: 'без адреса запроса нет');
    await tester.enterText(find.byKey(const ValueKey('compare-address')), 'example.org:8443');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сравнить'));
    await tester.pump(const Duration(milliseconds: 50));
    expect((core.request!['target'], core.request!['port']), ('example.org', 8443));
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    await closePage(tester, container);
  });

  testWidgets('старый файл без групп: записи раскладываются по стандартным группам', (tester) async {
    File('${dir.path}/split-tunnel.json').writeAsStringSync(
      jsonEncode({
        'bypass': {
          'apps': ['steam.exe', 'ssh.exe'],
        },
        'via': {
          'apps': ['cs2.exe', 'Marvel-Win64-Shipping.exe'],
        },
        'servers': {
          'NL игры': {
            'domains': ['gaming-sdk.com'],
          },
        },
      }),
    );
    final container = await start(tester, connections: const []);
    final groups = container.read(splitTunnelProvider).groups;
    expect([for (final g in groups) g.name], ['Игры', 'Marvel Rivals', 'Лаунчеры и магазины']);
    expect(groups[1].items.items, hasLength(2));
    expect(container.read(splitTunnelProvider).groupOf(SplitKind.app, 'ssh.exe'), isNull);
    await closePage(tester, container);
  });
}
