import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  Future<List<RouteChoice>> pumpSwitch(WidgetTester tester, {RouteChoice initial = RouteChoice.auto}) async {
    final calls = <RouteChoice>[];
    var value = initial;
    await pumpRescue(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: StatefulBuilder(
          builder: (context, setState) => RouteSwitch(
            value: value,
            semanticLabel: 'Куда идёт Google Chrome',
            onChanged: (v) {
              calls.add(v);
              setState(() => value = v);
            },
          ),
        ),
      ),
    );
    return calls;
  }

  Color segmentColor(WidgetTester tester, String label) {
    final container = tester.widget<AnimatedContainer>(
      find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)),
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('клик меняет значение и вызывает колбэк; цвета стиля «Д»', (tester) async {
    final calls = await pumpSwitch(tester);
    // Выбранный сегмент — светлый с тёмным текстом, независимо от значения.
    expect(segmentColor(tester, 'Авто'), RescueColors.text);

    await tester.tap(find.text('Мимо'));
    await tester.pumpAndSettle();
    expect(calls, [RouteChoice.bypass]);
    expect(segmentColor(tester, 'Мимо'), RescueColors.text);
    expect(segmentColor(tester, 'Авто'), Colors.transparent);

    await tester.tap(find.text('VPN'));
    await tester.pumpAndSettle();
    expect(calls, [RouteChoice.bypass, RouteChoice.vpn]);
    expect(segmentColor(tester, 'VPN'), RescueColors.text);
    expect(tester.widget<Text>(find.text('VPN')).style!.color, RescueColors.onAccent);

    // Повторное нажатие на выбранный — без колбэка.
    await tester.tap(find.text('VPN'));
    await tester.pump();
    expect(calls, hasLength(2));
  });

  testWidgets('клавиатура: Tab на переключатель, стрелки и Home/End', (tester) async {
    final calls = await pumpSwitch(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(calls.last, RouteChoice.bypass);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(calls.last, RouteChoice.vpn);

    // По кругу.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(calls.last, RouteChoice.auto);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(calls.last, RouteChoice.vpn);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(calls.last, RouteChoice.bypass);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(calls.last, RouteChoice.auto);
    expect(calls, hasLength(6));
  });

  testWidgets('Semantics: группа с подписью, сегменты — радиокнопки с полными подписями', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSwitch(tester, initial: RouteChoice.vpn);

    expect(find.bySemanticsLabel('Куда идёт Google Chrome'), findsOneWidget);
    final vpn = tester.getSemantics(find.bySemanticsLabel('Через VPN'));
    expect(vpn, containsSemantics(isInMutuallyExclusiveGroup: true));
    expect(vpn, containsSemantics(isChecked: true));
    final auto = tester.getSemantics(find.bySemanticsLabel('Авто, по общим правилам'));
    expect(auto, containsSemantics(isChecked: false));
    expect(find.bySemanticsLabel('Мимо VPN'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('зона нажатия сегмента не меньше 44 px', (tester) async {
    await pumpSwitch(tester);
    final segment = find.ancestor(of: find.text('Авто'), matching: find.byType(GestureDetector)).first;
    final size = tester.getSize(segment);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byType(RouteSwitch)).width, 230);
  });

  testWidgets('на жёлтом (onAccent): выбранный тёмный с жёлтым текстом', (tester) async {
    await pumpRescue(tester, const RouteSwitch(value: RouteChoice.bypass, onChanged: null, onAccent: true));
    expect(segmentColor(tester, 'Мимо'), RescueColors.onAccent);
    expect(tester.widget<Text>(find.text('Мимо')).style!.color, RescueColors.accent);
    expect(tester.widget<Text>(find.text('VPN')).style!.color, RescueColors.onAccent);
  });

  testWidgets('без onChanged — неактивен', (tester) async {
    await pumpRescue(tester, const RouteSwitch(value: RouteChoice.auto, onChanged: null));
    await tester.tap(find.text('VPN'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
