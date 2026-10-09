import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/insights/data/stats_reader.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/insights/notifier/insights_settings.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDirectories extends AppDirectories {
  _FakeDirectories(this.dir);

  final Directory dir;

  @override
  Future<Directories> build() async => (baseDir: dir, workingDir: dir, tempDir: dir);
}

void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() => dir = Directory.systemTemp.createTempSync('insights_providers_'));
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> start([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => sp),
        appDirectoriesProvider.overrideWith(() => _FakeDirectories(dir)),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(appDirectoriesProvider.future);
    return container;
  }

  Map<String, dynamic> coreJson() =>
      jsonDecode(jsonEncode(container.read(ConfigOptions.singboxConfigOptions).toJson())) as Map<String, dynamic>;

  /// Ждём, пока провайдер дочитает файлы.
  Future<T> settle<T>(ProviderListenable<AsyncValue<T>> provider) async {
    container.listen(provider, (_, _) {});
    for (var i = 0; i < 200; i++) {
      final v = container.read(provider);
      if (v.hasValue && !v.isLoading) return v.requireValue;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('провайдер не дочитал файлы');
  }

  group('rescue-stats-dir в настройках ядра', () {
    test('по умолчанию сбор включён: путь есть, папка создана', () async {
      await start();
      expect(container.read(insightsSettingsProvider), const InsightsSettings());
      final json = coreJson();
      expect(json['rescue-stats-dir'], rescueStatsDir(dir));
      expect(Directory(rescueStatsDir(dir)).existsSync(), isTrue);
    });

    test('сбор выключен — ключа нет', () async {
      await start({'rescue-collect-errors': false, 'rescue-measure-ping': false});
      expect(coreJson().containsKey('rescue-stats-dir'), isFalse);
    });

    test('переключатели сразу меняют настройку ядра', () async {
      await start();
      final settings = container.read(insightsSettingsProvider.notifier);
      await settings.setMeasurePing(false);
      expect(coreJson().containsKey('rescue-stats-dir'), isTrue, reason: 'ошибки ещё собираются');
      await settings.setCollectErrors(false);
      expect(
        container.read(insightsSettingsProvider),
        const InsightsSettings(collectErrors: false, measurePing: false),
      );
      expect(coreJson().containsKey('rescue-stats-dir'), isFalse);
    });
  });

  group('провайдеры на файлах', () {
    final now = DateTime.now();

    void append(String prefix, DateTime t, Map<String, Object?> record) {
      final f = File('${rescueStatsDir(dir)}/${statsFileName(prefix, t)}')..parent.createSync(recursive: true);
      f.writeAsStringSync('${jsonEncode({'v': 1, 't': t.millisecondsSinceEpoch, ...record})}\n', mode: FileMode.append);
    }

    setUp(() {
      final m5 = now.subtract(const Duration(minutes: 5));
      final h3 = now.subtract(const Duration(hours: 3));
      append('errors', h3, {'kind': 'timeout', 'app': 'steam.exe', 'route': 'direct'});
      append('errors', m5, {'kind': 'reset', 'host': 'kinopoisk.ru', 'app': 'chrome.exe', 'n': 3});
      append('quality', m5, {
        'type': 'probe',
        'path': 'vpn',
        'samples': [50, 50, 50, 50, 50],
      });
      append('quality', m5, {'type': 'counters', 'conns': 10, 'errs': 0, 'dns_ok': 5, 'dns_fail': 0});
    });

    test('ошибки, группы, счётчик', () async {
      await start();
      expect((await settle(errorEventsProvider(InsightsPeriod.hour))).single.host, 'kinopoisk.ru');
      final day = await settle(errorEventsProvider(InsightsPeriod.day));
      expect(day.map((e) => e.kind), [ErrorKind.reset, ErrorKind.timeout], reason: 'новые сверху');
      final groups = await settle(errorGroupsProvider(InsightsPeriod.day));
      expect(groups.map((g) => g.target), ['kinopoisk.ru', 'steam.exe']);
      container.listen(errorCountProvider(const Duration(hours: 1)), (_, _) {});
      expect(container.read(errorCountProvider(const Duration(hours: 1))), 3);
    });

    test('здоровье и история', () async {
      await start();
      final health = await settle(healthProvider);
      expect(health.overall.score, 100);
      expect(health.pingMs, 50);
      final history = await settle(healthHistoryProvider);
      expect(history, hasLength(30));
      expect(history.where((d) => d.score != null).single.score, 100);
    });

    test('сбор выключен — пусто', () async {
      await start({'rescue-collect-errors': false, 'rescue-measure-ping': false});
      expect(await settle(errorEventsProvider(InsightsPeriod.week)), isEmpty);
      expect(await settle(healthProvider), same(HealthSnapshot.empty));
      container.listen(errorCountProvider(const Duration(days: 7)), (_, _) {});
      expect(container.read(errorCountProvider(const Duration(days: 7))), 0);
    });

    test('экраны могут подменить провайдеры готовыми данными', () {
      container = ProviderContainer(
        overrides: [
          errorEventsProvider.overrideWith((ref, period) => const AsyncData([])),
          healthProvider.overrideWith((ref) => AsyncData(HealthSnapshot.empty)),
          errorCountProvider.overrideWith((ref, window) => 7),
        ],
      );
      expect(container.read(errorCountProvider(const Duration(hours: 1))), 7);
      expect(container.read(healthProvider).requireValue.isEmpty, isTrue);
      expect(container.read(errorGroupsProvider(InsightsPeriod.day)).requireValue, isEmpty);
    });
  });
}
