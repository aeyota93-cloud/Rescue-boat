import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';

void main() {
  final base = DateTime(2025, 10, 9, 20);
  DateTime at(int minute) => base.add(Duration(minutes: minute));

  ErrorEvent event(
    int minute, {
    String host = '',
    String app = '',
    int n = 1,
    ErrorKind kind = ErrorKind.reset,
    ErrorRoute route = ErrorRoute.vpn,
  }) => ErrorEvent(time: at(minute), kind: kind, host: host, app: app, count: n, route: route);

  test('новые сверху', () {
    final sorted = sortNewestFirst([event(1), event(30), event(10)]);
    expect(sorted.map((e) => e.time), [at(30), at(10), at(1)]);
  });

  test('по сайту, иначе по программе; частые сверху; внутри группы новые сверху', () {
    final groups = groupErrors([
      event(1, host: 'kinopoisk.ru', app: 'chrome.exe'),
      event(5, host: 'KinoPoisk.ru', app: 'chrome.exe', n: 3),
      event(2, host: 'kinopoisk.ru', app: 'msedge.exe'),
      event(40, app: 'steam.exe', route: ErrorRoute.direct),
      event(3, host: 'gateway.discord.gg', app: 'Discord.exe', n: 2),
      event(7, host: 'gateway.discord.gg', app: 'Discord.exe', kind: ErrorKind.stall),
      event(50, kind: ErrorKind.suppressed, n: 42),
    ]);

    expect(groups.map((g) => g.key), ['kinopoisk.ru', 'gateway.discord.gg', 'app:steam.exe']);

    final kino = groups.first;
    expect(kino.count, 5);
    expect(kino.app, 'chrome.exe', reason: 'самая частая программа');
    expect(kino.last, at(5));
    expect(kino.target, 'KinoPoisk.ru', reason: 'как в самом новом событии');
    expect(kino.events.map((e) => e.time), [at(5), at(2), at(1)]);

    final steam = groups.last;
    expect(steam.app, 'steam.exe');
    expect(steam.route, ErrorRoute.direct);
    expect(steam.count, 1);
  });

  test('при равном числе выше та группа, где ошибка новее', () {
    final groups = groupErrors([event(1, host: 'a.example'), event(9, host: 'b.example')]);
    expect(groups.map((g) => g.target), ['b.example', 'a.example']);
  });

  test('ни сайта, ни программы — одна группа «неизвестный адрес»', () {
    final groups = groupErrors([event(1), event(2)]);
    expect(groups.single.target, 'неизвестный адрес');
    expect(groups.single.count, 2);
  });

  test('счётчик с учётом n', () {
    expect(countErrors([event(1, n: 3), event(2), event(3, kind: ErrorKind.suppressed, n: 10)]), 14);
    expect(countErrors(const []), 0);
  });
}
