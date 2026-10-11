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
