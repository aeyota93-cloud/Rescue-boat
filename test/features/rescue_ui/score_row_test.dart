import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  Future<void> pumpRow(WidgetTester tester, {required double g, required double f, required double p, int? trend}) =>
      pumpRescue(
        tester,
        SizedBox(
          width: 403, // 403 − 2 промежутка по 3 = 397 на доли
          child: ScoreRow(
            name: 'Стабильность',
            value: '81',
            trend: trend,
            good: g,
            fair: f,
            poor: p,
            caption: '2 переподключения за сутки',
          ),
        ),
      );

  double width(WidgetTester tester, String part) => tester.getSize(find.byKey(ValueKey('score-bar-$part'))).width;

  testWidgets('три доли пропорциональны, текст и тренд на месте', (tester) async {
    await pumpRow(tester, g: 62, f: 24, p: 14, trend: -4);
    expect(find.text('Стабильность'), findsOneWidget);
    expect(find.text('81'), findsOneWidget);
    expect(find.text('↘ 4'), findsOneWidget);
    expect(tester.widget<Text>(find.text('↘ 4')).style!.color, RescueColors.poor);
    expect(find.text('2 переподключения за сутки'), findsOneWidget);

    final total = width(tester, 'good') + width(tester, 'fair') + width(tester, 'poor');
    expect(total, closeTo(397, 0.5));
    expect(width(tester, 'good') / total, closeTo(0.62, 0.01));
    expect(width(tester, 'fair') / total, closeTo(0.24, 0.01));
    expect(width(tester, 'poor') / total, closeTo(0.14, 0.01));
  });

  testWidgets('нулевые доли не рисуются, оставшаяся занимает всю ширину', (tester) async {
    await pumpRow(tester, g: 100, f: 0, p: 0, trend: 0);
    expect(find.byKey(const ValueKey('score-bar-fair')), findsNothing);
    expect(find.byKey(const ValueKey('score-bar-poor')), findsNothing);
    expect(width(tester, 'good'), closeTo(403, 0.5));
    expect(find.text('→ 0'), findsOneWidget);
    expect(tester.widget<Text>(find.text('→ 0')).style!.color, RescueColors.good);
  });

  testWidgets('две доли из трёх — один промежуток', (tester) async {
    await pumpRow(tester, g: 0, f: 0.5, p: 0.5, trend: 2);
    expect(find.byKey(const ValueKey('score-bar-good')), findsNothing);
    expect(width(tester, 'fair'), closeTo(200, 0.5));
    expect(width(tester, 'poor'), closeTo(200, 0.5));
    expect(find.text('↗ 2'), findsOneWidget);
  });

  testWidgets('все нули — серая дорожка, без ошибок', (tester) async {
    await pumpRow(tester, g: 0, f: 0, p: 0);
    expect(find.byKey(const ValueKey('score-bar-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('score-bar-good')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Semantics: всё одной фразой', (tester) async {
    await pumpRow(tester, g: 80, f: 14, p: 6, trend: 3);
    expect(
      find.bySemanticsLabel(
        'Стабильность: 81, выросло на 3. Хорошо 80%, средне 14%, плохо 6%. 2 переподключения за сутки',
      ),
      findsOneWidget,
    );
  });
}
