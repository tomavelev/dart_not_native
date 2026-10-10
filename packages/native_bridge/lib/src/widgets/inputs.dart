part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Text input.
// ---------------------------------------------------------------------------

/// Holds a text field's value the Flutter way, so an app can read it (to add a
/// todo) and `clear()` it after. Its `text` seeds the field and is kept current
/// as the user types.
///
/// A [_version] counter separates an app-driven edit (`clear()`, or setting
/// [text]) from the user's own typing: only the former bumps it, and the field
/// node carries it, so a renderer can apply a clear that happens while the field
/// is focused without a re-render on every keystroke fighting the typing.
///
/// It is a [ChangeNotifier], as Flutter's is: listeners hear both kinds of
/// change. Setting [text] also redraws the field it is attached to, so a
/// `clear()` needs no `setState` around it.
class TextEditingController extends ChangeNotifier {
  TextEditingController({String? text}) : _text = text ?? '';
  String _text;
  int _version = 0;
  _Owner? _owner;

  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _version++;
    notifyListeners();
    _owner?._requestRebuild();
  }

  void clear() => text = '';

  /// The field reporting the user's own typing; does not bump the version,
  /// and does not redraw - the field already shows what was typed.
  void _setFromUser(String value) {
    if (_text == value) return;
    _text = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _owner = null;
    super.dispose();
  }
}

/// Asks for, or gives up, the keyboard on a field.
///
/// Flutter's `FocusNode` is a live object a field attaches itself to; here the
/// tree is the only thing that crosses to a renderer, so the ask travels as a
/// version. `requestFocus()` bumps it and the renderer focuses the field it
/// sits on; `unfocus()` bumps it the other way and the keyboard goes.
///
/// ```dart
/// final email = FocusNode();
/// ...
/// TextField(focusNode: email, ...)
/// ...
/// onPressed: email.requestFocus,
/// ```
///
/// Asking redraws the field the node is attached to, since the ask reaches
/// the renderer with the next tree.
class FocusNode extends ChangeNotifier {
  FocusNode({this.debugLabel, this.skipTraversal = false, this.canRequestFocus = true});

  final String? debugLabel;

  /// Accepted for Flutter's signature and not consulted.
  bool skipTraversal;
  bool canRequestFocus;

  int _version = 0;
  bool _wanted = true;
  bool _focused = false;
  _Owner? _owner;

  /// Counts every ask for focus, on any node, so two asks can be told apart
  /// by which came later.
  static int _asks = 0;

  /// When this node was last asked for focus, on that count; 0 for never,
  /// and after an [unfocus]. A text field does not need it - a renderer
  /// knows which field has the keyboard - but a [KeyboardListener] has
  /// nothing else to go on.
  int _askedAt = 0;
  bool _autofocused = false;

  /// Whether the last ask was for the keyboard rather than against it.
  bool get isRequested => _wanted;

  /// Whether the field this node sits on has the keyboard, as far as the
  /// renderer has reported.
  bool get hasFocus => _focused;
  bool get hasPrimaryFocus => _focused;

  /// Take the keyboard on the next render.
  void requestFocus([FocusNode? node]) {
    if (node != null) return node.requestFocus();
    _version++;
    _wanted = true;
    _askedAt = ++_asks;
    _owner?._requestRebuild();
  }

  /// Give it up on the next render.
  void unfocus() {
    _version++;
    _wanted = false;
    _askedAt = 0;
    _owner?._requestRebuild();
  }

  void _report(bool focused) {
    if (_focused == focused) return;
    _focused = focused;
    if (focused) {
      FocusManager.instance._primary = this;
    } else if (identical(FocusManager.instance._primary, this)) {
      FocusManager.instance._primary = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _owner = null;
    if (identical(FocusManager.instance._primary, this)) {
      FocusManager.instance._primary = null;
    }
    super.dispose();
  }
}

/// Knows which [FocusNode] has the keyboard, for
/// `FocusManager.instance.primaryFocus?.unfocus()`.
class FocusManager {
  FocusManager._();
  static final FocusManager instance = FocusManager._();

  FocusNode? _primary;

  /// The node of the field that has the keyboard - if that field was given a
  /// node. A field without one is focused by the platform and invisible here.
  FocusNode? get primaryFocus => _primary;
}

/// What `FocusScope.of(context)` answers with.
class FocusScopeNode {
  const FocusScopeNode._(this._owner);
  final _Owner _owner;

  bool get hasFocus => FocusManager.instance._primary != null;

  /// Gives up the keyboard, if the field holding it has a [FocusNode].
  void unfocus() => FocusManager.instance._primary?.unfocus();

  /// Moves the keyboard to [node]'s field.
  void requestFocus([FocusNode? node]) => node?.requestFocus();

  /// Sends the keyboard to the field after the one that has it, in the
  /// order the fields are built, and round to the first after the last.
  ///
  /// "The one that has it" is the field whose `onSubmitted` or
  /// `onEditingComplete` this is called from - which is where it is nearly
  /// always called from - or else the field whose [FocusNode] last reported
  /// the keyboard. Called from anywhere else with no such node, it has no
  /// way to know where the keyboard is, and starts from the first field.
  /// Read-only and disabled fields, and ones whose node says
  /// `skipTraversal`, are passed over.
  ///
  /// False when there is no other field to go to. A field with
  /// `TextInputAction.next` is also moved on from by the renderer, to the
  /// same field.
  bool nextFocus() => _owner._moveFocus(1);

  /// As [nextFocus], the other way.
  bool previousFocus() => _owner._moveFocus(-1);
}

/// Flutter's entry to the focus tree, for the two calls apps make on it.
abstract final class FocusScope {
  static FocusScopeNode of(BuildContext context) =>
      FocusScopeNode._(_ownerOf(context));
}

/// What the keyboard's return key says and does.
///
/// Flutter's names. The protocol has two behaviours - close the keyboard, or
/// move to the next field - so `next` is the second and every other action is
/// the first.
enum TextInputAction {
  none,
  unspecified,

  /// Closes the keyboard.
  done,
  go,
  search,
  send,

  /// Moves to the next field in the tree's reading order, so a form is filled
  /// in without reaching for each field. The last field has nowhere to go and
  /// closes the keyboard instead, and a multi-line field keeps its newline key
  /// whatever this says.
  next,
  previous,
  continueAction,
  join,
  route,
  emergencyCall,
  newline,
}

/// Which keyboard a field raises.
class TextInputType {
  const TextInputType._(this._name);

  /// A number pad, with a decimal point if [decimal]. [signed] is accepted
  /// and not carried.
  const TextInputType.numberWithOptions({bool? signed, bool? decimal})
    : _name = decimal == true ? 'decimal' : 'number';

  final String _name;

  static const TextInputType text = TextInputType._('text');
  static const TextInputType multiline = TextInputType._('multiline');
  static const TextInputType number = TextInputType._('number');
  static const TextInputType phone = TextInputType._('phone');
  static const TextInputType emailAddress = TextInputType._('email');
  static const TextInputType url = TextInputType._('url');

  // No keyboard of their own on the platforms; they are the text keyboard.
  static const TextInputType datetime = TextInputType._('text');
  static const TextInputType visiblePassword = TextInputType._('text');
  static const TextInputType name = TextInputType._('text');
  static const TextInputType streetAddress = TextInputType._('text');
  static const TextInputType none = TextInputType._('text');

  @override
  bool operator ==(Object other) =>
      other is TextInputType && other._name == _name;
  @override
  int get hashCode => _name.hashCode;
}

/// Which letters the keyboard capitalises on its own.
enum TextCapitalization { words, sentences, characters, none }

/// Where a field's label sits - the slice of Flutter's `FloatingLabelBehavior`
/// the protocol carries.
enum FloatingLabelBehavior {
  /// Above the field, as plain text, on every renderer.
  never,

  /// In the field's outline, rising out of the way once the field has focus or
  /// a value. What Flutter does, and what Material and the web do. The native
  /// iOS renderer keeps the label above the field, since UIKit has no floating
  /// label and iOS forms do not use one.
  auto,

  /// Drawn as [auto]: a label that is always raised is one the renderers have
  /// no separate way to draw.
  always,
}

/// The outline of a field: none ([InputBorder.none]), a line under it
/// ([UnderlineInputBorder]) or a box around it ([OutlineInputBorder]). The
/// kind travels to the renderer, with the side's colour and width where the
/// app chose them and an outline's radius; a field given no border keeps its
/// platform's own.
class InputBorder {
  const InputBorder({this.borderSide = BorderSide.none});
  final BorderSide borderSide;
  static const InputBorder none = InputBorder();
}

class OutlineInputBorder extends InputBorder {
  const OutlineInputBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = const BorderRadius.all(Radius.circular(4.0)),
    this.gapPadding = 4.0,
  });
  final BorderRadius borderRadius;
  final double gapPadding;
}

class UnderlineInputBorder extends InputBorder {
  const UnderlineInputBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = const BorderRadius.only(
      topLeft: Radius.circular(4.0),
      topRight: Radius.circular(4.0),
    ),
  });
  final BorderRadius borderRadius;
}

/// What surrounds the text of a field: its label, hint, helper and error, and
/// an icon at either end.
///
/// Those travel, and so does the field's look: whether it is [filled] and
/// with what ([fillColor]), its outline ([border], or [enabledBorder] when
/// that is given - the kind, and the side's colour and width where the app
/// chose them), and the room inside it ([contentPadding]). The borders for
/// the other states - focused, in error, disabled - and the text styles of
/// the label, the hint and the helper are the renderer's own.
class InputDecoration {
  const InputDecoration({
    this.icon,
    this.label,
    this.labelText,
    this.labelStyle,
    this.helperText,
    this.helperStyle,
    this.helperMaxLines,
    this.hintText,
    this.hintStyle,
    this.errorText,
    this.errorStyle,
    this.errorMaxLines,
    this.floatingLabelBehavior = FloatingLabelBehavior.auto,
    this.isDense,
    this.contentPadding,
    this.prefixIcon,
    this.prefixText,
    this.suffixIcon,
    this.suffixText,
    this.counterText,
    this.filled,
    this.fillColor,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.focusedErrorBorder,
    this.disabledBorder,
    this.enabled = true,
    this.alignLabelWithHint,
  });

  /// A decoration with nothing in it. Flutter's has no outline either; this
  /// one keeps the platform's unless it is built with `border:
  /// InputBorder.none` through the ordinary constructor.
  const InputDecoration.collapsed({required this.hintText, this.hintStyle})
    : icon = null,
      label = null,
      labelText = null,
      labelStyle = null,
      helperText = null,
      helperStyle = null,
      helperMaxLines = null,
      errorText = null,
      errorStyle = null,
      errorMaxLines = null,
      floatingLabelBehavior = FloatingLabelBehavior.auto,
      isDense = null,
      contentPadding = null,
      prefixIcon = null,
      prefixText = null,
      suffixIcon = null,
      suffixText = null,
      counterText = null,
      filled = null,
      fillColor = null,
      border = null,
      enabledBorder = null,
      focusedBorder = null,
      errorBorder = null,
      focusedErrorBorder = null,
      disabledBorder = null,
      enabled = true,
      alignLabelWithHint = null;

  /// Drawn before the field, outside it, as it is: any widget, with its own
  /// taps.
  final Widget? icon;

  /// A label as a widget; its text is what travels.
  final Widget? label;
  final String? labelText;
  final TextStyle? labelStyle;
  final String? helperText;
  final TextStyle? helperStyle;
  final int? helperMaxLines;
  final String? hintText;
  final TextStyle? hintStyle;
  final String? errorText;
  final TextStyle? errorStyle;
  final int? errorMaxLines;

  /// Whether [labelText] floats in the field's outline or sits above it.
  final FloatingLabelBehavior floatingLabelBehavior;
  final bool? isDense;
  final EdgeInsetsGeometry? contentPadding;

  /// An icon at the start of the field: an [Icon].
  final Widget? prefixIcon;
  final String? prefixText;

  /// An icon at the end of the field: an [Icon], or an [IconButton] whose
  /// `onPressed` runs when it is tapped - a clear button, a show-password eye.
  final Widget? suffixIcon;
  final String? suffixText;
  final String? counterText;
  final bool? filled;
  final Color? fillColor;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final InputBorder? focusedErrorBorder;
  final InputBorder? disabledBorder;
  final bool enabled;
  final bool? alignLabelWithHint;

  InputDecoration copyWith({
    Widget? icon,
    Widget? label,
    String? labelText,
    String? helperText,
    String? hintText,
    String? errorText,
    FloatingLabelBehavior? floatingLabelBehavior,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? counterText,
    bool? filled,
    Color? fillColor,
    InputBorder? border,
    bool? enabled,
  }) => InputDecoration(
    icon: icon ?? this.icon,
    label: label ?? this.label,
    labelText: labelText ?? this.labelText,
    labelStyle: labelStyle,
    helperText: helperText ?? this.helperText,
    helperStyle: helperStyle,
    helperMaxLines: helperMaxLines,
    hintText: hintText ?? this.hintText,
    hintStyle: hintStyle,
    errorText: errorText ?? this.errorText,
    errorStyle: errorStyle,
    errorMaxLines: errorMaxLines,
    floatingLabelBehavior: floatingLabelBehavior ?? this.floatingLabelBehavior,
    isDense: isDense,
    contentPadding: contentPadding,
    prefixIcon: prefixIcon ?? this.prefixIcon,
    prefixText: prefixText,
    suffixIcon: suffixIcon ?? this.suffixIcon,
    suffixText: suffixText,
    counterText: counterText ?? this.counterText,
    filled: filled ?? this.filled,
    fillColor: fillColor ?? this.fillColor,
    border: border ?? this.border,
    enabledBorder: enabledBorder,
    focusedBorder: focusedBorder,
    errorBorder: errorBorder,
    focusedErrorBorder: focusedErrorBorder,
    disabledBorder: disabledBorder,
    enabled: enabled ?? this.enabled,
    alignLabelWithHint: alignLabelWithHint,
  );
}

/// The glyph of a decoration's icon, and what tapping it does: the protocol
/// carries a codepoint and a tap, so that is what is read out of the widget.
(IconData?, VoidCallback?) _fieldIcon(Widget? widget) => switch (widget) {
  Icon() => (widget.icon, null),
  IconButton() => (
    widget.icon is Icon ? (widget.icon as Icon).icon : null,
    widget.onPressed,
  ),
  InkWell() => (
    widget.child is Icon ? (widget.child as Icon).icon : null,
    widget.onTap,
  ),
  GestureDetector() => (
    widget.child is Icon ? (widget.child as Icon).icon : null,
    widget.onTap,
  ),
  Padding() => _fieldIcon(widget.child),
  _ => (null, null),
};

/// A field of text: Flutter's `TextField`, drawn by the platform's own.
///
/// [onFocus] and [onBlur] are this framework's additions; in Flutter the same
/// thing is a listener on a [FocusNode], which works here as well.
class TextField extends Widget {
  const TextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textAlign = TextAlign.start,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableInteractiveSelection,
    this.cursorColor,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.showCursor,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.enabled,
    this.onTap,
    this.onFocus,
    this.onBlur,
  });
  final TextEditingController? controller;

  /// Asks for the keyboard from the app's side - see [FocusNode].
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;

  /// What the keyboard's return key does - see [TextInputAction]. Closes the
  /// keyboard when left null.
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;

  /// The style of what is typed: its colour, size and weight travel. The
  /// rest of a [TextStyle] - the family, the spacing, the decoration - does
  /// not, and the hint stays the renderer's grey.
  final TextStyle? style;
  final TextAlign textAlign;

  /// Shows its value and takes a tap but not typing: the field that opens a
  /// date picker from [onTap].
  final bool readOnly;

  /// Takes the keyboard the first time the field is drawn, for a screen whose
  /// whole point is a field: a search, a single-question form.
  final bool autofocus;
  final bool obscureText;

  /// Accepted and not carried.
  final bool autocorrect;
  final bool enableSuggestions;

  /// Accepted and not carried: the caret and the selection handles are the
  /// platform field's own.
  final bool? enableInteractiveSelection;
  final Color? cursorColor;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final bool? showCursor;

  /// How many lines the field shows. Null in Flutter means "as many as the
  /// text needs"; a platform field wants a number, so null is drawn as
  /// [minLines], or four.
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final bool? enabled;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final VoidCallback? onBlur;

  /// How the field looks, where the app said: the style of what is typed,
  /// what the field is filled with, its outline and the room inside it.
  /// Nothing for a field that says none of it, which is then the renderer's.
  Map<String, dynamic> _look(_Owner owner) {
    final style = this.style;
    final decoration = this.decoration;
    // The border a field has at rest; the ones for the other states are the
    // renderer's own.
    final border = decoration?.enabledBorder ?? decoration?.border;
    final side = border?.borderSide;
    // A side nobody chose is Flutter's placeholder - black, one wide - which
    // a theme replaces there and a renderer replaces here.
    final chosen = side != null && side != const BorderSide() && side != BorderSide.none;
    final padding = decoration?.contentPadding?._resolved._ltrb;
    return {
      'textColor': ?style?.color?._hex,
      'fontSize': ?style?.fontSize,
      'fontWeight': ?style?.fontWeight?.value,
      // Filled, in the colour given or a faint wash of what is written on
      // the surface, which is Material's.
      if (decoration?.filled == true)
        'fillColor':
            (decoration!.fillColor ??
                    _themeOf(owner).colorScheme.onSurface.withOpacity(0.06))
                ._hex,
      if (border != null)
        'border': switch (border) {
          OutlineInputBorder() => 'outline',
          UnderlineInputBorder() => 'underline',
          _ => 'none',
        },
      if (chosen) 'borderColor': side.color._hex,
      if (chosen) 'borderWidth': side.width,
      if (border is OutlineInputBorder)
        'borderRadius': border.borderRadius.topLeft.x,
      'contentPadding': ?padding,
    };
  }

  @override
  WidgetNode _render(_Owner owner) {
    final bindings = EventBindings.required;
    final controller = this.controller;
    // Every field has a node, its own or one kept for its place, so that
    // `FocusScope.nextFocus` has somewhere to send the keyboard. Only a node
    // the app gave is told about focus and blur: that is an event per field
    // per move, and nobody is listening to a node nobody holds.
    final given = this.focusNode;
    final focusNode = owner._focusFor(given);
    controller?._owner = owner;
    if (owner._hidden == 0 &&
        (enabled ?? this.decoration?.enabled ?? true) &&
        !readOnly &&
        focusNode.canRequestFocus &&
        !focusNode.skipTraversal) {
      owner._focusOrder.add(focusNode);
    }
    // The controller tracks the value as it is typed (without bumping its
    // version, so no forced re-render per keystroke); the field's own callback
    // still runs. The node carries the version, so a renderer can tell an
    // app-driven clear() from the user's own typing.
    void Function(String)? handleChanged;
    if (controller != null || onChanged != null) {
      handleChanged = (value) {
        controller?._setFromUser(value);
        onChanged?.call(value);
      };
    }
    void Function(String)? handleSubmitted;
    if (onSubmitted != null || onEditingComplete != null) {
      handleSubmitted = (value) {
        // "Next" said from here means the field after this one.
        owner._submitting = focusNode;
        try {
          onEditingComplete?.call();
          onSubmitted?.call(value);
        } finally {
          owner._submitting = null;
        }
      };
    }
    final id = _idOf(key);
    final eventId = bindings.allocate(key: id);
    bindings.onText(
      eventId,
      onChanged: handleChanged,
      onSubmitted: handleSubmitted,
      onFocus: onFocus == null && given == null
          ? null
          : () {
              given?._report(true);
              onFocus?.call();
            },
      onBlur: onBlur == null && given == null
          ? null
          : () {
              given?._report(false);
              onBlur?.call();
            },
    );
    final tap = onTap;
    if (tap != null) bindings.onTap('${eventId}_tap', tap);
    final decoration = this.decoration;
    final (prefix, _) = _fieldIcon(decoration?.prefixIcon);
    final (suffix, suffixTap) = _fieldIcon(decoration?.suffixIcon);
    if (suffix != null && suffixTap != null) {
      bindings.onTap('${eventId}_suffix', suffixTap);
    }
    final label = decoration?.labelText ?? _stringOf(decoration?.label, owner);
    final keyboard = keyboardType?._name;
    final align = _textAlignName(textAlign, owner);
    final field = WidgetNode(
      type: 'TextField',
      props: {
        ..._look(owner),
        'hint': decoration?.hintText ?? '',
        'eventId': eventId,
        if (id != null) 'id': id,
        if (label != null) 'label': label,
        if (label != null &&
            decoration!.floatingLabelBehavior == FloatingLabelBehavior.never)
          'floatingLabel': false,
        if (decoration?.errorText != null) 'error': decoration!.errorText,
        'obscureText': obscureText,
        'enabled': enabled ?? decoration?.enabled ?? true,
        if (controller != null) 'initialValue': controller.text,
        if (controller != null) 'valueVersion': controller._version,
        if (autofocus) 'autofocus': true,
        // Version 0 is "never asked": a field holding a node nobody has
        // called yet must not take the keyboard on first render.
        if (focusNode._version > 0) 'focusVersion': focusNode._version,
        if (focusNode._version > 0 && !focusNode._wanted)
          'focusRequested': false,
        'maxLines': maxLines ?? math.max(minLines ?? 1, 4),
        'textInputAction': textInputAction == TextInputAction.next
            ? 'next'
            : 'done',
        if (keyboard != null && keyboard != 'text') 'keyboardType': keyboard,
        if (readOnly) 'readOnly': true,
        if (tap != null) 'tappable': true,
        if (decoration?.helperText != null) 'helper': decoration!.helperText,
        if (prefix != null) 'prefixIcon': prefix.codePoint,
        if (suffix != null) 'suffixIcon': suffix.codePoint,
        if (suffix != null && suffixTap != null) 'suffixTappable': true,
        if (maxLength != null) 'maxLength': maxLength,
        if (textCapitalization != TextCapitalization.none)
          'textCapitalization': textCapitalization.name,
        if (align != null) 'textAlign': align,
      },
    );
    // `InputDecoration.icon` stands outside the field, before it, and is any
    // widget at all - a button that opens a scanner, as often as a glyph. The
    // platform's field has no such place, so it is laid out here: the icon,
    // then the field in the room that is left.
    final icon = decoration?.icon;
    if (icon == null) return field;
    // Laid out as the widgets an app would write, so the row fills the width
    // it is given and the field takes what the icon leaves, on every renderer.
    return owner.inSlot(
      'decorated',
      () => Row(
        children: [
          icon,
          const SizedBox(width: 16),
          Expanded(child: _NodeWidget((_) => field)),
        ],
      )._render(owner),
    );
  }
}

// ---------------------------------------------------------------------------
// Forms, Flutter's way: a Form above, FormFields below, a GlobalKey to reach
// the FormState.
// ---------------------------------------------------------------------------

/// Checks a field's value, answering the error to show or null when it is
/// fine.
typedef FormFieldValidator<T> = String? Function(T? value);

/// Receives a field's value when the form is saved.
typedef FormFieldSetter<T> = void Function(T? newValue);

/// Builds a form field's widget from its state.
typedef FormFieldBuilder<T> = Widget Function(FormFieldState<T> field);

/// When a field checks itself without being asked.
enum AutovalidateMode {
  /// Only when `validate()` is called.
  disabled,

  /// On every build.
  always,

  /// On every build once the user has changed the field.
  onUserInteraction,

  /// Flutter validates when the field loses focus; drawn here as
  /// [onUserInteraction], the nearest thing a rebuild can know.
  onUnfocus,
}

class _FormScope extends InheritedWidget {
  const _FormScope({required this.form, required super.child});
  final FormState form;

  @override
  bool updateShouldNotify(_FormScope oldWidget) =>
      !identical(oldWidget.form, form);
}

/// Groups [FormField]s so they can be validated, saved and reset together.
///
/// ```dart
/// final _formKey = GlobalKey<FormState>();
///
/// Form(
///   key: _formKey,
///   child: TextFormField(validator: (v) => v!.isEmpty ? 'Required' : null),
/// )
/// ...
/// if (_formKey.currentState!.validate()) _formKey.currentState!.save();
/// ```
///
/// The framework's own form model - fields declared in Dart with validators,
/// async checks, undo - is still here, as [FormModel].
class Form extends StatefulWidget {
  const Form({
    super.key,
    required this.child,
    this.canPop,
    this.onChanged,
    this.autovalidateMode,
  });

  final Widget child;

  /// Accepted for Flutter's signature and not consulted.
  final bool? canPop;

  /// Called when any field of the form changes.
  final VoidCallback? onChanged;

  /// The mode every field without one of its own follows.
  final AutovalidateMode? autovalidateMode;

  static FormState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FormScope>()?.form;

  static FormState of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('Form.of() called with no Form above the context.'));

  @override
  FormState createState() => FormState();
}

class FormState extends State<Form> {
  /// The fields the last build drew. A field that left the tree has left the
  /// form with it.
  final Set<FormFieldState<dynamic>> _fields = {};

  /// Checks every field, shows each one's error, and answers whether all of
  /// them passed.
  bool validate() => _batch(() {
    var valid = true;
    for (final field in List.of(_fields)) {
      valid = field.validate() && valid;
    }
    return valid;
  });

  /// As [validate], answering the fields that failed.
  Set<FormFieldState<Object?>> validateGranularly() => _batch(
    () => {
      for (final field in List.of(_fields))
        if (!field.validate()) field,
    },
  );

  /// Hands every field's value to its `onSaved`.
  void save() {
    for (final field in List.of(_fields)) {
      field.save();
    }
  }

  /// Puts every field back to its initial value and clears the errors.
  void reset() => _batch(() {
    for (final field in List.of(_fields)) {
      field.reset();
    }
  });

  /// Runs [body], which may `setState` on every field, as one rebuild.
  T _batch<T>(T Function() body) {
    final owner = _owner;
    return owner == null ? body() : owner._batch(body);
  }

  void _fieldDidChange() => widget.onChanged?.call();

  @override
  Widget build(BuildContext context) {
    _fields.clear();
    return _FormScope(form: this, child: widget.child);
  }
}

/// One input of a [Form]: a value, a validator and the error it produced.
class FormField<T> extends StatefulWidget {
  const FormField({
    super.key,
    required this.builder,
    this.onSaved,
    this.forceErrorText,
    this.validator,
    this.initialValue,
    this.enabled = true,
    this.autovalidateMode,
  });

  final FormFieldBuilder<T> builder;
  final FormFieldSetter<T>? onSaved;

  /// An error shown whatever the validator says - one that came back from a
  /// server, say.
  final String? forceErrorText;
  final FormFieldValidator<T>? validator;
  final T? initialValue;
  final bool enabled;
  final AutovalidateMode? autovalidateMode;

  @override
  FormFieldState<T> createState() => FormFieldState<T>();
}

class FormFieldState<T> extends State<FormField<T>> {
  late T? _value = widget.initialValue;
  String? _errorText;
  bool _interacted = false;

  T? get value => _value;

  /// The error to show, or null.
  String? get errorText => widget.forceErrorText ?? _errorText;
  bool get hasError => errorText != null;
  bool get hasInteractedByUser => _interacted;

  /// Whether the validator passes, without showing its error.
  bool get isValid =>
      widget.forceErrorText == null && widget.validator?.call(_value) == null;

  /// Hands the value to `onSaved`.
  void save() => widget.onSaved?.call(value);

  /// Back to the initial value, with no error.
  void reset() {
    setState(() {
      _value = widget.initialValue;
      _interacted = false;
      _errorText = null;
    });
    Form.maybeOf(context)?._fieldDidChange();
  }

  /// Runs the validator, shows what it said, and answers whether it passed.
  bool validate() {
    setState(_validate);
    return !hasError;
  }

  void _validate() => _errorText = widget.validator?.call(_value);

  /// The user changed the field to [value].
  void didChange(T? value) {
    setState(() {
      _value = value;
      _interacted = true;
    });
    Form.maybeOf(context)?._fieldDidChange();
  }

  /// Sets the value without telling anyone - for a subclass keeping the
  /// field in step with something else.
  void setValue(T? value) => _value = value;

  bool get _autovalidates {
    if (!widget.enabled) return false;
    final mode =
        widget.autovalidateMode ??
        Form.maybeOf(context)?.widget.autovalidateMode ??
        AutovalidateMode.disabled;
    return switch (mode) {
      AutovalidateMode.disabled => false,
      AutovalidateMode.always => true,
      AutovalidateMode.onUserInteraction ||
      AutovalidateMode.onUnfocus => _interacted,
    };
  }

  /// What a subclass draws; the base draws the widget's `builder`.
  Widget buildField(BuildContext context) => widget.builder(this);

  @override
  Widget build(BuildContext context) {
    if (_autovalidates) _validate();
    Form.maybeOf(context)?._fields.add(this);
    return buildField(context);
  }
}

Widget _noFieldBuilder(FormFieldState<dynamic> field) =>
    const SizedBox.shrink();

/// A [TextField] that is a [FormField]: Flutter's `TextFormField`.
///
/// Give it a [validator] and put it under a [Form]; `FormState.validate()`
/// then shows the error under the field. Without a [controller] it keeps its
/// own, seeded from [initialValue].
class TextFormField extends FormField<String> {
  const TextFormField({
    super.key,
    this.controller,
    String? initialValue,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableInteractiveSelection,
    this.cursorColor,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.showCursor,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onTap,
    this.onEditingComplete,
    this.onFieldSubmitted,
    super.onSaved,
    super.validator,
    bool? enabled,
    super.autovalidateMode,
    super.forceErrorText,
  }) : assert(
         initialValue == null || controller == null,
         'Give a TextFormField an initialValue or a controller, not both.',
       ),
       super(
         builder: _noFieldBuilder,
         initialValue: initialValue,
         enabled: enabled ?? true,
       );

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool readOnly;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;

  /// Accepted and not carried, as on [TextField].
  final bool? enableInteractiveSelection;
  final Color? cursorColor;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final bool? showCursor;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  FormFieldState<String> createState() => _TextFormFieldState();
}

class _TextFormFieldState extends FormFieldState<String> {
  TextEditingController? _own;

  TextFormField get _field => widget as TextFormField;

  TextEditingController get _controller =>
      _field.controller ??
      (_own ??= TextEditingController(text: widget.initialValue));

  @override
  void initState() {
    final external = _field.controller;
    if (external != null) setValue(external.text);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(TextFormField oldWidget) {
    if (identical(oldWidget.controller, _field.controller)) return;
    (oldWidget.controller ?? _own)?.removeListener(_onControllerChanged);
    _controller.addListener(_onControllerChanged);
    setValue(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _own?.dispose();
  }

  /// The controller changed - typed into, or set by the app. Either way the
  /// field's value is the controller's text.
  void _onControllerChanged() {
    if (_controller.text != value) setValue(_controller.text);
  }

  @override
  void didChange(String? value) {
    setValue(value);
    _interacted = true;
    Form.maybeOf(context)?._fieldDidChange();
    // The platform field already shows what was typed, so there is nothing
    // to redraw - unless an error is showing, or would be: then every edit
    // re-checks it, and the message goes as soon as the value is right.
    if (_errorText != null || _autovalidates) setState(_validate);
  }

  @override
  void reset() {
    _controller.text = widget.initialValue ?? '';
    super.reset();
  }

  @override
  Widget buildField(BuildContext context) {
    final field = _field;
    final decoration = field.decoration ?? const InputDecoration();
    return TextField(
      key: field.key is ValueKey ? field.key : null,
      controller: _controller,
      focusNode: field.focusNode,
      decoration: errorText == null
          ? decoration
          : decoration.copyWith(errorText: errorText),
      keyboardType: field.keyboardType,
      textInputAction: field.textInputAction,
      textCapitalization: field.textCapitalization,
      style: field.style,
      textAlign: field.textAlign,
      readOnly: field.readOnly,
      autofocus: field.autofocus,
      obscureText: field.obscureText,
      maxLines: field.maxLines,
      minLines: field.minLines,
      maxLength: field.maxLength,
      enabled: widget.enabled,
      onTap: field.onTap,
      onEditingComplete: field.onEditingComplete,
      onSubmitted: field.onFieldSubmitted,
      onChanged: (value) {
        didChange(value);
        field.onChanged?.call(value);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The framework's own form model, under names that leave `Form` and
// `FormField` to Flutter's widgets.
// ---------------------------------------------------------------------------

/// The framework's form model: fields declared in Dart, validated together,
/// with async validators, auto-save and undo. `Form` in
/// `package:dart_not_native/forms/form.dart`.
typedef FormModel = forms.Form;

/// One field of a [FormModel]. `FormField` in
/// `package:dart_not_native/forms/form.dart`.
typedef FormFieldModel = forms.FormField;

/// A [TextField] bound to a [FormFieldModel].
///
/// It shows the field's value, label, hint and validation error, reports edits
/// back with `setValue`, and validates on submit (and on blur by default). Give
/// a field a [ModelTextFormField] and the wiring is done - build a
/// [FormModel] with a `FormBuilder`, then:
///
/// ```dart
/// final form = (FormBuilder()..addEmailField(name: 'email')).build();
/// // ...
/// ModelTextFormField(field: form.getField('email')!)
/// ```
///
/// It rebuilds itself when a validator reports an error, so a submit that calls
/// `form.validate()` shows every field's error without the app rebuilding.
class ModelTextFormField extends StatefulWidget {
  const ModelTextFormField({
    super.key,
    required this.field,
    this.validateOnBlur = true,
    this.maxLines = 1,
    this.focusNode,
  });

  /// The field this input is bound to.
  final FormFieldModel field;

  /// Lets the form move the caret here - a failed submit sending the user to
  /// the first field that needs attention, say. See [FocusNode].
  final FocusNode? focusNode;

  /// Whether losing focus validates the field. A submit always validates.
  final bool validateOnBlur;

  final int maxLines;

  @override
  State<ModelTextFormField> createState() => _ModelTextFormFieldState();
}

class _ModelTextFormFieldState extends State<ModelTextFormField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.field.value,
  );
  StreamSubscription<forms.FieldChange>? _changeSub;
  StreamSubscription<String>? _errorSub;

  FormFieldModel get _field => widget.field;

  /// Which validation run is the current one: an edit while an earlier run is
  /// still in flight makes that run's answer stale, and a stale answer must
  /// not repaint the field.
  int _validation = 0;

  @override
  void initState() {
    // Rebuild when the field changes from elsewhere (an external setValue) or a
    // validator reports an error; the user's own typing already shows in the
    // native field, so that case is skipped to avoid a rebuild per keystroke.
    _changeSub = _field.onChange.listen((_) {
      if (mounted && _field.value != _controller.text) setState(() {});
    });
    _errorSub = _field.onError.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _errorSub?.cancel();
  }

  Future<void> _validate() async {
    final run = ++_validation;
    await _field.validate();
    if (mounted && run == _validation) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Push an external value change (e.g. FormModel.reset) into the native
    // field. Set quietly: this is the build the change would ask for.
    if (_field.value != _controller.text) {
      _controller._text = _field.value;
      _controller._version++;
    }
    return TextField(
      key: ValueKey('field_${_field.name}'),
      controller: _controller,
      focusNode: widget.focusNode,
      obscureText: _field.obscured,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: _field.label,
        hintText: _field.hint,
        errorText: _field.errorMessage,
      ),
      onChanged: (value) {
        _field.markTouched();
        _field.setValue(value);
        // Once a field has shown an error, every edit re-checks it, so the
        // message goes as soon as the value is right instead of standing
        // until the next submit. A field that has never failed is not
        // validated on every keystroke - the first check is still the blur or
        // the submit, which is where someone expects to be told.
        if (_field.errorMessage != null) unawaited(_validate());
      },
      onSubmitted: (_) => _validate(),
      onBlur: widget.validateOnBlur ? _validate : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Choosing: a dropdown, a date, a time.
// ---------------------------------------------------------------------------

/// One choice of a [DropdownButton]. The platform's menu shows text, so the
/// text of [child] is what is listed.
class DropdownMenuItem<T> extends Widget {
  const DropdownMenuItem({
    super.key,
    this.onTap,
    this.value,
    this.enabled = true,
    this.alignment = AlignmentDirectional.centerStart,
    required this.child,
  });
  final VoidCallback? onTap;
  final T? value;
  final bool enabled;
  final AlignmentGeometry alignment;
  final Widget child;
  @override
  WidgetNode _render(_Owner owner) => _renderChild(owner, child);
}

WidgetNode _dropdown<T>(
  _Owner owner, {
  required List<DropdownMenuItem<T>>? items,
  required T? value,
  required ValueChanged<T?>? onChanged,
  required bool outlined,
  bool expanded = false,
  String? label,
  String? hint,
  String? error,
  String? id,
}) {
  final choices = items ?? const [];
  final index = choices.indexWhere((item) => item.value == value);
  final node = UIBuilder.dropdown(
    items: [
      for (final item in choices) _plainText(item.child, owner) ?? '${item.value}',
    ],
    selectedIndex: index < 0 ? null : index,
    onChanged: onChanged == null
        ? null
        : (chosen) {
            if (chosen < 0 || chosen >= choices.length) return;
            choices[chosen].onTap?.call();
            onChanged(choices[chosen].value);
          },
    label: label,
    hint: hint,
    error: error,
    enabled: onChanged != null && choices.isNotEmpty,
    outlined: outlined,
    id: id,
  );
  return expanded ? UIBuilder.box(expand: 'width', child: node) : node;
}

/// One of a list, chosen from the platform's own menu.
class DropdownButton<T> extends Widget {
  const DropdownButton({
    super.key,
    required this.items,
    this.value,
    this.hint,
    this.disabledHint,
    required this.onChanged,
    this.elevation = 8,
    this.style,
    this.underline,
    this.icon,
    this.isDense = false,
    this.isExpanded = false,
    this.dropdownColor,
    this.borderRadius,
    this.padding,
  });
  final List<DropdownMenuItem<T>>? items;
  final T? value;

  /// Shown while nothing is chosen; its text is what travels.
  final Widget? hint;
  final Widget? disabledHint;

  /// Null disables the menu.
  final ValueChanged<T?>? onChanged;

  /// Accepted and not carried: the menu is the platform's own.
  final int elevation;
  final TextStyle? style;
  final Widget? underline;
  final Widget? icon;
  final bool isDense;

  /// Fills the width it is offered.
  final bool isExpanded;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  WidgetNode _render(_Owner owner) => _dropdown<T>(
    owner,
    items: items,
    value: value,
    onChanged: onChanged,
    outlined: false,
    expanded: isExpanded,
    hint: _plainText(onChanged == null ? (disabledHint ?? hint) : hint, owner),
    id: _idOf(key),
  );
}

/// A [DropdownButton] that is a [FormField], with a decoration like a text
/// field's.
class DropdownButtonFormField<T> extends FormField<T> {
  const DropdownButtonFormField({
    super.key,
    required this.items,
    T? initialValue,
    T? value,
    this.hint,
    this.disabledHint,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = true,
    this.isDense = true,
    this.style,
    this.icon,
    this.dropdownColor,
    this.borderRadius,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
    super.forceErrorText,
  }) : super(builder: _noFieldBuilder, initialValue: initialValue ?? value);

  final List<DropdownMenuItem<T>>? items;
  final Widget? hint;
  final Widget? disabledHint;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  final bool isDense;
  final TextStyle? style;
  final Widget? icon;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;

  @override
  FormFieldState<T> createState() => _DropdownFormFieldState<T>();
}

class _DropdownFormFieldState<T> extends FormFieldState<T> {
  DropdownButtonFormField<T> get _field =>
      widget as DropdownButtonFormField<T>;

  @override
  void didUpdateWidget(DropdownButtonFormField<T> oldWidget) {
    // A parent that rebuilds with another value means it, as in Flutter.
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  @override
  Widget buildField(BuildContext context) => _NodeWidget((owner) {
    final field = _field;
    final decoration = field.decoration;
    final changed = field.onChanged;
    return _dropdown<T>(
      owner,
      items: field.items,
      value: value,
      onChanged: changed == null
          ? null
          : (chosen) {
              didChange(chosen);
              changed(chosen);
            },
      outlined: true,
      expanded: field.isExpanded,
      label: decoration.labelText ?? _stringOf(decoration.label, owner),
      hint: decoration.hintText ?? _plainText(field.hint, owner),
      error: errorText ?? decoration.errorText,
      id: _idOf(field.key),
    );
  });
}

/// How a date picker opens. Accepted for Flutter's signature; the picker is
/// the platform's own and opens its own way.
enum DatePickerEntryMode { calendar, input, calendarOnly, inputOnly }

enum DatePickerMode { day, year }

enum TimePickerEntryMode { dial, input, dialOnly, inputOnly }

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Shows the platform's date picker and answers the date chosen, or null when
/// it was closed without choosing.
///
/// [builder], [locale] and the entry modes are accepted for Flutter's
/// signature: the picker is not a widget this framework draws, so there is
/// nothing to wrap, and it speaks the device's language.
Future<DateTime?> showDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  String? helpText,
  String? cancelText,
  String? confirmText,
  Locale? locale,
  TransitionBuilder? builder,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
}) {
  final owner = _ownerOf(context);
  var initial = initialDate ?? currentDate ?? DateTime.now();
  if (initial.isBefore(firstDate)) initial = firstDate;
  if (initial.isAfter(lastDate)) initial = lastDate;
  late final _OverlayEntry entry;
  entry = _OverlayEntry(
    _OverlayKind.picker,
    (_) => _NodeWidget(
      (owner) => UIBuilder.datePicker(
        initial: _isoDate(initial),
        first: _isoDate(firstDate),
        last: _isoDate(lastDate),
        onPicked: (date) => owner._dismiss(entry, DateTime.tryParse(date)),
        onDismiss: () => owner._dismiss(entry, null),
        title: helpText,
        confirmLabel: confirmText,
        cancelLabel: cancelText,
        id: entry.id,
      ),
    ),
    scope: (context as _Context)._scope,
  );
  return owner.pushOverlay<DateTime>(entry);
}

/// Shows the platform's time picker and answers the time chosen, or null when
/// it was closed without choosing.
Future<TimeOfDay?> showTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TransitionBuilder? builder,
  String? helpText,
  String? cancelText,
  String? confirmText,
  TimePickerEntryMode initialEntryMode = TimePickerEntryMode.dial,
}) {
  final owner = _ownerOf(context);
  late final _OverlayEntry entry;
  entry = _OverlayEntry(
    _OverlayKind.picker,
    (_) => _NodeWidget(
      (owner) => UIBuilder.timePicker(
        hour: initialTime.hour,
        minute: initialTime.minute,
        onPicked: (hour, minute) =>
            owner._dismiss(entry, TimeOfDay(hour: hour, minute: minute)),
        onDismiss: () => owner._dismiss(entry, null),
        title: helpText,
        confirmLabel: confirmText,
        cancelLabel: cancelText,
        id: entry.id,
      ),
    ),
    scope: (context as _Context)._scope,
  );
  return owner.pushOverlay<TimeOfDay>(entry);
}
