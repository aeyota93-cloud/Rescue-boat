import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/common/rescue_page_header.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/settings/widget/rescue_settings_page.dart';

/// Ссылка «Для опытных»: подпись и имя существующего маршрута.
typedef AdvancedLink = ({String title, String subtitle, String routeName});

/// Порядок важен: первые четыре показываются прямо в «Настройках» (как в макете).
const List<AdvancedLink> advancedLinks = [
  (title: 'DNS', subtitle: 'Серверы имён для прямых соединений и для VPN', routeName: 'dnsOptions'),
  (title: 'Маршрутизация', subtitle: 'Правила маршрутов, регион, блокировка рекламы, IPv6', routeName: 'routeOptions'),
  (title: 'Журнал ядра', subtitle: 'Все строки, для поиска проблем', routeName: 'logs'),
  (title: 'Подключение', subtitle: 'Режим работы, порты прокси, TUN', routeName: 'inboundOptions'),
  (title: 'Прочее', subtitle: 'Адрес проверки связи, порт Clash API, отладка', routeName: 'general'),
  (title: 'О программе', subtitle: 'Версия и обновления', routeName: 'about'),
];

/// Шлюпка: «Для опытных» (/settings/advanced) — ссылки на прежние страницы настроек Hiddify.
class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RescueColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Назад',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.canPop() ? context.pop() : openRescueRoute(context, 'settings'),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: RescuePageHeader(title: 'Для опытных', subtitle: 'Обычно менять не нужно'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RescueCard(
              semanticLabel: 'Для опытных',
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final link in advancedLinks)
                    SettingsLinkTile(
                      title: link.title,
                      subtitle: link.subtitle,
                      onTap: () => openRescueRoute(context, link.routeName),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
