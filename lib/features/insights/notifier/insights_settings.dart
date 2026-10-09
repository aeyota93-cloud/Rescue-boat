import 'dart:io';

import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/insights/data/stats_reader.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

/// Шлюпка: что ядро собирает в папку статистики. По умолчанию всё включено.
abstract class InsightsPreferences {
  static final collectErrors = PreferencesNotifier.create<bool, bool>("rescue-collect-errors", true);
  static final measurePing = PreferencesNotifier.create<bool, bool>("rescue-measure-ping", true);
}

final insightsSettingsProvider = NotifierProvider<InsightsSettingsNotifier, InsightsSettings>(
  InsightsSettingsNotifier.new,
);

/// «Собирать ошибки соединений» и «Замерять пинг» одним значением; переключатели сохраняются сразу.
class InsightsSettingsNotifier extends Notifier<InsightsSettings> {
  @override
  InsightsSettings build() => InsightsSettings(
    collectErrors: ref.watch(InsightsPreferences.collectErrors),
    measurePing: ref.watch(InsightsPreferences.measurePing),
  );

  Future<void> setCollectErrors(bool value) => ref.read(InsightsPreferences.collectErrors.notifier).update(value);

  Future<void> setMeasurePing(bool value) => ref.read(InsightsPreferences.measurePing.notifier).update(value);
}

/// Значение HiddifyOptions.rescue-stats-dir: путь к папке (она создаётся заранее), если включён
/// хоть какой-то сбор, иначе null — ядро ничего не пишет и не замеряет.
String? rescueStatsDirOption(Directory baseDir, InsightsSettings settings) {
  if (!settings.anyEnabled) return null;
  final dir = rescueStatsDir(baseDir);
  try {
    Directory(dir).createSync(recursive: true);
  } catch (e, st) {
    Loggy("insights").error("could not create stats dir", e, st);
  }
  return dir;
}
