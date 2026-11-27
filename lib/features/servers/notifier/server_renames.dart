import 'dart:convert';

import 'package:hiddify/core/logger/logger.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: имя сервера пришло из подписки, а правила туннеля и выбранный сервер держатся за имя.
/// Когда имя в подписке поменяли, сервер узнаём по адресу и порту ([serverRenames]) и переносим
/// к новому имени всё, что было закреплено за старым. Адреса помним отдельно для каждого профиля:
/// у двух подписок одни и те же серверы могут называться по-разному.

/// Профиль и его серверы: тег → «vless|адрес:порт». null — профиля или конфига нет.
final serverEndpointsProvider = FutureProvider.autoDispose<({String profile, Map<String, String> endpoints})?>((
  ref,
) async {
  try {
    final profile = await ref.watch(activeProfileProvider.future);
    if (profile == null) return null;
    final file = ref.watch(profilePathResolverProvider).file(profile.id);
    if (!file.existsSync()) return null;
    final config = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (profile: profile.id, endpoints: endpointsOfConfig(config));
  } catch (_) {
    return null;
  }
});

String serverEndpointsKey(String profile) => 'rescue-server-endpoints-$profile';

/// Слушает ConnectionWrapper всё время работы.
final serverRenamesProvider = Provider<void>((ref) {
  final log = Logger.app;
  ref.listen(serverEndpointsProvider, (_, next) {
    final now = next.valueOrNull;
    if (now == null || now.endpoints.isEmpty) return;
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final key = serverEndpointsKey(now.profile);
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final before = (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
        final renames = serverRenames(before, now.endpoints);
        if (renames.isNotEmpty) {
          ref.read(splitTunnelProvider.notifier).renameServers(renames);
          final fixed = ref.read(FailoverPreferences.server);
          if (renames[fixed] case final to?) ref.read(FailoverPreferences.server.notifier).update(to);
          log.info('servers renamed in the subscription: ${renames.length}, pins moved');
        }
      } catch (e) {
        log.warning('server renames: unreadable saved endpoints', e);
      }
    }
    final text = jsonEncode(now.endpoints);
    if (raw != text) prefs.setString(key, text);
  }, fireImmediately: true);
});
