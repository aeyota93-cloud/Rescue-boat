import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/compare/data/compare_files.dart';
import 'package:hiddify/features/compare/model/compare_models.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Часы, паузы и номера запросов «Сравнить пути»; в тестах подменяются.
class CompareEnv {
  const CompareEnv({
    this.pollInterval = const Duration(milliseconds: 500),
    this.timeout = const Duration(seconds: 90),
    this.count = 10,
    this.now = DateTime.now,
    this.newId = newCompareId,
  });

  /// Как часто читаем ответ ядра.
  final Duration pollInterval;

  /// Сколько ждём окончания замеров, потом считаем, что ядро не ответило.
  final Duration timeout;

  /// Замеров на каждую дорогу (3..30).
  final int count;
  final DateTime Function() now;
  final String Function() newId;
}

final compareEnvProvider = Provider<CompareEnv>((ref) => const CompareEnv());

enum ComparePhase {
  /// Ничего не запущено.
  idle,

  /// Запрос записан, ждём и читаем ответ.
  running,

  /// Ядро закончило замеры.
  done,

  /// Ядро вернуло ошибку («не резолвится домен» и т. п.).
  failed,

  /// За [CompareEnv.timeout] ответа с done не было.
  timedOut,
}

class CompareState {
  const CompareState({this.phase = ComparePhase.idle, this.endpoint, this.result, this.error = '', this.expected = 0});

  final ComparePhase phase;
  final CompareEndpoint? endpoint;

  /// Последний прочитанный ответ ядра (частичный, пока идёт; полный, когда done).
  final CompareResult? result;
  final String error;

  /// Сколько замеров всего ожидается по двум дорогам.
  final int expected;

  bool get running => phase == ComparePhase.running;
  bool get finished => phase == ComparePhase.done || phase == ComparePhase.failed || phase == ComparePhase.timedOut;

  /// Доля готовности 0..1.
  double get progress {
    if (phase == ComparePhase.done) return 1;
    final done = result?.samplesDone ?? 0;
    return expected == 0 ? 0 : (done / expected).clamp(0.0, 1.0);
  }

  CompareVerdict? get verdict {
    final r = result;
    return phase == ComparePhase.done && r != null ? compareVerdict(r) : null;
  }
}

/// Один запрос за раз. Живёт, пока открыт диалог: при закрытии запрос отменяется, файлы убираются.
final compareProvider = NotifierProvider.autoDispose<CompareNotifier, CompareState>(CompareNotifier.new);

/// Пишет запрос в папку обмена, раз в [CompareEnv.pollInterval] читает ответ ядра, через
/// [CompareEnv.timeout] сдаётся. После результата, ошибки или отмены удаляет req- и res-файлы.
class CompareNotifier extends AutoDisposeNotifier<CompareState> with AppLogger {
  Timer? _timer;
  String? _id;
  String? _dir;
  late DateTime _startedAt;
  bool _disposed = false;

  @override
  CompareState build() {
    ref.onDispose(() {
      _disposed = true;
      _stop(deleteFiles: true);
    });
    return const CompareState();
  }

  /// Запускает сравнение; прошлый запуск отменяется.
  void start(CompareEndpoint endpoint) {
    _stop(deleteFiles: true);
    final env = ref.read(compareEnvProvider);
    final Directory baseDir;
    try {
      baseDir = ref.read(appDirectoriesProvider).requireValue.baseDir;
    } catch (e, st) {
      loggy.error("compare: no base dir", e, st);
      state = CompareState(phase: ComparePhase.failed, endpoint: endpoint, error: 'Папка настроек недоступна');
      return;
    }
    final dir = rescueCompareDir(baseDir);
    final count = env.count.clamp(3, 30);
    final request = CompareRequest(
      id: env.newId(),
      target: endpoint.host,
      port: endpoint.port,
      count: count,
      created: env.now().millisecondsSinceEpoch,
    );
    try {
      writeCompareRequest(dir, request);
    } catch (e, st) {
      loggy.error("compare: could not write request", e, st);
      state = CompareState(phase: ComparePhase.failed, endpoint: endpoint, error: 'Не удалось записать запрос');
      return;
    }
    _id = request.id;
    _dir = dir;
    _startedAt = env.now();
    state = CompareState(phase: ComparePhase.running, endpoint: endpoint, expected: count * 2);
    _timer = Timer.periodic(env.pollInterval, (_) => _poll());
  }

  /// Повторить для той же цели.
  void retry() {
    final endpoint = state.endpoint;
    if (endpoint != null) start(endpoint);
  }

  /// Остановить и убрать файлы; экран возвращается в «ничего не запущено».
  void cancel() {
    _stop(deleteFiles: true);
    if (!_disposed) state = const CompareState();
  }

  void _poll() {
    final id = _id;
    final dir = _dir;
    if (id == null || dir == null || _disposed) return;
    final env = ref.read(compareEnvProvider);
    final result = readCompareResult(dir, id);
    if (result != null) {
      if (result.done) {
        _stop(deleteFiles: true);
        final failed = result.error.isNotEmpty;
        state = CompareState(
          phase: failed ? ComparePhase.failed : ComparePhase.done,
          endpoint: state.endpoint,
          result: result,
          error: result.error,
          expected: state.expected,
        );
        return;
      }
      state = CompareState(
        phase: ComparePhase.running,
        endpoint: state.endpoint,
        result: result,
        expected: state.expected,
      );
    }
    if (env.now().difference(_startedAt) >= env.timeout) {
      _stop(deleteFiles: true);
      state = CompareState(
        phase: ComparePhase.timedOut,
        endpoint: state.endpoint,
        result: state.result,
        expected: state.expected,
      );
    }
  }

  void _stop({required bool deleteFiles}) {
    _timer?.cancel();
    _timer = null;
    final id = _id;
    final dir = _dir;
    _id = null;
    if (deleteFiles && id != null && dir != null) deleteCompareFiles(dir, id);
  }
}
