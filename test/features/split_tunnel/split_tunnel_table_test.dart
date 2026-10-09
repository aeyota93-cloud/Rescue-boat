import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/split_tunnel_table_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../screens_test_helpers.dart';

NetConnection conn(String exe, {String host = '', String ip = '1.2.3.4'}) => NetConnection(
  id: '$exe$host$ip',
  exe: exe,
  host: host,
  ip: ip,
  port: '443',
  network: 'tcp',
  viaVpn: true,
  upload: 0,
  download: 0,
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
  }) async {
    final container = await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          liveConnectionsProvider.overrideWith((ref) => Stream.value(connections)),
          errorGroupsProvider.overrideWith((ref, period) => AsyncData(groups)),
        ],
      ),
    );
    return container!;
  }

  Finder routeSwitch(String title) =>
      find.byWidgetPredicate((w) => w is RouteSwitch && w.semanticLabel == 'Куда идёт $title');

  Future<void> tapRoute(WidgetTester tester, String title, String segment) async {
    final target = find.descendant(of: routeSwitch(title), matching: find.text(segment));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('строки таблицы', () {
    test('ошибки сайта считаются вместе с поддоменами, но не с похожими доменами', () {
      expect(hostMatches('rr1.kinopoisk.ru', 'kinopoisk.ru'), isTrue);
      expect(hostMatches('KINOPOISK.RU', 'kinopoisk.ru'), isTrue);
      expect(hostMatches('notkinopoisk.ru', 'kinopoisk.ru'), isFalse);
      expect(errorsFor(SplitKind.domain, 'kinopoisk.ru', errors), 5);
      expect(errorsFor(SplitKind.app, 'discord.exe', errors), 2);
      expect(errorsFor(SplitKind.app, 'msedge.exe', errors), 5);
    });

    test('сети: адрес внутри, домашняя сеть', () {
      expect(ipInCidr('192.168.1.10', '192.168.0.0/16'), isTrue);
      expect(ipInCidr('192.169.1.10', '192.168.0.0/16'), isFalse);
      expect(ipInCidr('8.8.8.8', '8.8.8.8/32'), isTrue);
      expect(isHomeNetwork('192.168.0.0/16'), isTrue);
      expect(isHomeNetwork('8.8.8.8/32'), isFalse);
    });

    test('строки: списки плюс программы в сети; плитки', () {
      const split = SplitTunnel(
        via: SplitList(apps: ['Telegram.exe'], domains: ['youtube.com']),
        bypass: SplitList(apps: ['steam.exe'], ips: ['192.168.0.0/16']),
      );
      final rows = buildTunnelRows(split, [
        conn('chrome.exe', host: 'www.youtube.com'),
        conn('telegram.exe'),
      ], const []);
      final chrome = rows.entries.firstWhere((e) => e.value == 'chrome.exe');
      expect(chrome.target, isNull);
      expect(chrome.connections, 1);
      expect(rows.entries.firstWhere((e) => e.value == 'youtube.com').connections, 1);
      expect(rows.entries.firstWhere((e) => e.value == 'Telegram.exe').online, isTrue);
      expect(rows.summary.via, 2);
      expect(rows.summary.bypass, 2);
      expect(rows.summary.auto, 1);
      expect(rows.summary.online, 2);

      final offline = buildTunnelRows(split, null, const []);
      expect(offline.summary.online, isNull);
      expect(offline.entries.every((e) => e.connections == null), isTrue);
    });

    test('«1 соединение», «3 соединения», «14 соединений»', () {
      String f(int n) => pluralRu(n, 'соединение', 'соединения', 'соединений');
      expect(
        [f(1), f(3), f(14), f(21), f(112)],
        ['соединение', 'соединения', 'соединений', 'соединение', 'соединений'],
      );
    });
  });

  for (final size in const [Size(400, 900), Size(1440, 1000)]) {
    testWidgets('с данными, ${size.width.toInt()} px: без переполнений, игры свёрнуты', (tester) async {
      writeState(
        const SplitTunnel(
          via: SplitList(apps: ['Telegram.exe', 'Discord.exe'], domains: ['youtube.com']),
          bypass: SplitList(apps: defaultBypassApps, domains: ['kinopoisk.ru'], ips: ['192.168.0.0/16']),
        ),
      );
      final container = await start(
        tester,
        connections: [
          conn('chrome.exe', host: 'www.google.com'),
          conn('Telegram.exe'),
          conn('Telegram.exe'),
        ],
        groups: errors,
      );
      await pumpPage(tester, container, const SplitTunnelTablePage(), size: size);
      expectNoLayoutErrors(tester);

      expect(find.text('Раздельный туннель'), findsOneWidget);
      expect(find.text('Игры и лаунчеры (${defaultBypassApps.length})'), findsOneWidget);
      expect(find.text('steam'), findsNothing);
      expect(find.text('chrome'), findsOneWidget);
      expect(find.text('2 соединения'), findsOneWidget);
      // kinopoisk.ru: 5 ошибок с поддомена — красный бейдж; Discord: 2 — оранжевый.
      final kino = tester.widget<RescueBadge>(find.widgetWithText(RescueBadge, '5'));
      expect(kino.kind, RescueBadgeKind.important);
      expect(tester.widget<RescueBadge>(find.widgetWithText(RescueBadge, '2')).kind, RescueBadgeKind.warning);
      expect(find.text('домашняя сеть'), findsOneWidget);

      // Раскрыть группу игр.
      await tester.ensureVisible(find.text('Игры и лаунчеры (${defaultBypassApps.length})'));
      await tester.tap(find.text('Игры и лаунчеры (${defaultBypassApps.length})'));
      await tester.pumpAndSettle();
      expect(find.text('steam'), findsOneWidget);
      expectNoLayoutErrors(tester);

      await closePage(tester, container);
    });
  }

  testWidgets('пусто и VPN выключен: подсказка и прочерки', (tester) async {
    writeState(const SplitTunnel());
    final container = await start(tester);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 1000));
    expectNoLayoutErrors(tester);
    expect(find.text('Списки пусты. Добавьте программу, сайт или IP.'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('«Сейчас» появится, когда VPN подключён.'), findsOneWidget);
    await closePage(tester, container);
  });

  testWidgets('переключатель: «Авто» убирает из обоих списков, «Мимо»/«VPN» переносят', (tester) async {
    writeState(const SplitTunnel(via: SplitList(apps: ['Telegram.exe'])));
    final container = await start(tester, connections: [conn('chrome.exe'), conn('Telegram.exe')]);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 1000));

    SplitTunnel state() => container.read(splitTunnelProvider);

    await tapRoute(tester, 'Telegram', 'Авто');
    expect(state().targetOf(SplitKind.app, 'Telegram.exe'), isNull);

    await tapRoute(tester, 'chrome', 'Мимо');
    expect(state().bypass.apps, contains('chrome.exe'));
    expect(state().via.apps, isNot(contains('chrome.exe')));

    await tapRoute(tester, 'chrome', 'VPN');
    expect(state().via.apps, contains('chrome.exe'));
    expect(state().bypass.apps, isNot(contains('chrome.exe')));

    await tapRoute(tester, 'chrome', 'Авто');
    expect(state().targetOf(SplitKind.app, 'chrome.exe'), isNull);
    // Запись осталась в таблице: программа в сети.
    expect(routeSwitch('chrome'), findsOneWidget);

    await closePage(tester, container);
  });

  testWidgets('группа игр: «VPN» переносит все игры по умолчанию', (tester) async {
    writeState(const SplitTunnel(bypass: SplitList(apps: defaultBypassApps)));
    final container = await start(tester);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 1000));

    final groupSwitch = find.byWidgetPredicate(
      (w) => w is RouteSwitch && w.semanticLabel == 'Куда идут игры и лаунчеры',
    );
    await tester.tap(find.descendant(of: groupSwitch, matching: find.text('VPN')));
    await tester.pumpAndSettle();
    final state = container.read(splitTunnelProvider);
    expect(state.via.apps, hasLength(defaultBypassApps.length));
    expect(state.bypass.apps, isEmpty);

    await closePage(tester, container);
  });
}
