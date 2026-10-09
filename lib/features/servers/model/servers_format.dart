/// Шлюпка: подписи для «Подписок и серверов» — гигабайты, даты по-русски, протоколы, пинг.
library;

import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// «9 ноября».
String ruDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _two(int v) => v.toString().padLeft(2, '0');

/// «12:40» — если сегодня, иначе «9 ноября».
String updatedLabel(DateTime when, DateTime now) {
  final local = when.toLocal();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  return sameDay ? '${_two(local.hour)}:${_two(local.minute)}' : ruDate(local);
}

/// Байты → гигабайты: до 10 ГБ с одной цифрой после запятой («1,5»), дальше целые.
String formatGb(int bytes) {
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 10) return gb.round().toString();
  final s = gb.toStringAsFixed(1).replaceAll('.', ',');
  return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
}

/// Подписка без ограничения трафика (парсер ставит такое число, когда total = 0).
bool isUnlimitedTraffic(SubscriptionInfo info) => info.total > ProfileParser.infiniteTrafficThreshold;

/// Подписка без срока (парсер ставит дату далеко в будущем, когда expire = 0).
bool isUnlimitedTime(SubscriptionInfo info) => info.expire.year >= 2200;

/// «ещё 31 день», «истекла».
String daysLeftLabel(DateTime expire, DateTime now) {
  final days = expire.difference(now).inDays;
  if (!expire.isAfter(now)) return 'истекла';
  if (days == 0) return 'меньше суток';
  return 'ещё $days ${pluralRu(days, 'день', 'дня', 'дней')}';
}

/// «сама, раз в 6 часов» / «вручную».
String autoUpdateLabel(ProfileEntity profile) {
  if (profile is! RemoteProfileEntity) return 'конфиг без ссылки';
  final hours = profile.options?.updateInterval.inHours ?? 0;
  if (hours <= 0 || (profile.userOverride?.isAutoUpdateDisable ?? false)) return 'вручную';
  return 'сама, раз в $hours ${pluralRu(hours, 'час', 'часа', 'часов')}';
}

/// Тип outbound из ядра → как его называют люди.
String protocolName(String type) => switch (type.toLowerCase()) {
  'vless' => 'VLESS',
  'vmess' => 'VMess',
  'trojan' => 'Trojan',
  'shadowsocks' || 'ss' => 'Shadowsocks',
  'shadowsocksr' => 'ShadowsocksR',
  'hysteria' => 'Hysteria',
  'hysteria2' || 'hy2' => 'Hysteria2',
  'tuic' => 'TUIC',
  'wireguard' => 'WireGuard',
  'awg' => 'AmneziaWG',
  'ssh' => 'SSH',
  'socks' => 'SOCKS',
  'http' => 'HTTP',
  'tor' => 'Tor',
  'warp' => 'WARP',
  'urltest' => 'Автовыбор',
  'selector' => 'Группа',
  'direct' => 'Напрямую',
  '' => '—',
  _ => type,
};

/// Задержка из проверки: 0 — не проверяли, больше 65000 — нет ответа.
bool pingTimedOut(int delay) => delay > 65000;

String pingLabel(int delay) => switch (delay) {
  <= 0 => '—',
  _ when pingTimedOut(delay) => 'нет ответа',
  _ => '$delay мс',
};

/// Доля полоски пинга: 300 мс и больше — полная.
double pingFraction(int delay) {
  if (delay <= 0) return 0;
  if (pingTimedOut(delay)) return 1;
  return (delay / 300).clamp(0.03, 1.0);
}
