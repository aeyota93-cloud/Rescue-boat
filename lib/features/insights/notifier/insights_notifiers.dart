import 'dart:async';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/data/health_score.dart';
import 'package:hiddify/features/insights/data/stats_reader.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_settings.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

// Шлюпка: ошибки соединений и «Здоровье подключения» из файлов ядра (<baseDir>/stats).
// Файлы читаются, пока провайдер кто-то слушает (экран, трей), и затем раз в 10 с.
// Никаких сетевых запросов.

const insightsRefreshInterval = Duration(seconds: 10);

/// Окно «Здоровья» плюс прошлые сутки для тренда.
const _healthLookback = Duration(hours: 48);
const _historyDays = 30;

/// Один читатель на всё приложение: в нём кэш разобранных файлов.
final insightsReaderProvider = Provider<StatsReader>(
  (ref) => StatsReader(rescueStatsDir(ref.watch(appDirectoriesProvider).requireValue.baseDir)),
);

/// Текущее время; в тестах подменяется.
final insightsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ошибки за час/сутки/неделю, новые сверху.
final errorEventsProvider = Provider.autoDispose.family<AsyncValue<List<ErrorEvent>>, InsightsPeriod>(
  (ref, period) => ref.watch(_errorsSourceProvider(period.duration)),
);

/// Группы по сайту (или программе, если сайт неизвестен), частые сверху.
final errorGroupsProvider = Provider.autoDispose.family<AsyncValue<List<ErrorGroup>>, InsightsPeriod>(
  (ref, period) => ref.watch(errorEventsProvider(period)).whenData(groupErrors),
);

/// Сколько ошибок за последний промежуток (для меню и трея); пока файлы читаются — 0.
final errorCountProvider = Provider.autoDispose.family<int, Duration>(
  (ref, window) => countErrors(ref.watch(_errorsSourceProvider(window)).valueOrNull ?? const []),
);

/// «Здоровье подключения» за 24 часа; нет замеров — HealthSnapshot.empty.
final healthProvider = Provider.autoDispose<AsyncValue<HealthSnapshot>>(
  (ref) => ref
      .watch(_qualitySourceProvider(_healthLookback))
      .whenData((records) => computeHealth(records, ref.read(insightsClockProvider)())),
);

/// Оценка по дням за 30 дней, старые первыми; дни без замеров — score == null.
final healthHistoryProvider = Provider.autoDispose<AsyncValue<List<DailyHealth>>>(
  (ref) => ref
      .watch(_qualitySourceProvider(const Duration(days: _historyDays)))
      .whenData((records) => computeHistory(records, ref.read(insightsClockProvider)())),
);

final _errorsSourceProvider = AsyncNotifierProvider.autoDispose.family<_ErrorsSource, List<ErrorEvent>, Duration>(
  _ErrorsSource.new,
);

final _qualitySourceProvider = AsyncNotifierProvider.autoDispose.family<_QualitySource, List<QualityRecord>, Duration>(
  _QualitySource.new,
);

/// Ошибки за последние arg, новые сверху. Сбор выключен — пусто.
class _ErrorsSource extends AutoDisposeFamilyAsyncNotifier<List<ErrorEvent>, Duration> {
  @override
  Future<List<ErrorEvent>> build(Duration arg) {
    if (!ref.watch(insightsSettingsProvider).collectErrors) return Future.value(const []);
    _poll(ref, _load, (v) => state = AsyncData(v));
    return _load();
  }

  Future<List<ErrorEvent>> _load() async {
    final now = ref.read(insightsClockProvider)();
    return sortNewestFirst(await ref.read(insightsReaderProvider).errors(now.subtract(arg), now));
  }
}

/// Замеры и счётчики за последние arg. Замеры выключены — пусто (экраны пишут «Нет данных»).
class _QualitySource extends AutoDisposeFamilyAsyncNotifier<List<QualityRecord>, Duration> {
  @override
  Future<List<QualityRecord>> build(Duration arg) {
    if (!ref.watch(insightsSettingsProvider).measurePing) return Future.value(const []);
    _poll(ref, _load, (v) => state = AsyncData(v));
    return _load();
  }

  Future<List<QualityRecord>> _load() {
    final now = ref.read(insightsClockProvider)();
    return ref.read(insightsReaderProvider).quality(now.subtract(arg), now);
  }
}

/// Перечитывать раз в insightsRefreshInterval. Таймер отменяется при dispose и перестройке,
/// результат чтения, закончившегося после этого, выбрасывается.
void _poll<T>(Ref ref, Future<T> Function() load, void Function(T) set) {
  var active = true;
  var busy = false;
  final timer = Timer.periodic(insightsRefreshInterval, (_) async {
    if (busy) return;
    busy = true;
    try {
      final value = await load();
      if (active) set(value);
    } catch (e, st) {
      Loggy("insights").warning("could not read stats", e, st);
    } finally {
      busy = false;
    }
  });
  ref.onDispose(() {
    active = false;
    timer.cancel();
  });
}
