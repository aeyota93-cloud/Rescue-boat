import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/overview/widget/overview_page.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fakes.dart';

/// Главная внутри каркаса — как в приложении (ширина области меньше окна на меню и отступы).
Widget homeInShell() => RescueAppShell(selectedIndex: 0, onSelected: (_) {}, child: const OverviewPage());

Widget shell({int selected = 0}) => RescueAppShell(
  selectedIndex: selected,
  onSelected: (_) {},
  child: const Center(child: Text('раздел')),
);

RingStat ring(WidgetTester tester, String title) =>
    tester.widget<RingStat>(find.byWidgetPredicate((w) => w is RingStat && w.title == title));

void main() {
  testWidgets('подключено: статус, сервер, режимы, кольца, ошибки, туннель, подписка', (tester) async {
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides());

    expect(find.text('ГЛАВНАЯ'), findsOneWidget);
    expect(find.text('замеры раз в минуту'), findsOneWidget);

    // Жёлтый блок: кнопка, «Подключено», время · сервер · пинг (IP не выдумываем).
    expect(tester.widget<PowerButton>(find.byType(PowerButton)).state, PowerState.on);
    expect(find.text('Подключено'), findsOneWidget);
    final line = tester.widget<Text>(find.byKey(const ValueKey('home-status-line'))).data!;
    expect(line, matches(RegExp(r'^\d\d:\d\d:\d\d · Нидерланды · 48 мс$')));
    expect(find.textContaining('IP скрыт'), findsNothing);

    // Сервер: активная подписка, хост без токена, пинг.
    expect(find.text('Основной'), findsOneWidget);
    expect(find.text('Нидерланды · sub.example.org'), findsOneWidget);
    expect(find.text('48 МС'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);

    // Режимы — только те, что есть в приложении.
    final chips = tester.widgetList<ModeChip>(find.byType(ModeChip)).toList();
    expect(chips.map((c) => c.label), ['Весь компьютер', 'Российские сайты напрямую', 'Игры мимо VPN']);
    expect(chips[2].selected, isTrue, reason: 'стандартный список игр мимо VPN');

    // Связь: пинг, разброс, потери из healthProvider, замирания за час из ошибок.
    expect(ring(tester, 'МС ПИНГ').label, '48');
    expect(ring(tester, 'МС РАЗБРОС').label, '6');
    expect(ring(tester, '% ПОТЕРЬ').label, '1');
    expect(ring(tester, 'ЗАМИРАНИЙ').label, '1');
    expect(ring(tester, 'ЗАМИРАНИЙ').color, RescueColors.warn);

    // Здоровье: общий балл и составляющие.
    await tester.tap(find.text('Здоровье'));
    await tester.pump();
    expect(ring(tester, 'ОБЩАЯ').label, '92');
    expect(ring(tester, 'ПИНГ').caption, '48 мс, обычно 45–60');
    expect(ring(tester, 'СТАБИЛЬНОСТЬ').label, '81');
    expect(ring(tester, 'БЕЗ ОШИБОК').label, '97');

    // Ошибки за час: счётчик и частые группы, первая — жёлтая.
    final errors = tester.widget<DeepList>(find.byType(DeepList));
    expect(errors.count, '5');
    final tiles = tester.widgetList<DeepListTile>(find.byType(DeepListTile)).toList();
    expect(tiles.first.title, 'kinopoisk.ru');
    expect(tiles.first.trailingText, '4');
    expect(tiles.first.highlighted, isTrue);
    expect(tiles.first.subtitle, 'chrome.exe · сброс · через VPN');
    expect(tiles[1].highlighted, isFalse);

    // Туннель: размеры списков.
    final split = SplitTunnel.defaults;
    final bypass = split.bypass.apps.length + split.bypass.domains.length + split.bypass.ips.length;
    expect(find.text('$bypass'), findsOneWidget);

    // Подписка: расход, срок, имя и время обновления.
    expect(find.textContaining('48 ГБ'), findsOneWidget);
    expect(find.textContaining('из 200'), findsOneWidget);
    expect(find.textContaining('ДО '), findsOneWidget);
    expect(find.textContaining('Основной · обновлена в'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('без данных: честные «—» и пустые состояния', (tester) async {
    await pumpPage(
      tester,
      const OverviewPage(),
      overrides: pageOverrides(empty: true, connection: FakeConnection(const Disconnected())),
    );
    expect(find.text('Отключено'), findsOneWidget);
    expect(find.text('Сначала добавьте подписку'), findsOneWidget);
    expect(find.text('Подписка не добавлена'), findsNWidgets(2), reason: 'кнопка сервера и карточка подписки');
    expect(ring(tester, 'МС ПИНГ').label, '—');
    expect(find.textContaining('Нет данных: замеры идут, пока VPN включён'), findsOneWidget);
    expect(tester.widget<DeepList>(find.byType(DeepList)).count, '0');
    expect(find.text('За последний час ошибок не было'), findsOneWidget);
    expect(find.textContaining('ГБ'), findsNothing);
    expect(find.text('Добавить подписку'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final states = <String, ConnectionStatus Function()>{
    'отключено': () => const Disconnected(),
    'подключение': () => const Connecting(),
    'подключено': () => const Connected(),
  };
  for (final width in [1440.0, 900.0]) {
    for (final MapEntry(key: name, value: status) in states.entries) {
      testWidgets('в каркасе без переполнения: ${width.toInt()}×900, $name', (tester) async {
        await pumpPage(
          tester,
          homeInShell(),
          overrides: pageOverrides(connection: FakeConnection(status())),
          size: Size(width, 900),
        );
        expect(tester.takeException(), isNull);
        expect(tester.widget<PowerButton>(find.byType(PowerButton).first).state, switch (name) {
          'отключено' => PowerState.off,
          'подключение' => PowerState.connecting,
          _ => PowerState.on,
        });
        // Раскрытый список серверов тоже влезает.
        await tester.tap(find.byKey(const ValueKey('server-select-button')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final empty in [false, true]) {
    testWidgets('узкое окно 400 px без переполнения, ${empty ? 'пусто' : 'с данными'}', (tester) async {
      await pumpPage(
        tester,
        const OverviewPage(),
        overrides: pageOverrides(empty: empty),
        size: const Size(400, 900),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('выбор сервера делает подписку активной', (tester) async {
    final profiles = FakeProfiles([sampleProfile, secondProfile]);
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(profiles: profiles));
    await tester.tap(find.byKey(const ValueKey('server-select-button')));
    await tester.pump();
    expect(find.text('+ Добавить подписку или сервер'), findsOneWidget);
    await tester.tap(find.text('Запасная NL'));
    await tester.pump();
    expect(profiles.selected, ['2']);
    expect(find.byKey(const ValueKey('server-select-list')), findsNothing, reason: 'список закрылся');
    final select = tester.widget<ServerSelect<String>>(find.byType(ServerSelect<String>));
    expect(select.value, '2');
    expect(find.text('Запасная NL'), findsOneWidget);
  });

  testWidgets('режимы переключают настройки и списки туннеля', (tester) async {
    final split = FakeSplitTunnel(SplitTunnel.defaults);
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(split: split));
    ModeChip chip(String label) => tester.widget<ModeChip>(find.widgetWithText(ModeChip, label));

    final whole = chip('Весь компьютер').selected;
    await tester.tap(find.text('Весь компьютер'));
    await tester.pump();
    expect(chip('Весь компьютер').selected, !whole);

    expect(chip('Российские сайты напрямую').selected, isTrue, reason: 'по умолчанию регион ru');
    await tester.tap(find.text('Российские сайты напрямую'));
    await tester.pump();
    expect(chip('Российские сайты напрямую').selected, isFalse);

    await tester.tap(find.text('Игры мимо VPN'));
    await tester.pump();
    expect(chip('Игры мимо VPN').selected, isFalse);
    expect(split.state.bypass.apps.where((a) => defaultBypassApps.contains(a)), isEmpty);
    await tester.tap(find.text('Игры мимо VPN'));
    await tester.pump();
    expect(split.state.bypass.apps, containsAll(defaultBypassApps));
  });

  testWidgets('кнопка: подключено — нажатие выключает VPN', (tester) async {
    final connection = FakeConnection(const Connected());
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(connection: connection));
    await tester.tap(find.byType(PowerButton));
    await tester.pump();
    expect(connection.toggles, 1);
  });

  testWidgets('кнопка: отключено — включает VPN после проверки уведомления', (tester) async {
    final connection = FakeConnection(const Disconnected());
    final dialogs = FakeDialogs();
    await pumpPage(
      tester,
      const OverviewPage(),
      overrides: pageOverrides(connection: connection, dialogs: dialogs),
    );
    expect(find.text('Отключено'), findsOneWidget);
    expect(find.text('Нажмите на кнопку, чтобы подключиться'), findsOneWidget);
    expect(find.bySemanticsLabel('Подключить VPN'), findsOneWidget);
    await tester.tap(find.byType(PowerButton));
    await tester.pump();
    expect(dialogs.notices, 1);
    expect(connection.toggles, 1);
  });

  testWidgets('кнопка: без подписки не подключает, а подсказывает', (tester) async {
    final connection = FakeConnection(const Disconnected());
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(connection: connection, empty: true));
    await tester.tap(find.byType(PowerButton));
    await tester.pump();
    expect(connection.toggles, 0);
    expect(find.text('Сначала добавьте подписку'), findsNWidgets(2), reason: 'строка под кнопкой и SnackBar');
  });

  testWidgets('кнопка неактивна во время подключения', (tester) async {
    final connection = FakeConnection(const Connecting());
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(connection: connection));
    final button = tester.widget<PowerButton>(find.byType(PowerButton));
    expect(button.state, PowerState.connecting);
    expect(button.onPressed, isNull);
    expect(find.text('Подключение…'), findsOneWidget);
  });

  testWidgets('ссылки ведут на /errors, /split, /servers', (tester) async {
    setWindowSize(tester, const Size(1440, 1000));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: OverviewPage()),
        ),
        for (final p in ['errors', 'split', 'servers']) GoRoute(path: '/$p', builder: (_, _) => Text('страница $p')),
      ],
    );
    addTearDown(router.dispose);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefs, ...pageOverrides()],
        child: MaterialApp.router(theme: RescueTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    for (final (link, page) in [
      ('Все ошибки ›', 'errors'),
      ('Открыть туннель', 'split'),
      ('Подписки и серверы', 'servers'),
    ]) {
      await tester.ensureVisible(find.text(link));
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      expect(find.text('страница $page'), findsOneWidget);
      router.go('/home');
      await tester.pumpAndSettle();
    }
  });

  group('строка статуса', () {
    test('подключено: с сервером на Главной, без сервера в трее', () {
      final proxy = OutboundInfo(urlTestDelay: 48, tagDisplay: 'Нидерланды');
      final s = vpnStatusOf(const AsyncData(Connected()), proxy);
      expect(s.label, 'Подключено · Нидерланды · 48 мс');
      expect(s.power, PowerState.on);
      expect(s.server, 'Нидерланды');
      expect(s.delayMs, 48);
      expect(vpnStatusOf(const AsyncData(Connected()), proxy, withServer: false).label, 'Подключено · 48 мс');
    });

    test('подключено, но пинга ещё нет — «Подключение…», выключить можно', () {
      final s = vpnStatusOf(const AsyncData(Connected()), OutboundInfo(urlTestDelay: 65000));
      expect(s.label, 'Подключение…');
      expect(s.busy, isTrue);
      expect(s.canToggle, isTrue);
      expect(s.power, PowerState.connecting);
      expect(s.powerLabel, 'Отключить VPN');
    });

    test('отключено и ошибка', () {
      final off = vpnStatusOf(const AsyncData(Disconnected()), null);
      expect(off.label, 'Отключено');
      expect(off.power, PowerState.off);
      expect(off.powerLabel, 'Подключить VPN');
      expect(
        vpnStatusOf(const AsyncError<ConnectionStatus>('x', StackTrace.empty), null).label,
        'Не удалось подключиться',
      );
    });

    test('время подключения', () {
      expect(elapsedText(const Duration(hours: 1, minutes: 24, seconds: 10)), '01:24:10');
      expect(elapsedText(Duration.zero), '00:00:00');
      expect(elapsedText(const Duration(seconds: -5)), '00:00:00');
    });
  });

  test('подписи: размер, проценты, буквы подписки', () {
    expect(sizeText(48 * 1073741824), '48 ГБ');
    expect(sizeText((4.5 * 1073741824).round()), '4,5 ГБ');
    expect(sizeText(1073741824), '1 ГБ');
    expect(sizeText(820 * 1048576), '820 МБ');
    expect(formatPercentNumber(1), '1');
    expect(formatPercentNumber(0.4), '0,4');
    expect(formatPercentNumber(0), '0');
    expect(profileCode('Основной'), 'О');
    expect(profileCode('NL Amsterdam'), 'NA');
    expect(profileCode('🇳🇱 Нидерланды'), 'Н');
    expect(profileCode(''), '?');
  });

  group('каркас: меню и карточка статуса', () {
    testWidgets('меню: подписи как в макете, счётчик ошибок за час, версия', (tester) async {
      await pumpPage(tester, shell(), overrides: pageOverrides(), size: const Size(1440, 900));
      for (final label in ['Главная', 'Раздельный туннель', 'Ошибки', 'Подписки и серверы', 'Настройки']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // За час в образце 5 ошибок (3 + 1 + 1).
      final count = find.byKey(const ValueKey('rescue-shell-count'));
      expect(count, findsOneWidget);
      expect(find.descendant(of: count, matching: find.text('5')), findsOneWidget);
      expect(find.bySemanticsLabel('Ошибки, 5'), findsOneWidget);
      expect(find.text('Версия 0.2.0 · основано на Hiddify'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('нет ошибок за час — нет счётчика', (tester) async {
      await pumpPage(tester, shell(), overrides: pageOverrides(empty: true), size: const Size(1440, 900));
      expect(find.byKey(const ValueKey('rescue-shell-count')), findsNothing);
    });

    testWidgets('карточка статуса: подключено, сервер и пинг; мини-кнопка отключает', (tester) async {
      final connection = FakeConnection(const Connected());
      await pumpPage(
        tester,
        shell(),
        overrides: pageOverrides(connection: connection),
        size: const Size(1440, 900),
      );
      final card = tester.widget<ShellStatusCard>(find.byType(ShellStatusCard));
      expect(card.state, PowerState.on);
      expect(card.title, 'Подключено');
      expect(card.subtitle, 'Нидерланды · 48 мс');
      expect(card.powerLabel, 'Отключить VPN');
      await tester.tap(find.descendant(of: find.byType(ShellStatusCard), matching: find.byType(PowerButton)));
      await tester.pump();
      expect(connection.toggles, 1);
    });

    testWidgets('карточка статуса: отключено — мини-кнопка подключает, как на Главной', (tester) async {
      final connection = FakeConnection(const Disconnected());
      final dialogs = FakeDialogs();
      await pumpPage(
        tester,
        shell(),
        overrides: pageOverrides(connection: connection, dialogs: dialogs),
        size: const Size(1440, 900),
      );
      final card = tester.widget<ShellStatusCard>(find.byType(ShellStatusCard));
      expect(card.state, PowerState.off);
      expect(card.title, 'Отключено');
      expect(card.subtitle, 'нажмите кнопку');
      await tester.tap(find.bySemanticsLabel('Подключить VPN'));
      await tester.pump();
      expect(dialogs.notices, 1);
      expect(connection.toggles, 1);
    });

    testWidgets('карточка статуса: во время подключения нажатие ничего не делает', (tester) async {
      final connection = FakeConnection(const Connecting());
      await pumpPage(
        tester,
        shell(),
        overrides: pageOverrides(connection: connection),
        size: const Size(1440, 900),
      );
      final card = tester.widget<ShellStatusCard>(find.byType(ShellStatusCard));
      expect(card.state, PowerState.connecting);
      expect(card.title, 'Подключение…');
      await tester.tap(find.descendant(of: find.byType(ShellStatusCard), matching: find.byType(PowerButton)));
      await tester.pump();
      expect(connection.toggles, 0);
    });

    testWidgets('меню значками (600–900): мини-кнопка внизу', (tester) async {
      final connection = FakeConnection(const Connected());
      await pumpPage(
        tester,
        shell(),
        overrides: pageOverrides(connection: connection),
        size: const Size(800, 700),
      );
      expect(find.byType(ShellStatusCard), findsNothing);
      final mini = tester.widget<PowerButton>(find.byType(PowerButton));
      expect(mini.state, PowerState.on);
      await tester.tap(find.byType(PowerButton));
      await tester.pump();
      expect(connection.toggles, 1);
      expect(tester.takeException(), isNull);
    });

    test('подпись карточки статуса', () {
      final on = vpnStatusOf(const AsyncData(Connected()), OutboundInfo(urlTestDelay: 48, tagDisplay: 'Нидерланды'));
      expect(shellStatusSubtitle(on), 'Нидерланды · 48 мс');
      final waiting = vpnStatusOf(const AsyncData(Connected()), OutboundInfo(tagDisplay: 'Нидерланды'));
      expect(shellStatusSubtitle(waiting), 'Нидерланды');
      expect(shellStatusSubtitle(vpnStatusOf(const AsyncData(Connecting()), null)), isNull);
      expect(shellStatusSubtitle(vpnStatusOf(const AsyncData(Disconnected()), null)), 'нажмите кнопку');
    });
  });
}
