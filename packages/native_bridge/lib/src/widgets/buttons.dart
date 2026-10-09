part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Buttons and the other things that are pressed.
// ---------------------------------------------------------------------------

/// What a control is doing, for a style that depends on it.
enum WidgetState {
  hovered,
  focused,
  pressed,
  dragged,
  selected,
  scrolledUnder,
  disabled,
  error,
}

/// Flutter's older name for [WidgetState].
typedef MaterialState = WidgetState;

/// A value that may depend on a control's [WidgetState]s.
///
/// The renderers draw hover, focus and press themselves, so a property is
/// only ever resolved here for a control at rest or a disabled one.
abstract class WidgetStateProperty<T> {
  const WidgetStateProperty();

  T resolve(Set<WidgetState> states);

  /// The same value in every state.
  static WidgetStateProperty<T> all<T>(T value) =>
      WidgetStatePropertyAll<T>(value);

  /// A value worked out from the states.
  static WidgetStateProperty<T> resolveWith<T>(
    T Function(Set<WidgetState> states) callback,
  ) => _WidgetStatePropertyWith<T>(callback);
}

/// Flutter's older name for [WidgetStateProperty].
typedef MaterialStateProperty<T> = WidgetStateProperty<T>;

class WidgetStatePropertyAll<T> extends WidgetStateProperty<T> {
  const WidgetStatePropertyAll(this.value);
  final T value;
  @override
  T resolve(Set<WidgetState> states) => value;
}

/// Flutter's older name for [WidgetStatePropertyAll].
typedef MaterialStatePropertyAll<T> = WidgetStatePropertyAll<T>;

class _WidgetStatePropertyWith<T> extends WidgetStateProperty<T> {
  const _WidgetStatePropertyWith(this._resolve);
  final T Function(Set<WidgetState> states) _resolve;
  @override
  T resolve(Set<WidgetState> states) => _resolve(states);
}

/// How a button is filled, coloured, sized and shaped: Flutter's
/// `ButtonStyle`, which most apps make with `styleFrom`.
///
/// The platform's own button carries the colours, the padding (symmetric, so
/// the left and top edges are the ones that travel), the minimum size and the
/// text size. A [shape] or a [side] is not something that button can be
/// given, so asking for one draws the button from a box instead - the same
/// thing that happens when its child is not a plain label.
class ButtonStyle {
  const ButtonStyle({
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.overlayColor,
    this.shadowColor,
    this.elevation,
    this.padding,
    this.minimumSize,
    this.fixedSize,
    this.maximumSize,
    this.iconColor,
    this.iconSize,
    this.side,
    this.shape,
    this.visualDensity,
    this.tapTargetSize,
    this.alignment,
  });

  final WidgetStateProperty<TextStyle?>? textStyle;
  final WidgetStateProperty<Color?>? backgroundColor;
  final WidgetStateProperty<Color?>? foregroundColor;

  /// Accepted and not carried: touch feedback is the platform's.
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<Color?>? shadowColor;
  final WidgetStateProperty<double?>? elevation;
  final WidgetStateProperty<EdgeInsetsGeometry?>? padding;
  final WidgetStateProperty<Size?>? minimumSize;
  final WidgetStateProperty<Size?>? fixedSize;
  final WidgetStateProperty<Size?>? maximumSize;
  final WidgetStateProperty<Color?>? iconColor;
  final WidgetStateProperty<double?>? iconSize;
  final WidgetStateProperty<BorderSide?>? side;
  final WidgetStateProperty<OutlinedBorder?>? shape;
  final VisualDensity? visualDensity;
  final MaterialTapTargetSize? tapTargetSize;
  final AlignmentGeometry? alignment;

  ButtonStyle copyWith({
    WidgetStateProperty<TextStyle?>? textStyle,
    WidgetStateProperty<Color?>? backgroundColor,
    WidgetStateProperty<Color?>? foregroundColor,
    WidgetStateProperty<EdgeInsetsGeometry?>? padding,
    WidgetStateProperty<Size?>? minimumSize,
    WidgetStateProperty<Size?>? fixedSize,
    WidgetStateProperty<BorderSide?>? side,
    WidgetStateProperty<OutlinedBorder?>? shape,
  }) => ButtonStyle(
    textStyle: textStyle ?? this.textStyle,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    overlayColor: overlayColor,
    shadowColor: shadowColor,
    elevation: elevation,
    padding: padding ?? this.padding,
    minimumSize: minimumSize ?? this.minimumSize,
    fixedSize: fixedSize ?? this.fixedSize,
    maximumSize: maximumSize,
    iconColor: iconColor,
    iconSize: iconSize,
    side: side ?? this.side,
    shape: shape ?? this.shape,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    alignment: alignment,
  );
}

/// How much room a control leaves around itself for a finger. Accepted for
/// Flutter's signature; the platform's controls have their own.
enum MaterialTapTargetSize { padded, shrinkWrap }

WidgetStateProperty<T?>? _all<T>(T? value) =>
    value == null ? null : WidgetStatePropertyAll<T?>(value);

/// `styleFrom` for every button: Flutter's flat parameters as a [ButtonStyle].
ButtonStyle _styleFrom({
  Color? foregroundColor,
  Color? backgroundColor,
  Color? disabledForegroundColor,
  Color? disabledBackgroundColor,
  Color? shadowColor,
  Color? iconColor,
  double? iconSize,
  double? elevation,
  TextStyle? textStyle,
  EdgeInsetsGeometry? padding,
  Size? minimumSize,
  Size? fixedSize,
  Size? maximumSize,
  BorderSide? side,
  OutlinedBorder? shape,
  VisualDensity? visualDensity,
  MaterialTapTargetSize? tapTargetSize,
  AlignmentGeometry? alignment,
}) {
  WidgetStateProperty<Color?>? colour(Color? enabled, Color? disabled) {
    if (enabled == null && disabled == null) return null;
    if (disabled == null) return WidgetStatePropertyAll<Color?>(enabled);
    return WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled) ? disabled : enabled,
    );
  }

  return ButtonStyle(
    textStyle: _all(textStyle),
    backgroundColor: colour(backgroundColor, disabledBackgroundColor),
    foregroundColor: colour(foregroundColor, disabledForegroundColor),
    shadowColor: _all(shadowColor),
    elevation: _all(elevation),
    padding: _all(padding),
    minimumSize: _all(minimumSize),
    fixedSize: _all(fixedSize),
    maximumSize: _all(maximumSize),
    iconColor: _all(iconColor),
    iconSize: _all(iconSize),
    side: _all(side),
    shape: _all(shape),
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    alignment: alignment,
  );
}

/// The four Material buttons, which differ in how they are filled.
///
/// A button whose child is a [Text] (or a [Tr]) is the platform's own button,
/// which takes a label. Any other child - a spinner swapped in while a
/// request runs, a row of two things - cannot be a label, so the button is
/// drawn from a box in the same colours, with the child inside it.
abstract class ButtonStyleButton extends Widget {
  const ButtonStyleButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.autofocus = false,
    this.clipBehavior,
    required this.child,
    Widget? icon,
  }) : _icon = icon;

  /// Null disables the button, as in Flutter.
  final VoidCallback? onPressed;

  /// Only a button drawn from a box reports a long press; the platform's own
  /// button has the one event.
  final VoidCallback? onLongPress;
  final ButtonStyle? style;

  /// Accepted and not carried: only text fields take focus here.
  final bool autofocus;
  final Clip? clipBehavior;
  final Widget? child;
  final Widget? _icon;

  bool get enabled => onPressed != null;

  /// The protocol's name for this kind of button.
  String get _variant;

  /// The colours this kind of button has when its style names none, for the
  /// button drawn from a box: fill, content, outline.
  (Color?, Color, Color?) _colors(ColorScheme scheme);

  @override
  WidgetNode _render(_Owner owner) {
    final style = this.style;
    final states = enabled ? const <WidgetState>{} : {WidgetState.disabled};
    final background = style?.backgroundColor?.resolve(states);
    final foreground = style?.foregroundColor?.resolve(states);
    final padding = style?.padding?.resolve(states)?._resolved;
    final minimum = style?.minimumSize?.resolve(states);
    final fixed = style?.fixedSize?.resolve(states);
    final textStyle = style?.textStyle?.resolve(states);
    final shape = style?.shape?.resolve(states);
    final side = style?.side?.resolve(states);
    final child = this.child;
    final icon = _icon;
    final label = _stringOf(child, owner);
    final minWidth = fixed?.width ?? minimum?.width;
    final minHeight = fixed?.height ?? minimum?.height;
    final fills = minWidth == double.infinity;
    final id = _idOf(key);

    final glyph = icon is Icon ? icon.icon : null;
    if (label != null &&
        shape == null &&
        side == null &&
        (icon == null || glyph != null)) {
      // Material 3's button, which is what Flutter draws by default: 40 tall
      // with 24 either side of the label (12 on a text button). Stated on the
      // node, because the protocol's own default is the smaller button of
      // its scale - and the same numbers the button drawn from a box, below,
      // already has. A Material 2 theme keeps that default, which is its own.
      final material3 = _themeOf(owner).useMaterial3;
      return UIBuilder.button(
        label: label,
        onPressed: onPressed,
        variant: _variant,
        color: background?._hex,
        foregroundColor: foreground?._hex,
        // A button's padding is symmetric in the protocol, so one edge of
        // each axis travels; a Flutter app writing EdgeInsets.symmetric -
        // which is what button padding is - loses nothing.
        paddingHorizontal:
            padding?.left ??
            (material3 ? (_variant == 'tertiary' ? 12 : 24) : null),
        paddingVertical: padding?.top,
        minWidth: minWidth != null && minWidth.isFinite ? minWidth : null,
        minHeight: minHeight != null && minHeight.isFinite
            ? minHeight
            : (material3 ? 40 : null),
        fontSize: textStyle?.fontSize,
        disabled: !enabled,
        iconCodepoint: glyph?.codePoint,
        expand: fills,
        id: id,
      );
    }

    final scheme = _themeOf(owner).colorScheme;
    final (fill, content, outline) = _colors(scheme);
    final ink = foreground ?? content;
    final border =
        side ??
        (shape != null && shape.side.width > 0 ? shape.side : null) ??
        (outline == null ? null : BorderSide(color: outline));
    final radius = switch (shape) {
      RoundedRectangleBorder() => shape.borderRadius._resolved,
      null || StadiumBorder() => null,
      _ => null,
    };
    final pressed = onPressed;
    final held = onLongPress;
    final content0 = _withForeground(
      owner,
      ink,
      () => [
        if (icon != null) _renderChild(owner, icon, 'icon'),
        if (child != null) _renderChild(owner, child),
      ],
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ).merge(textStyle),
      iconSize: style?.iconSize?.resolve(states) ?? 18,
    );
    return UIBuilder.box(
      minWidth: minWidth != null && minWidth.isFinite ? minWidth : null,
      minHeight: minHeight != null && minHeight.isFinite ? minHeight : 40,
      expand: fills ? 'width' : null,
      padding:
          padding?._ltrb ??
          (_variant == 'tertiary'
              ? const [12, 10, 12, 10]
              : const [24, 10, 24, 10]),
      alignment: const [0, 0],
      color: (background ?? fill)?._hex,
      borderWidth: border != null && border.width > 0 ? border.width : null,
      borderColor: border != null && border.width > 0
          ? border.color._hex
          : null,
      borderRadius: shape is CircleBorder
          ? null
          : (radius == null ? 20 : radius._uniform),
      borderRadii: radius != null && radius._uniform == null
          ? radius._radii
          : null,
      shape: shape is CircleBorder ? 'circle' : null,
      // Material's disabled look: the same button at 38%.
      opacity: enabled ? null : 0.38,
      onTap: pressed == null ? null : (_, _) => pressed(),
      onLongPress: pressed == null || held == null ? null : (_, _) => held(),
      ripple: enabled,
      // Without its tap a box is only a box: say that it is a button, and
      // that it is off.
      semanticRole: enabled ? null : 'button',
      disabled: !enabled,
      id: id,
      child: content0.length == 1
          ? content0.single
          : UIBuilder.row(
              mainAxisAlignment: 'center',
              mainAxisSize: 'min',
              spacing: 8,
              children: content0,
            ),
    );
  }
}

/// A raised, filled button. `onPressed: null` disables it, like Flutter.
class ElevatedButton extends ButtonStyleButton {
  const ElevatedButton({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    required super.child,
  });

  /// A button with an [icon] before its [label].
  const ElevatedButton.icon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    super.icon,
    required Widget label,
  }) : super(child: label);

  /// Mirrors `ElevatedButton.styleFrom(...)`.
  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? shadowColor,
    Color? iconColor,
    double? iconSize,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    BorderSide? side,
    OutlinedBorder? shape,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    AlignmentGeometry? alignment,
  }) => _styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    shadowColor: shadowColor,
    iconColor: iconColor,
    iconSize: iconSize,
    elevation: elevation,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
    side: side,
    shape: shape,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    alignment: alignment,
  );

  @override
  String get _variant => 'primary';

  @override
  (Color?, Color, Color?) _colors(ColorScheme scheme) =>
      (scheme.primary, scheme.onPrimary, null);
}

/// A filled button; [FilledButton.tonal] is the quieter fill.
class FilledButton extends ButtonStyleButton {
  const FilledButton({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    required super.child,
  }) : _tonal = false;

  const FilledButton.icon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    super.icon,
    required Widget label,
  }) : _tonal = false,
       super(child: label);

  const FilledButton.tonal({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    required super.child,
  }) : _tonal = true;

  const FilledButton.tonalIcon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    super.icon,
    required Widget label,
  }) : _tonal = true,
       super(child: label);

  final bool _tonal;

  /// Mirrors `FilledButton.styleFrom(...)`.
  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? shadowColor,
    Color? iconColor,
    double? iconSize,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    BorderSide? side,
    OutlinedBorder? shape,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    AlignmentGeometry? alignment,
  }) => _styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    shadowColor: shadowColor,
    iconColor: iconColor,
    iconSize: iconSize,
    elevation: elevation,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
    side: side,
    shape: shape,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    alignment: alignment,
  );

  @override
  String get _variant => _tonal ? 'tonal' : 'primary';

  @override
  (Color?, Color, Color?) _colors(ColorScheme scheme) => _tonal
      ? (scheme.secondaryContainer, scheme.onSecondaryContainer, null)
      : (scheme.primary, scheme.onPrimary, null);
}

/// A button with an outline and no fill.
class OutlinedButton extends ButtonStyleButton {
  const OutlinedButton({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    required super.child,
  });

  const OutlinedButton.icon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    super.icon,
    required Widget label,
  }) : super(child: label);

  /// Mirrors `OutlinedButton.styleFrom(...)`.
  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? shadowColor,
    Color? iconColor,
    double? iconSize,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    BorderSide? side,
    OutlinedBorder? shape,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    AlignmentGeometry? alignment,
  }) => _styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    shadowColor: shadowColor,
    iconColor: iconColor,
    iconSize: iconSize,
    elevation: elevation,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
    side: side,
    shape: shape,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    alignment: alignment,
  );

  @override
  String get _variant => 'outlined';

  @override
  (Color?, Color, Color?) _colors(ColorScheme scheme) =>
      (null, scheme.primary, scheme.outline);
}

/// A flat button; the tertiary variant of the design system.
class TextButton extends ButtonStyleButton {
  const TextButton({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    required super.child,
  });

  const TextButton.icon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.autofocus,
    super.clipBehavior,
    super.icon,
    required Widget label,
  }) : super(child: label);

  /// Mirrors `TextButton.styleFrom(...)`.
  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? shadowColor,
    Color? iconColor,
    double? iconSize,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    BorderSide? side,
    OutlinedBorder? shape,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    AlignmentGeometry? alignment,
  }) => _styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    shadowColor: shadowColor,
    iconColor: iconColor,
    iconSize: iconSize,
    elevation: elevation,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
    side: side,
    shape: shape,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    alignment: alignment,
  );

  @override
  String get _variant => 'tertiary';

  @override
  (Color?, Color, Color?) _colors(ColorScheme scheme) =>
      (null, scheme.primary, null);
}

/// A button that is only an icon.
///
/// With an [Icon] it is the platform's icon button. The filled, tonal and
/// outlined forms - and an [icon] that is some other widget - are drawn from
/// a round box, since the platform's button has neither a fill nor a child.
class IconButton extends Widget {
  const IconButton({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.disabledColor,
    required this.onPressed,
    this.autofocus = false,
    this.tooltip,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
  }) : _kind = 'standard';

  const IconButton.filled({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.disabledColor,
    required this.onPressed,
    this.autofocus = false,
    this.tooltip,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
  }) : _kind = 'filled';

  const IconButton.filledTonal({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.disabledColor,
    required this.onPressed,
    this.autofocus = false,
    this.tooltip,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
  }) : _kind = 'tonal';

  const IconButton.outlined({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.disabledColor,
    required this.onPressed,
    this.autofocus = false,
    this.tooltip,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
  }) : _kind = 'outlined';

  final double? iconSize;

  /// Accepted for Flutter's signature; the button keeps the platform's size.
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final double? splashRadius;
  final Color? color;
  final Color? disabledColor;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool autofocus;
  final String? tooltip;
  final BoxConstraints? constraints;
  final ButtonStyle? style;

  /// With [selectedIcon], which of the two is shown.
  final bool? isSelected;
  final Widget? selectedIcon;
  final Widget icon;
  final String _kind;

  @override
  WidgetNode _render(_Owner owner) {
    final shown = isSelected == true ? (selectedIcon ?? icon) : icon;
    final pressed = onPressed;
    final states = pressed == null
        ? {WidgetState.disabled}
        : const <WidgetState>{};
    final tint = color ?? style?.foregroundColor?.resolve(states);
    final id = _idOf(key);
    if (_kind == 'standard' && shown is Icon && shown.icon != null) {
      return UIBuilder.iconButton(
        icon: shown.icon!.name ?? '',
        codepoint: shown.icon!.codePoint,
        onPressed: pressed,
        tooltip: tooltip ?? shown.semanticLabel ?? '',
        // Then the colour icons are drawn in around here, as an `Icon` in the
        // same place takes it: a bar composed from boxes states its
        // foreground that way, and a button that ignored it was drawn in the
        // renderer's own default - dark on a dark bar.
        color: (tint ?? shown.color ?? owner._inherited<IconTheme>()?.data.color)
            ?._hex,
        size: iconSize ?? shown.size,
        disabled: pressed == null,
        id: id,
      );
    }
    final scheme = _themeOf(owner).colorScheme;
    final (fill, ink, outline) = switch (_kind) {
      'filled' => (scheme.primary, scheme.onPrimary, null),
      'tonal' => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        null,
      ),
      'outlined' => (null, scheme.onSurfaceVariant, scheme.outline),
      _ => (null, scheme.onSurfaceVariant, null),
    };
    return UIBuilder.box(
      width: 40,
      height: 40,
      shape: 'circle',
      alignment: const [0, 0],
      color: (style?.backgroundColor?.resolve(states) ?? fill)?._hex,
      borderWidth: outline == null ? null : 1,
      borderColor: outline?._hex,
      opacity: pressed == null ? 0.38 : null,
      onTap: pressed == null ? null : (_, _) => pressed(),
      ripple: pressed != null,
      semanticRole: pressed == null ? 'button' : null,
      disabled: pressed == null,
      tooltip: tooltip,
      id: id,
      child: _withForeground(
        owner,
        tint ?? ink,
        () => _renderChild(owner, shown, 'icon'),
        iconSize: iconSize ?? 24,
      ),
    );
  }
}

/// The round button floating over a screen's content.
///
/// It is the platform's own button, which is an icon and, for
/// [FloatingActionButton.extended], a label beside it. So [child] is read for
/// its icon; [backgroundColor], [foregroundColor], [mini] and [elevation] are
/// accepted and not carried - the button takes the theme's colours and the
/// platform's size.
class FloatingActionButton extends Widget {
  const FloatingActionButton({
    super.key,
    this.child,
    this.tooltip,
    this.foregroundColor,
    this.backgroundColor,
    this.elevation,
    required this.onPressed,
    this.mini = false,
    this.shape,
    this.heroTag,
  }) : _icon = null,
       _label = null;

  const FloatingActionButton.small({
    super.key,
    this.child,
    this.tooltip,
    this.foregroundColor,
    this.backgroundColor,
    this.elevation,
    required this.onPressed,
    this.shape,
    this.heroTag,
  }) : mini = true,
       _icon = null,
       _label = null;

  const FloatingActionButton.large({
    super.key,
    this.child,
    this.tooltip,
    this.foregroundColor,
    this.backgroundColor,
    this.elevation,
    required this.onPressed,
    this.shape,
    this.heroTag,
  }) : mini = false,
       _icon = null,
       _label = null;

  /// The pill-shaped button: an [icon] and a [label].
  const FloatingActionButton.extended({
    super.key,
    this.tooltip,
    this.foregroundColor,
    this.backgroundColor,
    this.elevation,
    required this.onPressed,
    this.shape,
    this.heroTag,
    Widget? icon,
    required Widget label,
  }) : child = null,
       mini = false,
       _icon = icon,
       _label = label;

  final Widget? child;
  final String? tooltip;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final double? elevation;
  final VoidCallback? onPressed;
  final bool mini;
  final ShapeBorder? shape;

  /// Accepted and unused: there are no hero transitions.
  final Object? heroTag;
  final Widget? _icon;
  final Widget? _label;

  @override
  WidgetNode _render(_Owner owner) {
    final glyph = _icon ?? child;
    // Default to the add icon so a FAB without one still carries a codepoint
    // and renders a glyph on the native renderers, which draw by codepoint.
    final icon = (glyph is Icon ? glyph.icon : null) ?? Icons.add;
    final label = _plainText(_label ?? (child is Icon ? null : child), owner);
    return UIBuilder.floatingActionButton(
      tooltip: tooltip ?? '',
      // The node must fire something; a disabled button fires nothing.
      onPressed: onPressed ?? () {},
      icon: icon.name ?? 'add',
      codepoint: icon.codePoint,
      label: label,
      id: _idOf(key),
    );
  }
}

/// A rectangle that answers to touch, with the platform's touch feedback.
class InkWell extends Widget {
  const InkWell({
    super.key,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.borderRadius,
    this.customBorder,
    this.splashColor,
    this.highlightColor,
    this.hoverColor,
    this.focusColor,
    this.radius,
  });
  final Widget? child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  /// Rounds the corners of the feedback, and so of the box.
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;

  /// Accepted and not carried: the feedback is the platform's own colour.
  final Color? splashColor;
  final Color? highlightColor;
  final Color? hoverColor;
  final Color? focusColor;
  final double? radius;

  @override
  WidgetNode _render(_Owner owner) {
    final node = child == null ? null : _renderChild(owner, child!);
    final tap = onTap;
    final doubleTap = onDoubleTap;
    final longPress = onLongPress;
    if (tap == null && doubleTap == null && longPress == null) {
      return node ?? UIBuilder.sizedBox();
    }
    final radius = customBorder is RoundedRectangleBorder
        ? (customBorder as RoundedRectangleBorder).borderRadius._resolved
        : borderRadius;
    return UIBuilder.box(
      onTap: tap == null ? null : (_, _) => tap(),
      onDoubleTap: doubleTap == null ? null : (_, _) => doubleTap(),
      onLongPress: longPress == null ? null : (_, _) => longPress(),
      ripple: true,
      borderRadius: customBorder is StadiumBorder ? 999 : radius?._uniform,
      borderRadii: radius != null && radius._uniform == null
          ? radius._radii
          : null,
      shape: customBorder is CircleBorder ? 'circle' : null,
      clip: radius != null || customBorder != null,
      expand: _expandOfChild(node),
      id: _idOf(key),
      child: node,
    );
  }
}

/// [InkWell] without the splash, in Flutter. Here the feedback is the
/// platform's either way.
class InkResponse extends InkWell {
  const InkResponse({
    super.key,
    super.child,
    super.onTap,
    super.onDoubleTap,
    super.onLongPress,
    super.borderRadius,
    super.radius,
  });
}

// ---------------------------------------------------------------------------
// Chips.
// ---------------------------------------------------------------------------

/// Every chip is this: a small rounded box holding an optional avatar, a
/// label and an optional delete button, in Material 3's metrics.
WidgetNode _chip(
  _Owner owner, {
  required Widget label,
  Widget? avatar,
  Widget? deleteIcon,
  VoidCallback? onDeleted,
  VoidCallback? onPressed,
  bool selected = false,
  bool selectable = false,
  bool showCheckmark = false,
  bool enabled = true,
  Color? backgroundColor,
  Color? selectedColor,
  BorderSide? side,
  OutlinedBorder? shape,
  TextStyle? labelStyle,
  EdgeInsetsGeometry? padding,
  String? tooltip,
  String? id,
}) {
  final scheme = _themeOf(owner).colorScheme;
  final ink = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
  final fill = selected
      ? (selectedColor ?? scheme.secondaryContainer)
      : backgroundColor;
  final outline =
      side ??
      (shape != null && shape.side.width > 0 ? shape.side : null) ??
      (selected ? null : BorderSide(color: scheme.outlineVariant));
  final radius = shape is RoundedRectangleBorder
      ? shape.borderRadius._resolved._uniform
      : (shape is StadiumBorder ? 999.0 : null);
  final leading = selected && showCheckmark
      ? const Icon(Icons.check, size: 18)
      : avatar;
  final insets = padding?._resolved._ltrb;
  final children = _withForeground(
    owner,
    ink,
    () => [
      if (leading != null) _renderChild(owner, leading, 'avatar'),
      _renderChild(owner, label, 'label'),
      if (onDeleted != null)
        UIBuilder.box(
          onTap: (_, _) => onDeleted(),
          ripple: true,
          // The name Flutter gives the same button; it is only an icon.
          tooltip: 'Delete',
          shape: 'circle',
          id: id == null ? null : '$id.delete',
          child: _renderChild(
            owner,
            deleteIcon ?? const Icon(Icons.close, size: 18),
            'delete',
          ),
        ),
    ],
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    ).merge(labelStyle),
    iconSize: 18,
  );
  return UIBuilder.box(
    minHeight: 32,
    padding:
        insets ??
        [
          leading == null ? 16 : 8,
          6,
          onDeleted == null ? 16 : 8,
          6,
        ],
    alignment: const [0, 0],
    color: fill?._hex,
    borderWidth: outline != null && outline.width > 0 ? outline.width : null,
    borderColor: outline != null && outline.width > 0
        ? outline.color._hex
        : null,
    borderRadius: radius ?? 8,
    opacity: enabled ? null : 0.38,
    onTap: onPressed == null || !enabled ? null : (_, _) => onPressed(),
    ripple: onPressed != null && enabled,
    // A chip that is on or off says which: the tick is only a picture.
    selected: selectable ? selected : null,
    tooltip: tooltip,
    id: id,
    child: UIBuilder.row(
      mainAxisSize: 'min',
      spacing: 8,
      children: children,
    ),
  );
}

/// A compact label: a tag, an attribute, a person. Composed from boxes in
/// Material 3's look, since no platform has a chip of its own everywhere.
class Chip extends Widget {
  const Chip({
    super.key,
    this.avatar,
    required this.label,
    this.labelStyle,
    this.labelPadding,
    this.deleteIcon,
    this.onDeleted,
    this.deleteIconColor,
    this.side,
    this.shape,
    this.backgroundColor,
    this.padding,
    this.visualDensity,
    this.elevation,
  });
  final Widget? avatar;
  final Widget label;
  final TextStyle? labelStyle;

  /// Accepted for Flutter's signature; the chip keeps Material's own metrics.
  final EdgeInsetsGeometry? labelPadding;
  final Widget? deleteIcon;

  /// With one, the chip grows a delete button that calls it.
  final VoidCallback? onDeleted;
  final Color? deleteIconColor;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;
  final double? elevation;

  @override
  WidgetNode _render(_Owner owner) => _chip(
    owner,
    label: label,
    avatar: avatar,
    deleteIcon: deleteIcon,
    onDeleted: onDeleted,
    backgroundColor: backgroundColor,
    side: side,
    shape: shape,
    labelStyle: labelStyle,
    padding: padding,
    id: _idOf(key),
  );
}

/// A chip that is on or off, with a tick while it is on.
class FilterChip extends Widget {
  const FilterChip({
    super.key,
    this.avatar,
    required this.label,
    this.labelStyle,
    this.selected = false,
    required this.onSelected,
    this.backgroundColor,
    this.selectedColor,
    this.checkmarkColor,
    this.showCheckmark,
    this.side,
    this.shape,
    this.padding,
    this.visualDensity,
    this.tooltip,
  });
  final Widget? avatar;
  final Widget label;
  final TextStyle? labelStyle;
  final bool selected;

  /// Null disables the chip.
  final ValueChanged<bool>? onSelected;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? checkmarkColor;
  final bool? showCheckmark;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;
  final String? tooltip;

  @override
  WidgetNode _render(_Owner owner) {
    final changed = onSelected;
    return _chip(
      owner,
      label: label,
      avatar: avatar,
      selected: selected,
      selectable: true,
      showCheckmark: showCheckmark ?? true,
      enabled: changed != null,
      onPressed: changed == null ? null : () => changed(!selected),
      backgroundColor: backgroundColor,
      selectedColor: selectedColor,
      side: side,
      shape: shape,
      labelStyle: labelStyle,
      padding: padding,
      tooltip: tooltip,
      id: _idOf(key),
    );
  }
}

/// A chip that is one choice among several.
class ChoiceChip extends Widget {
  const ChoiceChip({
    super.key,
    this.avatar,
    required this.label,
    this.labelStyle,
    required this.selected,
    this.onSelected,
    this.backgroundColor,
    this.selectedColor,
    this.showCheckmark,
    this.side,
    this.shape,
    this.padding,
    this.visualDensity,
    this.tooltip,
  });
  final Widget? avatar;
  final Widget label;
  final TextStyle? labelStyle;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Color? backgroundColor;
  final Color? selectedColor;
  final bool? showCheckmark;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;
  final String? tooltip;

  @override
  WidgetNode _render(_Owner owner) {
    final changed = onSelected;
    return _chip(
      owner,
      label: label,
      avatar: avatar,
      selected: selected,
      selectable: true,
      showCheckmark: showCheckmark ?? true,
      enabled: changed != null,
      onPressed: changed == null ? null : () => changed(!selected),
      backgroundColor: backgroundColor,
      selectedColor: selectedColor,
      side: side,
      shape: shape,
      labelStyle: labelStyle,
      padding: padding,
      tooltip: tooltip,
      id: _idOf(key),
    );
  }
}

/// A chip that does something when pressed.
class ActionChip extends Widget {
  const ActionChip({
    super.key,
    this.avatar,
    required this.label,
    this.labelStyle,
    this.onPressed,
    this.backgroundColor,
    this.side,
    this.shape,
    this.padding,
    this.visualDensity,
    this.tooltip,
  });
  final Widget? avatar;
  final Widget label;
  final TextStyle? labelStyle;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;
  final String? tooltip;

  @override
  WidgetNode _render(_Owner owner) => _chip(
    owner,
    label: label,
    avatar: avatar,
    enabled: onPressed != null,
    onPressed: onPressed,
    backgroundColor: backgroundColor,
    side: side,
    shape: shape,
    labelStyle: labelStyle,
    padding: padding,
    tooltip: tooltip,
    id: _idOf(key),
  );
}

/// A chip standing for something the user entered: pressable, selectable and
/// deletable, each if its callback is given.
class InputChip extends Widget {
  const InputChip({
    super.key,
    this.avatar,
    required this.label,
    this.labelStyle,
    this.selected = false,
    this.isEnabled = true,
    this.onSelected,
    this.deleteIcon,
    this.onDeleted,
    this.onPressed,
    this.backgroundColor,
    this.selectedColor,
    this.showCheckmark,
    this.side,
    this.shape,
    this.padding,
    this.visualDensity,
    this.tooltip,
  });
  final Widget? avatar;
  final Widget label;
  final TextStyle? labelStyle;
  final bool selected;
  final bool isEnabled;
  final ValueChanged<bool>? onSelected;
  final Widget? deleteIcon;
  final VoidCallback? onDeleted;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? selectedColor;
  final bool? showCheckmark;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;
  final String? tooltip;

  @override
  WidgetNode _render(_Owner owner) {
    final changed = onSelected;
    return _chip(
      owner,
      label: label,
      avatar: avatar,
      deleteIcon: deleteIcon,
      onDeleted: isEnabled ? onDeleted : null,
      selected: selected,
      selectable: true,
      showCheckmark: showCheckmark ?? true,
      enabled: isEnabled,
      onPressed:
          onPressed ?? (changed == null ? null : () => changed(!selected)),
      backgroundColor: backgroundColor,
      selectedColor: selectedColor,
      side: side,
      shape: shape,
      labelStyle: labelStyle,
      padding: padding,
      tooltip: tooltip,
      id: _idOf(key),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggles.
// ---------------------------------------------------------------------------

/// A box that is ticked or not.
///
/// [label] is this framework's addition - text beside the box, which the
/// platform's checkbox draws itself; Flutter's way to label one is a
/// [CheckboxListTile], which is here too.
class Checkbox extends Widget {
  const Checkbox({
    super.key,
    required this.value,
    this.tristate = false,
    required this.onChanged,
    this.activeColor,
    this.checkColor,
    this.side,
    this.shape,
    this.visualDensity,
    this.label,
    this.semanticLabel,
    this.labelledBy,
  });

  /// Whether it is ticked. Null - which only a [tristate] box may be - is
  /// drawn as unticked: the platform's checkbox has two states.
  final bool? value;
  final bool tristate;

  /// Called with the new state; null disables the box. The parameter is
  /// nullable because Flutter's is, for the tristate box.
  final ValueChanged<bool?>? onChanged;

  /// Accepted and not carried: the box takes the theme's primary colour.
  final Color? activeColor;
  final Color? checkColor;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final VisualDensity? visualDensity;
  final String? label;

  /// What a screen reader calls a box with no [label] beside it - Flutter's
  /// `Checkbox.semanticLabel`.
  final String? semanticLabel;

  /// This framework's addition: the widget whose text names the box, which is
  /// how a [CheckboxListTile] gives its title to the control inside it.
  final Widget? labelledBy;

  @override
  WidgetNode _render(_Owner owner) {
    final changed = onChanged;
    final spoken = _spokenName(owner, label, semanticLabel, labelledBy);
    final node = UIBuilder.checkbox(
      checked: value ?? false,
      label: label,
      // The node must be able to fire; a disabled box fires into nothing.
      onChanged: changed ?? (_) {},
      id: _idOf(key),
    );
    return _withProps(node, {
      if (changed == null) 'disabled': true,
      if (spoken != null) 'semanticLabel': spoken,
    });
  }
}

/// The name a control with no visible [label] is announced by: the one it was
/// given, or the text of the widget that labels it.
String? _spokenName(
  _Owner owner,
  String? label,
  String? semanticLabel,
  Widget? labelledBy,
) {
  if (label != null) return null;
  final name = semanticLabel ?? _plainText(labelledBy, owner);
  return name == null || name.isEmpty ? null : name;
}

/// A radio button in a group: it is selected when [value] equals [groupValue],
/// and calls [onChanged] with its own value when tapped.
class Radio<T> extends Widget {
  const Radio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.toggleable = false,
    this.activeColor,
    this.visualDensity,
    this.label,
    this.semanticLabel,
    this.labelledBy,
  });
  final T value;
  final T? groupValue;

  /// Null disables the button. Called with null only when a [toggleable]
  /// button that is selected is tapped again.
  final ValueChanged<T?>? onChanged;
  final bool toggleable;

  /// Accepted and not carried: the button takes the theme's primary colour.
  final Color? activeColor;
  final VisualDensity? visualDensity;

  /// This framework's addition: text beside the button.
  final String? label;

  /// This framework's additions: what a screen reader calls a button with no
  /// [label], or the widget whose text does (see [Checkbox.labelledBy]).
  final String? semanticLabel;
  final Widget? labelledBy;

  @override
  WidgetNode _render(_Owner owner) {
    final bindings = EventBindings.required;
    final eventId = bindings.allocate(key: _idOf(key));
    final changed = onChanged;
    final selected = value == groupValue;
    if (changed != null) {
      bindings.onTap(
        eventId,
        () => changed(toggleable && selected ? null : value),
      );
    }
    return WidgetNode(
      type: 'Radio',
      props: {
        'eventId': eventId,
        'value': '$value',
        'selected': selected,
        if (label != null) 'label': label,
        'semanticLabel': ?_spokenName(owner, label, semanticLabel, labelledBy),
        if (changed == null) 'disabled': true,
        if (_idOf(key) != null) 'id': _idOf(key),
      },
    );
  }
}

/// An on/off switch.
class Switch extends Widget {
  const Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.label,
    this.semanticLabel,
    this.labelledBy,
  });

  /// Flutter's switch that looks native on each platform - which is the only
  /// kind there is here.
  const Switch.adaptive({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.label,
    this.semanticLabel,
    this.labelledBy,
  });

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Accepted and not carried: the switch is the platform's own, in the
  /// theme's colours.
  final Color? activeColor;
  final Color? activeThumbColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;

  /// This framework's addition: text beside the switch.
  final String? label;

  /// This framework's additions: what a screen reader calls a switch with no
  /// [label], or the widget whose text does (see [Checkbox.labelledBy]).
  final String? semanticLabel;
  final Widget? labelledBy;

  @override
  WidgetNode _render(_Owner owner) {
    final bindings = EventBindings.required;
    final eventId = bindings.allocate(key: _idOf(key));
    final changed = onChanged;
    if (changed != null) {
      bindings.onToggle(eventId, changed, field: 'enabled');
    }
    return WidgetNode(
      type: 'Toggle',
      props: {
        'eventId': eventId,
        'enabled': value,
        if (label != null) 'label': label,
        'semanticLabel': ?_spokenName(owner, label, semanticLabel, labelledBy),
        if (changed == null) 'disabled': true,
        if (_idOf(key) != null) 'id': _idOf(key),
      },
    );
  }
}

/// A value chosen by dragging along a track - Flutter's `Slider`.
///
/// [onChanged] fires as the thumb moves; [onChangeEnd] when it is let go,
/// which is the one to act on when acting is expensive.
class Slider extends Widget {
  const Slider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  });

  final double value;

  /// Null disables the slider, as in Flutter.
  final ValueChanged<double>? onChanged;

  /// Accepted and never called: the renderers report movement and release,
  /// not the touch that starts them.
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;

  /// Flutter shows this in a bubble over the thumb while it is dragged. No
  /// platform slider has that bubble, so it is accepted and not shown.
  final String? label;

  /// Accepted and not carried: the slider takes the theme's primary colour.
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.slider(
    value: value,
    onChanged: onChanged,
    onChangeEnd: onChangeEnd,
    min: min,
    max: max,
    divisions: divisions,
    disabled: onChanged == null,
    id: _idOf(key),
  );
}

// ---------------------------------------------------------------------------
// Progress.
// ---------------------------------------------------------------------------

/// A determinate (or, with a null [value], indeterminate) linear progress bar.
///
/// The plain bar is the platform's. One that asks for a [backgroundColor] or
/// a [minHeight] while showing a value is drawn from two boxes, which can be
/// any colour and any height; an indeterminate bar is always the platform's,
/// because its motion is.
class LinearProgressIndicator extends Widget {
  const LinearProgressIndicator({
    super.key,
    this.value,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.minHeight,
    this.semanticsLabel,
    this.borderRadius,
  });
  final double? value;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final double? minHeight;
  final String? semanticsLabel;
  final BorderRadiusGeometry? borderRadius;

  @override
  WidgetNode _render(_Owner owner) {
    final tint = color ?? valueColor?.value;
    final value = this.value;
    if (value == null || (backgroundColor == null && minHeight == null)) {
      return _named(
        DSLoading.progressLinear(
          value: value ?? 0,
          color: tint?._hex,
          indeterminate: value == null,
        ),
      );
    }
    final scheme = _themeOf(owner).colorScheme;
    final done = (value.clamp(0.0, 1.0) * 1000).round();
    return UIBuilder.box(
      height: minHeight ?? 4,
      expand: 'width',
      color: (backgroundColor ?? scheme.secondaryContainer)._hex,
      borderRadius: borderRadius?._resolved._uniform,
      clip: true,
      semanticLabel: semanticsLabel,
      semanticRole: 'progress',
      semanticValue: '${(value.clamp(0.0, 1.0) * 100).round()}%',
      id: _idOf(key),
      child: UIBuilder.row(
        crossAxisAlignment: 'stretch',
        children: [
          if (done > 0)
            UIBuilder.expanded(
              flex: done,
              child: UIBuilder.box(color: (tint ?? scheme.primary)._hex),
            ),
          if (done < 1000)
            UIBuilder.expanded(flex: 1000 - done, child: UIBuilder.sizedBox()),
        ],
      ),
    );
  }

  /// The platform's bar with this widget's key and name on it.
  WidgetNode _named(WidgetNode node) => _withProps(node, {
    'semanticLabel': ?semanticsLabel,
    'id': ?_idOf(key),
  });
}

/// A determinate (or, with a null [value], spinning) circular progress ring.
///
/// [strokeWidth] is accepted and not carried; the ring is the platform's. Its
/// size follows a [SizedBox] put around it, which is how Flutter code makes a
/// small one for a button.
class CircularProgressIndicator extends Widget {
  const CircularProgressIndicator({
    super.key,
    this.value,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.strokeWidth = 4.0,
    this.semanticsLabel,
    this.strokeCap,
  });

  /// Flutter's spinner that looks native on each platform - the only kind
  /// there is here.
  const CircularProgressIndicator.adaptive({
    super.key,
    this.value,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.strokeWidth = 4.0,
    this.semanticsLabel,
    this.strokeCap,
  });

  final double? value;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final double strokeWidth;
  final String? semanticsLabel;
  final Object? strokeCap;

  @override
  WidgetNode _render(_Owner owner) => _spinner(owner, null);

  WidgetNode _spinner(_Owner owner, double? size) {
    final tint =
        (color ??
                valueColor?.value ??
                owner._inherited<IconTheme>()?.data.color)
            ?._hex;
    final value = this.value;
    final node = value != null
        ? DSLoading.progressCircular(value: value, color: tint)
        : DSLoading.spinner(color: tint);
    // A key and a name travel with the ring: an id for a test to wait on, and
    // what a screen reader says is in progress.
    return _withProps(node, {
      'size': ?size,
      'semanticLabel': ?semanticsLabel,
      'id': ?_idOf(key),
    });
  }
}

/// A placeholder bar shown while content loads.
class Skeleton extends Widget {
  const Skeleton({super.key, this.width, this.height = 16});
  final double? width;
  final double height;
  @override
  WidgetNode _render(_Owner owner) =>
      DSLoading.skeleton(width: width ?? double.infinity, height: height);
}
