import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/overview/widget/overview_page.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fakes.dart';

void main() {
  testWidgets('с данными: подключение, здоровье, график, ошибки, правила, подписка', (tester) async {
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides());

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Подключено · Нидерланды · 48 мс'), findsOneWidget);

    // Здоровье: пять строк, общая — жирная.
    expect(find.byType(ScoreRow), findsNWidgets(5));
    final overall = tester.widget<ScoreRow>(find.byType(ScoreRow).first);
    expect(overall.name, 'Общая оценка');
    expect(overall.value, '92');
    expect(overall.emphasized, isTrue);

    // График: красная отметка с подписью у сбоя, оранжевая у дня с ошибками.
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.values, hasLength(30));
    expect(chart.values.first, isNull);
    final red = chart.markers.singleWhere((m) => m.color == RescueColors.poor);
    expect(red.index, 12);
    expect(red.label, 'сервер был недоступен 40 мин');
    expect(chart.markers.singleWhere((m) => m.color == RescueColors.fair).index, 20);

    // Ошибки: счётчики и последние события.
    expect(find.text('5 за час'), findsOneWidget);
    expect(find.text('7 за сутки'), findsOneWidget);
    expect(find.text('kinopoisk.ru'), findsNWidgets(2));
    expect(find.text('соединение сброшено ×3'), findsOneWidget);
    expect(find.text('23.62.214.9:443'), findsOneWidget, reason: 'без сайта — адрес');

    // Правила: стандартный список игр мимо VPN.
    final donut = tester.widget<DonutChart>(find.byType(DonutChart));
    expect(donut.centerValue, '${defaultBypassApps.length}');
    expect(find.textContaining('игры и лаунчеры'), findsOneWidget);

    // Подписка: расход из SubscriptionInfo, хост без пути и токена.
    expect(find.textContaining('48 ГБ'), findsOneWidget);
    expect(find.text('Основной · sub.example.org'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
    expect(find.textContaining('Действует до'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('без данных: понятные пустые состояния, без выдуманных цифр', (tester) async {
    await pumpPage(
      tester,
      const OverviewPage(),
      overrides: pageOverrides(empty: true, connection: FakeConnection(const Disconnected())),
    );
    expect(find.text('Отключено'), findsOneWidget);
    expect(find.text('Нет данных: замеры идут, пока VPN включён'), findsNWidgets(2));
    expect(find.byType(ScoreRow), findsNothing);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('0 за час'), findsOneWidget);
    expect(find.text('Ошибок за сутки нет'), findsOneWidget);
    expect(find.text('Подписка не добавлена'), findsOneWidget);
    expect(find.textContaining('ГБ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [400.0, 1440.0]) {
    for (final empty in [false, true]) {
      testWidgets('нет переполнения: ${width.toInt()} px, ${empty ? 'пусто' : 'с данными'}', (tester) async {
        await pumpPage(
          tester,
          const OverviewPage(),
          overrides: pageOverrides(empty: empty),
          size: Size(width, 900),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('таблетка: подключено — нажатие выключает VPN', (tester) async {
    final connection = FakeConnection(const Connected());
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(connection: connection));
    await tester.tap(find.byType(ConnectionPill));
    await tester.pump();
    expect(connection.toggles, 1);
  });

  testWidgets('таблетка: отключено — включает VPN после проверки уведомления', (tester) async {
    final connection = FakeConnection(const Disconnected());
    final dialogs = FakeDialogs();
    await pumpPage(
      tester,
      const OverviewPage(),
      overrides: pageOverrides(connection: connection, dialogs: dialogs),
    );
    expect(find.text('Отключено'), findsOneWidget);
    await tester.tap(find.byType(ConnectionPill));
    await tester.pump();
    expect(dialogs.notices, 1);
    expect(connection.toggles, 1);
  });

  testWidgets('таблетка: без подписки не подключает, а подсказывает', (tester) async {
    final connection = FakeConnection(const Disconnected());
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(connection: connection, empty: true));
    await tester.tap(find.byType(ConnectionPill));
    await tester.pump();
    expect(connection.toggles, 0);
    expect(find.text('Сначала добавьте подписку'), findsOneWidget);
  });

  testWidgets('таблетка неактивна во время подключения', (tester) async {
    final connection = FakeConnection(const Connecting());
    await pumpPage(tester, const OverviewPage(), overrides: pageOverrides(connection: connection));
    final pill = tester.widget<ConnectionPill>(find.byType(ConnectionPill));
    expect(pill.busy, isTrue);
    expect(pill.onChanged, isNull);
    expect(pill.label, 'Подключение…');
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: pageOverrides(),
        child: MaterialApp.router(theme: RescueTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    for (final (link, page) in [('Все ошибки ›', 'errors'), ('Открыть ›', 'split'), ('Серверы ›', 'servers')]) {
      await tester.ensureVisible(find.text(link));
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      expect(find.text('страница $page'), findsOneWidget);
      router.go('/home');
      await tester.pumpAndSettle();
    }
  });

  group('строка статуса', () {
    test('подключено: с сервером на Обзоре, без сервера в трее', () {
      final proxy = OutboundInfo(urlTestDelay: 48, tagDisplay: 'Нидерланды');
      expect(vpnStatusOf(const AsyncData(Connected()), proxy).label, 'Подключено · Нидерланды · 48 мс');
      expect(vpnStatusOf(const AsyncData(Connected()), proxy, withServer: false).label, 'Подключено · 48 мс');
    });

    test('подключено, но пинга ещё нет — «Подключение…», выключить можно', () {
      final s = vpnStatusOf(const AsyncData(Connected()), OutboundInfo(urlTestDelay: 65000));
      expect(s.label, 'Подключение…');
      expect(s.busy, isTrue);
      expect(s.canToggle, isTrue);
    });

    test('отключено и ошибка', () {
      expect(vpnStatusOf(const AsyncData(Disconnected()), null).label, 'Отключено');
      expect(
        vpnStatusOf(const AsyncError<ConnectionStatus>('x', StackTrace.empty), null).label,
        'Не удалось подключиться',
      );
    });
  });

  test('подписи: размер и минуты', () {
    expect(sizeText(48 * 1073741824), '48 ГБ');
    expect(sizeText((4.5 * 1073741824).round()), '4,5 ГБ');
    expect(sizeText(1073741824), '1 ГБ');
    expect(sizeText(820 * 1048576), '820 МБ');
    expect(minutesText(40), '40 мин');
    expect(minutesText(125), '2 ч 5 мин');
  });
}
