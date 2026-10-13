import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Папка с наборами правил для ядра (HiddifyOptions.split-tunnel-dir).
String splitTunnelDir(Directory baseDir) => '${baseDir.path}${Platform.pathSeparator}split';

/// Имя файла пунктов сервера с ключом [key] (см. serverKey).
String viaServerFile(String key) => 'via-server-$key.json';

final splitTunnelProvider = NotifierProvider<SplitTunnelNotifier, SplitTunnel>(SplitTunnelNotifier.new);

/// Шлюпка: списки «через VPN» / «мимо VPN». Каждое изменение сразу записывается в файлы
/// наборов правил, ядро их перечитывает само (без переподключения).
class SplitTunnelNotifier extends Notifier<SplitTunnel> with AppLogger {
  late Directory _baseDir;

  File get _stateFile => File('${_baseDir.path}${Platform.pathSeparator}split-tunnel.json');

  @override
  SplitTunnel build() {
    _baseDir = ref.watch(appDirectoriesProvider).requireValue.baseDir;
    SplitTunnel state;
    if (_stateFile.existsSync()) {
      try {
        state = SplitTunnel.fromJson(jsonDecode(_stateFile.readAsStringSync()) as Map<String, dynamic>);
      } catch (e, st) {
        loggy.warning("split tunnel: unreadable state, starting empty", e, st);
        state = const SplitTunnel();
      }
    } else {
      state = PlatformUtils.isWindows ? SplitTunnel.defaults : const SplitTunnel();
    }
    _writeRuleSets(state);
    if (!_stateFile.existsSync()) _save(state);
    return state;
  }

  /// Добавить в список. Если запись была в другом месте (другой список, сервер), она оттуда убирается.
  void add(SplitTarget target, SplitKind kind, String value) => commit(state.placed(kind, value, target));

  /// Закрепить запись за сервером с тегом [tag] (меню «Через VPN ▸ Запасной 1»). Из списков и с других
  /// серверов она убирается.
  void addToServer(String tag, SplitKind kind, String value) =>
      commit(state.placed(kind, value, SplitTarget.via, server: tag));

  void remove(SplitTarget target, SplitKind kind, String value) =>
      commit(state.withList(target, state.list(target).without(kind, value)));

  /// Много записей одного вида в список одним сохранением (из другого списка они убираются).
  void addAll(SplitTarget target, SplitKind kind, Iterable<String> values) {
    var updated = state;
    for (final v in values) {
      updated = updated.placed(kind, v, target);
    }
    commit(updated);
  }

  /// «Авто» в таблице туннеля: как по умолчанию. Обычные записи убираются из обоих списков
  /// (решают общие правила), а игры из стандартного списка снова идут мимо VPN — иначе их
  /// зарубежные серверы уходили бы в VPN.
  void resetToDefault(SplitKind kind, Iterable<String> values) {
    final games = values.where((v) => kind == SplitKind.app && defaultBypassApps.any((d) => sameItem(kind, d, v)));
    removeEverywhere(kind, values.where((v) => !games.contains(v)).toList());
    if (games.isNotEmpty) addAll(SplitTarget.bypass, kind, games.toList());
  }

  /// Убрать записи из обоих списков и с серверов.
  void removeEverywhere(SplitKind kind, Iterable<String> values) {
    var updated = state;
    for (final v in values) {
      updated = updated.without(kind, v);
    }
    commit(updated);
  }

  /// Вставка блоком: каждая строка (или элемент через запятую) распознаётся сама.
  /// Возвращает число добавленных и список нераспознанных строк.
  ({int added, List<String> skipped}) addMany(SplitTarget target, String text) {
    var added = 0;
    final skipped = <String>[];
    for (final raw in text.split(RegExp(r'[\r\n,;]+'))) {
      if (raw.trim().isEmpty) continue;
      final item = parseSplitItem(raw);
      if (item == null) {
        skipped.add(raw.trim());
        continue;
      }
      if (!state.list(target).contains(item.kind, item.value)) added++;
      add(target, item.kind, item.value);
    }
    return (added: added, skipped: skipped);
  }

  void resetToDefaults() => commit(PlatformUtils.isWindows ? SplitTunnel.defaults : const SplitTunnel());

  /// Новое состояние: сохранить и выгрузить наборы правил. В тестах подменяется.
  @protected
  void commit(SplitTunnel updated) {
    state = updated;
    _save(updated);
    _writeRuleSets(updated);
  }

  void _save(SplitTunnel s) {
    try {
      _stateFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(s.toJson()));
    } catch (e, st) {
      loggy.error("split tunnel: could not save state", e, st);
    }
  }

  void _writeRuleSets(SplitTunnel s) {
    final dir = Directory(splitTunnelDir(_baseDir));
    try {
      dir.createSync(recursive: true);
      // «Через VPN» — это «Авто» вместе со всеми серверными пунктами: пропал сервер из подписки —
      // его пункты идут через «Авто», а не мимо VPN.
      final via = s.viaAll;
      _writeAtomic(dir, 'via-vpn.json', via.toRuleSet());
      // Ядро rb.12+: DNS сайтов «через VPN» идёт через VPN и не режется блокировкой рекламы.
      _writeAtomic(dir, 'via-domains.json', via.toDomainsRuleSet());
      _writeAtomic(dir, 'bypass-vpn.json', s.bypass.toRuleSet());
      _writeAtomic(dir, 'bypass-domains.json', s.bypass.toDomainsRuleSet());
      _writeServerRuleSets(dir, s);
    } catch (e, st) {
      loggy.error("split tunnel: could not write rule sets", e, st);
    }
  }

  /// `via-server-<key>.json` для каждого сервера с пунктами. У серверов, с которых пункты убрали,
  /// файл перезаписывается пустым (а не удаляется), чтобы ядро перечитало его и сняло правила.
  void _writeServerRuleSets(Directory dir, SplitTunnel s) {
    final wanted = {for (final e in s.servers.entries) viaServerFile(serverKey(e.key)): e.value};
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (RegExp(r'^via-server-[0-9a-f]{12}\.json$').hasMatch(name) && !wanted.containsKey(name)) {
        _writeAtomic(dir, name, const SplitList().toRuleSet());
      }
    }
    for (final e in wanted.entries) {
      _writeAtomic(dir, e.key, e.value.toRuleSet());
    }
  }

  // Через временный файл: ядро следит за файлом и не должно прочитать его наполовину записанным.
  void _writeAtomic(Directory dir, String name, Map<String, dynamic> content) {
    final target = File('${dir.path}${Platform.pathSeparator}$name');
    final text = const JsonEncoder.withIndent('  ').convert(content);
    if (target.existsSync() && target.readAsStringSync() == text) return;
    final tmp = File('${target.path}.tmp')..writeAsStringSync(text, flush: true);
    tmp.renameSync(target.path);
  }
}
