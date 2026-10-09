import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/rescue_ui/rescue_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Папка настроек в temp вместо настоящей.
class FakeDirectories extends AppDirectories {
  FakeDirectories(this.dir);

  final Directory dir;

  @override
  Future<Directories> build() async => (baseDir: dir, workingDir: dir, tempDir: dir);
}

/// Контейнер с подменёнными настройками (SharedPreferences в памяти) и папкой [dir].
/// Создавать вне testWidgets-кода с pump, а ждать — через [ready].
Future<ProviderContainer> screensContainer(
  Directory dir, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => sp),
      appDirectoriesProvider.overrideWith(() => FakeDirectories(dir)),
      ...overrides,
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(appDirectoriesProvider.future);
  return container;
}

/// Страница в теме Шлюпки, окно [size]. Контейнер закрывает тест сам ([closePage]).
Future<void> pumpPage(WidgetTester tester, ProviderContainer container, Widget page, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: RescueTheme.dark(), home: page),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Убрать страницу и закрыть контейнер до проверки таймеров в конце теста.
Future<void> closePage(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
}

/// Нет ошибок отрисовки (в том числе переполнений «RenderFlex overflowed»).
void expectNoLayoutErrors(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: '$error');
}
