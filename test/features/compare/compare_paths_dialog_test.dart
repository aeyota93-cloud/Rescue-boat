import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/notifier/compare_notifier.dart';
import 'package:hiddify/features/compare/widget/compare_paths_dialog.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../overview/fakes.dart' show FakeSplitTunnel;
import '../screens_test_helpers.dart';
import '../servers/servers_fixtures.dart';
import 'fake_core.dart';

const _id = 'dialogid0001';

const _on = VpnStatus(connected: true, busy: false, label: 'Подключено', canToggle: true);
const _off = VpnStatus(connected: false, busy: false, label: 'Отключено', canToggle: true);

void main() {
  late Directory dir;
  late FakeCore core;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('compare_dialog_');
    core = FakeCore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Окно с кнопкой, которая открывает «Сравнить пути»; открываем сразу.
  Future<ProviderContainer> open(
    WidgetTester tester,
    CompareSubject subject, {
    Size size = const Size(1440, 900),
    VpnStatus vpn = _on,
    FakeSplitTunnel? split,
    RescueServers? servers,
  }) async {
    final container = (await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          vpnStatusProvider.overrideWith((ref) => vpn),
          splitTunnelProvider.overrideWith(() => split ?? FakeSplitTunnel()),
          compareEnvProvider.overrideWithValue(CompareEnv(newId: () => _id)),
          if (servers != null) rescueServersProvider.overrideWith((ref) => servers),
        ],
      ),
    ))!;
    await pumpPage(
      tester,
      container,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => showComparePathsDialog(context, subject), child: const Text('открыть')),
          ),
        ),
      ),
      size: size,
    );
    await tester.tap(find.text('открыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return container;
  }

  /// Ядро отвечает, приложение читает раз в 500 мс.
  Future<void> respond(WidgetTester tester, List<int?> direct, List<int?> vpn, {bool done = false}) async {
    core.respond(_id, direct: direct, vpn: vpn, done: done, directFirst: 120, vpnFirst: 380);
    await tester.pump(const Duration(milliseconds: 600));
  }

  const site = CompareSubject(endpoints: [CompareEndpoint('www.example.com')]);
  final direct10 = [41, 40, 42, 43, 41, 42, 40, 41, 43, 40];
  final vpn10 = [95, 97, 96, 99, 95, 94, 97, 96, 98, 95];

  for (final size in const [Size(1440, 900), Size(420, 700)]) {
    final name = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('$name: замеры идут — прогресс и карточки обновляются, без переполнений', (tester) async {
      final container = await open(tester, site, size: size);
      expect(find.text('Сравнить пути'), findsOneWidget);
      expect(find.text('www.example.com'), findsOneWidget);
      expect(core.request!['target'], 'www.example.com');
      expect(find.text('Ждём ядро…'), findsOneWidget);
      expectNoLayoutErrors(tester);

      await respond(tester, [41, 40, null], [95, 97]);
      expect(find.text('Замеряем: 5 из 20. Обычно это 10–20 секунд'), findsOneWidget);
      expect(find.text('НАПРЯМУЮ'), findsOneWidget);
      expect(find.text('ЧЕРЕЗ VPN'), findsOneWidget);
      expect(find.text('41 мс'), findsOneWidget, reason: 'медиана без неудачи');
      expect(find.text('96 мс'), findsOneWidget);
      expect(find.text('33 %'), findsOneWidget, reason: 'неудачи напрямую');
      expect(find.byKey(const ValueKey('compare-verdict')), findsNothing, reason: 'вывода нет, пока идёт замер');
      expect(
        find.widgetWithText(OutlinedButton, 'Пустить мимо VPN'),
        findsOneWidget,
        reason: 'пока вывода нет, не подсказываем',
      );
      expect(find.widgetWithText(OutlinedButton, 'Всегда через VPN'), findsOneWidget);
      expectNoLayoutErrors(tester);

      await respond(tester, direct10, vpn10, done: true);
      expect(find.text('Лучше напрямую: на 55 мс быстрее'), findsOneWidget);
      expect(find.text('ЛУЧШЕ'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Пустить мимо VPN'),
        findsOneWidget,
        reason: 'лучшая дорога — жёлтая кнопка',
      );
      expect(find.byKey(const ValueKey('compare-progress')), findsNothing);
      expect(find.text('120 мс'), findsOneWidget, reason: 'первое подключение напрямую');
      expect(find.text('380 мс'), findsOneWidget);
      expect(core.allFiles, isEmpty, reason: 'файлы убраны после результата');
      expectNoLayoutErrors(tester);

      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Сравнить пути'), findsNothing);
      await closePage(tester, container);
    });

    testWidgets('$name: игры по UDP — оценка туннеля и пояснение, без «лучше»', (tester) async {
      final container = await open(
        tester,
        const CompareSubject(endpoints: [CompareEndpoint('1.2.3.4', 27015)]),
        size: size,
      );
      expect(core.request!['port'], 27015);
      core.respond(
        _id,
        direct: [31, 30, 32],
        vpn: [88, 90, 87],
        done: true,
        method: 'icmp',
        vpnEstimate: true,
        vpnAvailable: false,
        vpnNote: 'через VPN измерить нельзя: сервер отвечает только на игровые пакеты',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('ОЦЕНКА: КАЧЕСТВО ТУННЕЛЯ'), findsOneWidget);
      expect(find.text('через VPN измерить нельзя: сервер отвечает только на игровые пакеты'), findsOneWidget);
      expect(find.text('Для игр по UDP сравнить нельзя. Прямой путь: 31 мс.'), findsOneWidget);
      expect(find.text('ЛУЧШЕ'), findsNothing);
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });
  }

  testWidgets('VPN не подключён: подсказка, запрос не пишется', (tester) async {
    final container = await open(tester, site, vpn: _off);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Подключите VPN, чтобы сравнить пути'), findsOneWidget);
    expect(core.allFiles, isEmpty);
    expect(find.text('Пустить мимо VPN'), findsNothing);
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('«Пустить мимо VPN» и «Всегда через VPN» меняют списки (сайт без www)', (tester) async {
    final split = FakeSplitTunnel();
    final container = await open(tester, site, split: split);
    await respond(tester, direct10, vpn10, done: true);

    await tester.tap(find.text('Пустить мимо VPN'));
    await tester.pump();
    expect(split.state.bypass.domains, ['example.com']);
    expect(find.text('Уже мимо VPN'), findsOneWidget);

    await tester.tap(find.text('Всегда через VPN'));
    await tester.pump();
    expect(split.state.via.domains, ['example.com']);
    expect(split.state.bypass.domains, isEmpty);
    expect(find.text('Уже через VPN'), findsOneWidget);
    await closePage(tester, container);
  });

  testWidgets('программа: выбор цели из текущих, кнопки добавляют саму программу', (tester) async {
    final split = FakeSplitTunnel();
    final container = await open(
      tester,
      const CompareSubject(
        endpoints: [CompareEndpoint('a.example.com'), CompareEndpoint('b.example.com', 8443)],
        appExe: 'chrome.exe',
      ),
      split: split,
    );
    expect(core.request!['target'], 'a.example.com');
    expect(find.textContaining('программа chrome.exe'), findsOneWidget);

    await tester.tap(find.text('b.example.com:8443').last);
    await tester.pump(const Duration(milliseconds: 50));
    expect(core.request!['target'], 'b.example.com');
    expect(core.request!['port'], 8443);
    expect(core.requests, hasLength(1), reason: 'прошлый запрос убран');

    await tester.tap(find.text('Всегда через VPN'));
    await tester.pump();
    expect(split.state.via.apps, ['chrome.exe']);
    await closePage(tester, container);
  });

  testWidgets('программа без адресов в сети: подсказка, запроса нет', (tester) async {
    final container = await open(tester, const CompareSubject(appExe: 'steam.exe'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Сейчас нет адресов, которые можно измерить. Откройте программу и повторите'), findsOneWidget);
    expect(core.allFiles, isEmpty);
    await closePage(tester, container);
  });

  testWidgets('ввод адреса: ссылка приводится к домену, запрос уходит по кнопке', (tester) async {
    final container = await open(tester, const CompareSubject.ask(), size: const Size(420, 700));
    expect(core.allFiles, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('compare-address')), 'не адрес');
    await tester.pump();
    expect(find.text('Не понял адрес. Примеры: example.com, 8.8.8.8'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('compare-address')), 'https://Kinopoisk.ru/film/1');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сравнить'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(core.request!['target'], 'kinopoisk.ru');
    expectNoLayoutErrors(tester);
    await closePage(tester, container);
  });

  testWidgets('ошибка ядра и «Повторить»', (tester) async {
    final container = await open(tester, site);
    core.respond(_id, done: true, error: 'не резолвится домен');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Не удалось сравнить: не резолвится домен'), findsOneWidget);
    expect(core.allFiles, isEmpty);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(core.request!['target'], 'www.example.com');
    expect(find.text('Ждём ядро…'), findsOneWidget);
    await closePage(tester, container);
  });

  testWidgets('закрытие во время замера убирает файлы', (tester) async {
    final container = await open(tester, site);
    await respond(tester, [41], [95]);
    expect(core.allFiles, isNotEmpty);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(core.allFiles, isEmpty);
    await closePage(tester, container);
  });

  group('v2: все дороги (три сервера)', () {
    final three = rescueServersOf(threeServers(), threeServersOrder)!;
    List<int?> around(int ms) => [ms, ms + 1, ms - 1, ms + 2, ms, ms - 2, ms + 1, ms, ms - 1, ms];

    List<Map<String, Object?>> serversJson(
      List<int?> nl,
      List<int?> backup,
      List<int?> games, {
      bool estimate = false,
    }) => [
      {'tag': 'NL', 'available': !estimate, 'samples': nl, if (estimate) 'estimate': true},
      {'tag': 'NL запасной', 'available': !estimate, 'samples': backup, if (estimate) 'estimate': true},
      {'tag': 'NL игры', 'available': !estimate, 'samples': games, if (estimate) 'estimate': true},
    ];

    for (final size in const [Size(1440, 900), Size(420, 700)]) {
      final name = '${size.width.toInt()}×${size.height.toInt()}';

      testWidgets('$name: таблица «Напрямую» + серверы, «сейчас», лучшая дорога и кнопка «Пустить через»', (
        tester,
      ) async {
        // Сайт в «через VPN (Авто)», select смотрит на основной — «сейчас» у основного.
        final split = FakeSplitTunnel(const SplitTunnel(via: SplitList(domains: ['example.com'])));
        final container = await open(tester, site, size: size, split: split, servers: three);
        // До первого ответа таблица уже со всеми дорогами.
        expect(find.byKey(const ValueKey('compare-road-direct')), findsOneWidget);
        expect(find.byKey(const ValueKey('compare-road-NL игры')), findsOneWidget);
        expect(find.text('ЧЕРЕЗ VPN'), findsNothing, reason: 'строку vpn не показываем, когда есть серверы');

        core.respond(_id, direct: [140], vpn: [95], servers: serversJson([95], [], []));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Замеряем: 3 из 50. Обычно это 10–20 секунд'), findsOneWidget);

        core.respond(
          _id,
          direct: around(140),
          vpn: around(95),
          servers: serversJson(around(95), around(120), around(40)),
          done: true,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expectNoLayoutErrors(tester);
        expect(find.text('Напрямую'), findsOneWidget);
        expect(find.text('Основной'), findsOneWidget);
        expect(find.text('Запасной 1'), findsOneWidget);
        expect(find.text('Запасной 2'), findsOneWidget);
        expect(find.text('NL игры · для игр и звонков'), findsOneWidget);
        expect(find.text('СЕЙЧАС'), findsOneWidget);
        expect(find.text('ЛУЧШЕ'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^Основной, сейчас, задержка 95 мс')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^Запасной 2, лучше, задержка 40 мс')), findsOneWidget);
        expect(find.text('Лучше через запасной 2: на 55 мс быстрее, чем сейчас'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Пустить через «Запасной 2»'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Пустить напрямую'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Оставить как есть'), findsOneWidget);

        await tester.ensureVisible(find.text('Пустить через «Запасной 2»'));
        await tester.tap(find.text('Пустить через «Запасной 2»'));
        await tester.pump();
        expect(split.state.serverOf(SplitKind.domain, 'example.com'), 'NL игры');
        expect(split.state.via.domains, isEmpty);
        expect(find.text('Уже через «Запасной 2»'), findsOneWidget);
        expectNoLayoutErrors(tester);
        await closePage(tester, container);
      });

      testWidgets('$name: игры по UDP — оговорка, кнопка сервера остаётся', (tester) async {
        final container = await open(
          tester,
          const CompareSubject(endpoints: [CompareEndpoint('1.2.3.4', 27015)]),
          size: size,
          servers: three,
        );
        core.respond(
          _id,
          direct: around(30),
          vpn: around(90),
          done: true,
          method: 'icmp',
          vpnEstimate: true,
          vpnAvailable: false,
          servers: serversJson(around(90), around(95), around(60), estimate: true),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.text('Для игры точно покажет только сама игра; по качеству дороги лучше всего — запасной 2'),
          findsOneWidget,
        );
        expect(find.text('ОЦЕНКА'), findsNWidgets(3));
        expect(find.widgetWithText(FilledButton, 'Пустить через «Запасной 2»'), findsOneWidget);
        expectNoLayoutErrors(tester);
        await closePage(tester, container);
      });
    }

    testWidgets('лидеры «одинаково», среди них текущая — «Оставить как есть» жёлтая и закрывает окно', (tester) async {
      final split = FakeSplitTunnel(const SplitTunnel(via: SplitList(domains: ['example.com'])));
      final container = await open(tester, site, split: split, servers: three);
      core.respond(
        _id,
        direct: around(140),
        vpn: around(42),
        servers: serversJson(around(42), around(40), around(41)),
        done: true,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Разницы почти нет — лучше оставить как есть'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Оставить как есть'), findsOneWidget);
      await tester.tap(find.text('Оставить как есть'));
      await tester.pumpAndSettle();
      expect(find.text('Сравнить пути'), findsNothing);
      expect(split.state.via.domains, ['example.com'], reason: 'ничего не трогали');
      await closePage(tester, container);
    });

    testWidgets('ядро без servers (один сервер) — две карточки, как раньше', (tester) async {
      final container = await open(tester, site, servers: three);
      await respond(tester, direct10, vpn10, done: true);
      expect(find.text('ЧЕРЕЗ VPN'), findsOneWidget);
      expect(find.byKey(const ValueKey('compare-road-direct')), findsNothing);
      expect(find.text('Лучше напрямую: на 55 мс быстрее'), findsOneWidget);
      expect(find.text('Всегда через VPN'), findsOneWidget);
      await closePage(tester, container);
    });
  });
}
