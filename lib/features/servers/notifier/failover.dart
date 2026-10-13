import 'dart:async';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: автопереключение «основной → запасной» (договор — docs/redesign/failover.md).
abstract class FailoverPreferences {
  /// «Переключаться на запасной автоматически». По умолчанию включено.
  static final auto = PreferencesNotifier.create<bool, bool>("rescue-failover", true);
}

/// Значение HiddifyOptions.rescue-failover: true — сторож ядра работает, null — ключа нет.
/// Сколько серверов в профиле, ядро проверяет само.
bool? rescueFailoverOption(bool enabled) => enabled ? true : null;

/// Серверы активной подписки в порядке подписки: первый — основной, второй — запасной.
class FailoverServers {
  const FailoverServers({required this.servers, required this.selected});

  /// Только настоящие серверы (без групп «Автовыбор» и балансировщика), не меньше двух.
  final List<OutboundInfo> servers;

  /// Куда сейчас смотрит выход `select`.
  final String selected;

  OutboundInfo get main => servers.first;

  /// Тот, кого показываем в карточке «Запасной».
  OutboundInfo get backup => servers[1];

  /// Карточка «Запасной»: этот сервер выбран сейчас.
  bool get backupInUse => selected == backup.tag;

  /// Выбран сервер, но не основной (первый) — работаем через запасной.
  bool get onBackup => selected != main.tag && servers.any((s) => s.tag == selected);
}

/// null — в подписке меньше двух серверов (или список ещё не пришёл от ядра).
///
/// [order] — теги в порядке подписки (список на экране может быть отсортирован по пингу);
/// пусто — берём порядок [group] как есть.
FailoverServers? failoverServersOf(OutboundGroup? group, [List<String> order = const []]) {
  if (group == null) return null;
  final servers = group.items.where((e) => !e.isGroup).toList();
  if (servers.length < 2) return null;
  if (order.isNotEmpty) {
    int pos(OutboundInfo e) {
      final i = order.indexOf(e.tag);
      return i < 0 ? order.length : i;
    }

    final indexed = servers.indexed.toList()
      ..sort((a, b) {
        final byOrder = pos(a.$2).compareTo(pos(b.$2));
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    servers
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
  }
  return FailoverServers(servers: servers, selected: group.selected);
}

/// Серверы для карточки «Запасной» и пометки на Главной; null — запасного нет или VPN выключен.
final failoverServersProvider = Provider.autoDispose<FailoverServers?>((ref) {
  final group = ref.watch(proxiesOverviewNotifierProvider).valueOrNull;
  return failoverServersOf(group, ref.read(proxiesOverviewNotifierProvider.notifier).subscriptionOrder);
});

/// Пометка «работаем через запасной» на Главной: автопереключение включено и выбран не основной.
final failoverOnBackupProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(FailoverPreferences.auto) && (ref.watch(failoverServersProvider)?.onBackup ?? false),
);

/// Пометка на Главной: «работаем через запасной 2»; null — пометки нет.
final failoverNoteProvider = Provider.autoDispose<String?>((ref) {
  if (!ref.watch(FailoverPreferences.auto)) return null;
  final servers = ref.watch(rescueServersProvider);
  final current = servers == null || !servers.live ? null : servers.current;
  return current == null || current.index == 0 ? null : 'работаем через ${current.lowerName}';
});

/// Где хранится последний известный список серверов (теги, типы, имена из подписки).
const lastServersKey = 'rescue-servers-last';

/// Серверы активной подписки с именами из интерфейса — общий источник для всех экранов
/// (docs/redesign/servers-v2.md). Пока VPN подключён — живой список ядра с пингом и выбором;
/// выключен — список из прошлого раза (только имена), чтобы Туннель знал, кого предлагать.
/// null — серверов не видели ни разу.
final rescueServersProvider = Provider.autoDispose<RescueServers?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  final group = ref.watch(proxiesOverviewNotifierProvider).valueOrNull;
  final live = rescueServersOf(group, ref.read(proxiesOverviewNotifierProvider.notifier).subscriptionOrder);
  if (live != null && !live.isEmpty) {
    final text = live.encode();
    if (prefs.getString(lastServersKey) != text) unawaited(prefs.setString(lastServersKey, text));
    return live;
  }
  return RescueServers.decode(prefs.getString(lastServersKey));
});
