import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/data/tun_routes.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Мимо Шлюпки» включено (model/direct_routes.dart). По умолчанию да.
abstract class DirectRoutesPreferences {
  static final enabled = PreferencesNotifier.create<bool, bool>("rescue-game-routes", true);
}

/// Как часто смотреть соединения, пока VPN включён.
const directRoutesPollInterval = Duration(seconds: 10);

/// Маршруты туннеля в Windows; в тестах подменяется.
final tunRoutesProvider = Provider<TunRoutes>((ref) => WindowsTunRoutes());

/// Что получило ядро при подключении или последнее «Применить сейчас»; null — VPN выключен.
/// Отличается от [DirectRoutesNotifier.effectiveNow] — есть изменения, которые ещё не действуют.
final directAppliedProvider = StateProvider<List<V4Net>?>((ref) => null);

/// Итоговый список прямо сейчас (с учётом «мимо VPN» и выключателя).
final directEffectiveProvider = Provider<List<V4Net>>((ref) {
  final routes = ref.watch(directRoutesProvider);
  final enabled = ref.watch(directRoutesEnabledProvider);
  return routes.effective(ref.watch(splitTunnelProvider), enabled: enabled);
});

/// Включено и работает на этой системе (только Windows: маршруты туннеля — её таблица).
final directRoutesEnabledProvider = Provider<bool>(
  (ref) => PlatformUtils.isWindows && ref.watch(DirectRoutesPreferences.enabled),
);

final directRoutesProvider = NotifierProvider<DirectRoutesNotifier, DirectRoutes>(DirectRoutesNotifier.new);

/// Держит tun-exclude.txt в актуальном виде, пока VPN включён — запоминает адреса игр, и
/// умеет применить список сразу ([applyNow]). Слушает его ConnectionWrapper всё время работы.
class DirectRoutesNotifier extends Notifier<DirectRoutes> with AppLogger {
  late Directory _dir;
  bool _seeding = false;
  bool _applying = false;
  bool _wasConnected = false;

  File _file(String name) => File('${_dir.path}${Platform.pathSeparator}$name');

  @override
  DirectRoutes build() {
    _dir = Directory(splitTunnelDir(ref.watch(appDirectoriesProvider).requireValue.baseDir));
    final routes = _load();
    // Файл для ядра — при каждом изменении списка, «мимо VPN» или выключателя: к подключению он готов.
    // (Свой расчёт, а не directEffectiveProvider: тот зависит от этого провайдера.)
    final split = ref.watch(splitTunnelProvider);
    final enabled = ref.watch(directRoutesEnabledProvider);
    _writeExclude(routes.effective(split, enabled: enabled));

    final status = ref.watch(connectionNotifierProvider.select((s) => s.valueOrNull));
    final connected = status?.isConnected ?? false;
    if (connected && !_wasConnected) {
      // Ядро только что прочитало файл: это и есть действующий список.
      final applied = routes.effective(split, enabled: enabled);
      Future(() => ref.read(directAppliedProvider.notifier).state = applied);
    } else if (status is Disconnected) {
      Future(() => ref.read(directAppliedProvider.notifier).state = null);
    }
    _wasConnected = connected;

    if (connected && enabled) {
      final port = ref.read(ConfigOptions.clashApiPort);
      var active = true;
      var busy = false;
      final timer = Timer.periodic(directRoutesPollInterval, (_) async {
        if (busy) return;
        busy = true;
        try {
          final list = await fetchConnections(port);
          if (active && list != null) _learn(list);
        } finally {
          busy = false;
        }
      });
      ref.onDispose(() {
        active = false;
        timer.cancel();
      });
    }
    if (!routes.seeded && !_seeding && PlatformUtils.isWindows) unawaited(Future(_seedFromErrors));
    return routes;
  }

  SplitTunnel get _split => ref.read(splitTunnelProvider);

  // ---------- Правка списка ----------

  /// Добавить адрес или сеть. Возвращает текст ошибки или null.
  String? add(String raw) {
    final parsed = parseDirectInput(raw);
    if (parsed.net == null) return parsed.error ?? 'Введите адрес или сеть';
    _update(state.withUser(parsed.net!, DateTime.now()));
    return null;
  }

  void remove(V4Net n) => _update(state.without(n));

  void setPinned(V4Net n, bool pinned) => _update(state.withPinned(n, pinned));

  /// «Никогда мимо Шлюпки». Возвращает текст ошибки или null.
  String? addNever(String raw) {
    final parsed = parseDirectInput(raw);
    if (parsed.net == null) return parsed.error ?? 'Введите адрес или сеть';
    _update(state.withNever(parsed.net!));
    return null;
  }

  void never(V4Net n) => _update(state.withNever(n));

  void removeNever(V4Net n) => _update(state.withoutNever(n));

  /// Из «только через Шлюпку» обратно в «Мимо Шлюпки».
  void neverBack(V4Net n) => _update(state.withNeverBack(n, DateTime.now()));

  void setNets(String id, bool on) => _update(state.withNets(id, on));

  /// Добавить отобранное в меню ([directCandidates]).
  void addPicks(List<DirectPick> picks) => _update(state.withPicks(picks, DateTime.now()));

  /// Перестать следить за сайтом и убрать его запомненные адреса.
  void removeSite(String site) => _update(state.withoutSite(site));

  // ---------- Применить сейчас ----------

  /// Перестроить маршруты туннеля под текущий список, не дожидаясь переподключения.
  /// Только при включённом VPN. Возвращает текст ошибки или null.
  Future<String?> applyNow() async {
    if (_applying) return 'Уже применяется';
    // ref.read до первого await: после него провайдер может быть пересобран.
    final status = ref.read(connectionNotifierProvider).valueOrNull;
    final routes = ref.read(tunRoutesProvider);
    final target = state.effective(_split, enabled: ref.read(directRoutesEnabledProvider));
    final applied = ref.read(directAppliedProvider.notifier);
    if (status is! Connected) return 'Применить сейчас можно только при включённом VPN';
    _applying = true;
    try {
      final r = await applyTunRoutes(routes, target);
      applied.state = target;
      loggy.info('direct routes applied now: +${r.added} -${r.removed}');
      return null;
    } on TunRoutesException catch (e) {
      loggy.warning('direct routes: apply failed: $e');
      return e.message;
    } catch (e, st) {
      loggy.error('direct routes: apply failed', e, st);
      return 'Не получилось применить. Переподключите VPN — список уже сохранён.';
    } finally {
      _applying = false;
    }
  }

  // ---------- Запоминание ----------

  void _learn(List<NetConnection> list) {
    final now = DateTime.now();
    final split = _split;
    _update(
      state.learnHits([
        for (final c in list)
          if (isGameFlow(c, split)) (ip: c.ip, app: c.exe, site: '', seen: now),
        ...siteHits(list, state, now),
      ], now),
    );
  }

  /// Один раз: UDP-адреса игр из журнала ошибок за неделю.
  Future<void> _seedFromErrors() async {
    _seeding = true;
    final reader = ref.read(insightsReaderProvider);
    final split = _split;
    final now = DateTime.now();
    try {
      final errors = await reader.errors(now.subtract(const Duration(days: 7)), now);
      final found = [
        for (final e in errors)
          if (isGameError(e, split)) (e.ip, e.app, e.time),
      ];
      _update(state.learn(found, now).copyWith(seeded: true));
      loggy.info('direct routes: ${found.length} game addresses from the error log');
    } catch (e, st) {
      loggy.warning('direct routes: could not read the error log', e, st);
    } finally {
      _seeding = false;
    }
  }

  // ---------- Файлы ----------

  void _update(DirectRoutes next) {
    if (identical(next, state)) return;
    state = next;
    _writeExclude(next.effective(_split, enabled: ref.read(directRoutesEnabledProvider)));
    try {
      _writeTextAtomic(_file(directRoutesFileName), const JsonEncoder.withIndent('  ').convert(next.toJson()));
    } catch (e, st) {
      loggy.warning('direct routes: could not save', e, st);
    }
  }

  DirectRoutes _load() {
    for (final name in [directRoutesFileName, legacyGameRoutesFileName]) {
      final f = _file(name);
      try {
        if (f.existsSync()) return DirectRoutes.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      } catch (e, st) {
        loggy.warning('direct routes: unreadable $name', e, st);
      }
    }
    return const DirectRoutes();
  }

  /// Ядро читает файл при подключении.
  void _writeExclude(List<V4Net> nets) {
    try {
      _dir.createSync(recursive: true);
      final f = _file(tunExcludeFileName);
      final text = tunExcludeText(nets);
      if (f.existsSync() && f.readAsStringSync() == text) return;
      _writeTextAtomic(f, text);
    } catch (e, st) {
      loggy.warning('direct routes: could not write $tunExcludeFileName', e, st);
    }
  }

  void _writeTextAtomic(File target, String text) {
    final tmp = File('${target.path}.tmp');
    try {
      tmp.writeAsStringSync(text, flush: true);
      tmp.renameSync(target.path);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }
}

/// Есть изменения, которые ещё не действуют (VPN включён, а список другой).
bool directPending(List<V4Net>? applied, List<V4Net> effective) => applied != null && !listEquals(applied, effective);
