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
              const RescueNavItem(icon: Icons.call_split, label: 'Раздельный туннель'),
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

  testWidgets('широкое окно: меню 236 px с подписями, область panel без зазора', (tester) async {
    final taps = await pumpShell(tester, const Size(1440, 900));
    expect(tester.getSize(find.byKey(rail)).width, 236);
    expect(tester.getTopLeft(find.byKey(rail)).dx, 20);
    expect(find.byKey(bar), findsNothing);
    expect(find.byType(RescueLogo), findsOneWidget);
    expect(find.text('Шлюпка'), findsOneWidget);
    expect(find.text('спасения'), findsOneWidget);
    for (final label in ['Главная', 'Раздельный туннель', 'Ошибки', 'Подписки и серверы', 'Настройки']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // Область: panel, радиус 32, сразу за меню.
    final areaBox = tester.widget<Container>(find.byKey(area));
    final decoration = areaBox.decoration! as BoxDecoration;
    expect(decoration.color, RescueColors.panel);
    expect(decoration.borderRadius, BorderRadius.circular(32));
    expect(tester.getTopLeft(find.byKey(area)).dx, tester.getTopRight(find.byKey(rail)).dx);
    expect(tester.getTopLeft(find.text('Содержимое')).dx, tester.getTopLeft(find.byKey(area)).dx + 24);

    // Слот footer и версия внизу меню.
    expect(find.text('Карточка статуса'), findsOneWidget);
    expect(find.text('Версия 0.3.0'), findsOneWidget);
    expect(find.text('Мини'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Карточка статуса')).dy,
      greaterThan(tester.getBottomLeft(find.text('Настройки')).dy),
    );

    // Пункты 52 px; «Настройки» (bottomItem) — последний пункт списка, индекс items.length.
    final item = find.ancestor(of: find.text('Раздельный туннель'), matching: find.byType(InkWell));
    expect(tester.getSize(item).height, 52);
    await tester.tap(find.text('Настройки'));
    await tester.pump();
    await tester.tap(find.text('Раздельный туннель'));
    await tester.pump();
    expect(taps, [4, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбранный пункт сливается с областью: panel, скругление слева, «ушки»', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    final selected = find.byKey(const ValueKey('rescue-shell-selected'));
    expect(selected, findsOneWidget);
    final material = tester.widget<Material>(selected);
    expect(material.color, RescueColors.panel);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, const BorderRadius.horizontal(left: Radius.circular(18)));

    // Правый край выбранного пункта = левый край области.
    final areaLeft = tester.getTopLeft(find.byKey(area)).dx;
    expect(tester.getTopRight(selected).dx, areaLeft);

    // «Ушки» 20×20 только у выбранного: над и под ним, вплотную к области.
    expect(find.byKey(top), findsOneWidget);
    expect(find.byKey(bottom), findsOneWidget);
    expect(tester.getSize(find.byKey(top)), const Size(20, 20));
    expect(tester.getBottomRight(find.byKey(top)), tester.getTopRight(selected));
    expect(tester.getTopRight(find.byKey(bottom)), tester.getBottomRight(selected));
    expect(tester.getTopRight(find.byKey(top)).dx, areaLeft);

    // Ушко: снаружи panel, внутри page со скруглением к пункту.
    final outer = tester.widget<ColoredBox>(find.descendant(of: find.byKey(top), matching: find.byType(ColoredBox)));
    expect(outer.color, RescueColors.panel);
    final inner = tester.widget<DecoratedBox>(
      find.descendant(of: find.byKey(top), matching: find.byType(DecoratedBox)),
    );
    expect((inner.decoration as BoxDecoration).color, RescueColors.page);
    expect(
      (inner.decoration as BoxDecoration).borderRadius,
      const BorderRadius.only(bottomRight: Radius.circular(20)),
    );

    // Переход на другой пункт — «ушки» переезжают.
    await tester.tap(find.text('Ошибки'));
    await tester.pump();
    expect(find.byKey(top), findsOneWidget);
    final errorsTile = find.byKey(const ValueKey('rescue-shell-selected'));
    expect(find.descendant(of: errorsTile, matching: find.text('Ошибки')), findsOneWidget);
    expect(tester.getBottomRight(find.byKey(top)), tester.getTopRight(errorsTile));
  });

  testWidgets('счётчик у пункта: число, «99+», для чтеца, без счётчика при 0', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester, const Size(1440, 900));
    final count = find.byKey(const ValueKey('rescue-shell-count'));
    expect(count, findsOneWidget);
    expect(find.descendant(of: count, matching: find.text('7')), findsOneWidget);
    final box = tester.widget<Container>(count).decoration! as BoxDecoration;
    expect(box.color, RescueColors.warn);
    expect(tester.widget<Text>(find.text('7')).style!.color, RescueColors.onAccent);
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
    expect(tester.getSemantics(find.bySemanticsLabel('Раздельный туннель')), containsSemantics(isSelected: false));
    expect(find.bySemanticsLabel('Шлюпка спасения'), findsOneWidget);
    expect(find.bySemanticsLabel('Разделы'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('< 900: меню только значками, слияние то же, подписи в подсказках', (tester) async {
    final taps = await pumpShell(tester, const Size(800, 700));
    expect(tester.getSize(find.byKey(rail)).width, RescueShell.railWidth);
    expect(find.byKey(bar), findsNothing);
    expect(find.text('Раздельный туннель'), findsNothing);
    expect(find.byTooltip('Раздельный туннель'), findsOneWidget);
    expect(find.text('Шлюпка'), findsNothing);
    expect(find.text('Мини'), findsOneWidget);
    expect(find.text('Карточка статуса'), findsNothing);
    expect(find.text('Версия 0.3.0'), findsNothing);

    final selected = find.byKey(const ValueKey('rescue-shell-selected'));
    expect(tester.getTopRight(selected).dx, tester.getTopLeft(find.byKey(area)).dx);
    expect(find.byKey(top), findsOneWidget);
    expect(find.byKey(bottom), findsOneWidget);
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
