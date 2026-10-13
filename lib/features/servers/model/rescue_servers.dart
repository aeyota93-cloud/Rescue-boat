/// Шлюпка: серверы активной подписки и их имена в интерфейсе (docs/redesign/servers-v2.md).
///
/// Имена — по порядку подписки, а не по remark: первый — «Основной», дальше «Запасной 1»,
/// «Запасной 2», … Так их называют все экраны: Подписки и серверы, Туннель, «Сейчас в сети»,
/// «Сравнить пути», Главная. Без виджетов, чтобы проверять тестами.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// Ключ сервера для файлов `via-server-<key>.json`: первые 12 символов hex(sha256(UTF-8 тега)),
/// строчные. Ядро считает так же (договор, пример — тег «NL запасной»).
String serverKey(String tag) => sha256.convert(utf8.encode(tag)).toString().substring(0, 12);

/// «Основной», «Запасной 1», «Запасной 2»…
String serverName(int index) => index == 0 ? 'Основной' : 'Запасной $index';

/// Подсказка под именем по типу выхода; null — без подсказки (основной на TCP).
String? serverHint(String type, int index) {
  final t = type.toLowerCase();
  if (t == 'hysteria2' || t == 'hy2' || t == 'tuic') return 'для игр и звонков';
  return index == 0 ? null : 'если основной заблокируют';
}

/// Один сервер из выхода `select` (без групп).
class RescueServer {
  const RescueServer({required this.tag, required this.index, this.type = '', this.remark = '', this.delay = 0});

  /// Тег выхода в ядре — по нему правила и выбор в `select`.
  final String tag;

  /// Место в подписке: 0 — основной.
  final int index;

  /// Тип выхода ядра (vless, hysteria2…) — только для подсказки, людям не показываем.
  final String type;

  /// Имя из подписки («🇳🇱 NL запасной»), показываем мелко рядом.
  final String remark;

  /// Пинг последней проверки: 0 — не проверяли, больше 65000 — нет ответа.
  final int delay;

  String get name => serverName(index);

  /// Для середины фразы: «через запасной 2».
  String get lowerName => name.toLowerCase();

  String? get hint => serverHint(type, index);

  String get key => serverKey(tag);

  /// Настоящее имя без флага: «NL запасной».
  String get title => serverTitle(remark.isNotEmpty ? remark : tag);

  bool get responds => delay > 0 && !pingTimedOut(delay);

  Map<String, dynamic> toJson() => {'tag': tag, 'type': type, 'remark': remark};
}

/// Серверы подписки по порядку и куда сейчас смотрит `select`.
class RescueServers {
  const RescueServers({required this.servers, this.selected = '', this.group = 'select', this.live = true});

  /// По порядку подписки; первый — основной.
  final List<RescueServer> servers;

  /// Тег, выбранный в `select` сейчас; пусто — неизвестно.
  final String selected;

  /// Тег самого выхода `select` — для ручного выбора через clash API.
  final String group;

  /// false — список из прошлого запуска (VPN выключен): имена есть, пинга и выбора нет.
  final bool live;

  bool get isEmpty => servers.isEmpty;

  /// Есть из чего выбирать: подменю «Через VPN ▸», режимы «Авто / Всегда».
  bool get several => servers.length >= 2;

  RescueServer get main => servers.first;

  RescueServer? byTag(String tag) {
    for (final s in servers) {
      if (s.tag == tag) return s;
    }
    return null;
  }

  /// Сервер, выбранный в `select`; null — выбран не сервер (группа) или неизвестно.
  RescueServer? get current => byTag(selected);

  /// Работаем не через основной.
  bool get onBackup => (current?.index ?? 0) > 0;

  /// Сколько серверов ответило на последней проверке пинга.
  int get responding => servers.where((s) => s.responds).length;

  /// Сервер, через который реально идёт соединение: элемент цепочки clash API, который
  /// является сервером. В sing-box цепочка развёрнута (первый — настоящий выход, дальше
  /// группы), поэтому ищем по тегам, а не по месту в списке. null — напрямую или не сервер.
  RescueServer? serverOfChain(List<String> chains) {
    for (final tag in chains) {
      final s = byTag(tag);
      if (s != null) return s;
    }
    return null;
  }

  /// Для сохранения между запусками (имена в Туннеле, пока VPN выключен).
  String encode() => jsonEncode([for (final s in servers) s.toJson()]);

  /// Список из прошлого запуска; null — нечего читать или испорчено.
  static RescueServers? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final list = jsonDecode(text) as List<dynamic>;
      final servers = [
        for (final (i, e) in list.cast<Map<String, dynamic>>().indexed)
          RescueServer(
            tag: e['tag'] as String,
            index: i,
            type: e['type'] as String? ?? '',
            remark: e['remark'] as String? ?? '',
          ),
      ];
      return servers.isEmpty ? null : RescueServers(servers: servers, live: false);
    } catch (_) {
      return null;
    }
  }
}

/// Серверы выхода `select` по порядку подписки, без групп («Автовыбор», балансировщик).
///
/// [order] — теги в порядке подписки (на экране список может быть отсортирован по пингу);
/// пусто — берём порядок [group] как есть. null — группы нет (VPN выключен).
RescueServers? rescueServersOf(OutboundGroup? group, [List<String> order = const []]) {
  if (group == null) return null;
  final items = group.items.where((e) => !e.isGroup).toList();
  if (order.isNotEmpty) {
    int pos(OutboundInfo e) {
      final i = order.indexOf(e.tag);
      return i < 0 ? order.length : i;
    }

    final indexed = items.indexed.toList()
      ..sort((a, b) {
        final byOrder = pos(a.$2).compareTo(pos(b.$2));
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    items
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
  }
  return RescueServers(
    servers: [
      for (final (i, e) in items.indexed)
        RescueServer(tag: e.tag, index: i, type: e.type, remark: e.tagDisplay, delay: e.urlTestDelay),
    ],
    selected: group.selected,
    group: group.tag,
  );
}
