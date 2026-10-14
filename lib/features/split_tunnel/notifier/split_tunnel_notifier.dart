import 'dart:async';
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
final splitTunnelIssueProvider = StateProvider<String?>((ref) => null);

/// Шлюпка: списки «через VPN» / «мимо VPN». Каждое изменение сразу записывается в файлы
/// наборов правил, ядро их перечитывает само (без переподключения).
class SplitTunnelNotifier extends Notifier<SplitTunnel> with AppLogger {
  late Directory _baseDir;
  bool _unreadable = false;
  bool _disposed = false;

  File get _stateFile => File('${_baseDir.path}${Platform.pathSeparator}split-tunnel.json');
  File get _backupFile => File('${_stateFile.path}.bak');

  SplitTunnel _read(File file) => SplitTunnel.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);

  void _notice(String? message) {
    final notice = ref.read(splitTunnelIssueProvider.notifier);
    scheduleMicrotask(() {
      if (!_disposed) notice.state = message;
    });
  }

  @override
  SplitTunnel build() {
    _baseDir = ref.watch(appDirectoriesProvider).requireValue.baseDir;
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _unreadable = false;
    SplitTunnel state;
    if (FileSystemEntity.typeSync(_stateFile.path) != FileSystemEntityType.notFound) {
      try {
        state = _read(_stateFile);
      } catch (e, st) {
        loggy.warning("split tunnel: unreadable state", e, st);
        try {
          state = _read(_backupFile);
          _save(state);
          _notice('Правила восстановлены из резервной копии. Проверьте последние изменения.');
        } catch (_) {
          _unreadable = true;
          _notice(
            'Файл правил повреждён. Рабочие файлы VPN сохранены. Восстановите файл или верните списки по умолчанию.',
          );
          return const SplitTunnel();
        }
      }
    } else {
      state = PlatformUtils.isWindows ? SplitTunnel.defaults : const SplitTunnel();
    }
    try {
      _writeRuleSets(state);
      if (!_stateFile.existsSync()) _save(state);
    } catch (e, st) {
      loggy.error('split tunnel: could not load rules', e, st);
      _notice('Не удалось применить правила. Проверьте доступ к папке настроек.');
    }
    return state;
  }

  /// Добавить в список. Если запись была в другом месте (другой список, сервер), она оттуда убирается.
  void add(SplitTarget target, SplitKind kind, String value) => commit(state.placed(kind, value, target));

  /// Закрепить запись за сервером с тегом [tag] (меню «Через VPN ▸ Запасной 1»). Из списков и с других
  /// серверов она убирается.
  void addToServer(String tag, SplitKind kind, String value) =>
      commit(state.placed(kind, value, SplitTarget.via, server: tag));

  /// Записи [items] (любых видов) в одно место: [target] или за сервером [server] — одним
  /// сохранением. Так группа меняет путь всем своим записям.
  void placeAll(Iterable<SplitRef> items, SplitTarget target, {String? server}) {
    var updated = state;
    for (final i in items) {
      updated = updated.placed(i.kind, i.value, target, server: server);
    }
    commit(updated);
  }

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
  void resetToDefault(SplitKind kind, Iterable<String> values) =>
      resetAllToDefault([for (final v in values) (kind: kind, value: v)]);

  /// [resetToDefault] для записей разных видов одним сохранением («Авто» у группы).
  void resetAllToDefault(Iterable<SplitRef> items) => setPlace(items, autoPlace);

  /// Записи [items] — в место [place] одним сохранением: «Авто» (как [resetAllToDefault]),
  /// мимо, через VPN или за сервер.
  void setPlace(Iterable<SplitRef> items, SplitPlace place) => commit(_placedAll(state, items, place));

  /// Добавить записи: место [place] и, если задана, группа [group] (нет такой — создаётся).
  /// Окно «Добавить»: всё одним сохранением.
  bool addItems(Iterable<SplitRef> items, SplitPlace place, {String? group}) {
    final list = items.toList();
    var updated = _placedAll(state, list, place);
    if (group != null && group.trim().isNotEmpty) updated = updated.inGroup(group, list);
    return commit(updated);
  }

  static SplitTunnel _placedAll(SplitTunnel from, Iterable<SplitRef> items, SplitPlace place) {
    var updated = from;
    for (final i in items) {
      if (place.target case final target?) {
        updated = updated.placed(i.kind, i.value, target, server: place.server);
      } else {
        final game = i.kind == SplitKind.app && defaultBypassApps.any((d) => sameItem(i.kind, d, i.value));
        updated = game ? updated.placed(i.kind, i.value, SplitTarget.bypass) : updated.without(i.kind, i.value);
      }
    }
    return updated;
  }

  /// Записи — в группу [name] (нет такой — создаётся). Пути не меняются.
  void moveToGroup(String name, Iterable<SplitRef> items) => commit(state.inGroup(name, items));

  /// Записи — из групп. Пути не меняются.
  void removeFromGroup(Iterable<SplitRef> items) => commit(state.outOfGroups(items));

  void renameGroup(String from, String to) => commit(state.renameGroup(from, to));

  /// Удалить группу; записи остаются в списках, где были.
  void deleteGroup(String name) => commit(state.withoutGroup(name));

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
    var updated = state;
    final skipped = <String>[];
    for (final raw in text.split(RegExp(r'[\r\n,;]+'))) {
      if (raw.trim().isEmpty) continue;
      final item = parseSplitItem(raw);
      if (item == null) {
        skipped.add(raw.trim());
        continue;
      }
      if (!updated.list(target).contains(item.kind, item.value)) added++;
      updated = updated.placed(item.kind, item.value, target);
    }
    return (added: commit(updated) ? added : 0, skipped: skipped);
  }

  void resetToDefaults() {
    final wasUnreadable = _unreadable;
    _unreadable = false;
    if (!commit(PlatformUtils.isWindows ? SplitTunnel.defaults : const SplitTunnel())) _unreadable = wasUnreadable;
  }

  /// Новое состояние: сохранить и выгрузить наборы правил. В тестах подменяется.
  @protected
  bool commit(SplitTunnel updated) {
    if (_unreadable) {
      _notice('Изменения не сохранены: сначала восстановите повреждённый файл правил.');
      return false;
    }
    final previous = state;
    try {
      _writeRuleSets(updated);
      _save(updated);
      state = updated;
      _notice(null);
      return true;
    } catch (e, st) {
      loggy.error('split tunnel: could not commit rules', e, st);
      var restored = true;
      try {
        _writeRuleSets(previous);
      } catch (rollbackError, rollbackStack) {
        restored = false;
        loggy.error('split tunnel: could not restore exported rules', rollbackError, rollbackStack);
      }
      _notice(
        restored
            ? 'Не удалось сохранить и применить правила. Изменение отменено; проверьте доступ к папке настроек.'
            : 'Не удалось сохранить правила и полностью восстановить рабочие файлы. Проверьте доступ к папке настроек и переподключите VPN.',
      );
      return false;
    }
  }

  void _save(SplitTunnel s) {
    final text = const JsonEncoder.withIndent('  ').convert(s.toJson());
    String? previous;
    if (_stateFile.existsSync()) {
      try {
        _read(_stateFile);
        previous = _stateFile.readAsStringSync();
      } catch (_) {
        // Повреждённый основной файл не должен затереть рабочую резервную копию.
      }
    }
    if (previous != null || !_backupFile.existsSync()) _writeTextAtomic(_backupFile, previous ?? text);
    _writeTextAtomic(_stateFile, text);
  }

  void _writeRuleSets(SplitTunnel s) {
    final dir = Directory(splitTunnelDir(_baseDir));
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
    _writeTextAtomic(target, text);
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
