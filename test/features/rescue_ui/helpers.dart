import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_theme.dart';

/// Задаёт размер окна теста и возвращает его к исходному после теста.
void setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Кирпичик внутри приложения с темой Шлюпки.
Future<void> pumpRescue(WidgetTester tester, Widget child, {Size size = const Size(1000, 800)}) async {
  setWindowSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: RescueTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}
