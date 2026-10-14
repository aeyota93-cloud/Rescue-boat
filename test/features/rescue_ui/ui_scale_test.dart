import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/ui_scale.dart';

void main() {
  test('шаги − / +: кратно 10, в пределах 70…150', () {
    expect(UiScalePreferences.stepped(100, 1), 110);
    expect(UiScalePreferences.stepped(100, -1), 90);
    expect(UiScalePreferences.stepped(150, 1), 150);
    expect(UiScalePreferences.stepped(70, -1), 70);
    expect(UiScalePreferences.stepped(104, 1), 110);
    expect(UiScalePreferences.stepped(500, -1), 150);
    expect(UiScalePreferences.factor(125), 1.25);
    expect(UiScalePreferences.factor(10), 0.7);
    expect(UiScalePreferences.factor(900), 1.5);
  });

  Future<(Size, Rect)> layout(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Size seen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => UiScale(scale: scale, child: child!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(key: ValueKey('box'), width: 100, height: 50),
            );
          },
        ),
      ),
    );
    return (seen, tester.getRect(find.byKey(const ValueKey('box'))));
  }

  testWidgets('125%: экран видит окно 800×640, квадрат 100 px на деле 125 px', (tester) async {
    final (size, rect) = await layout(tester, 1.25);
    expect(size, const Size(800, 640));
    expect(rect.size, const Size(125, 62.5));
    expect(rect.topLeft, Offset.zero);
  });

  testWidgets('100%: ничего не меняется', (tester) async {
    final (size, rect) = await layout(tester, 1);
    expect(size, const Size(1000, 800));
    expect(rect.size, const Size(100, 50));
  });

  testWidgets('нажатия попадают туда, где кнопка нарисована', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => UiScale(scale: 1.5, child: child!),
        home: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 200, top: 100),
            child: TextButton(onPressed: () => taps++, child: const Text('Жми')),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(TextButton));
    expect(rect.left, 300);
    expect(rect.top, 150);
    await tester.tapAt(rect.center);
    expect(taps, 1);
    await tester.tapAt(const Offset(250, 120));
    expect(taps, 1);
  });
}
