part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// A stepper and a data table.
//
// Both are built here from the widgets above - rows, columns, boxes, buttons
// - rather than drawn by a renderer, so they look the same on all four and
// cost the protocol nothing.
// ---------------------------------------------------------------------------

/// What a [Step]'s circle shows.
enum StepState { indexed, editing, complete, disabled, error }

/// Which way a [Stepper] runs.
enum StepperType { vertical, horizontal }

/// One step of a [Stepper].
class Step {
  const Step({
    required this.title,
    this.subtitle,
    required this.content,
    this.state = StepState.indexed,
    this.isActive = false,
    this.label,
    this.stepStyle,
  });
  final Widget title;
  final Widget? subtitle;

  /// Shown under the title while this is the current step.
  final Widget content;
  final StepState state;

  /// Whether the step's circle is drawn in the primary colour.
  final bool isActive;

  /// Under the circle of a horizontal stepper.
  final Widget? label;

  /// Accepted and not carried.
  final Object? stepStyle;
}

/// What a [Stepper.controlsBuilder] is given.
class ControlsDetails {
  const ControlsDetails({
    required this.currentStep,
    required this.stepIndex,
    this.onStepCancel,
    this.onStepContinue,
  });
  final int currentStep;
  final int stepIndex;
  final VoidCallback? onStepCancel;
  final VoidCallback? onStepContinue;

  bool get isActive => currentStep == stepIndex;
}

/// Builds the buttons under a step's content.
typedef ControlsWidgetBuilder =
    Widget Function(BuildContext context, ControlsDetails details);

/// A sequence of numbered steps, one of them open.
///
/// The app says which with [currentStep], and moves it in [onStepContinue],
/// [onStepCancel] and [onStepTapped], as in Flutter. A step does not animate
/// open, and a vertical stepper does not scroll itself: put it in a
/// `SingleChildScrollView` if its steps are taller than the page.
class Stepper extends StatelessWidget {
  const Stepper({
    super.key,
    required this.steps,
    this.controller,
    this.physics,
    this.type = StepperType.vertical,
    this.currentStep = 0,
    this.onStepTapped,
    this.onStepContinue,
    this.onStepCancel,
    this.controlsBuilder,
    this.elevation,
    this.margin,
    this.connectorColor,
    this.connectorThickness,
    this.stepIconBuilder,
    this.stepIconHeight,
    this.stepIconWidth,
    this.stepIconMargin,
    this.clipBehavior = Clip.none,
  }) : assert(0 <= currentStep && currentStep < steps.length);

  final List<Step> steps;
  final int currentStep;
  final StepperType type;
  final ValueChanged<int>? onStepTapped;

  /// What "Continue" does; null disables the button.
  final VoidCallback? onStepContinue;

  /// What "Cancel" does; null disables the button.
  final VoidCallback? onStepCancel;

  /// The buttons under the open step, in place of Continue and Cancel.
  final ControlsWidgetBuilder? controlsBuilder;

  /// The room around a vertical step's content.
  final EdgeInsetsGeometry? margin;

  /// What a step's circle holds, in place of its number or tick. Null keeps
  /// the stepper's own.
  final Widget? Function(int stepIndex, StepState stepState)? stepIconBuilder;

  /// How thick the line between steps is.
  final double? connectorThickness;

  /// Accepted and not carried.
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final double? elevation;
  final Object? connectorColor;
  final double? stepIconHeight;
  final double? stepIconWidth;
  final EdgeInsets? stepIconMargin;
  final Clip clipBehavior;

  Widget _circle(BuildContext context, int index) {
    final step = steps[index];
    final scheme = Theme.of(context).colorScheme;
    final error = step.state == StepState.error;
    final lit = step.isActive || step.state == StepState.complete;
    final fill = error
        ? scheme.error
        : (lit ? scheme.primary : scheme.onSurface.withOpacity(0.38));
    final ink = error ? scheme.onError : (lit ? scheme.onPrimary : scheme.surface);
    final custom = stepIconBuilder?.call(index, step.state);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child:
          custom ??
          switch (step.state) {
            StepState.complete => Icon(Icons.check, size: 16, color: ink),
            StepState.editing => Icon(Icons.edit, size: 16, color: ink),
            StepState.error => Text(
              '!',
              style: TextStyle(color: ink, fontSize: 12),
            ),
            _ => Text(
              '${index + 1}',
              style: TextStyle(color: ink, fontSize: 12),
            ),
          },
    );
  }

  Widget _heading(BuildContext context, int index) {
    final step = steps[index];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final off = step.state == StepState.disabled;
    final ink = step.state == StepState.error
        ? scheme.error
        : (off ? scheme.onSurface.withOpacity(0.38) : scheme.onSurface);
    final subtitle = step.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTextStyle(
          style: TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: index == currentStep ? FontWeight.w500 : null,
          ),
          child: step.title,
        ),
        if (subtitle != null)
          DefaultTextStyle(
            style: TextStyle(
              color: scheme.onSurface.withOpacity(off ? 0.38 : 0.6),
              fontSize: 12,
            ),
            child: subtitle,
          ),
      ],
    );
  }

  /// A step's head, tappable when the app listens and the step is not off.
  Widget _tappable(int index, Widget child) {
    final tapped = onStepTapped;
    if (tapped == null || steps[index].state == StepState.disabled) {
      return child;
    }
    return InkWell(onTap: () => tapped(index), child: child);
  }

  Widget _controls(BuildContext context, int index) {
    final builder = controlsBuilder;
    if (builder != null) {
      return builder(
        context,
        ControlsDetails(
          currentStep: currentStep,
          stepIndex: index,
          onStepContinue: onStepContinue,
          onStepCancel: onStepCancel,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          FilledButton(
            onPressed: onStepContinue,
            child: const Text('Continue'),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onStepCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.onSurface.withOpacity(0.24);
    final thickness = connectorThickness ?? 1.0;
    if (type == StepperType.horizontal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: thickness,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: line,
                      ),
                    ),
                  _tappable(
                    i,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _circle(context, i),
                        const SizedBox(width: 8),
                        _heading(context, i),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: margin ?? const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                steps[currentStep].content,
                _controls(context, currentStep),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _tappable(
            i,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  _circle(context, i),
                  const SizedBox(width: 12),
                  Expanded(child: _heading(context, i)),
                ],
              ),
            ),
          ),
          // Under the head: the line down to the next step, with the open
          // step's content beside it.
          if (i == currentStep || i < steps.length - 1)
            Container(
              margin: const EdgeInsets.only(left: 35.5),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: i == currentStep ? 16 : 0,
              ),
              constraints: const BoxConstraints(minHeight: 16),
              decoration: i < steps.length - 1
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(color: line, width: thickness),
                      ),
                    )
                  : null,
              child: i == currentStep
                  ? Padding(
                      padding: margin ?? EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [steps[i].content, _controls(context, i)],
                      ),
                    )
                  : null,
            ),
        ],
      ],
    );
  }
}

/// A column of a [DataTable].
class DataColumn {
  const DataColumn({
    required this.label,
    this.tooltip,
    this.numeric = false,
    this.onSort,
    this.columnWidth,
    this.headingRowAlignment,
  });
  final Widget label;
  final String? tooltip;

  /// A column of numbers is set against the end of its cells.
  final bool numeric;

  /// Called with this column's index and the order to sort in when its
  /// heading is tapped.
  final void Function(int columnIndex, bool ascending)? onSort;

  /// Accepted and not carried: the columns share the table's width.
  final Object? columnWidth;
  final MainAxisAlignment? headingRowAlignment;
}

/// A cell of a [DataRow].
class DataCell {
  const DataCell(
    this.child, {
    this.placeholder = false,
    this.showEditIcon = false,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
  });

  /// A cell with nothing in it.
  static const DataCell empty = DataCell(SizedBox.shrink());

  final Widget child;

  /// Draws the child in the quieter colour of a prompt.
  final bool placeholder;
  final bool showEditIcon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
}

/// A row of a [DataTable].
class DataRow {
  const DataRow({
    this.key,
    this.selected = false,
    this.onSelectChanged,
    this.onLongPress,
    this.color,
    required this.cells,
  });

  /// A row keyed by where it is in the table.
  DataRow.byIndex({
    int? index,
    this.selected = false,
    this.onSelectChanged,
    this.onLongPress,
    this.color,
    required this.cells,
  }) : key = ValueKey<int?>(index);

  final Key? key;
  final bool selected;

  /// Makes the row selectable: it gains a checkbox, and a tap on it calls
  /// this with what it should become.
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onLongPress;
  final WidgetStateProperty<Color?>? color;
  final List<DataCell> cells;
}

/// A table of data: a heading row, then a row for each record.
///
/// One thing is different from Flutter, and it decides how a table is used:
/// **the columns share the table's width equally.** Flutter measures every
/// cell and makes each column as wide as its widest, which usually needs a
/// horizontal scroll view around the table; here there is nothing to measure
/// with, so a table is as wide as what it is in and its columns divide that.
/// A cell too narrow for its text wraps it.
///
/// Sorting is the app's: a heading with [DataColumn.onSort] is tapped, the
/// app sorts its rows and says so with [sortColumnIndex] and [sortAscending],
/// and the arrow follows.
class DataTable extends StatelessWidget {
  const DataTable({
    super.key,
    required this.columns,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSelectAll,
    this.decoration,
    this.dataRowColor,
    this.dataRowMinHeight,
    this.dataRowMaxHeight,
    this.dataTextStyle,
    this.headingRowColor,
    this.headingRowHeight,
    this.headingTextStyle,
    this.horizontalMargin,
    this.columnSpacing,
    this.showCheckboxColumn = true,
    this.showBottomBorder = false,
    this.dividerThickness,
    required this.rows,
    this.checkboxHorizontalMargin,
    this.border,
    this.clipBehavior = Clip.none,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final int? sortColumnIndex;
  final bool sortAscending;

  /// Called by the heading's checkbox; without it the checkbox calls every
  /// row's own [DataRow.onSelectChanged].
  final ValueChanged<bool?>? onSelectAll;
  final Decoration? decoration;
  final WidgetStateProperty<Color?>? dataRowColor;
  final double? dataRowMinHeight;
  final TextStyle? dataTextStyle;
  final WidgetStateProperty<Color?>? headingRowColor;
  final double? headingRowHeight;
  final TextStyle? headingTextStyle;

  /// The room at each end of a row. 24 where it is not said.
  final double? horizontalMargin;

  /// The room between two columns. 24 where it is not said - Flutter's 56
  /// supposes a table wider than the screen.
  final double? columnSpacing;
  final bool showCheckboxColumn;
  final bool showBottomBorder;
  final double? dividerThickness;

  /// Accepted and not carried.
  final double? dataRowMaxHeight;
  final double? checkboxHorizontalMargin;
  final Object? border;
  final Clip clipBehavior;

  bool get _selectable =>
      showCheckboxColumn && rows.any((row) => row.onSelectChanged != null);

  void _selectAll(bool? checked) {
    final all = onSelectAll;
    if (all != null) return all(checked);
    for (final row in rows) {
      if (row.selected != (checked ?? false)) row.onSelectChanged?.call(checked);
    }
  }

  /// A row of the table: the checkbox, when rows can be selected, then a
  /// share of the width for each cell.
  Widget _row({
    required Widget? leading,
    required List<Widget> cells,
    required double minHeight,
    Color? color,
  }) {
    final margin = horizontalMargin ?? 24;
    final gap = (columnSpacing ?? 24) / 2;
    return Container(
      color: color,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.symmetric(horizontal: math.max(0, margin - gap)),
      child: Row(
        children: [
          if (_selectable) SizedBox(width: 48, child: leading),
          for (final cell in cells)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gap, vertical: 8),
                child: cell,
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, int index) {
    final column = columns[index];
    final sort = column.onSort;
    final sorted = sortColumnIndex == index;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: column.numeric
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(child: column.label),
        if (sorted)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            ),
          ),
      ],
    );
    final aligned = Align(
      alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: label,
    );
    if (sort == null) return aligned;
    return InkWell(
      // A column already sorted turns round; another starts ascending.
      onTap: () => sort(index, sorted ? !sortAscending : true),
      child: aligned,
    );
  }

  Widget _cell(BuildContext context, DataCell cell, bool numeric) {
    final scheme = Theme.of(context).colorScheme;
    Widget content = cell.child;
    if (cell.placeholder) {
      content = DefaultTextStyle(
        style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
        child: content,
      );
    }
    if (cell.showEditIcon) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: content),
          const SizedBox(width: 4),
          const Icon(Icons.edit, size: 18),
        ],
      );
    }
    content = Align(
      alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: content,
    );
    if (cell.onTap == null &&
        cell.onLongPress == null &&
        cell.onDoubleTap == null) {
      return content;
    }
    return InkWell(
      onTap: cell.onTap,
      onLongPress: cell.onLongPress,
      onDoubleTap: cell.onDoubleTap,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Divider(
      height: dividerThickness ?? 1,
      thickness: dividerThickness ?? 1,
    );
    final selectable = rows.where((row) => row.onSelectChanged != null);
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTextStyle(
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ).merge(headingTextStyle),
          child: _row(
            minHeight: headingRowHeight ?? 56,
            color: headingRowColor?.resolve(const {}),
            leading: Checkbox(
              value:
                  selectable.isNotEmpty &&
                  selectable.every((row) => row.selected),
              onChanged: _selectAll,
            ),
            cells: [
              for (var i = 0; i < columns.length; i++) _heading(context, i),
            ],
          ),
        ),
        for (final (index, row) in rows.indexed) ...[
          divider,
          _dataRow(context, row, index, scheme),
        ],
        if (showBottomBorder) divider,
      ],
    );
    final box = decoration;
    return box == null ? table : Container(decoration: box, child: table);
  }

  Widget _dataRow(
    BuildContext context,
    DataRow row,
    int index,
    ColorScheme scheme,
  ) {
    final states = {if (row.selected) WidgetState.selected};
    final changed = row.onSelectChanged;
    final line = DefaultTextStyle(
      style: const TextStyle(fontSize: 14).merge(dataTextStyle),
      child: _row(
        minHeight: dataRowMinHeight ?? 48,
        color:
            row.color?.resolve(states) ??
            dataRowColor?.resolve(states) ??
            (row.selected ? scheme.primary.withOpacity(0.08) : null),
        leading: changed == null
            ? null
            : Checkbox(value: row.selected, onChanged: changed),
        cells: [
          for (var i = 0; i < row.cells.length && i < columns.length; i++)
            _cell(context, row.cells[i], columns[i].numeric),
        ],
      ),
    );
    if (changed == null && row.onLongPress == null) {
      return KeyedSubtree(key: row.key, child: line);
    }
    return InkWell(
      key: row.key,
      onTap: changed == null ? null : () => changed(!row.selected),
      onLongPress: row.onLongPress,
      child: line,
    );
  }
}

// ---------------------------------------------------------------------------
// Table.
// ---------------------------------------------------------------------------

/// How wide a [Table]'s column is.
///
/// Nothing here measures a cell, so the widths that depend on measuring -
/// [IntrinsicColumnWidth], and the smaller or larger of two - cannot be what
/// they are in Flutter: they share the width like a [FlexColumnWidth].
abstract class TableColumnWidth {
  const TableColumnWidth();

  /// A stated width in pixels, for a column that has one.
  double? get _fixed => null;

  /// The column's share of the width the fixed columns leave.
  double get _flex => 1;
}

/// A share of the width left once the fixed columns have theirs.
class FlexColumnWidth extends TableColumnWidth {
  const FlexColumnWidth([this.value = 1.0]);
  final double value;
  @override
  double get _flex => value;
}

/// A width in pixels.
class FixedColumnWidth extends TableColumnWidth {
  const FixedColumnWidth(this.value);
  final double value;
  @override
  double? get _fixed => value;
}

/// A fraction of the table's width. Drawn as that share against the other
/// columns', which is the same thing where the fractions add up to one.
class FractionColumnWidth extends TableColumnWidth {
  const FractionColumnWidth(this.value);
  final double value;
  @override
  double get _flex => value;
}

/// As wide as its widest cell in Flutter; here a share of the width, [flex]
/// of it or one.
class IntrinsicColumnWidth extends TableColumnWidth {
  const IntrinsicColumnWidth({this.flex});
  final double? flex;
  @override
  double get _flex => flex ?? 1;
}

/// The larger of two widths in Flutter; here the first.
class MaxColumnWidth extends TableColumnWidth {
  const MaxColumnWidth(this.a, this.b);
  final TableColumnWidth a;
  final TableColumnWidth b;
  @override
  double? get _fixed => a._fixed;
  @override
  double get _flex => a._flex;
}

/// The smaller of two widths in Flutter; here the first.
class MinColumnWidth extends MaxColumnWidth {
  const MinColumnWidth(super.a, super.b);
}

/// Where a cell sits in a row taller than it.
enum TableCellVerticalAlignment {
  top,
  middle,
  bottom,
  baseline,
  fill,
  intrinsicHeight,
}

/// The lines of a [Table]: round the outside and between the cells.
class TableBorder {
  const TableBorder({
    this.top = BorderSide.none,
    this.right = BorderSide.none,
    this.bottom = BorderSide.none,
    this.left = BorderSide.none,
    this.horizontalInside = BorderSide.none,
    this.verticalInside = BorderSide.none,
    this.borderRadius = BorderRadius.zero,
  });

  /// The same line everywhere.
  factory TableBorder.all({
    Color color = const Color(0xFF000000),
    double width = 1.0,
    BorderStyle style = BorderStyle.solid,
    BorderRadius borderRadius = BorderRadius.zero,
  }) {
    final side = BorderSide(color: color, width: width, style: style);
    return TableBorder(
      top: side,
      right: side,
      bottom: side,
      left: side,
      horizontalInside: side,
      verticalInside: side,
      borderRadius: borderRadius,
    );
  }

  /// One line for between the cells and one for round the outside.
  const TableBorder.symmetric({
    BorderSide inside = BorderSide.none,
    BorderSide outside = BorderSide.none,
    this.borderRadius = BorderRadius.zero,
  }) : top = outside,
       right = outside,
       bottom = outside,
       left = outside,
       horizontalInside = inside,
       verticalInside = inside;

  final BorderSide top;
  final BorderSide right;
  final BorderSide bottom;
  final BorderSide left;
  final BorderSide horizontalInside;
  final BorderSide verticalInside;
  final BorderRadius borderRadius;

  static bool _drawn(BorderSide side) =>
      side != BorderSide.none && side.width > 0;
}

/// A row of a [Table].
class TableRow {
  const TableRow({this.key, this.decoration, this.children = const []});
  final Key? key;
  final Decoration? decoration;
  final List<Widget> children;
}

/// A cell that sits differently in its row from the table's other cells.
class TableCell extends StatelessWidget {
  const TableCell({super.key, this.verticalAlignment, required this.child});
  final TableCellVerticalAlignment? verticalAlignment;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Rows of cells in columns that line up.
///
/// A column is a stated number of pixels ([FixedColumnWidth]) or a share of
/// what is left ([FlexColumnWidth], the default) - see [TableColumnWidth]
/// for the widths that would need measuring. A cell is as tall as its own
/// content, so the line between two columns ([TableBorder.verticalInside])
/// is as tall as the cell it stands beside rather than the row.
class Table extends StatelessWidget {
  const Table({
    super.key,
    this.children = const [],
    this.columnWidths,
    this.defaultColumnWidth = const FlexColumnWidth(),
    this.textDirection,
    this.border,
    this.defaultVerticalAlignment = TableCellVerticalAlignment.top,
    this.textBaseline,
  });
  final List<TableRow> children;
  final Map<int, TableColumnWidth>? columnWidths;
  final TableColumnWidth defaultColumnWidth;
  final TextDirection? textDirection;
  final TableBorder? border;
  final TableCellVerticalAlignment defaultVerticalAlignment;

  /// Accepted and not carried: see [CrossAxisAlignment.baseline].
  final Object? textBaseline;

  Widget _row(TableRow row) {
    final lines = border;
    final between =
        lines != null && TableBorder._drawn(lines.verticalInside)
        ? lines.verticalInside
        : null;
    final cells = <Widget>[];
    for (final (index, child) in row.children.indexed) {
      final width = columnWidths?[index] ?? defaultColumnWidth;
      final own = child is TableCell ? child.verticalAlignment : null;
      Widget cell = child;
      if (own != null && own != defaultVerticalAlignment) {
        cell = Align(
          alignment: switch (own) {
            TableCellVerticalAlignment.middle => Alignment.centerLeft,
            TableCellVerticalAlignment.bottom => Alignment.bottomLeft,
            _ => Alignment.topLeft,
          },
          child: cell,
        );
      }
      if (between != null && index > 0) {
        cell = Container(
          decoration: BoxDecoration(border: Border(left: between)),
          child: cell,
        );
      }
      final fixed = width._fixed;
      cells.add(
        fixed != null
            ? SizedBox(width: fixed, child: cell)
            // Flex is whole numbers; a thousandth is fine enough for 1.5.
            : Expanded(
                flex: math.max(1, (width._flex * 1000).round()),
                child: cell,
              ),
      );
    }
    final line = Row(
      crossAxisAlignment: switch (defaultVerticalAlignment) {
        TableCellVerticalAlignment.middle => CrossAxisAlignment.center,
        TableCellVerticalAlignment.bottom => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      },
      children: cells,
    );
    final decoration = row.decoration;
    return KeyedSubtree(
      key: row.key,
      child: decoration == null
          ? line
          : Container(decoration: decoration, child: line),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = border;
    final inside =
        lines != null && TableBorder._drawn(lines.horizontalInside)
        ? lines.horizontalInside
        : null;
    Widget table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, row) in children.indexed) ...[
          if (inside != null && index > 0)
            Container(height: inside.width, color: inside.color),
          _row(row),
        ],
      ],
    );
    if (lines != null &&
        [lines.top, lines.right, lines.bottom, lines.left].any(
          TableBorder._drawn,
        )) {
      table = Container(
        decoration: BoxDecoration(
          border: Border(
            top: lines.top,
            right: lines.right,
            bottom: lines.bottom,
            left: lines.left,
          ),
          borderRadius: lines.borderRadius == BorderRadius.zero
              ? null
              : lines.borderRadius,
        ),
        child: table,
      );
    }
    final direction = textDirection;
    return direction == null
        ? table
        : Directionality(textDirection: direction, child: table);
  }
}

// ---------------------------------------------------------------------------
// A list whose rows are dragged into a new order.
// ---------------------------------------------------------------------------

/// Called when a row has been dropped: it was at [oldIndex] and goes before
/// the row now at [newIndex] - Flutter's convention, so an app moving it
/// down takes one off: `if (newIndex > oldIndex) newIndex--`.
typedef ReorderCallback = void Function(int oldIndex, int newIndex);

/// A list whose rows are picked up and dropped into a new order.
///
/// Built on the platform's drag and drop: a row is picked up (after a long
/// press on a touch screen) and dropped on the row whose place it takes.
/// The rows do not part to show where it will land - the row under it is
/// what says so, by what the app draws there - and there is no drag handle:
/// the whole row is what is held.
class ReorderableListView extends StatelessWidget {
  const ReorderableListView({
    super.key,
    required List<Widget> this.children,
    required this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.header,
    this.footer,
    this.padding,
    this.reverse = false,
    this.scrollController,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.buildDefaultDragHandles = true,
    this.proxyDecorator,
    this.scrollDirection = Axis.vertical,
  }) : itemBuilder = null,
       itemCount = null;

  /// Rows built from an index; each needs a key, as in Flutter.
  const ReorderableListView.builder({
    super.key,
    required IndexedWidgetBuilder this.itemBuilder,
    required int this.itemCount,
    required this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.header,
    this.footer,
    this.padding,
    this.reverse = false,
    this.scrollController,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.buildDefaultDragHandles = true,
    this.proxyDecorator,
    this.scrollDirection = Axis.vertical,
  }) : children = null;

  final List<Widget>? children;
  final IndexedWidgetBuilder? itemBuilder;
  final int? itemCount;
  final ReorderCallback onReorder;
  final void Function(int index)? onReorderStart;
  final void Function(int index)? onReorderEnd;
  final Widget? header;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final bool reverse;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final Axis scrollDirection;

  /// Accepted and not carried: the whole row is what is held, and the
  /// lifted picture is the row itself.
  final bool? primary;
  final bool buildDefaultDragHandles;
  final Object? proxyDecorator;

  @override
  Widget build(BuildContext context) {
    final count = children?.length ?? itemCount!;
    Widget rowAt(int index) => children?[index] ?? itemBuilder!(context, index);
    return ListView(
      padding: padding,
      reverse: reverse,
      controller: scrollController,
      physics: physics,
      shrinkWrap: shrinkWrap,
      scrollDirection: scrollDirection,
      children: [
        ?header,
        for (var index = 0; index < count; index++)
          _ReorderRow(
            key: rowAt(index).key,
            index: index,
            onReorder: onReorder,
            onStart: onReorderStart,
            onEnd: onReorderEnd,
            child: rowAt(index),
          ),
        ?footer,
      ],
    );
  }
}

/// A row that can be picked up, and dropped on.
class _ReorderRow extends StatelessWidget {
  const _ReorderRow({
    super.key,
    required this.index,
    required this.onReorder,
    required this.child,
    this.onStart,
    this.onEnd,
  });
  final int index;
  final ReorderCallback onReorder;
  final void Function(int index)? onStart;
  final void Function(int index)? onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<_Reordered>(
    onWillAcceptWithDetails: (details) => details.data.index != index,
    onAcceptWithDetails: (details) {
      final from = details.data.index;
      // Before the row it was dropped on - which, coming from above, is
      // the place after it once the row itself has gone.
      onReorder(from, from < index ? index + 1 : index);
    },
    builder: (context, candidates, rejected) => Draggable<_Reordered>(
      data: _Reordered(index),
      feedback: const SizedBox.shrink(),
      onDragStarted: onStart == null ? null : () => onStart!(index),
      onDragEnd: onEnd == null ? null : (_) => onEnd!(index),
      // Something is over this row: it is where the dragged one will go.
      child: candidates.isEmpty ? child : Opacity(opacity: 0.5, child: child),
    ),
  );
}

/// What a row of a [ReorderableListView] carries while it is dragged.
class _Reordered {
  const _Reordered(this.index);
  final int index;
}

/// Starts a reorder from a handle in Flutter; here the whole row is what is
/// held, so this is its child.
class ReorderableDragStartListener extends StatelessWidget {
  const ReorderableDragStartListener({
    super.key,
    required this.child,
    required this.index,
    this.enabled = true,
  });
  final Widget child;
  final int index;
  final bool enabled;
  @override
  Widget build(BuildContext context) => child;
}

/// As [ReorderableDragStartListener], after a long press.
class ReorderableDelayedDragStartListener extends ReorderableDragStartListener {
  const ReorderableDelayedDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });
}

// ---------------------------------------------------------------------------
// A child that is moved about under the finger.
// ---------------------------------------------------------------------------

/// The transform an [InteractiveViewer] is showing, for an app that wants to
/// read it or set it - to zoom from a button, or put the child back.
class TransformationController extends ValueNotifier<Matrix4> {
  TransformationController([Matrix4? value])
    : super(value ?? Matrix4.identity());
}

/// A child that is dragged about, and zoomed by its controller.
///
/// A finger pans the child. **Two fingers do not zoom it:** no renderer
/// reports a pinch, so the scale is whatever the [transformationController]
/// says - which is how an app gives it zoom buttons - held between
/// [minScale] and [maxScale]. The child is not kept inside the viewer:
/// [boundaryMargin] is accepted and not carried.
class InteractiveViewer extends StatefulWidget {
  const InteractiveViewer({
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = EdgeInsets.zero,
    this.constrained = true,
    this.maxScale = 2.5,
    this.minScale = 0.8,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.transformationController,
    required this.child,
  });
  final Widget child;
  final Clip clipBehavior;

  /// Which way a finger may pan the child.
  final PanAxis panAxis;
  final bool panEnabled;
  final double minScale;
  final double maxScale;
  final TransformationController? transformationController;
  final void Function(Object details)? onInteractionStart;
  final void Function(Object details)? onInteractionUpdate;
  final void Function(Object details)? onInteractionEnd;

  /// Accepted and not carried.
  final EdgeInsets boundaryMargin;
  final bool constrained;
  final bool scaleEnabled;

  @override
  State<InteractiveViewer> createState() => _InteractiveViewerState();
}

/// Which way an [InteractiveViewer] pans.
enum PanAxis { horizontal, vertical, aligned, free }

class _InteractiveViewerState extends State<InteractiveViewer> {
  TransformationController? _own;

  TransformationController get _controller =>
      widget.transformationController ?? (_own ??= TransformationController());

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(InteractiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformationController != widget.transformationController) {
      (oldWidget.transformationController ?? _own)?.removeListener(_changed);
      _controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _pan(DragUpdateDetails details) {
    final across = widget.panAxis != PanAxis.vertical;
    final down = widget.panAxis != PanAxis.horizontal;
    _controller.value = _controller.value.clone()
      ..translate(across ? details.delta.dx : 0, down ? details.delta.dy : 0);
    widget.onInteractionUpdate?.call(details);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _controller.value.clone();
    // Held to the scales the viewer allows, whoever asked for more.
    final scale = shown._scaleX;
    final held = scale.clamp(widget.minScale, widget.maxScale).toDouble();
    if (held != scale) shown.scale(held / scale);
    final moved = Transform(transform: shown, child: widget.child);
    final clipped = widget.clipBehavior == Clip.none
        ? moved as Widget
        : ClipRect(child: moved);
    if (!widget.panEnabled) return clipped;
    final across = widget.panAxis == PanAxis.horizontal;
    final down = widget.panAxis == PanAxis.vertical;
    return GestureDetector(
      onPanStart: across || down ? null : widget.onInteractionStart,
      onPanUpdate: across || down ? null : _pan,
      onPanEnd: across || down ? null : widget.onInteractionEnd,
      onHorizontalDragStart: across ? widget.onInteractionStart : null,
      onHorizontalDragUpdate: across ? _pan : null,
      onHorizontalDragEnd: across ? widget.onInteractionEnd : null,
      onVerticalDragStart: down ? widget.onInteractionStart : null,
      onVerticalDragUpdate: down ? _pan : null,
      onVerticalDragEnd: down ? widget.onInteractionEnd : null,
      child: clipped,
    );
  }
}
