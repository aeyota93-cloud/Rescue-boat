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
import '../shell_frame_helper.dart';

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

  for (final size in shellSizes) {
    testWidgets('с данными, окно ${size.width.toInt()} px: без переполнений, игры свёрнуты', (tester) async {
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
      await pumpInShell(tester, container, const SplitTunnelTablePage(), size: size, selected: 1);
      expectNoLayoutErrors(tester);
      final semantics = tester.ensureSemantics();

      expect(find.text('РАЗДЕЛЬНЫЙ ТУННЕЛЬ'), findsOneWidget);
      expect(find.text('Игры и лаунчеры · ${defaultBypassApps.length}'), findsOneWidget);
      expect(find.text('steam'), findsNothing);
      expect(find.text('chrome'), findsOneWidget);
      expect(find.text('2 соединения'), findsOneWidget);
      // Первая строка (программа в сети) — жёлтая, переключатель в ней в цветах «на жёлтом».
      expect(tester.widget<RouteSwitch>(routeSwitch('chrome')).onAccent, isTrue);
      expect(tester.widget<RouteSwitch>(routeSwitch('Telegram')).onAccent, isFalse);
      // kinopoisk.ru: 5 ошибок с поддомена; Discord: 2 по имени программы.
      expect(find.bySemanticsLabel(RegExp(r'^kinopoisk\.ru, .*, 5 ошибок за сутки$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Discord, .*, 2 ошибки за сутки$')), findsOneWidget);
      expect(find.text('домашняя сеть'), findsOneWidget);

      // Раскрыть группу игр.
      await tester.ensureVisible(find.text('Игры и лаунчеры · ${defaultBypassApps.length}'));
      await tester.tap(find.text('Игры и лаунчеры · ${defaultBypassApps.length}'));
      await tester.pumpAndSettle();
      // Строки строятся по мере прокрутки: игры внизу списка (в узком окне — внизу страницы).
      final rows = find.byKey(const ValueKey('tunnel-rows'));
      final scrollable = rows.evaluate().isNotEmpty
          ? find.descendant(of: rows, matching: find.byType(Scrollable)).first
          : find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('steam'), 200, scrollable: scrollable);
      expect(find.text('steam'), findsOneWidget);
      expectNoLayoutErrors(tester);

      semantics.dispose();
      await closePage(tester, container);
    });
  }

  group('длинный список (200 записей)', () {
    SplitTunnel longState() =>
        SplitTunnel(via: SplitList(domains: [for (var i = 0; i < 200; i++) 'site-$i.example.com']));

    Rect rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

    void expectOnScreen(WidgetTester tester, Finder f, Size window, String what) {
      expect(f, findsWidgets, reason: what);
      final r = rect(tester, f);
      expect(r.top, greaterThanOrEqualTo(0), reason: '$what сверху: $r');
      expect(r.bottom, lessThanOrEqualTo(window.height), reason: '$what снизу: $r');
      expect(r.right, lessThanOrEqualTo(window.width), reason: '$what справа: $r');
    }

    testWidgets('1440×900: шапка, закладки, поиск и заголовки колонок на месте, крутятся только строки', (
      tester,
    ) async {
      const window = Size(1440, 900);
      writeState(longState());
      final container = await start(tester, connections: const []);
      await pumpPage(tester, container, const SplitTunnelTablePage(), size: window);
      expectNoLayoutErrors(tester);

      final fixed = {
        'заголовок': find.text('РАЗДЕЛЬНЫЙ ТУННЕЛЬ'),
        'добавить': find.text('+ Добавить сайт, IP или программу'),
        'из запущенных': find.text('Из запущенных'),
        'закладка «Все»': find.byKey(const ValueKey('folder-tab-0')),
        'закладка «Через VPN»': find.byKey(const ValueKey('folder-tab-2')),
        'поиск': find.byType(TextField),
        'колонка НАЗВАНИЕ': find.text('НАЗВАНИЕ'),
        'колонка КУДА ИДЁТ': find.text('КУДА ИДЁТ'),
      };
      for (final e in fixed.entries) {
        expectOnScreen(tester, e.value, window, e.key);
      }
      final before = {for (final e in fixed.entries) e.key: rect(tester, e.value)};

      final rows = find.byKey(const ValueKey('tunnel-rows'));
      final scrollable = find.descendant(of: rows, matching: find.byType(Scrollable)).first;
      expect(find.byType(RouteSwitch).evaluate().length, lessThan(60), reason: 'строки строятся лениво');
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
      await tester.drag(scrollable, const Offset(0, -4000));
      await tester.pump();
      expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0));

      for (final e in fixed.entries) {
        expect(rect(tester, e.value), before[e.key], reason: '${e.key} не сдвинулся(ась) от прокрутки');
      }
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });

    testWidgets('420×700: прокручивается вся страница, строк сначала 30, «Показать ещё»', (tester) async {
      writeState(longState());
      final container = await start(tester, connections: const []);
      await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(420, 700));
      expectNoLayoutErrors(tester);
      expect(find.byKey(const ValueKey('tunnel-rows')), findsNothing);
      expect(find.byType(RouteSwitch), findsNWidgets(30));

      final page = find.byType(Scrollable).first;
      final more = find.byKey(const ValueKey('tunnel-more'));
      await tester.scrollUntilVisible(more, 300, scrollable: page);
      expect(find.text('Показать ещё · 30 из 200'), findsOneWidget);
      await tester.tap(more);
      await tester.pump();
      expect(find.byType(RouteSwitch), findsNWidgets(60));
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });

    testWidgets('1440×500: широко, но невысоко — прокручивается страница', (tester) async {
      writeState(longState());
      final container = await start(tester, connections: const []);
      await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 500));
      expectNoLayoutErrors(tester);
      expect(find.byKey(const ValueKey('tunnel-rows')), findsNothing);
      expect(find.text('НАЗВАНИЕ'), findsOneWidget, reason: 'таблица с колонками');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
      await tester.pump();
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });
  });

  testWidgets('закладки «Все / Мимо / Через VPN» и поиск', (tester) async {
    writeState(
      const SplitTunnel(
        via: SplitList(apps: ['Telegram.exe'], domains: ['youtube.com']),
        bypass: SplitList(domains: ['kinopoisk.ru'], ips: ['192.168.0.0/16']),
      ),
    );
    final container = await start(tester, connections: [conn('chrome.exe')]);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 1000));

    // Метки на закладках: все записи (с программой в сети), «мимо» и «через VPN».
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));

    Future<void> openTab(int i) async {
      await tester.tap(find.byKey(ValueKey('folder-tab-$i')));
      await tester.pumpAndSettle();
    }

    await openTab(1);
    expect(routeSwitch('kinopoisk.ru'), findsOneWidget);
    expect(routeSwitch('Telegram'), findsNothing);
    expect(routeSwitch('chrome'), findsNothing);
    expect(find.text('Идут напрямую, с домашнего IP'), findsOneWidget);

    await openTab(2);
    expect(routeSwitch('Telegram'), findsOneWidget);
    expect(routeSwitch('youtube.com'), findsOneWidget);
    expect(routeSwitch('kinopoisk.ru'), findsNothing);

    await openTab(0);
    await tester.enterText(find.byType(TextField), 'KINO');
    await tester.pumpAndSettle();
    expect(routeSwitch('kinopoisk.ru'), findsOneWidget);
    expect(routeSwitch('Telegram'), findsNothing);

    await tester.enterText(find.byType(TextField), 'нет такого');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не нашлось.'), findsOneWidget);

    await closePage(tester, container);
  });

  testWidgets('пусто и VPN выключен: подсказка и прочерки', (tester) async {
    writeState(const SplitTunnel());
    final container = await start(tester);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 1000));
    expectNoLayoutErrors(tester);
    expect(find.text('Списки пусты. Добавьте программу, сайт или IP.'), findsOneWidget);
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

  testWidgets('игра из стандартного списка: «Авто» возвращает её мимо VPN', (tester) async {
    writeState(const SplitTunnel(via: SplitList(apps: ['Marvel-Win64-Shipping.exe'])));
    final container = await start(tester, connections: [conn('Marvel-Win64-Shipping.exe')]);
    await pumpPage(tester, container, const SplitTunnelTablePage(), size: const Size(1440, 1000));

    await tapRoute(tester, 'Marvel-Win64-Shipping', 'Авто');
    final s = container.read(splitTunnelProvider);
    expect(s.targetOf(SplitKind.app, 'Marvel-Win64-Shipping.exe'), SplitTarget.bypass);
    expect(s.via.apps, isEmpty);

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
