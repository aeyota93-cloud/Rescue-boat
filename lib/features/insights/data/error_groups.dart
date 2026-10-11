import 'package:hiddify/features/insights/model/insights_models.dart';

/// Новые сверху.
List<ErrorEvent> sortNewestFirst(Iterable<ErrorEvent> events) =>
    events.toList()..sort((a, b) => b.time.compareTo(a.time));

/// Сколько ошибок с учётом схлопнутых (поле n) и пропущенных сверх лимита. Переключения
/// основной ↔ запасной — не ошибки соединений, их не считаем.
int countErrors(Iterable<ErrorEvent> events) =>
    events.fold(0, (sum, e) => e.kind == ErrorKind.failover ? sum : sum + e.count);

/// Ключ группы «переключения сервера»: все события автопереключения — одной строкой списка.
const failoverGroupKey = 'failover:';

/// Название группы переключений в списке.
const failoverGroupTitle = 'Переключение сервера';

/// Группа переключений основной ↔ запасной (а не сайт или программа).
bool isFailoverGroup(ErrorGroup group) => group.key == failoverGroupKey;

/// Группы по сайту, а если сайт неизвестен — по программе. Частые сверху (при равенстве —
/// у кого ошибка новее), внутри группы новые события сверху. Строки «часть пропущена» в группы
/// не попадают: у них нет ни сайта, ни программы.
List<ErrorGroup> groupErrors(Iterable<ErrorEvent> events) {
  final byKey = <String, List<ErrorEvent>>{};
  for (final e in events) {
    if (e.kind == ErrorKind.suppressed) continue;
    final key = e.kind == ErrorKind.failover
        ? failoverGroupKey
        : e.host.isNotEmpty
        ? e.host.toLowerCase()
        : e.app.isNotEmpty
        ? 'app:${e.app.toLowerCase()}'
        : '';
    byKey.putIfAbsent(key, () => []).add(e);
  }

  final groups = [
    for (final MapEntry(:key, :value) in byKey.entries)
      () {
        final list = sortNewestFirst(value);
        final newest = list.first;
        final app = _mostFrequentApp(list);
        final failover = key == failoverGroupKey;
        return ErrorGroup(
          key: key,
          target: failover
              ? failoverGroupTitle
              : newest.host.isNotEmpty
              ? newest.host
              : (app.isNotEmpty ? app : 'неизвестный адрес'),
          app: app,
          route: newest.route,
          // У переключений «сколько» — число переключений, а не ошибок.
          count: failover ? list.fold(0, (s, e) => s + e.count) : countErrors(list),
          last: newest.time,
          events: list,
        );
      }(),
  ];
  groups.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : b.last.compareTo(a.last);
  });
  return groups;
}

String _mostFrequentApp(List<ErrorEvent> events) {
  final counts = <String, int>{};
  for (final e in events) {
    if (e.app.isNotEmpty) counts[e.app] = (counts[e.app] ?? 0) + e.count;
  }
  if (counts.isEmpty) return '';
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
