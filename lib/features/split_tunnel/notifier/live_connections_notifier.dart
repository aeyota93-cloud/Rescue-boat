import 'dart:async';

import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: соединения «сейчас в сети» для таблицы раздельного туннеля.
///
/// Опрос Clash API раз в 2 с, пока провайдер кто-то слушает (страница открыта и видна).
/// Закрывшееся соединение держим 60 с, иначе короткие запросы не успеть увидеть.
/// null — ядро не запущено или API недоступен.
final liveConnectionsProvider = StreamProvider.autoDispose<List<NetConnection>?>((ref) {
  const interval = Duration(seconds: 2);
  const keep = Duration(seconds: 60);
  final port = ref.watch(ConfigOptions.clashApiPort);
  final controller = StreamController<List<NetConnection>?>();
  final seen = <String, (NetConnection, DateTime)>{};
  var active = true;
  var busy = false;

  Future<void> poll() async {
    if (busy) return;
    busy = true;
    try {
      final list = await fetchConnections(port);
      if (!active) return;
      final now = DateTime.now();
      for (final c in list ?? const <NetConnection>[]) {
        seen['${c.exe}|${c.host.isNotEmpty ? c.host : c.ip}|${c.port}'] = (c, now);
      }
      seen.removeWhere((_, s) => now.difference(s.$2) > keep);
      controller.add(list == null && seen.isEmpty ? null : [for (final s in seen.values) s.$1]);
    } finally {
      busy = false;
    }
  }

  unawaited(poll());
  final timer = Timer.periodic(interval, (_) => poll());
  ref.onDispose(() {
    active = false;
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});
