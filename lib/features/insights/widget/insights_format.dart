import 'package:flutter/material.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

/// Шлюпка: общие подписи для Обзора, Ошибок и трея (даты по-русски без intl-локали).

const _monthsShort = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
const _monthsLong = [
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

String _two(int v) => v.toString().padLeft(2, '0');

/// «20:41».
String hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// «20:41:03».
String hhmmss(DateTime t) => '${hhmm(t)}:${_two(t.second)}';

/// «9 окт».
String dayMonthShort(DateTime t) => '${t.day} ${_monthsShort[t.month - 1]}';

/// «9 ноября».
String dayMonthLong(DateTime t) => '${t.day} ${_monthsLong[t.month - 1]}';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Время события: сегодня — «20:41», иначе «9 окт 20:41».
String eventTime(DateTime t, DateTime now) => sameDay(t, now) ? hhmm(t) : '${dayMonthShort(t)} ${hhmm(t)}';

/// «1 ошибка», «3 ошибки», «7 ошибок».
String plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

String errorsWord(int n) => plural(n, 'ошибка', 'ошибки', 'ошибок');

/// «за час», «за сутки», «за неделю».
String periodPhrase(InsightsPeriod p) => switch (p) {
  InsightsPeriod.hour => 'за час',
  InsightsPeriod.day => 'за сутки',
  InsightsPeriod.week => 'за неделю',
};

/// Метка пути в таблицах: «VPN» / «мимо» / «блок».
Widget routeTag(ErrorRoute route) => RescueBadge.tag(
  label: route.short,
  semanticLabel: route.long,
  kind: switch (route) {
    ErrorRoute.vpn => RescueBadgeKind.soft,
    ErrorRoute.direct => RescueBadgeKind.bypass,
    ErrorRoute.block => RescueBadgeKind.important,
  },
);

/// Что случилось — одной строкой: вид ошибки, длина замирания, сколько раз подряд.
String eventWhat(ErrorEvent e) {
  final parts = [e.kind.title];
  if (e.kind == ErrorKind.stall && e.gapMs > 0) {
    parts.add('на ${(e.gapMs / 1000).toStringAsFixed(1).replaceAll('.', ',')} с');
  }
  if (e.count > 1) parts.add('×${e.count}');
  return parts.join(' ');
}

/// Моноширинный текст: время в таблицах, сырые строки ядра. Шрифты Windows, ничего не вшиваем.
const monoStyle = TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: ['Cascadia Mono', 'Courier New', 'monospace'],
  fontSize: 12,
  color: RescueColors.textSecondary,
);

/// Вид ошибки коротко — для подписей строк: «сброс», «таймаут».
String kindShort(ErrorKind kind) => switch (kind) {
  ErrorKind.timeout => 'таймаут',
  ErrorKind.reset => 'сброс',
  ErrorKind.refused => 'отказ',
  ErrorKind.dns => 'DNS',
  ErrorKind.tls => 'TLS',
  ErrorKind.eof => 'закрылось сразу',
  ErrorKind.stall => 'замирание',
  ErrorKind.other => 'другое',
  ErrorKind.suppressed => 'пропущено',
};

/// Самый частый вид ошибки в группе (с учётом схлопнутых n).
ErrorKind mainKind(ErrorGroup group) {
  final counts = <ErrorKind, int>{};
  for (final e in group.events) {
    if (e.kind == ErrorKind.suppressed) continue;
    counts[e.kind] = (counts[e.kind] ?? 0) + e.count;
  }
  if (counts.isEmpty) return ErrorKind.other;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Буква для плитки строки: первая буква сайта (без «www.») или программы; IP — «#».
String tileLetter(String target) {
  final t = target.trim().toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (t.isEmpty) return '?';
  if (RegExp(r'^[\d.:\[\]a-f]+$').hasMatch(t) && RegExp(r'\d').hasMatch(t) && !RegExp('[g-z]').hasMatch(t)) {
    return '#';
  }
  return t.characters.first.toUpperCase();
}

/// Подпись группы: «chrome.exe · сброс · VPN»; без сайта — «сайт неизвестен · …».
String groupSubtitle(ErrorGroup group) {
  final byApp = group.key.startsWith('app:');
  final who = byApp ? 'сайт неизвестен' : (group.app.isEmpty ? 'программа неизвестна' : group.app);
  return '$who · ${kindShort(mainKind(group))} · ${group.route.long}';
}
