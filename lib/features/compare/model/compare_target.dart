/// Шлюпка: что сравниваем. Адрес приводится к виду из договора (домен, IPv4 или IPv6 без схемы и пути).
library;

import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';

/// Один адрес для замера: [host] — домен или IP, [port] — по умолчанию 443.
class CompareEndpoint {
  const CompareEndpoint(this.host, [this.port = 443]);

  final String host;
  final int port;

  bool get isIp => isIpAddress(host);

  /// Для показа: «example.com» или «example.com:8443».
  String get label => port == 443 ? host : '$host:$port';

  @override
  bool operator ==(Object other) => other is CompareEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Что выбрал пользователь: сайт, IP или программа с несколькими целями. Нужен диалогу «Сравнить пути».
class CompareSubject {
  const CompareSubject({this.endpoints = const [], this.appExe, this.askAddress = false});

  /// Адрес, введённый вручную (меню «⋯»): сначала поле ввода.
  const CompareSubject.ask() : endpoints = const [], appExe = null, askAddress = true;

  /// Цели для замера. У программы — её текущие адреса, пользователь выбирает один.
  final List<CompareEndpoint> endpoints;

  /// Программа («chrome.exe»): кнопки «Мимо VPN» / «Через VPN» добавляют её саму, а не адрес.
  final String? appExe;

  /// Показать поле ввода адреса.
  final bool askAddress;
}

/// Запись для списков туннеля, которую добавляют кнопки диалога.
({SplitKind kind, String value}) compareSplitItem(CompareSubject subject, CompareEndpoint endpoint) {
  final app = subject.appExe;
  if (app != null) return (kind: SplitKind.app, value: app);
  if (endpoint.isIp) return (kind: SplitKind.ip, value: cidrOf(endpoint.host));
  final parsed = parseSplitItem(endpoint.host);
  return (
    kind: SplitKind.domain,
    value: parsed?.kind == SplitKind.domain ? parsed!.value : endpoint.host.toLowerCase(),
  );
}

bool isIpAddress(String s) {
  if (RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(s) case final m?) {
    return [1, 2, 3, 4].every((i) => int.parse(m.group(i)!) <= 255);
  }
  return s.contains(':') && RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(s) && s.contains(RegExp('[0-9a-fA-F]'));
}

/// Приводит то, что ввёл пользователь, к цели замера: убирает схему, путь, логин, `www.` не трогает
/// (меряем ровно этот адрес). Кириллические домены — в punycode. null — не похоже на адрес.
CompareEndpoint? parseCompareTarget(String raw) {
  var s = raw.trim().replaceAll('"', '').replaceAll("'", '');
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
  s = s.split(RegExp(r'[/?#\s]')).first;
  s = s.replaceFirst(RegExp('^[^@]*@'), '');
  if (s.isEmpty) return null;

  var port = 443;
  // [IPv6]:порт или [IPv6]
  final bracket = RegExp(r'^\[([0-9a-fA-F:.]+)\](?::(\d{1,5}))?$').firstMatch(s);
  if (bracket != null) {
    final p = bracket.group(2) == null ? 443 : int.parse(bracket.group(2)!);
    if (p < 1 || p > 65535) return null;
    final ip = bracket.group(1)!.toLowerCase();
    return isIpAddress(ip) ? CompareEndpoint(ip, p) : null;
  }
  // Голый IPv6 (два и больше двоеточий) — порт не бывает.
  if (':'.allMatches(s).length >= 2) {
    return isIpAddress(s) ? CompareEndpoint(s.toLowerCase()) : null;
  }
  final withPort = RegExp(r'^(.*):(\d{1,5})$').firstMatch(s);
  if (withPort != null) {
    port = int.parse(withPort.group(2)!);
    if (port < 1 || port > 65535) return null;
    s = withPort.group(1)!;
  }
  if (s.contains(':')) return null;
  s = s.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (s.isEmpty) return null;
  if (RegExp(r'^[\d.]+$').hasMatch(s)) return isIpAddress(s) ? CompareEndpoint(s, port) : null;

  final labels = s.split('.');
  if (labels.length < 2 || labels.any((l) => l.isEmpty)) return null;
  final ascii = <String>[];
  for (final label in labels) {
    if (RegExp(r'^[a-z0-9_-]+$').hasMatch(label)) {
      ascii.add(label);
    } else if (RegExp('^[a-z0-9À-￿-]+\$').hasMatch(label)) {
      ascii.add('xn--${punycodeEncode(label)}');
    } else {
      return null;
    }
  }
  return CompareEndpoint(ascii.join('.'), port);
}

/// Адреса, куда программа ходит сейчас: сайт (или IP, если сайт неизвестен), топ-[limit] по числу
/// соединений. Домашние сети и localhost пропускаем — через VPN они не ходят, сравнивать нечего.
List<CompareEndpoint> endpointsForApp(String exe, List<NetConnection> all, {int limit = 5}) {
  final counts = <CompareEndpoint, int>{};
  for (final c in all) {
    if (c.exe.toLowerCase() != exe.toLowerCase()) continue;
    final host = c.host.isNotEmpty ? c.host.toLowerCase() : c.ip;
    if (host.isEmpty) continue;
    if (isIpAddress(host) && (isHomeNetwork(cidrOf(host)) || _isLoopback(host))) continue;
    final port = c.network.toLowerCase().startsWith('tcp') ? (int.tryParse(c.port) ?? 443) : 443;
    final e = CompareEndpoint(host, port == 0 ? 443 : port);
    counts[e] = (counts[e] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.label.compareTo(b.key.label);
    });
  return [for (final e in sorted.take(limit)) e.key];
}

bool _isLoopback(String ip) => ip.startsWith('127.') || ip == '::1' || ip == '0.0.0.0';
