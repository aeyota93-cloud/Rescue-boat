import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/insights/widget/errors_page.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../overview/fakes.dart';

void main() {
  String stat(WidgetTester tester, String label) =>
      tester.widget<StatColumns>(find.byType(StatColumns)).columns.firstWhere((c) => c.label == label).value;

  Text detailsTitle(WidgetTester tester) =>
      tester.widget<Text>(find.descendant(of: find.bySemanticsLabel('Подробности'), matching: find.byType(Text)).first);

  testWidgets('с данными: счётчики, группы, подробности первой группы', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: FakeSplitTunnel()));

    expect(find.text('ОШИБКИ СОЕДИНЕНИЙ'), findsOneWidget);
    expect(find.textContaining('Хранится только на этом компьютере, 7 дней'), findsOneWidget);
    expect(stat(tester, 'ВСЕГО ОШИБОК'), '7');
    expect(stat(tester, 'ЧЕРЕЗ VPN'), '5');
    expect(stat(tester, 'МИМО VPN'), '2');
    expect(stat(tester, 'ЗАМИРАНИЯ СВЯЗИ'), '1');

    // Тёмный список: частые сверху, kinopoisk.ru (4) выбран сразу и подсвечен жёлтым.
    final list = tester.widget<DeepList>(find.byType(DeepList));
    expect(list.title, 'По сайтам и программам');
    expect(list.count, '4');
    final tiles = tester.widgetList<DeepListTile>(find.byType(DeepListTile)).toList();
    expect(tiles.map((t) => t.title), ['kinopoisk.ru', 'gateway.discord.gg', 'steam.exe', 'api.example-shop.ru']);
    expect(tiles.map((t) => t.highlighted), [true, false, false, false]);
    expect(tiles.first.subtitle, 'chrome.exe · сброс · через VPN');
    expect(tiles[2].subtitle, 'сайт неизвестен · таймаут · мимо VPN');
    expect(detailsTitle(tester).data, 'kinopoisk.ru');
    expect(find.text('chrome.exe · идёт через VPN · 4 ошибки за сутки'), findsOneWidget);
    final bars = tester.widget<HourBars>(find.byType(HourBars));
    expect(bars.counts, hasLength(24));
    expect(bars.counts.reduce((a, b) => a + b), 4);
    expect(find.text('213.180.204.211:443'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбор группы меняет подробности', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: FakeSplitTunnel()));
    await tester.tap(find.bySemanticsLabel(RegExp('^steam.exe, сайт неизвестен')));
    await tester.pump();
    expect(detailsTitle(tester).data, 'steam.exe');
    final selected = tester.widgetList<DeepListTile>(find.byType(DeepListTile)).where((t) => t.highlighted);
    expect(selected.single.title, 'steam.exe');
    expect(find.text('steam.exe · идёт мимо VPN · 1 ошибка за сутки'), findsOneWidget);
    expect(find.text('23.62.214.9:443'), findsOneWidget);
  });

  testWidgets('«Пустить мимо VPN» добавляет сайт в список и показывает SnackBar', (tester) async {
    final split = FakeSplitTunnel();
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: split));
    await tester.tap(find.text('Пустить мимо VPN'));
    await tester.pump();
    expect(split.state.bypass.domains, ['kinopoisk.ru']);
    expect(find.text('Добавлено в «Мимо VPN»: kinopoisk.ru'), findsOneWidget);
    expect(find.text('Уже мимо VPN'), findsOneWidget);
  });

  testWidgets('«Всегда через VPN» для группы без сайта добавляет программу', (tester) async {
    final split = FakeSplitTunnel(SplitTunnel.defaults);
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: split));
    await tester.tap(find.bySemanticsLabel(RegExp('^steam.exe, сайт неизвестен')));
    await tester.pump();
    await tester.tap(find.text('Всегда через VPN'));
    await tester.pump();
    expect(split.state.via.apps, ['steam.exe']);
    expect(split.state.bypass.apps, isNot(contains('steam.exe')), reason: 'из «мимо» убрано');
  });

  testWidgets('сводка для владельца сервера: без IP', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: FakeSplitTunnel()));
    await tester.tap(find.text('Скопировать для владельца сервера'));
    await tester.pump();
    expect(copied, contains('Сайт: kinopoisk.ru'));
    expect(copied, contains('Программа: chrome.exe'));
    expect(copied, contains('Путь: через VPN'));
    expect(copied, contains('соединение сброшено — 3'));
    expect(copied, isNot(contains('213.180')));
  });

  testWidgets('сырые строки раскрываются', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: FakeSplitTunnel()));
    expect(find.textContaining('connection reset by peer'), findsNothing);
    await tester.tap(find.text('Сырые строки'));
    await tester.pump();
    expect(find.textContaining('connection reset by peer'), findsOneWidget);
  });

  testWidgets('период «Час»: меньше событий, столбики по 5 минут', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: FakeSplitTunnel()));
    await tester.tap(find.text('Час'));
    await tester.pump();
    expect(stat(tester, 'ВСЕГО ОШИБОК'), '5');
    expect(find.bySemanticsLabel(RegExp('^steam.exe')), findsNothing);
    expect(tester.widget<HourBars>(find.byType(HourBars)).counts, hasLength(12));
  });

  testWidgets('пусто: понятное сообщение', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(empty: true));
    expect(find.text('Ошибок нет за сутки'), findsOneWidget);
    expect(stat(tester, 'ВСЕГО ОШИБОК'), '0');
    expect(find.byType(HourBars), findsNothing);
    expect(find.byType(DeepList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [400.0, 900.0, 1440.0]) {
    for (final empty in [false, true]) {
      testWidgets('нет переполнения: ${width.toInt()} px, ${empty ? 'пусто' : 'с данными'}', (tester) async {
        await pumpPage(
          tester,
          const ErrorsPage(),
          overrides: pageOverrides(empty: empty, split: FakeSplitTunnel()),
          size: Size(width, 900),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('узкое окно: список и подробности друг под другом', (tester) async {
    await pumpPage(
      tester,
      const ErrorsPage(),
      overrides: pageOverrides(split: FakeSplitTunnel()),
      size: const Size(600, 900),
    );
    final list = tester.getTopLeft(find.text('ПО САЙТАМ И ПРОГРАММАМ'));
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.byType(HourBars), 200, scrollable: page);
    expect(tester.getTopLeft(find.byType(HourBars)).dx, closeTo(list.dx, 30));
    await tester.scrollUntilVisible(find.text('Пустить мимо VPN'), 200, scrollable: page);
    expect(find.text('Пустить мимо VPN'), findsOneWidget);
  });

  group('длинные списки: закрепление и прокрутка', () {
    /// Группа «big.example.com» с 300 событиями и ещё 39 групп по одному событию.
    List<ErrorEvent> longEvents() => [
      for (var i = 0; i < 300; i++)
        event(
          Duration(minutes: 1 + i),
          ErrorKind.reset,
          app: 'chrome.exe',
          host: 'big.example.com',
          ip: '1.2.3.4',
        ),
      for (var i = 0; i < 39; i++) event(Duration(minutes: 5 + i), ErrorKind.timeout, host: 'site-$i.example.org'),
    ];

    List<Override> longOverrides() => [
      ...pageOverrides(split: FakeSplitTunnel()),
      errorEventsProvider.overrideWith((ref, period) => AsyncData(longEvents())),
    ];

    Rect rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

    void expectOnScreen(WidgetTester tester, Finder f, Size window, {String? what}) {
      expect(f, findsWidgets, reason: what);
      final r = rect(tester, f);
      expect(r.top, greaterThanOrEqualTo(0), reason: '$what сверху: $r');
      expect(r.bottom, lessThanOrEqualTo(window.height), reason: '$what снизу: $r');
      expect(r.left, greaterThanOrEqualTo(0), reason: '$what слева: $r');
      expect(r.right, lessThanOrEqualTo(window.width), reason: '$what справа: $r');
    }

    Finder scrollableOf(String key) =>
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Scrollable)).first;

    double offsetOf(WidgetTester tester, String key) =>
        tester.state<ScrollableState>(scrollableOf(key)).position.pixels;

    testWidgets('1440×900: заголовок, период, шапка списка и кнопки на месте, крутятся только списки', (tester) async {
      const window = Size(1440, 900);
      await pumpPage(tester, const ErrorsPage(), overrides: longOverrides(), size: window);

      final fixed = {
        'заголовок': find.text('ОШИБКИ СОЕДИНЕНИЙ'),
        'период': find.text('Час'),
        'шапка списка': find.text('ПО САЙТАМ И ПРОГРАММАМ'),
        'график': find.byType(HourBars),
        'мимо VPN': find.text('Пустить мимо VPN'),
        'через VPN': find.text('Всегда через VPN'),
        'копировать': find.text('Скопировать для владельца сервера'),
        'сырые строки': find.text('Сырые строки'),
      };
      for (final e in fixed.entries) {
        expectOnScreen(tester, e.value, window, what: e.key);
      }
      final before = {for (final e in fixed.entries) e.key: rect(tester, e.value)};

      // Список групп: 40 строк, строится только видимая часть, прокручивается внутри карточки.
      expect(tester.widgetList(find.byType(DeepListTile)).length, lessThan(40));
      expect(offsetOf(tester, 'errors-groups-list'), 0);
      await tester.drag(scrollableOf('errors-groups-list'), const Offset(0, -3000));
      await tester.pump();
      expect(offsetOf(tester, 'errors-groups-list'), greaterThan(0));
      expect(find.text('site-38.example.org'), findsOneWidget, reason: 'последняя группа достижима');

      // События: 100 из 300, тоже внутри карточки.
      expect(offsetOf(tester, 'errors-events-list'), 0);
      await tester.drag(scrollableOf('errors-events-list'), const Offset(0, -9000));
      await tester.pump();
      expect(offsetOf(tester, 'errors-events-list'), greaterThan(0));
      expect(find.text('Показаны последние 100 из 300'), findsOneWidget);

      for (final e in fixed.entries) {
        expect(rect(tester, e.value), before[e.key], reason: '${e.key} не сдвинулся(ась) от прокрутки');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('1440×900: сырые строки занимают область событий и крутятся внутри', (tester) async {
      const window = Size(1440, 900);
      await pumpPage(tester, const ErrorsPage(), overrides: longOverrides(), size: window);
      final actions = rect(tester, find.text('Пустить мимо VPN'));
      await tester.tap(find.text('Сырые строки'));
      await tester.pump();
      expect(find.byKey(const ValueKey('errors-events-list')), findsNothing);
      await tester.drag(scrollableOf('errors-raw-scroll'), const Offset(0, -2000));
      await tester.pump();
      expect(offsetOf(tester, 'errors-raw-scroll'), greaterThan(0));
      expect(rect(tester, find.text('Пустить мимо VPN')), actions, reason: 'кнопки на месте');
      expect(find.text('Сырые строки'), findsOneWidget);
      await tester.tap(find.text('Сырые строки'));
      await tester.pump();
      expect(find.byKey(const ValueKey('errors-events-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1200×600 — невысокая область: сводка без пояснения, кнопки и списки на месте', (tester) async {
      const window = Size(1200, 600);
      await pumpPage(tester, const ErrorsPage(), overrides: longOverrides(), size: window);
      expect(find.byKey(const ValueKey('errors-events-list')), findsOneWidget);
      expect(find.textContaining('Хранится только на этом компьютере'), findsNothing);
      for (final t in ['Пустить мимо VPN', 'Скопировать для владельца сервера', 'ПО САЙТАМ И ПРОГРАММАМ', 'Час']) {
        expectOnScreen(tester, find.text(t), window, what: t);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('860×600 — самое узкое «закрепление»: нет переполнения, всё достижимо', (tester) async {
      const window = Size(860, 600);
      await pumpPage(tester, const ErrorsPage(), overrides: longOverrides(), size: window);
      expect(find.byKey(const ValueKey('errors-groups-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Колонке подробностей не хватает места закрепить всё — тогда крутится её карточка.
      final scroll = find.byKey(const ValueKey('errors-details-scroll'));
      if (scroll.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          find.text('Пустить мимо VPN'),
          200,
          scrollable: find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        );
      }
      expectOnScreen(tester, find.text('Пустить мимо VPN'), window, what: 'мимо VPN');
      expect(tester.takeException(), isNull);
    });

    testWidgets('420×700: прокручивается вся страница, списки обрезаны с «Показать ещё»', (tester) async {
      const window = Size(420, 700);
      await pumpPage(tester, const ErrorsPage(), overrides: longOverrides(), size: window);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('errors-groups-list')), findsNothing);
      expect(tester.widgetList(find.byType(DeepListTile)), hasLength(ErrorsPage.compactStep));

      final page = find.byType(Scrollable).first;
      final more = find.byKey(const ValueKey('errors-groups-more'));
      await tester.scrollUntilVisible(more, 300, scrollable: page);
      expect(find.text('Показать ещё · 30 из 40'), findsOneWidget);
      await tester.tap(more);
      await tester.pump();
      expect(tester.widgetList(find.byType(DeepListTile)), hasLength(40));
      expect(more, findsNothing);

      final eventsMore = find.byKey(const ValueKey('errors-events-more'));
      await tester.scrollUntilVisible(eventsMore, 300, scrollable: page);
      expect(find.text('Показать ещё · 30 из 300'), findsOneWidget);
      await tester.tap(eventsMore);
      await tester.pump();
      expect(find.text('Показать ещё · 60 из 300'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Пустить мимо VPN'), 300, scrollable: page);
      expect(find.text('Пустить мимо VPN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('широко, но невысоко (1440×500): колонки рядом, прокручивается страница', (tester) async {
      await pumpPage(tester, const ErrorsPage(), overrides: longOverrides(), size: const Size(1440, 500));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('errors-groups-list')), findsNothing);
      final list = tester.getTopLeft(find.text('ПО САЙТАМ И ПРОГРАММАМ'));
      final bars = tester.getTopLeft(find.byType(HourBars));
      expect(bars.dx, greaterThan(list.dx + 300), reason: 'подробности справа от списка');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('расчёты', () {
    test('по часам за сутки: 24 столбика, сумма с учётом n', () {
      final b = hourBuckets(eventsFor(InsightsPeriod.day), InsightsPeriod.day, now);
      expect(b.counts, hasLength(24));
      expect(b.counts.reduce((a, c) => a + c), 7);
      expect(b.counts.last, greaterThanOrEqualTo(3), reason: 'свежие ошибки — в последнем столбике');
      expect(b.end, 'сейчас');
    });

    test('за неделю — по дням', () {
      final b = hourBuckets(eventsFor(InsightsPeriod.week), InsightsPeriod.week, now);
      expect(b.counts, hasLength(7));
      expect(b.counts.reduce((a, c) => a + c), 7);
    });

    test('что добавлять в туннель: сайт, иначе программа', () {
      final groups = groupErrors(sampleEvents);
      final kino = groups.firstWhere((g) => g.target == 'kinopoisk.ru');
      final steam = groups.firstWhere((g) => g.target == 'steam.exe');
      expect(splitItemFor(kino), (kind: SplitKind.domain, value: 'kinopoisk.ru'));
      expect(splitItemFor(steam), (kind: SplitKind.app, value: 'steam.exe'));
    });
  });
}
