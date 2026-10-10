import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Папка с наборами правил для ядра (HiddifyOptions.split-tunnel-dir).
String splitTunnelDir(Directory baseDir) => '${baseDir.path}${Platform.pathSeparator}split';

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

  /// Добавить в список. Если запись была в другом списке, она оттуда убирается.
  void add(SplitTarget target, SplitKind kind, String value) {
    final updated = state
        .withList(target.other, state.list(target.other).without(kind, value))
        .withList(target, state.list(target).withItem(kind, value));
    _set(updated);
  }

  void remove(SplitTarget target, SplitKind kind, String value) =>
      _set(state.withList(target, state.list(target).without(kind, value)));

  /// Много записей одного вида в список одним сохранением (из другого списка они убираются).
  void addAll(SplitTarget target, SplitKind kind, Iterable<String> values) {
    var into = state.list(target);
    var other = state.list(target.other);
    for (final v in values) {
      other = other.without(kind, v);
      into = into.withItem(kind, v);
    }
    _set(state.withList(target.other, other).withList(target, into));
  }

  /// «Авто»: убрать записи из обоих списков, решают общие правила.
  void removeEverywhere(SplitKind kind, Iterable<String> values) {
    var bypass = state.bypass;
    var via = state.via;
    for (final v in values) {
      bypass = bypass.without(kind, v);
      via = via.without(kind, v);
    }
    _set(SplitTunnel(bypass: bypass, via: via));
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

  void resetToDefaults() => _set(PlatformUtils.isWindows ? SplitTunnel.defaults : const SplitTunnel());

  void _set(SplitTunnel updated) {
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
      _writeAtomic(dir, 'via-vpn.json', s.via.toRuleSet());
      // Ядро rb.12+: DNS сайтов «через VPN» идёт через VPN и не режется блокировкой рекламы.
      _writeAtomic(dir, 'via-domains.json', s.via.toDomainsRuleSet());
      _writeAtomic(dir, 'bypass-vpn.json', s.bypass.toRuleSet());
      _writeAtomic(dir, 'bypass-domains.json', s.bypass.toDomainsRuleSet());
    } catch (e, st) {
      loggy.error("split tunnel: could not write rule sets", e, st);
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
