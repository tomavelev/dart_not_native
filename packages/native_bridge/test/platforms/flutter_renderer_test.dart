/// Widget tests for the Flutter renderer: a WidgetNode tree painted with
/// Flutter widgets.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the todo list's draft handling: every keystroke is echoed back,
/// and a submit records the value and clears the field.
class _DraftApp extends NativeUIApp {
  String draft = '';
  final List<String> submitted = [];

  @override
  void init() {
    on(
      'f_change',
      (data) => setState(() => draft = data['value'] as String? ?? ''),
    );
    on(
      'f_submit',
      (data) => setState(() {
        submitted.add(data['value'] as String? ?? draft);
        draft = '';
      }),
    );
  }

  @override
  WidgetNode build() => UIBuilder.column(
    children: [
      UIBuilder.text('submitted: ${submitted.length}'),
      UIBuilder.textField(hint: 'Draft', eventId: 'f', initialValue: draft),
    ],
  );
}

/// A one-screen app for the host tests.
class _CounterApp extends NativeUIApp {
  int count = 0;

  @override
  void init() => on('increment', (_) => setState(() => count++));

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Counter'),
    body: UIBuilder.center(child: UIBuilder.text('$count')),
    floatingActionButton: UIBuilder.floatingActionButton(
      tooltip: 'Increment',
      eventId: 'increment',
    ),
  );
}

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());
  tearDown(() => renderer.dispose());

  /// Renders [node] on its own inside a Material app.
  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  group('structure', () {
    testWidgets('a scaffold becomes a Scaffold with its app bar and fab', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(title: 'Demo'),
          body: UIBuilder.center(child: UIBuilder.text('Body')),
          floatingActionButton: UIBuilder.floatingActionButton(
            tooltip: 'Add',
            eventId: 'add',
          ),
        ),
      );

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Demo'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('a scaffold without an app bar or fab still renders its body', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: UIBuilder.text('Only body')));

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Only body'), findsOneWidget);
    });

    testWidgets('nothing is painted before the first render', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: renderer.build)),
      );

      expect(find.byType(SizedBox), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unknown node type is visible rather than silently absent', (
      tester,
    ) async {
      await show(tester, const WidgetNode(type: 'Hologram', props: {}));

      expect(find.text('Unknown widget: Hologram'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('column alignment maps onto Flutter', (tester) async {
      await show(
        tester,
        UIBuilder.column(
          crossAxisAlignment: 'stretch',
          children: [UIBuilder.text('a')],
        ),
      );

      expect(
        tester.widget<Column>(find.byType(Column)).crossAxisAlignment,
        CrossAxisAlignment.stretch,
      );
    });

    testWidgets('a plain row reflows rather than overflowing', (tester) async {
      await show(
        tester,
        UIBuilder.row(
          mainAxisAlignment: 'spaceBetween',
          spacing: 12,
          children: [UIBuilder.text('a'), UIBuilder.text('b')],
        ),
      );

      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.alignment, WrapAlignment.spaceBetween);
      expect(wrap.spacing, 12);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('a row holding an Expanded keeps real flex semantics', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.row(
          spacing: 12,
          children: [
            UIBuilder.expanded(child: UIBuilder.text('a')),
            UIBuilder.text('b'),
          ],
        ),
      );

      expect(find.byType(Row), findsOneWidget);
      final gaps = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width == 12);
      expect(gaps, hasLength(1), reason: 'one gap between two children');
    });

    testWidgets('padding, sized box and expanded carry their measurements', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.padding(all: 24, child: UIBuilder.text('padded')),
            UIBuilder.sizedBox(height: 8, width: 16),
            UIBuilder.row(
              children: [
                UIBuilder.expanded(child: UIBuilder.text('grow'), flex: 3),
              ],
            ),
          ],
        ),
      );

      expect(
        tester
            .widget<Padding>(find.widgetWithText(Padding, 'padded').first)
            .padding,
        const EdgeInsets.all(24),
      );
      expect(tester.widget<Expanded>(find.byType(Expanded)).flex, 3);
    });

    testWidgets('iOS stacks become columns and rows', (tester) async {
      await show(
        tester,
        iOSUIBuilder.navigationStack(
          content: iOSUIBuilder.vStack(
            alignment: 'center',
            children: [
              iOSUIBuilder.navigationBar(title: 'Settings'),
              iOSUIBuilder.hStack(children: [UIBuilder.text('row')]),
            ],
          ),
        ),
      );

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.text('row'), findsOneWidget);
    });
  });

  group('text', () {
    testWidgets('styling reaches the TextStyle', (tester) async {
      await show(
        tester,
        UIBuilder.text(
          'styled',
          fontSize: 20,
          fontWeight: 700,
          color: '#ff0000',
          decoration: 'lineThrough',
        ),
      );

      final style = tester.widget<Text>(find.text('styled')).style!;
      expect(style.fontSize, 20);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, const Color(0xffff0000));
      expect(style.decoration, TextDecoration.lineThrough);
    });

    testWidgets('short hex colours are understood', (tester) async {
      await show(tester, UIBuilder.text('x', color: '#f00'));

      expect(
        tester.widget<Text>(find.text('x')).style!.color,
        const Color(0xffff0000),
      );
    });

    testWidgets('an unparseable colour falls back to the theme, not an error', (
      tester,
    ) async {
      await show(tester, UIBuilder.text('x', color: 'rebeccapurple'));

      // Text always carries a colour from the palette - the other renderers
      // paint one too, and inheriting whatever DefaultTextStyle the host
      // happens to have would leave dark text on a dark surface.
      expect(
        tester.widget<Text>(find.text('x')).style!.color,
        const Color(0xff212121),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('events', () {
    testWidgets('a button sends its event and payload', (tester) async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('delete', received.add);
      await show(
        tester,
        UIBuilder.button(label: 'Delete', eventId: 'delete', data: {'id': 7}),
      );

      await tester.tap(find.text('Delete'));

      expect(received, [
        {'id': 7},
      ]);
    });

    testWidgets('a disabled button cannot be tapped', (tester) async {
      var taps = 0;
      renderer.onEvent('save', (_) => taps++);
      await show(
        tester,
        UIBuilder.button(label: 'Save', eventId: 'save', disabled: true),
      );

      await tester.tap(find.text('Save'));

      expect(taps, 0);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    });

    testWidgets('button variants pick different Flutter buttons', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            DSButton.primary(label: 'P', eventId: 'p'),
            DSButton.secondary(label: 'S', eventId: 's'),
            DSButton.tertiary(label: 'T', eventId: 't'),
          ],
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('the fab and icon buttons fire and carry tooltips', (
      tester,
    ) async {
      final fired = <String>[];
      renderer
        ..onEvent('add', (_) => fired.add('add'))
        ..onEvent('delete', (_) => fired.add('delete'));
      await show(
        tester,
        UIBuilder.scaffold(
          body: UIBuilder.iconButton(
            icon: 'delete',
            eventId: 'delete',
            tooltip: 'Delete item',
          ),
          floatingActionButton: UIBuilder.floatingActionButton(
            tooltip: 'Add',
            eventId: 'add',
          ),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.tap(find.byIcon(Icons.delete));

      expect(fired, ['add', 'delete']);
      expect(find.byTooltip('Delete item'), findsOneWidget);
    });

    testWidgets('a checkbox reports its new state with the payload', (
      tester,
    ) async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('toggle', received.add);
      await show(
        tester,
        UIBuilder.checkbox(eventId: 'toggle', checked: false, data: {'id': 3}),
      );

      await tester.tap(find.byType(Checkbox));

      expect(received, [
        {'id': 3, 'checked': true},
      ]);
    });

    testWidgets('a toggle reports its new state', (tester) async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('t', received.add);
      await show(tester, DSToggle.input(eventId: 't', enabled: false));

      await tester.tap(find.byType(Switch));

      expect(received, [
        {'enabled': true},
      ]);
    });

    testWidgets('a radio reports its value', (tester) async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('r', received.add);
      await show(tester, DSRadio.input(eventId: 'r', value: 'b', label: 'B'));

      await tester.tap(find.byIcon(Icons.radio_button_unchecked));

      expect(received, [
        {'value': 'b'},
      ]);
    });

    testWidgets('an event with no handler is reported, not thrown', (
      tester,
    ) async {
      await show(tester, UIBuilder.button(label: 'X', eventId: 'nobody'));

      await tester.tap(find.text('X'));

      expect(tester.takeException(), isNull);
    });
  });

  group('text fields', () {
    testWidgets('render hint, label and error', (tester) async {
      await show(
        tester,
        UIBuilder.textField(
          hint: 'you@example.com',
          eventId: 'email',
          label: 'Email',
          error: 'Invalid email',
        ),
      );

      expect(find.text('you@example.com'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Invalid email'), findsOneWidget);
    });

    testWidgets('honour the iOS placeholder prop too', (tester) async {
      await show(
        tester,
        iOSUIBuilder.textField(placeholder: 'Name', eventId: 'name'),
      );

      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('typing sends change, Enter sends submit', (tester) async {
      final events = <String>[];
      final values = <String>[];
      for (final suffix in ['change', 'submit']) {
        renderer.onEvent('name_$suffix', (data) {
          events.add(suffix);
          values.add(data['value'] as String);
        });
      }
      await show(tester, UIBuilder.textField(hint: 'Name', eventId: 'name'));

      await tester.enterText(find.byType(TextField), 'Ada');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(events, ['change', 'submit']);
      expect(values, ['Ada', 'Ada']);
    });

    testWidgets('focus and blur are reported', (tester) async {
      final events = <String>[];
      for (final suffix in ['focus', 'blur']) {
        renderer.onEvent('name_$suffix', (_) => events.add(suffix));
      }
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.textField(hint: 'Name', eventId: 'name'),
            UIBuilder.button(label: 'Elsewhere', eventId: 'x'),
          ],
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(events, ['focus', 'blur']);
    });

    testWidgets('obscureText and maxLines are honoured', (tester) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.textField(hint: 'pw', eventId: 'pw', obscureText: true),
            UIBuilder.textField(hint: 'bio', eventId: 'bio', maxLines: 4),
          ],
        ),
      );

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.first.obscureText, isTrue);
      expect(fields.first.maxLines, 1);
      expect(fields.last.maxLines, 4);
    });

    testWidgets('a button is drawn at the size it asked for', (tester) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.button(label: 'small', eventId: 's', size: 'sm'),
            UIBuilder.button(label: 'medium', eventId: 'm'),
            UIBuilder.button(label: 'large', eventId: 'l', size: 'lg'),
          ],
        ),
      );

      // The scale every renderer shares: 28/12, 36/14, 44/16.
      final heights = tester
          .widgetList<ElevatedButton>(find.byType(ElevatedButton))
          .map((b) => b.style!.minimumSize!.resolve({})!.height)
          .toList();
      expect(heights, [28.0, 36.0, 44.0]);

      final fonts = tester
          .widgetList<ElevatedButton>(find.byType(ElevatedButton))
          .map((b) => b.style!.textStyle!.resolve({})!.fontSize)
          .toList();
      expect(fonts, [12.0, 14.0, 16.0]);
    });

    testWidgets('a fade is Flutter\'s own AnimatedOpacity', (tester) async {
      await show(
        tester,
        UIBuilder.animatedOpacity(
          opacity: 0.25,
          duration: const Duration(milliseconds: 300),
          child: UIBuilder.text('Saved'),
        ),
      );

      final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(fade.opacity, 0.25);
      expect(fade.duration, const Duration(milliseconds: 300));
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('a box is Flutter\'s own AnimatedContainer', (tester) async {
      await show(
        tester,
        UIBuilder.animatedContainer(
          width: 300,
          height: 64,
          color: '#2196f3',
          duration: const Duration(milliseconds: 300),
          curve: 'easeOut',
          child: UIBuilder.text('Tap'),
        ),
      );

      final box = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(box.constraints?.maxWidth, 300);
      expect(box.constraints?.maxHeight, 64);
      // A colour reaches AnimatedContainer as a decoration; the widget folds
      // it into one either way, and that is what animates.
      expect(
        (box.decoration as BoxDecoration?)?.color,
        const Color(0xFF2196F3),
      );
      expect(box.duration, const Duration(milliseconds: 300));
      expect(box.curve, Curves.easeOut);
      expect(find.text('Tap'), findsOneWidget);
    });

    testWidgets('every curve name reaches a Flutter curve', (tester) async {
      for (final pair in const [
        ('linear', Curves.linear),
        ('ease', Curves.ease),
        ('easeIn', Curves.easeIn),
        ('easeOut', Curves.easeOut),
        ('easeInOut', Curves.easeInOut),
      ]) {
        await show(
          tester,
          UIBuilder.animatedContainer(
            width: 10,
            curve: pair.$1,
            child: UIBuilder.text('x'),
          ),
        );

        expect(
          tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).curve,
          pair.$2,
          reason: pair.$1,
        );
      }
    });

    testWidgets('an opacity outside 0..1 is clamped, not an assertion', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.animatedOpacity(opacity: 4, child: UIBuilder.text('x')),
      );

      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
    });

    testWidgets('tabs are Flutter\'s own, selected where the tree says', (
      tester,
    ) async {
      final taps = <int>[];
      renderer.onEvent('folders', (d) => taps.add(d['index'] as int));

      await show(
        tester,
        UIBuilder.tabs(
          eventId: 'folders',
          tabs: const ['All', 'Unread', 'Archived'],
          selectedIndex: 1,
        ),
      );

      expect(find.text('Unread'), findsOneWidget);
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        1,
      );

      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();

      expect(taps, [2]);
    });

    testWidgets('a grid is Flutter\'s own count grid, which does not scroll', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.grid(
          crossAxisCount: 3,
          spacing: 4,
          runSpacing: 8,
          childAspectRatio: 1.5,
          children: [for (var i = 0; i < 7; i++) UIBuilder.text('$i')],
        ),
      );

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      expect(delegate.crossAxisSpacing, 4);
      expect(delegate.mainAxisSpacing, 8);
      expect(delegate.childAspectRatio, 1.5);
      // The screen around it scrolls; a grid that scrolled too would trap the
      // gesture and size itself to nothing.
      expect(grid.shrinkWrap, isTrue);
      expect(grid.physics, isA<NeverScrollableScrollPhysics>());
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('a slider is Flutter\'s own, and reports both events', (
      tester,
    ) async {
      final changes = <double>[];
      final ends = <double>[];
      renderer
        ..onEvent('vol_change', (d) => changes.add(d['value'] as double))
        ..onEvent('vol_end', (d) => ends.add(d['value'] as double));

      await show(
        tester,
        UIBuilder.slider(
          eventId: 'vol',
          value: 5,
          min: 0,
          max: 10,
          divisions: 10,
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 5);
      expect(slider.min, 0);
      expect(slider.max, 10);
      expect(slider.divisions, 10);

      // Off-centre, because the thumb starts in the middle and a tap that does
      // not move it reports nothing.
      final track = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(track.right - 16, track.center.dy));
      await tester.pumpAndSettle();

      expect(changes, isNotEmpty, reason: 'a tap moves the thumb');
      expect(ends, isNotEmpty, reason: 'and letting go is a decision');
    });

    testWidgets('a value outside the range is clamped, not an assertion', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.slider(eventId: 'v', value: 99, min: 0, max: 10),
      );

      expect(tester.widget<Slider>(find.byType(Slider)).value, 10);
    });

    testWidgets('a stated shape wins over the named size', (tester) async {
      await show(
        tester,
        UIBuilder.button(
          label: 'exact',
          eventId: 'e',
          size: 'lg',
          minHeight: 30,
          minWidth: 120,
          fontSize: 11,
          paddingHorizontal: 6,
          paddingVertical: 2,
        ),
      );

      final style = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .style!;
      expect(style.minimumSize!.resolve({}), const Size(120, 30));
      expect(style.textStyle!.resolve({})!.fontSize, 11);
      expect(
        style.padding!.resolve({}),
        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      );
    });

    testWidgets('a column distributes its children when asked to', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          mainAxisAlignment: 'spaceBetween',
          children: [UIBuilder.text('top'), UIBuilder.text('bottom')],
        ),
      );

      final column = tester.widget<Column>(find.byType(Column).first);
      expect(column.mainAxisAlignment, MainAxisAlignment.spaceBetween);
      // Nothing to distribute inside a column that hugs its children.
      expect(column.mainAxisSize, MainAxisSize.max);
    });

    testWidgets('a column that was not asked still hugs its children', (
      tester,
    ) async {
      await show(tester, UIBuilder.column(children: [UIBuilder.text('x')]));

      final column = tester.widget<Column>(find.byType(Column).first);
      expect(column.mainAxisAlignment, MainAxisAlignment.start);
      expect(column.mainAxisSize, MainAxisSize.min);
    });

    testWidgets('padding reaches Flutter one edge at a time', (tester) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.padding(all: 12, child: UIBuilder.text('uniform')),
            UIBuilder.padding(
              left: 8,
              top: 24,
              right: 4,
              child: UIBuilder.text('mixed'),
            ),
          ],
        ),
      );

      final paddings = tester
          .widgetList<Padding>(find.byType(Padding))
          .where((p) => p.padding is EdgeInsets)
          .map((p) => p.padding as EdgeInsets)
          .toList();

      expect(paddings, contains(const EdgeInsets.all(12)));
      expect(paddings, contains(const EdgeInsets.fromLTRB(8, 24, 4, 0)));
    });

    testWidgets('a label floats in the field, as Flutter draws it', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.textField(hint: 'you@example.com', eventId: 'e',
            label: 'Email'),
      );

      // InputDecoration.labelText is Flutter's floating label; the hint stays
      // the placeholder behind it.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.labelText, 'Email');
      expect(field.decoration!.hintText, 'you@example.com');
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('floatingLabel: false draws the label above the field', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.textField(
          hint: 'you@example.com',
          eventId: 'e',
          label: 'Email',
          floatingLabel: false,
        ),
      );

      // The plain layout the other renderers draw: a label of its own, and
      // nothing in the decoration for the field to float.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.labelText, isNull);
      final label = find.text('Email');
      expect(label, findsOneWidget);
      expect(
        tester.getTopLeft(label).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
    });

    testWidgets('a disabled field is disabled', (tester) async {
      await show(
        tester,
        UIBuilder.textField(hint: 'x', eventId: 'x', enabled: false),
      );

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('keeps what the user typed while the app re-renders', (
      tester,
    ) async {
      Future<void> renderWith(String summary) => show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.text(summary),
            UIBuilder.textField(
              hint: 'Add a todo',
              eventId: 'new_todo',
              initialValue: '',
            ),
          ],
        ),
      );

      await renderWith('0 todos');
      await tester.enterText(find.byType(TextField), 'Buy milk');

      await renderWith('1 todo');

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Buy milk',
      );
    });

    testWidgets(
      'a value that changes twice before the next frame still lands',
      (tester) async {
        // Typing then submitting sets the value and clears it again within one
        // frame, which is what a todo list does on Enter.
        final app = _DraftApp();
        await tester.pumpWidget(MaterialApp(home: NativeUIAppHost(app: app)));

        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(app.submitted, ['Buy milk']);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
          reason: 'the app cleared the draft, so the field must be empty',
        );
      },
    );

    testWidgets('the app can clear a field by changing its value', (
      tester,
    ) async {
      Future<void> renderWith(String value) => show(
        tester,
        UIBuilder.textField(
          hint: 'Add a todo',
          eventId: 'new_todo',
          initialValue: value,
        ),
      );

      await renderWith('draft');
      expect(find.text('draft'), findsOneWidget);

      await renderWith('');

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  });

  group('design system components', () {
    testWidgets('a card renders its title and content', (tester) async {
      await show(
        tester,
        DSCard.elevated(content: UIBuilder.text('Body'), title: 'Title'),
      );

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('an alert shows its message and can be dismissed', (
      tester,
    ) async {
      await show(tester, DSAlert.error(message: 'Save failed', title: 'Oops'));
      expect(find.text('Save failed'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.text('Save failed'), findsNothing);
    });

    testWidgets('loading indicators map onto Flutter progress widgets', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            DSLoading.spinner(),
            DSLoading.progressLinear(value: 0.4),
            DSLoading.skeleton(height: 24),
          ],
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.4);
    });

    testWidgets('an indeterminate bar has no value', (tester) async {
      await show(tester, DSLoading.progressLinear(indeterminate: true));

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    });

    testWidgets('badges and dividers render', (tester) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            DSBadge.solid(label: 'New'),
            DSBadge.dot(),
            DSDivider.horizontal(),
          ],
        ),
      );

      expect(find.text('New'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('lists render one tile per row', (tester) async {
      await show(
        tester,
        AndroidUIBuilder.listView(
          children: [
            AndroidUIBuilder.listItem(text: 'One', subtitle: 'first'),
            AndroidUIBuilder.listItem(text: 'Two'),
          ],
        ),
      );

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('first'), findsOneWidget);
    });
  });

  group('images', () {
    testWidgets('an asset image announces its alt text', (tester) async {
      await show(
        tester,
        UIBuilder.image(src: 'assets/logo.png', alt: 'Company logo'),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.bySemanticsLabel('Company logo'), findsOneWidget);
    });

    testWidgets('a size and a fit reach the widget', (tester) async {
      await show(
        tester,
        UIBuilder.image(
          src: 'assets/logo.png',
          alt: 'Logo',
          width: 120,
          height: 80,
          fit: 'contain',
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 120);
      expect(image.height, 80);
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('an image that will not load shows its alt text instead', (
      tester,
    ) async {
      // The test binding answers every request with a 400, so this is the
      // failure path a broken URL takes.
      await show(
        tester,
        UIBuilder.image(src: 'https://example.com/missing.png', alt: 'Avatar'),
      );
      await tester.pump();

      expect(find.text('Avatar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a url is loaded over the network, a path from assets', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.image(src: 'https://example.com/a.png', alt: 'remote'),
            UIBuilder.image(src: 'images/b.png', alt: 'local'),
          ],
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.first.image, isA<NetworkImage>());
      expect(images.last.image, isA<AssetImage>());
    });
  });

  group('NativeUIAppHost', () {
    testWidgets('mounts the app and paints its first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NativeUIAppHost(app: _CounterApp())),
      );

      expect(find.widgetWithText(AppBar, 'Counter'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('an interaction updates the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NativeUIAppHost(app: _CounterApp())),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('can be pushed as a route into an existing app', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NativeUIAppHost(app: _CounterApp()),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('hot reload repaints the screen', (tester) async {
      final app = _CounterApp();
      await tester.pumpWidget(MaterialApp(home: NativeUIAppHost(app: app)));

      // Hot reload changes what build() returns without changing state, so
      // nothing else would ask the app to paint again. Flutter delivers that
      // to the host as reassemble().
      app.count = 7;
      tester
          .state<NativeUIAppHostState>(find.byType(NativeUIAppHost))
          .reassemble();
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('disposing the host does not leave the app rendering', (
      tester,
    ) async {
      final app = _CounterApp();
      await tester.pumpWidget(MaterialApp(home: NativeUIAppHost(app: app)));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      app.setState(() => app.count = 5);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('text over a colour the app chose', () {
    /// The colour a `Text` node was actually painted in.
    Color? colorOf(WidgetTester tester, String text) => tester
        .widget<Text>(find.text(text))
        .style
        ?.color;

    testWidgets('a dark card carries white text, a pale one near-black', (
      tester,
    ) async {
      await show(
        tester,
        DSCard.filled(
          title: 'Title',
          backgroundColor: '#1a237e',
          content: UIBuilder.text('Body'),
        ),
      );

      expect(colorOf(tester, 'Body'), const Color(0xFFFFFFFF));
      expect(colorOf(tester, 'Title'), const Color(0xFFFFFFFF));

      await show(
        tester,
        DSCard.filled(
          title: 'Title',
          backgroundColor: '#ffeb3b',
          content: UIBuilder.text('Body'),
        ),
      );

      expect(colorOf(tester, 'Body'), const Color(0xFF212121));
    });

    testWidgets('every variant draws the colour the app stated', (
      tester,
    ) async {
      for (final variant in ['elevated', 'outlined', 'filled']) {
        await show(
          tester,
          WidgetNode(
            type: 'Card',
            props: {'variant': variant, 'backgroundColor': '#1a237e'},
            children: [UIBuilder.text('Body')],
          ),
        );

        expect(
          tester.widget<Card>(find.byType(Card)).color,
          const Color(0xFF1A237E),
          reason: variant,
        );
        expect(colorOf(tester, 'Body'), const Color(0xFFFFFFFF), reason: variant);
      }
    });

    testWidgets('text that states its own colour keeps it', (tester) async {
      await show(
        tester,
        DSCard.filled(
          backgroundColor: '#1a237e',
          content: UIBuilder.text('Body', color: '#ff0000'),
        ),
      );

      expect(colorOf(tester, 'Body'), const Color(0xFFFF0000));
    });

    testWidgets('a card the app did not colour keeps the theme\'s text', (
      tester,
    ) async {
      await show(tester, DSCard.filled(content: UIBuilder.text('Body')));

      expect(colorOf(tester, 'Body'), isNot(const Color(0xFFFFFFFF)));
    });

    testWidgets('a filled button reads over the fill it was given', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.button(label: 'Go', eventId: 'go', color: '#ffeb3b'),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(
        button.style!.foregroundColor!.resolve({}),
        const Color(0xFF212121),
      );
    });

    testWidgets('an animated box hands its colour to what is inside it', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.animatedContainer(
          color: '#1a237e',
          child: UIBuilder.text('Inside'),
        ),
      );

      expect(colorOf(tester, 'Inside'), const Color(0xFFFFFFFF));
    });
  });


  group('text that does not fit', () {
    testWidgets('a cap and an ellipsis reach Flutter\'s own Text', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.text('A long line', maxLines: 2, overflow: 'ellipsis'),
      );

      final text = tester.widget<Text>(find.text('A long line'));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('clipping says clip, and no cap says nothing', (tester) async {
      await show(
        tester,
        UIBuilder.text('Clipped', maxLines: 1, overflow: 'clip'),
      );
      expect(
        tester.widget<Text>(find.text('Clipped')).overflow,
        TextOverflow.clip,
      );

      await show(tester, UIBuilder.text('Free'));
      final free = tester.widget<Text>(find.text('Free'));
      expect(free.maxLines, isNull);
      expect(free.overflow, isNull);
    });
  });
}
