import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Области раздела не меньше этого размера хватает, чтобы закрепить шапку и кнопки, а прокручивать
/// только длинный список. Меньше — прокручивается вся страница (вложенная прокрутка на маленьком
/// экране неудобна).
const pinnedMinWidth = 860.0;
const pinnedMinHeight = 600.0;

/// Хватает ли области раздела ([constraints] из LayoutBuilder) для режима «закреплено».
bool isPinnedLayout(BoxConstraints constraints) =>
    constraints.hasBoundedHeight && constraints.maxWidth >= pinnedMinWidth && constraints.maxHeight >= pinnedMinHeight;

/// Справа от содержимого оставляем место, чтобы полоса прокрутки не лежала на нём.
const _scrollbarGutter = 12.0;

/// Список, который прокручивается внутри своей карточки: видимая полоса прокрутки, колесо мыши
/// крутит только его. Строки строятся по мере прокрутки, поэтому подходит для сотен записей.
/// Ставить внутрь [Expanded] (нужна ограниченная высота).
class PinnedList extends HookWidget {
  const PinnedList({super.key, required this.itemCount, required this.itemBuilder, this.spacing = 0});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Расстояние между строками.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final controller = useScrollController();
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ListView.separated(
        controller: controller,
        padding: const EdgeInsets.only(right: _scrollbarGutter),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: (_, _) => SizedBox(height: spacing),
      ),
    );
  }
}

/// То же для небольшого набора разнородных блоков (карточки, сетка): прокручивается внутри
/// своей области, полоса прокрутки видна. Ставить внутрь [Expanded].
class PinnedScroll extends HookWidget {
  const PinnedScroll({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final controller = useScrollController();
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: controller,
        padding: padding + const EdgeInsets.only(right: _scrollbarGutter),
        child: child,
      ),
    );
  }
}
