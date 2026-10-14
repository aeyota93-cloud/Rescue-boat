import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../overview/fakes.dart' as fakes;
import '../screens_test_helpers.dart';

class PendingConnection implements ConnectionRepository {
  final entered = Completer<void>();
  final gate = Completer<void>();
  final statuses = StreamController<ConnectionStatus>.broadcast();
  int stops = 0;
  @override
  SingboxConfigOption? get configOptionsSnapshot => null;
  @override
  Stream<ConnectionStatus> watchConnectionStatus() async* {
    yield const Disconnected();
    yield* statuses.stream;
  }

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity p, bool limit) => TaskEither(() async {
    entered.complete();
    statuses.add(const Connecting());
    await gate.future;
    statuses.add(const Connected());
    return right(unit);
  });
  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => TaskEither(() async {
    stops++;
    statuses.add(const Disconnected());
    return right(unit);
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoHaptic extends HapticService {
  @override
  bool build() => false;
}

class RejectOptionsCore implements HiddifyCoreService {
  int starts = 0;
  int restarts = 0;
  bool rejectOptions = true;
  @override
  TaskEither<String, Unit> setup() => TaskEither.of(unit);
  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) =>
      rejectOptions ? TaskEither.left('synthetic rejection') : TaskEither.of(unit);
  @override
  TaskEither<ConnectionFailure, Unit> start(String path, String name, bool limit) {
    starts++;
    return TaskEither.of(unit);
  }

  @override
  TaskEither<String, Unit> restart(String path, String name, bool limit) {
    restarts++;
    return TaskEither.of(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('подключение ожидает ядро и не повторяется при втором нажатии', () async {
    final repo = PendingConnection();
    final c = ProviderContainer(
      overrides: [
        await fakes.mockPrefs(),
        hapticServiceProvider.overrideWith(NoHaptic.new),
        activeProfileProvider.overrideWith(() => fakes.FakeActiveProfile(fakes.sampleProfile)),
        connectionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await c.read(sharedPreferencesProvider.future);
    await c.read(connectionNotifierProvider.future);
    var returned = false;
    final operation = c.read(connectionNotifierProvider.notifier).toggleConnection().then((_) => returned = true);
    await repo.entered.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    expect(returned, isFalse);
    final repeat = c.read(connectionNotifierProvider.notifier).toggleConnection();
    expect(repo.gate.isCompleted, isFalse);
    repo.gate.complete();
    await operation;
    await repeat;
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await repo.statuses.close();
  });
  test('отказ применить настройки запрещает запуск ядра', () async {
    final dir = Directory.systemTemp.createTempSync('rb_audit_');
    final core = RejectOptionsCore();
    final provider = Provider<ConnectionRepositoryImpl>(
      (ref) => ConnectionRepositoryImpl(
        ref: ref,
        directories: (baseDir: dir, workingDir: dir, tempDir: dir),
        singbox: core,
        profilePathResolver: ProfilePathResolver(dir),
        configOptionRepository: ConfigOptionRepository(
          preferences: ref.read(sharedPreferencesProvider).requireValue,
          getConfigOptions: () => ref.read(ConfigOptions.singboxConfigOptions),
        ),
      ),
    );
    final c = await screensContainer(dir);
    final result = await c.read(provider).connect(fakes.sampleProfile, false).run();
    expect(result.isLeft(), isTrue);
    expect(c.read(provider).configOptionsSnapshot, isNull);
    expect(core.starts, 0);
    core.rejectOptions = false;
    expect((await c.read(provider).connect(fakes.sampleProfile, false).run()).isRight(), isTrue);
    final snapshot = c.read(provider).configOptionsSnapshot;
    expect(snapshot, isNotNull);
    core.rejectOptions = true;
    expect((await c.read(provider).reconnect(fakes.sampleProfile, false).run()).isLeft(), isTrue);
    expect(core.restarts, 0);
    expect(c.read(provider).configOptionsSnapshot, same(snapshot));
    c.dispose();
    dir.deleteSync(recursive: true);
  });
  test('остановка ждёт окончания запуска; сбой не блокирует следующую операцию', () async {
    final queue = ConnectionOperationQueue();
    final gate = Completer<void>();
    final order = <String>[];
    final start = queue.run(() async {
      order.add('start');
      await gate.future;
      order.add('started');
    });
    final failedStop = queue.run<void>(() {
      order.add('stop');
      return Future<void>.error(StateError('synthetic stop failure'));
    });
    final handledFailure = expectLater(failedStop, throwsStateError);
    final retry = queue.run(() => Future<void>.sync(() => order.add('retry')));
    await Future<void>.delayed(Duration.zero);
    expect(order, ['start']);
    gate.complete();
    await start;
    await handledFailure;
    await retry;
    expect(order, ['start', 'started', 'stop', 'retry']);
    expect(queue.busy, isFalse);
  });
  test('настоящий контроллер не останавливает ядро одновременно с запуском', () async {
    final repo = PendingConnection();
    final c = ProviderContainer(
      overrides: [
        await fakes.mockPrefs(),
        hapticServiceProvider.overrideWith(NoHaptic.new),
        activeProfileProvider.overrideWith(() => fakes.FakeActiveProfile(fakes.sampleProfile)),
        connectionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await c.read(sharedPreferencesProvider.future);
    await c.read(connectionNotifierProvider.future);
    final notifier = c.read(connectionNotifierProvider.notifier);
    final start = notifier.toggleConnection();
    await repo.entered.future.timeout(const Duration(seconds: 3));
    final stop = notifier.abortConnection();
    expect(repo.stops, 0);
    repo.gate.complete();
    await start;
    await stop;
    expect(repo.stops, 1);
    c.dispose();
    await repo.statuses.close();
  });
}
