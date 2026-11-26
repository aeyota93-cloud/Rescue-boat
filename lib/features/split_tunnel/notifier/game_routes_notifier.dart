import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/game_routes.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Игровые серверы мимо Шлюпки» (model/game_routes.dart). По умолчанию включено.
abstract class GameRoutesPreferences {
  static final enabled = PreferencesNotifier.create<bool, bool>("rescue-game-routes", true);
}

/// Как часто смотреть соединения, пока VPN включён.
const gameRoutesPollInterval = Duration(seconds: 10);

final gameRoutesProvider = NotifierProvider<GameRoutesNotifier, GameRoutes>(GameRoutesNotifier.new);

/// Держит tun-exclude.txt в актуальном виде и, пока VPN включён, запоминает адреса игр.
/// Слушает его ConnectionWrapper всё время работы программы.
class GameRoutesNotifier extends Notifier<GameRoutes> with AppLogger {
  late Directory _dir;
  late SplitTunnel _split;
  late bool _enabled;
  bool _seeding = false;

  File get _stateFile => File('${_dir.path}${Platform.pathSeparator}$gameRoutesFileName');
  File get _excludeFile => File('${_dir.path}${Platform.pathSeparator}$tunExcludeFileName');

  @override
  GameRoutes build() {
    _dir = Directory(splitTunnelDir(ref.watch(appDirectoriesProvider).requireValue.baseDir));
    _split = ref.watch(splitTunnelProvider);
    _enabled = PlatformUtils.isWindows && ref.watch(GameRoutesPreferences.enabled);
    final routes = _load();
    _writeExclude(routes);
    if (!_enabled) return routes;

    final connected = ref.watch(connectionNotifierProvider.select((s) => s.valueOrNull?.isConnected ?? false));
    if (connected) {
      final port = ref.read(ConfigOptions.clashApiPort);
      var active = true;
      var busy = false;
      final timer = Timer.periodic(gameRoutesPollInterval, (_) async {
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
    if (!routes.seeded && !_seeding) unawaited(Future(_seedFromErrors));
    return routes;
  }

  void _learn(List<NetConnection> list) {
    final now = DateTime.now();
    _update(
      state.learn([
        for (final c in list)
          if (isGameFlow(c, _split)) (c.ip, c.exe, now),
      ], now),
    );
  }

  /// Один раз: UDP-адреса игр из журнала ошибок за неделю.
  Future<void> _seedFromErrors() async {
    // ref.read до первого await: после него провайдер может быть уже пересобран.
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
      loggy.info('game routes: ${found.length} game addresses from the error log');
    } catch (e, st) {
      loggy.warning('game routes: could not read the error log', e, st);
    } finally {
      _seeding = false;
    }
  }

  void _update(GameRoutes next) {
    if (identical(next, state)) return;
    state = next;
    try {
      _writeTextAtomic(_stateFile, const JsonEncoder.withIndent('  ').convert(next.toJson()));
    } catch (e, st) {
      loggy.warning('game routes: could not save', e, st);
    }
    _writeExclude(next);
  }

  GameRoutes _load() {
    try {
      if (_stateFile.existsSync()) {
        return GameRoutes.fromJson(jsonDecode(_stateFile.readAsStringSync()) as Map<String, dynamic>);
      }
    } catch (e, st) {
      loggy.warning('game routes: unreadable state, starting over', e, st);
    }
    return const GameRoutes();
  }

  /// Ядро читает файл при подключении; пишем его при каждом изменении, чтобы он всегда был готов.
  void _writeExclude(GameRoutes routes) {
    try {
      _dir.createSync(recursive: true);
      final text = tunExcludeText(routes, _split, enabled: _enabled);
      if (_excludeFile.existsSync() && _excludeFile.readAsStringSync() == text) return;
      _writeTextAtomic(_excludeFile, text);
    } catch (e, st) {
      loggy.warning('game routes: could not write $tunExcludeFileName', e, st);
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
