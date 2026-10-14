import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/gallery_page.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  // Узкое и широкое окна проверяются на настоящих экранах, витрине достаточно smoke-проверки.
  testWidgets('витрина открывается без ошибок', (tester) async {
    setWindowSize(tester, const Size(700, 900));
    await tester.pumpWidget(const MaterialApp(home: RescueGalleryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PowerButton), findsWidgets);
  });
  testWidgets('витрина живая: RouteSwitch в таблице меняет счётчик', (tester) async {
    setWindowSize(tester, const Size(1440, 1000));
    await tester.pumpWidget(const MaterialApp(home: RescueGalleryPage()));
    final viaTile = find.widgetWithText(StatTile, 'Через VPN');
    String viaValue() => tester.widget<StatTile>(viaTile).value;
    expect(viaValue(), '1');

    final chromeSwitch = find.byWidgetPredicate(
      (w) => w is RouteSwitch && w.semanticLabel == 'Куда идёт Google Chrome',
    );
    await tester.ensureVisible(chromeSwitch);
    await tester.tap(find.descendant(of: chromeSwitch, matching: find.text('VPN')));
    await tester.pumpAndSettle();
    expect(viaValue(), '2');
  });
}
