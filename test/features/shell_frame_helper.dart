import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Пункты меню как в приложении: 0 — Главная … 4 — Настройки.
const _items = [
  RescueNavItem(icon: Icons.home_rounded, label: 'Главная'),
  RescueNavItem(icon: Icons.call_split_rounded, label: 'Раздельный туннель'),
  RescueNavItem(icon: Icons.warning_amber_rounded, label: 'Ошибки', count: 7),
  RescueNavItem(icon: Icons.dns_rounded, label: 'Подписки и серверы'),
];

/// Страница внутри каркаса [RescueShell] (меню 236 px + область с отступом 24), окно [size] —
/// так ширина страницы такая же, как в приложении: на 1440 px ≈ 1116, на 900 px ≈ 576.
Future<void> pumpInShell(
  WidgetTester tester,
  ProviderContainer container,
  Widget page, {
  required Size size,
  int selected = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: RescueTheme.dark(),
        home: RescueShell(
          items: _items,
          bottomItem: const RescueNavItem(icon: Icons.tune_rounded, label: 'Настройки'),
          selectedIndex: selected,
          onSelected: (_) {},
          versionLabel: 'Версия 0.3.0 · основано на Hiddify',
          child: page,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Размеры окна для проверки раскладки: широкое, граница меню с подписями и узкое.
const shellSizes = [Size(1440, 900), Size(900, 900), Size(420, 900)];
