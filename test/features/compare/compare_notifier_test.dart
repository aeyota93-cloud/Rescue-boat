import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/model/compare_models.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/notifier/compare_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../screens_test_helpers.dart';
import 'fake_core.dart';

void main() {
  late Directory dir;
  late FakeCore core;
  late ProviderContainer container;
  var clock = DateTime(2026, 10, 11, 12);
  const id = 'testid000001';

  Future<void> boot({Duration timeout = const Duration(seconds: 90)}) async {
    clock = DateTime(2026, 10, 11, 12);
    container = await screensContainer(
      dir,
      overrides: [
        compareEnvProvider.overrideWithValue(
          CompareEnv(
            pollInterval: const Duration(milliseconds: 10),
            timeout: timeout,
            now: () => clock,
            newId: () => id,
          ),
        ),
      ],
    );
    container.listen(compareProvider, (_, _) {});
  }

  CompareState state() => container.read(compareProvider);
  CompareNotifier notifier() => container.read(compareProvider.notifier);

  Future<void> until(bool Function() test, {String reason = 'условие'}) async {
    for (var i = 0; i < 1000; i++) {
      if (test()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('не дождались: $reason (фаза ${state().phase})');
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('compare_');
    core = FakeCore(dir);
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  test('запрос пишется по договору, атомарно: во временный файл и переименованием', () async {
    await boot();
    notifier().start(const CompareEndpoint('www.example.com'));

    final req = core.request!;
    expect(req['v'], 1);
    expect(req['id'], id);
    expect(req['target'], 'www.example.com');
    expect(req['port'], 443);
    expect(req['count'], 10);
    expect(req['created'], clock.millisecondsSinceEpoch);
    expect(RegExp(r'^[a-z0-9]{8,32}$').hasMatch(req['id'] as String), isTrue);
    expect(core.allFiles, ['req-$id.json'], reason: 'временного файла не осталось');
    expect(state().phase, ComparePhase.running);
    expect(state().expected, 20);
  });

  test('порт из цели уходит в запрос', () async {
    await boot();
    notifier().start(const CompareEndpoint('game.example.com', 27015));
    expect(core.request!['port'], 27015);
    expect(core.request!['target'], 'game.example.com');
  });

  test('частичный ответ обновляет состояние, итоговый — завершает и убирает файлы', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));

    core.respond(id, direct: [41, 40], vpn: [95]);
    await until(() => state().result != null, reason: 'частичный ответ');
    expect(state().phase, ComparePhase.running);
    expect(state().result!.direct!.samples, [41, 40]);
    expect(state().result!.samplesDone, 3);
    expect(state().progress, closeTo(3 / 20, 1e-9));
    expect(state().verdict, isNull, reason: 'вывода нет, пока замеры идут');
    expect(core.requests, hasLength(1), reason: 'запрос на месте, пока идёт замер');

    core.respond(
      id,
      direct: [41, 40, 42, 43, 41, 42, 40, 41, 43, 40],
      vpn: [95, 97, 96, 99, 95, 94, 97, 96, 98, 95],
      done: true,
      directFirst: 120,
      vpnFirst: 380,
    );
    await until(() => state().phase == ComparePhase.done);
    expect(state().progress, 1);
    expect(state().result!.direct!.firstMs, 120);
    expect(state().verdict!.kind, VerdictKind.direct);
    expect(state().verdict!.text, 'Лучше напрямую: на 55 мс быстрее');
    expect(core.allFiles, isEmpty, reason: 'req и res удалены после результата');
  });

  test('битый ответ пропускается, следующее чтение берёт нормальный', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));
    core.respondBroken(id);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(state().result, isNull);
    expect(state().phase, ComparePhase.running);
    core.respond(id, direct: [41], vpn: [95]);
    await until(() => state().result != null);
    expect(state().result!.samplesDone, 2);
  });

  test('ответ с другим номером не принимается', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));
    // Файл с нашим именем, но чужим id внутри.
    core.respond('other0000001', direct: [1], vpn: [2], done: true);
    File('${core.compareDir.path}/res-other0000001.json').renameSync('${core.compareDir.path}/res-$id.json');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(state().result, isNull);
    expect(state().phase, ComparePhase.running);
  });

  test('ошибка ядра: фаза «не вышло», текст ошибки, файлы убраны', () async {
    await boot();
    notifier().start(const CompareEndpoint('нет-такого.example'));
    core.respond(id, done: true, error: 'не резолвится домен');
    await until(() => state().phase == ComparePhase.failed);
    expect(state().error, 'не резолвится домен');
    expect(state().verdict, isNull);
    expect(core.allFiles, isEmpty);
  });

  test('таймаут 90 с: ядро не ответило — фаза «не дождались», файлы убраны', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));
    clock = clock.add(const Duration(seconds: 89));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(state().phase, ComparePhase.running);
    clock = clock.add(const Duration(seconds: 2));
    await until(() => state().phase == ComparePhase.timedOut);
    expect(core.allFiles, isEmpty);
  });

  test('таймаут и при частичном ответе, который так и не закончился', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));
    core.respond(id, direct: [41], vpn: [95]);
    await until(() => state().result != null);
    clock = clock.add(const Duration(seconds: 91));
    await until(() => state().phase == ComparePhase.timedOut);
    expect(state().result!.samplesDone, 2, reason: 'то, что успели, остаётся');
  });

  test('отмена убирает файлы и останавливает опрос', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));
    core.respond(id, direct: [41], vpn: [95]);
    await until(() => state().result != null);
    notifier().cancel();
    expect(state().phase, ComparePhase.idle);
    expect(core.allFiles, isEmpty);
    // Ядро дописало ответ уже после отмены: приложение его не подбирает и не оставляет мусор.
    core.respond(id, direct: [41, 42], vpn: [95, 96], done: true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(state().phase, ComparePhase.idle);
  });

  test('закрытие (dispose) убирает файлы', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com'));
    expect(core.allFiles, ['req-$id.json']);
    container.dispose();
    expect(core.allFiles, isEmpty);
    // tearDown ещё раз закроет контейнер — для riverpod это безопасно.
    await boot();
  });

  test('повторить: новый запрос по той же цели', () async {
    await boot();
    notifier().start(const CompareEndpoint('example.com', 8443));
    core.respond(id, direct: [10, 10, 10], vpn: [50, 50, 50], done: true);
    await until(() => state().phase == ComparePhase.done);
    notifier().retry();
    expect(state().phase, ComparePhase.running);
    expect(state().result, isNull, reason: 'старый результат не показывается');
    expect(core.request!['port'], 8443);
  });

  test('игры по UDP: оценка, вывода «лучше» нет', () async {
    await boot();
    notifier().start(const CompareEndpoint('game.example.com', 27015));
    core.respond(
      id,
      direct: [31, 30, 32],
      vpn: [88, 90, 87],
      done: true,
      method: 'icmp',
      vpnEstimate: true,
      vpnAvailable: false,
      vpnNote: 'через VPN измерить нельзя: сервер отвечает только на игровые пакеты',
    );
    await until(() => state().phase == ComparePhase.done);
    expect(state().result!.method, 'icmp');
    expect(state().result!.vpn!.estimate, isTrue);
    expect(state().verdict!.kind, VerdictKind.notComparable);
    expect(state().verdict!.text, startsWith('Для игр по UDP сравнить нельзя.'));
    expect(state().verdict!.text, contains('Прямой путь: 31 мс'));
  });
}
