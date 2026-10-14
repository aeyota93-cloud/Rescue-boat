import 'package:flutter/widgets.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';

/// Шлюпка: масштаб всего окна в процентах (Настройки → «Масштаб»).
abstract class UiScalePreferences {
  static const min = 70;
  static const max = 150;
  static const step = 10;

  static final percent = PreferencesNotifier.create<int, int>("rescue-ui-scale", 100);

  /// Шаг − / + от [current]; результат всегда в пределах [min]…[max] и кратен [step].
  static int stepped(int current, int direction) {
    final base = (current / step).round() * step;
    return (base + direction * step).clamp(min, max);
  }

  /// Сохранённое значение, приведённое к допустимому (файл настроек мог быть поправлен руками).
  static double factor(int percent) => percent.clamp(min, max) / 100;
}

/// Масштабирует всё под собой: раскладка считается для окна размером «окно ÷ [scale]», а готовая
/// картинка растягивается до окна. В отличие от увеличения шрифта, растут и кнопки, и отступы,
/// а сетки сами переходят на меньшее число колонок.
///
/// Обёртка всегда остаётся в дереве (и при 100%): иначе при смене масштаба Flutter пересоздал бы
/// всё под ней, вместе с навигацией и открытым экраном.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth / scale, box.maxHeight / scale);
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: media.copyWith(
                size: size,
                devicePixelRatio: media.devicePixelRatio * scale,
                padding: media.padding / scale,
                viewPadding: media.viewPadding / scale,
                viewInsets: media.viewInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
