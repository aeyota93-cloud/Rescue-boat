import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: состояние VPN для «таблетки» на Обзоре и строки в меню трея.
class VpnStatus {
  const VpnStatus({required this.connected, required this.busy, required this.label, required this.canToggle});

  /// Положение переключателя.
  final bool connected;

  /// Идёт подключение или отключение.
  final bool busy;

  /// «Подключено · Нидерланды · 48 мс», «Отключено».
  final String label;

  /// Можно ли сейчас нажать (не во время переключения).
  final bool canToggle;
}

/// Пинг сервера, если он настоящий (ядро пишет 0 или 65000+, пока замера нет).
int? validDelay(int? delay) => delay != null && delay > 0 && delay < 65000 ? delay : null;

/// [withServer] — добавить имя сервера (на Обзоре); в трее только пинг.
VpnStatus vpnStatusOf(AsyncValue<ConnectionStatus> connection, OutboundInfo? proxy, {bool withServer = true}) {
  final delay = validDelay(proxy?.urlTestDelay);
  final server = withServer ? (proxy?.tagDisplay ?? '').trim() : '';
  return switch (connection) {
    // Подключено, но сервер ещё ни разу не ответил — для людей это всё ещё «Подключение…».
    AsyncData(value: Connected()) when delay == null => const VpnStatus(
      connected: true,
      busy: true,
      label: 'Подключение…',
      canToggle: true,
    ),
    AsyncData(value: Connected()) => VpnStatus(
      connected: true,
      busy: false,
      label: ['Подключено', if (server.isNotEmpty) server, '$delay мс'].join(' · '),
      canToggle: true,
    ),
    AsyncData(value: Connecting()) => const VpnStatus(
      connected: true,
      busy: true,
      label: 'Подключение…',
      canToggle: false,
    ),
    AsyncData(value: Disconnecting()) => const VpnStatus(
      connected: false,
      busy: true,
      label: 'Отключение…',
      canToggle: false,
    ),
    AsyncData(value: Disconnected(:final connectionFailure)) => VpnStatus(
      connected: false,
      busy: false,
      label: connectionFailure != null ? 'Не удалось подключиться' : 'Отключено',
      canToggle: true,
    ),
    AsyncError() => const VpnStatus(connected: false, busy: false, label: 'Не удалось подключиться', canToggle: true),
    _ => const VpnStatus(connected: false, busy: false, label: 'Отключено', canToggle: false),
  };
}

final vpnStatusProvider = Provider.autoDispose<VpnStatus>(
  (ref) => vpnStatusOf(ref.watch(connectionNotifierProvider), ref.watch(activeProxyNotifierProvider).valueOrNull),
);
