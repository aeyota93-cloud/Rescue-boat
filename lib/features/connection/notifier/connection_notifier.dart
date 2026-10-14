import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      // Удаление активной подписки само отключает и подключает заново ([connectWhenStopped]); свой
      // перезапуск тут столкнулся бы с остановкой, и вызовы ядра повисали (приложение «замирало»).
      if (_switchingProfile) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        await reconnect(next);
      }
    });
    ref.watch(coreRestartSignalProvider);

    yield* _connectionRepo.watchConnectionStatus().doOnData((event) {
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
        ref.read(Preferences.startedByUser.notifier).update(false);
      }
      loggy.info("connection status: ${event.format()}");
    });
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  final _operations = ConnectionOperationQueue();

  Future<void> mayConnect() => _operations.run(() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  });

  bool _switchingProfile = false;

  /// Шлюпка: пока идёт [action] (удаление активной подписки), смена активной подписки не
  /// перезапускает ядро — [action] отключает и подключает сам.
  Future<T> whileSwitchingProfile<T>(Future<T> Function() action) async {
    _switchingProfile = true;
    try {
      return await action();
    } finally {
      // Новая активная подписка приходит из базы чуть позже — не пропустить её перезапуск сюда.
      await Future<void>.delayed(const Duration(seconds: 1));
      _switchingProfile = false;
    }
  }

  /// Шлюпка: подключиться, как только ядро остановится (после [abortConnection] состояние
  /// приходит не сразу). Ждёт не дольше [timeout]; подключение с активной подпиской.
  Future<void> connectWhenStopped({Duration timeout = const Duration(seconds: 10)}) async {
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      if (state case AsyncData(value: Disconnected())) {
        loggy.info("reconnecting after the active profile was deleted");
        await ref.read(Preferences.startedByUser.notifier).update(true);
        return mayConnect();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    loggy.warning("not reconnecting: core did not stop in $timeout");
  }

  Future<void> toggleConnection() {
    // Повторное нажатие не запускает обратную операцию после завершения первой.
    if (_operations.busy) return _operations.idle;
    return _operations.run(_toggleConnection);
  }

  Future<void> _toggleConnection() async {
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          await haptic.lightImpact();
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _connect();
        case Connected():
          // default:
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        default:
          loggy.warning("switching status, debounce");
      }
    }
  }

  Future<void> reconnect(ProfileEntity? profile) => _operations.run(() async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        await _disconnect();
        return;
      }
      loggy.info("active profile changed, reconnecting");
      await ref.read(Preferences.startedByUser.notifier).update(true);
      final result = await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).run();
      await result.match((err) async {
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        await ref
            .read(dialogNotifierProvider.notifier)
            .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      }, (_) => Future<void>.value());
    }
  });

  Future<void> abortConnection() => _operations.run(() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          if (!await _disconnect()) throw StateError('Не удалось остановить VPN');
        default:
      }
    }
  });

  Future<void> _connect() async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    final result = await _connectionRepo.connect(activeProfile, ref.read(Preferences.disableMemoryLimit)).run();
    await result.match((ConnectionFailure err) async {
      loggy.warning("error connecting", err);
      //Go err is not normal object to see the go errors are string and need to be dumped
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      loggy.warning(err);
      if (err.toString().contains("panic")) {
        await Sentry.captureException(Exception(err.toString()));
      }
      await ref.read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }, (_) => Future<void>.value());
  }

  Future<bool> _disconnect() async {
    final result = await _connectionRepo.disconnect().run();
    return result.match((err) {
      loggy.warning("error disconnecting", err);
      ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      state = AsyncError(err, StackTrace.current);
      return false;
    }, (_) => true);
  }
}

@Riverpod(keepAlive: true)
Future<bool> serviceRunning(Ref ref) async {
  // ref.watch(coreRestartSignalProvider);
  return await ref
      .watch(connectionNotifierProvider.selectAsync((data) => data.isConnected))
      .onError((error, stackTrace) => false);
}

/// Все обращения к подключению выполняются последовательно; ошибка не ломает очередь.
class ConnectionOperationQueue {
  Future<void> _tail = Future.value();
  int _pending = 0;
  bool get busy => _pending > 0;
  Future<void> get idle => _tail;

  Future<T> run<T>(Future<T> Function() task) {
    _pending++;
    final result = _tail.then((_) async {
      try {
        return await task();
      } finally {
        _pending--;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }
}
