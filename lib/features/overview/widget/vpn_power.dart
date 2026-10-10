import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: нажатие кнопки питания — одно и то же на Главной и в карточке статуса в меню.
///
/// Подключено (или «Подключение…», когда сервер ещё не ответил) — отключает. Отключено —
/// подключает, как большая кнопка старой главной: без подписки не подключает, а подсказывает
/// перейти к серверам; перед подключением — уведомление об экспериментальных функциях.
/// Во время переключения (ядро ещё не ответило) ничего не делает.
Future<void> toggleVpn(BuildContext context, WidgetRef ref) async {
  final status = ref.read(vpnStatusProvider);
  if (!status.canToggle) return;
  final connection = ref.read(connectionNotifierProvider.notifier);
  if (status.connected) return connection.toggleConnection();
  // Подписка могла ещё не прочитаться (каркас её не слушает) — дождёмся.
  final profile = ref.read(activeProfileProvider).valueOrNull ?? await ref.read(activeProfileProvider.future);
  if (!context.mounted) return;
  if (profile == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text('Сначала добавьте подписку'),
        action: SnackBarAction(label: 'Серверы', onPressed: () => GoRouter.maybeOf(context)?.go('/servers')),
      ),
    );
    return;
  }
  if (!await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) return;
  await connection.toggleConnection();
}
