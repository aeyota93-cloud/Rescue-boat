import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  Future<List<int>> pumpShell(WidgetTester tester, Size size) async {
    final taps = <int>[];
    setWindowSize(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: RescueTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) => RescueShell(
            selectedIndex: taps.isEmpty ? 0 : taps.last,
            onSelected: (i) => setState(() => taps.add(i)),
            items: const [
              RescueNavItem(icon: Icons.home_outlined, label: 'Обзор'),
              RescueNavItem(icon: Icons.call_split, label: 'Раздельный туннель'),
              RescueNavItem(icon: Icons.warning_amber, label: 'Ошибки соединений', badge: true),
            ],
            bottomItem: const RescueNavItem(icon: Icons.tune, label: 'Настройки'),
            child: const Text('Содержимое'),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('широкое окно: панель 64 px слева, логотип, настройки внизу', (tester) async {
    final taps = await pumpShell(tester, const Size(1200, 800));
    final rail = find.byKey(const ValueKey('rescue-shell-rail'));
    expect(rail, findsOneWidget);
    expect(find.byKey(const ValueKey('rescue-shell-bottom-bar')), findsNothing);
    expect(tester.getSize(rail).width, 64);
    expect(tester.getTopLeft(rail).dx, 16);
    expect(find.byType(RescueLogo), findsOneWidget);
    expect(tester.getTopLeft(find.text('Содержимое')).dx, greaterThan(64 + 16));

    // «Настройки» прижаты к низу панели.
    final settings = tester.getCenter(find.byIcon(Icons.tune));
    final errors = tester.getCenter(find.byIcon(Icons.warning_amber));
    expect(settings.dy, greaterThan(errors.dy + 200));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.tap(find.byIcon(Icons.call_split));
    expect(taps, [3, 1]);
  });

  testWidgets('узкое окно (< 700): панель внизу', (tester) async {
    final taps = await pumpShell(tester, const Size(500, 800));
    final bar = find.byKey(const ValueKey('rescue-shell-bottom-bar'));
    expect(bar, findsOneWidget);
    expect(find.byKey(const ValueKey('rescue-shell-rail')), findsNothing);
    expect(tester.getBottomLeft(bar).dy, 800);
    expect(tester.getSize(bar).width, 500);
    expect(tester.getTopLeft(find.text('Содержимое')).dy, lessThan(tester.getTopLeft(bar).dy));
    await tester.tap(find.byIcon(Icons.warning_amber));
    expect(taps, [2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('кнопки-значки: подписи для чтеца, выбранный пункт, бейдж, зона 44 px', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester, const Size(1200, 800));

    final home = tester.getSemantics(find.bySemanticsLabel('Обзор'));
    expect(home, containsSemantics(isButton: true));
    expect(home, containsSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Раздельный туннель')), containsSemantics(isSelected: false));
    expect(find.bySemanticsLabel('Ошибки соединений, есть новое'), findsOneWidget);
    expect(find.bySemanticsLabel('Настройки'), findsOneWidget);

    final button = find.ancestor(of: find.byIcon(Icons.home_outlined), matching: find.byType(InkWell));
    expect(tester.getSize(button), const Size(44, 44));

    // Подсказка при наведении.
    expect(find.byTooltip('Раздельный туннель'), findsOneWidget);
    handle.dispose();
  });
}
