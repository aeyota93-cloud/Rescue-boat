import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/notifier/compare_notifier.dart';
import 'package:hiddify/features/compare/widget/compare_paths_dialog.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../overview/fakes.dart' show FakeSplitTunnel;
import '../screens_test_helpers.dart';
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
  }) async {
    final container = (await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          vpnStatusProvider.overrideWith((ref) => vpn),
          splitTunnelProvider.overrideWith(() => split ?? FakeSplitTunnel()),
          compareEnvProvider.overrideWithValue(CompareEnv(newId: () => _id)),
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
}
