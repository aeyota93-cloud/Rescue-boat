import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';

/// Колонка [RescueTable]: либо доля ширины [flex], либо точная ширина [width].
class RescueColumn {
  const RescueColumn(this.label, {this.flex = 1, this.width, this.alignEnd = false});

  final String label;
  final double flex;

  /// Фиксированная ширина в px (например, 60 для «Время», 230 для переключателя).
  final double? width;

  /// Прижать заголовок и ячейки вправо («Путь», «Ошибки за сутки»).
  final bool alignEnd;
}

/// Строка [RescueTable].
class RescueTableRow {
  const RescueTableRow({required this.cells, this.onTap, this.selected = false, this.semanticLabel});

  /// По одной ячейке на колонку.
  final List<Widget> cells;

  /// Строка-кнопка (например, выбор сервера). Высота тогда не меньше 44.
  final VoidCallback? onTap;
  final bool selected;

  /// Как прочитать строку целиком; null — чтец читает ячейки по очереди.
  /// Если задано, ячейки скрыты от чтеца — не задавайте для строк с кнопками внутри.
  final String? semanticLabel;
}

/// Шлюпка: таблица — серые заголовки колонок, строки с разделителями.
///
/// Если окно уже [minWidth], таблица прокручивается по горизонтали (как overflow-x в макете).
/// Строится целиком (не лениво) — для коротких списков на карточках.
class RescueTable extends StatelessWidget {
  const RescueTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 760,
    this.rowHeight = 42,
    this.gap = 12,
    this.horizontalPadding = 4,
  });

  final List<RescueColumn> columns;
  final List<RescueTableRow> rows;
  final double minWidth;

  /// Минимальная высота строки: 42 в списке ошибок, 60 в туннеле, 64 у серверов.
  final double rowHeight;

  /// Промежуток между колонками.
  final double gap;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: horizontalPadding),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: RescueColors.line)),
          ),
          child: _cellsRow([
            for (final c in columns)
              Text(
                c.label,
                style: RescueText.tableHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: c.alignEnd ? TextAlign.end : TextAlign.start,
              ),
          ]),
        ),
        for (final row in rows) _buildRow(row),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) return table;
        // Полосу прокрутки на Windows добавляет ScrollBehavior сам.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      },
    );
  }

  Widget _cellsRow(List<Widget> cells) {
    final children = <Widget>[];
    for (final (i, column) in columns.indexed) {
      if (i > 0) children.add(SizedBox(width: gap));
      final cell = i < cells.length ? cells[i] : const SizedBox.shrink();
      final aligned = Align(alignment: column.alignEnd ? Alignment.centerRight : Alignment.centerLeft, child: cell);
      final width = column.width;
      children.add(
        width != null
            ? SizedBox(width: width, child: aligned)
            : Expanded(flex: (column.flex * 100).round().clamp(1, 1 << 20), child: aligned),
      );
    }
    return Row(children: children);
  }

  Widget _buildRow(RescueTableRow row) {
    final onTap = row.onTap;
    Widget content = Container(
      constraints: BoxConstraints(minHeight: onTap != null && rowHeight < 44 ? 44 : rowHeight),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: row.selected ? RescueColors.selected : null,
        border: const Border(bottom: BorderSide(color: RescueColors.rowLine)),
      ),
      child: DefaultTextStyle.merge(
        style: RescueText.small,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: _cellsRow(row.cells),
      ),
    );
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: content),
      );
    }
    final label = row.semanticLabel;
    if (label != null || onTap != null) {
      content = Semantics(
        container: true,
        button: onTap != null,
        selected: row.selected,
        label: label,
        onTap: onTap,
        child: label != null ? ExcludeSemantics(child: content) : content,
      );
    }
    return content;
  }
}
