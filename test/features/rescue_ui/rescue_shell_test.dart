import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  const top = ValueKey('rescue-shell-ear-top');
  const bottom = ValueKey('rescue-shell-ear-bottom');
  const rail = ValueKey('rescue-shell-rail');
  const area = ValueKey('rescue-shell-area');
  const bar = ValueKey('rescue-shell-bottom-bar');

  Future<List<int>> pumpShell(WidgetTester tester, Size size, {int? errors = 7, Widget? child}) async {
    final taps = <int>[];
    setWindowSize(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: RescueTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) => RescueShell(
            selectedIndex: taps.isEmpty ? 0 : taps.last,
            onSelected: (i) => setState(() => taps.add(i)),
            items: [
              const RescueNavItem(icon: Icons.home_outlined, label: 'Главная'),
              const RescueNavItem(icon: Icons.call_split, label: 'Туннелирование'),
              RescueNavItem(icon: Icons.warning_amber, label: 'Ошибки', count: errors),
              const RescueNavItem(icon: Icons.dns_outlined, label: 'Подписки и серверы', badge: true),
            ],
            bottomItem: const RescueNavItem(icon: Icons.tune, label: 'Настройки'),
            footer: const Text('Карточка статуса'),
            compactFooter: const Text('Мини'),
            versionLabel: 'Версия 0.3.0',
            child: child ?? const Text('Содержимое'),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('широкое окно: рейка 72 px, подсказки и переходы', (tester) async {
    final taps = await pumpShell(tester, const Size(1440, 900));
    expect(tester.getSize(find.byKey(rail)).width, 72);
    expect(tester.getTopLeft(find.byKey(rail)).dx, 0);
    expect(find.byKey(bar), findsNothing);
    expect(find.byType(RescueLogo), findsOneWidget);
    expect(find.byTooltip('Шлюпка спасения'), findsOneWidget);
    for (final label in ['Главная', 'Туннелирование', 'Ошибки', 'Подписки и серверы', 'Настройки']) {
      expect(find.byTooltip(label), findsOneWidget, reason: label);
    }
    final areaBox = tester.widget<Container>(find.byKey(area));
    expect(areaBox.color, RescueColors.page);
    expect(tester.getTopLeft(find.byKey(area)).dx, tester.getTopRight(find.byKey(rail)).dx);
    expect(tester.getTopLeft(find.text('Содержимое')).dx, tester.getTopLeft(find.byKey(area)).dx + 24);
    expect(find.text('Карточка статуса'), findsOneWidget);
    expect(find.byTooltip('Версия 0.3.0'), findsOneWidget);
    final item = find.ancestor(of: find.byIcon(Icons.call_split), matching: find.byType(InkWell));
    expect(tester.getSize(item), const Size(48, 48));
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.call_split));
    await tester.pump();
    expect(taps, [4, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбранный пункт: жёлтая плитка, радиус 12, без ушек', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    final selected = find.byKey(const ValueKey('rescue-shell-selected'));
    final material = tester.widget<Material>(selected);
    expect(material.color, RescueColors.accentTint);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(12));
    expect(tester.getSize(selected), const Size(48, 48));
    expect(find.byKey(top), findsNothing);
    expect(find.byKey(bottom), findsNothing);
    await tester.tap(find.byIcon(Icons.warning_amber));
    await tester.pump();
    final errorsTile = find.byKey(const ValueKey('rescue-shell-selected'));
    expect(find.descendant(of: errorsTile, matching: find.byIcon(Icons.warning_amber)), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber)).color, RescueColors.accent);
  });
  testWidgets('счётчик у пункта: число, «99+», для чтеца, без счётчика при 0', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester, const Size(1440, 900));
    final count = find.byKey(const ValueKey('rescue-shell-count'));
    expect(count, findsOneWidget);
    expect(find.descendant(of: count, matching: find.text('7')), findsOneWidget);
    final box = tester.widget<Container>(count).decoration! as BoxDecoration;
    expect(box.color, RescueColors.accentTint);
    expect(tester.widget<Text>(find.text('7')).style!.color, RescueColors.accent);
    expect(find.bySemanticsLabel('Ошибки, 7'), findsOneWidget);
    expect(find.bySemanticsLabel('Подписки и серверы, есть новое'), findsOneWidget);

    await pumpShell(tester, const Size(1440, 900), errors: 150);
    expect(find.text('99+'), findsOneWidget);

    await pumpShell(tester, const Size(1440, 900), errors: 0);
    expect(count, findsNothing);
    expect(find.bySemanticsLabel('Ошибки'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Semantics: кнопки, выбранный пункт, зона нажатия ≥ 44', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester, const Size(1440, 900));
    final home = tester.getSemantics(find.bySemanticsLabel('Главная'));
    expect(home, containsSemantics(isButton: true, isSelected: true, hasTapAction: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Туннелирование')), containsSemantics(isSelected: false));
    expect(find.bySemanticsLabel('Шлюпка спасения'), findsOneWidget);
    expect(find.bySemanticsLabel('Разделы'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('< 900: меню только значками, слияние то же, подписи в подсказках', (tester) async {
    final taps = await pumpShell(tester, const Size(800, 700));
    expect(tester.getSize(find.byKey(rail)).width, RescueShell.railWidth);
    expect(find.byKey(bar), findsNothing);
    expect(find.text('Туннелирование'), findsNothing);
    expect(find.byTooltip('Туннелирование'), findsOneWidget);
    expect(find.text('Шлюпка'), findsNothing);
    expect(find.text('Мини'), findsOneWidget);
    expect(find.text('Карточка статуса'), findsNothing);
    expect(find.byTooltip('Версия 0.3.0'), findsOneWidget);

    final selected = find.byKey(const ValueKey('rescue-shell-selected'));
    expect(tester.getTopRight(selected).dx, lessThan(tester.getTopLeft(find.byKey(area)).dx));
    expect(find.byKey(top), findsNothing);
    expect(find.byKey(bottom), findsNothing);
    // Счётчик в углу значка.
    expect(find.text('7'), findsOneWidget);
    expect(tester.getSize(selected).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(selected).width, greaterThanOrEqualTo(44));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    expect(taps, [4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('< 600: панель внизу, без «ушек»', (tester) async {
    final taps = await pumpShell(tester, const Size(500, 800));
    expect(find.byKey(bar), findsOneWidget);
    expect(find.byKey(rail), findsNothing);
    expect(find.byKey(top), findsNothing);
    expect(tester.getBottomLeft(find.byKey(bar)).dy, 800);
    expect(tester.getSize(find.byKey(bar)).width, 500);
    expect(tester.getTopLeft(find.text('Содержимое')).dy, lessThan(tester.getTopLeft(find.byKey(bar)).dy));
    expect(find.text('Мини'), findsNothing);
    expect(find.text('7'), findsOneWidget);
    final button = find.ancestor(of: find.byIcon(Icons.warning_amber), matching: find.byType(InkWell));
    expect(tester.getSize(button), const Size(52, 52));
    await tester.tap(find.byIcon(Icons.warning_amber));
    expect(taps, [2]);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(400, 700), Size(1440, 900), Size(1440, 420)]) {
    testWidgets('нет переполнений на ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      await pumpShell(
        tester,
        size,
        errors: 1234,
        child: ListView(children: [for (var i = 0; i < 40; i++) Text('Строка $i')]),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
