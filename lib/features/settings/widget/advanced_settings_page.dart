import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/common/rescue_page_header.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/settings/widget/rescue_settings_page.dart';

/// Ссылка «Для опытных»: подпись и имя существующего маршрута.
typedef AdvancedLink = ({String title, String subtitle, String routeName});

/// Порядок важен: первые четыре показываются прямо в «Настройках» (как в макете).
const List<AdvancedLink> advancedLinks = [
  (title: 'Журнал', subtitle: 'Все строки ядра, для поиска проблем', routeName: 'logs'),
  (title: 'Маршрутизация', subtitle: 'Правила маршрутов, регион, блокировка рекламы, IPv6', routeName: 'routeOptions'),
  (title: 'DNS', subtitle: 'Какие серверы имён использовать для прямых соединений и для VPN', routeName: 'dnsOptions'),
  (title: 'Подключение', subtitle: 'Режим работы, порты прокси, тонкости туннеля', routeName: 'inboundOptions'),
  (title: 'Прочее', subtitle: 'Адрес проверки связи, порт Clash API, отладка', routeName: 'general'),
  (title: 'О программе', subtitle: 'Версия и обновления', routeName: 'about'),
];

/// Шлюпка: «Для опытных» (/settings/advanced) — тёмный блок со ссылками на прежние страницы
/// настроек Hiddify (они сами в теме «Д» через RescueTheme).
class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RescueColors.panel,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RescuePageHeader(
              title: 'Для опытных',
              subtitle: 'Обычно менять не нужно',
              leading: IconButton(
                tooltip: 'Назад',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.canPop() ? context.pop() : openRescueRoute(context, 'settings'),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: RescueCard.deep(
                  semanticLabel: 'Для опытных',
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: SectionLabel('Тонкая настройка', color: RescueColors.accent),
                      ),
                      for (final (i, link) in advancedLinks.indexed)
                        SettingsLinkTile(
                          title: link.title,
                          subtitle: link.subtitle,
                          onDeep: true,
                          divider: i < advancedLinks.length - 1,
                          onTap: () => openRescueRoute(context, link.routeName),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
