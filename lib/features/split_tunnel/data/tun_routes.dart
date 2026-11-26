import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';

/// Шлюпка: маршруты туннеля в Windows — для «Применить сейчас» в «Мимо Шлюпки».
///
/// Ядро при подключении ставит маршруты «весь IPv4 без списка» на интерфейс туннеля (адрес
/// 172.19.0.1, шлюз 172.19.0.2, метрика 0) и потом их не трогает: следит только за маршрутом
/// 0.0.0.0/0 других сетевых карт. Поэтому их можно перестроить на ходу: сначала добавить новые,
/// потом убрать лишние — так ни на миг не бывает дыры, через которую трафик ушёл бы мимо VPN.
/// При отключении интерфейс туннеля пропадает вместе со всеми маршрутами — хвостов не остаётся.
/// Нужны права администратора: они у Шлюпки есть, без них не работает режим VPN.
abstract class TunRoutes {
  /// Номер интерфейса туннеля и его маршруты IPv4; null — туннеля нет (VPN выключен или режим прокси).
  Future<({int index, List<V4Net> routes})?> read();

  /// Добавить [add], затем убрать [remove] на интерфейсе [index].
  Future<void> change(int index, {required List<V4Net> add, required List<V4Net> remove});
}

const tunAddress = '172.19.0.1';
const tunGateway = '172.19.0.2';

class WindowsTunRoutes implements TunRoutes {
  @override
  Future<({int index, List<V4Net> routes})?> read() async {
    // Только маршруты через шлюз туннеля: служебные (сама подсеть, 224.0.0.0/4, широковещание)
    // у Windows идут без шлюза, их не трогаем.
    const script =
        "\$ErrorActionPreference='Stop'; "
        "\$a=Get-NetIPAddress -AddressFamily IPv4 -IPAddress '$tunAddress' -ErrorAction SilentlyContinue "
        "| Select-Object -First 1; "
        "if(-not \$a){'{}';exit}; "
        "\$r=@(Get-NetRoute -AddressFamily IPv4 -InterfaceIndex \$a.InterfaceIndex -PolicyStore ActiveStore "
        "| Where-Object NextHop -eq '$tunGateway' | ForEach-Object DestinationPrefix); "
        "ConvertTo-Json -Compress @{index=\$a.InterfaceIndex;routes=\$r}";
    final res = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
    if (res.exitCode != 0) throw TunRoutesException('Не удалось прочитать маршруты: ${res.stderr}'.trim());
    final json = jsonDecode((res.stdout as String).trim()) as Map<String, dynamic>;
    final index = json['index'];
    if (index is! int) return null;
    final raw = json['routes'];
    final list = raw is List ? raw : (raw == null ? const [] : [raw]);
    return (
      index: index,
      routes: [
        for (final s in list.whereType<String>())
          if (V4Net.tryParse(s) case final n?) n,
      ],
    );
  }

  @override
  Future<void> change(int index, {required List<V4Net> add, required List<V4Net> remove}) async {
    if (add.isEmpty && remove.isEmpty) return;
    // Одним запуском netsh: тысячи маршрутов по одному процессу на каждый ставились бы минутами.
    // store=active — только до перезагрузки, как у ядра.
    final script = StringBuffer();
    for (final n in add) {
      script.writeln('interface ipv4 add route prefix=$n interface=$index nexthop=$tunGateway metric=0 store=active');
    }
    for (final n in remove) {
      script.writeln('interface ipv4 delete route prefix=$n interface=$index nexthop=$tunGateway store=active');
    }
    final dir = await Directory.systemTemp.createTemp('rescue_routes_');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}routes.txt');
      await file.writeAsString(script.toString());
      final res = await Process.run('netsh', ['-f', file.path]);
      if (res.exitCode != 0) {
        throw TunRoutesException('Windows не приняла маршруты: ${res.stdout} ${res.stderr}'.trim());
      }
    } finally {
      await dir.delete(recursive: true);
    }
  }
}

class TunRoutesException implements Exception {
  TunRoutesException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Перестроить маршруты туннеля под список [direct]. Возвращает сколько маршрутов добавлено и убрано.
/// Ошибка — [TunRoutesException] с понятным текстом.
Future<({int added, int removed})> applyTunRoutes(TunRoutes routes, List<V4Net> direct) async {
  final now = await routes.read();
  if (now == null || now.routes.isEmpty) {
    throw TunRoutesException('Туннель не найден: VPN выключен или работает в режиме прокси.');
  }
  final target = tunRouteRanges(direct);
  final diff = tunRouteDiff(now.routes, target);
  await routes.change(now.index, add: diff.add, remove: diff.remove);
  // Проверка: таблица должна совпасть с тем, что построило бы ядро при подключении.
  final after = await routes.read();
  final left = after == null ? null : tunRouteDiff(after.routes, target);
  if (left == null || left.add.isNotEmpty || left.remove.isNotEmpty) {
    throw TunRoutesException('Применилось не всё. Переподключите VPN — список уже сохранён и применится целиком.');
  }
  return (added: diff.add.length, removed: diff.remove.length);
}
