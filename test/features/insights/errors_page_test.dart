import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/widget/errors_page.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

import '../overview/fakes.dart';

void main() {
  Text detailsTitle(WidgetTester tester) =>
      tester.widget<Text>(find.descendant(of: find.bySemanticsLabel('Подробности'), matching: find.byType(Text)).first);

  testWidgets('с данными: счётчики, группы, подробности первой группы', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(split: FakeSplitTunnel()));

    expect(find.text('Ошибки соединений'), findsOneWidget);
    expect(find.textContaining('Хранится только на этом компьютере, 7 дней'), findsOneWidget);
    String tile(String label) => tester.widget<StatTile>(find.widgetWithText(StatTile, label)).value;
    expect(tile('Всего ошибок'), '7');
    expect(tile('Через VPN'), '5');
    expect(tile('Мимо VPN'), '2');
    expect(tile('Замирания связи'), '1');

    // Частые сверху: kinopoisk.ru (4) выбран сразу.
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
    expect(tester.widget<StatTile>(find.widgetWithText(StatTile, 'Всего ошибок')).value, '5');
    expect(find.bySemanticsLabel(RegExp('^steam.exe')), findsNothing);
    expect(tester.widget<HourBars>(find.byType(HourBars)).counts, hasLength(12));
  });

  testWidgets('пусто: понятное сообщение', (tester) async {
    await pumpPage(tester, const ErrorsPage(), overrides: pageOverrides(empty: true));
    expect(find.text('Ошибок нет за сутки'), findsOneWidget);
    expect(tester.widget<StatTile>(find.widgetWithText(StatTile, 'Всего ошибок')).value, '0');
    expect(find.byType(HourBars), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [400.0, 1440.0]) {
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
    final list = tester.getTopLeft(find.text('По сайтам и программам'));
    await tester.scrollUntilVisible(find.byType(HourBars), 200);
    expect(tester.getTopLeft(find.byType(HourBars)).dx, closeTo(list.dx, 30));
    await tester.scrollUntilVisible(find.text('Пустить мимо VPN'), 200);
    expect(find.text('Пустить мимо VPN'), findsOneWidget);
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
