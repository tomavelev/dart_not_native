part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// What is inherited down the tree for drawing: the theme, the text style,
// the icon style.
// ---------------------------------------------------------------------------

/// The app's theme, visible to everything below it.
///
/// `Theme.of(context)` is Flutter's `ThemeData`: a colour scheme, a text
/// theme and the handful of component themes. With no theme declared it is
/// the one derived from the palette handed to `runApp(appTheme:)` - or the
/// framework's fallback palette - so a screen can read a colour without
/// asking whether anyone set one.
///
/// The palette the renderers themselves draw with is an [AppTheme], and is
/// still reachable as `Theme.of(context).appTheme`.
class Theme extends InheritedWidget {
  const Theme({super.key, required this.data, required super.child});

  final ThemeData data;

  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Theme>()?.data ?? _fallback;

  static final ThemeData _fallback = ThemeData.fromAppTheme(AppTheme.fallback);

  @override
  bool updateShouldNotify(Theme oldWidget) => oldWidget.data != data;
}

/// The theme as the build in progress sees it.
ThemeData _themeOf(_Owner owner) =>
    owner._inherited<Theme>()?.data ?? Theme._fallback;

/// The text style a [Text] starts from when it is not given all of one.
class DefaultTextStyle extends InheritedWidget {
  const DefaultTextStyle({
    super.key,
    required this.style,
    this.textAlign,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    required super.child,
  });

  /// As the constructor, but [style] is laid over the default already in
  /// effect instead of replacing it.
  static Widget merge({
    Key? key,
    TextStyle? style,
    TextAlign? textAlign,
    bool? softWrap,
    TextOverflow? overflow,
    int? maxLines,
    required Widget child,
  }) => Builder(
    builder: (context) {
      final parent = DefaultTextStyle.of(context);
      return DefaultTextStyle(
        key: key,
        style: parent.style.merge(style),
        textAlign: textAlign ?? parent.textAlign,
        softWrap: softWrap ?? parent.softWrap,
        overflow: overflow ?? parent.overflow,
        maxLines: maxLines ?? parent.maxLines,
        child: child,
      );
    },
  );

  final TextStyle style;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextOverflow overflow;
  final int? maxLines;

  /// The nearest default, or an empty style - in which case a [Text] sends
  /// only what it was given and the renderer draws the rest its own way.
  static DefaultTextStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DefaultTextStyle>() ??
      const DefaultTextStyle(style: TextStyle(), child: SizedBox.shrink());

  @override
  bool updateShouldNotify(DefaultTextStyle oldWidget) =>
      oldWidget.style != style ||
      oldWidget.textAlign != textAlign ||
      oldWidget.softWrap != softWrap ||
      oldWidget.overflow != overflow ||
      oldWidget.maxLines != maxLines;
}

/// The colour and size an [Icon] takes when it is not given its own.
class IconTheme extends InheritedWidget {
  const IconTheme({super.key, required this.data, required super.child});

  final IconThemeData data;

  @override
  bool updateShouldNotify(IconTheme oldWidget) => oldWidget.data != data;

  static IconThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data ??
      const IconThemeData();

  /// As the constructor, with [data] laid over the theme already in effect.
  static Widget merge({
    Key? key,
    required IconThemeData data,
    required Widget child,
  }) => Builder(
    builder: (context) {
      final parent = IconTheme.of(context);
      return IconTheme(
        key: key,
        data: IconThemeData(
          color: data.color ?? parent.color,
          size: data.size ?? parent.size,
        ),
        child: child,
      );
    },
  );
}

/// Renders [body] with [style] laid over the default text style in effect.
T _withTextStyle<T>(_Owner owner, TextStyle style, T Function() body) {
  final parent = owner._inherited<DefaultTextStyle>();
  return owner._withInherited(
    DefaultTextStyle(
      style: parent == null ? style : parent.style.merge(style),
      child: const SizedBox.shrink(),
    ),
    body,
  );
}

/// Renders [body] with text and icons defaulting to [color] - what a filled
/// button, a chip or an avatar does for its content.
T _withForeground<T>(
  _Owner owner,
  Color? color,
  T Function() body, {
  TextStyle? style,
  double? iconSize,
}) {
  if (color == null && style == null && iconSize == null) return body();
  final parentIcon = owner._inherited<IconTheme>()?.data;
  return _withTextStyle(
    owner,
    (style ?? const TextStyle()).copyWith(color: style?.color ?? color),
    () => owner._withInherited(
      IconTheme(
        data: IconThemeData(
          color: color ?? parentIcon?.color,
          size: iconSize ?? parentIcon?.size,
        ),
        child: const SizedBox.shrink(),
      ),
      body,
    ),
  );
}

// ---------------------------------------------------------------------------
// Text.
// ---------------------------------------------------------------------------

/// The string a widget handed as a title or a label draws.
///
/// The protocol carries those as text rather than as a subtree, so the facade
/// reads it out of the widget: a [Text], or a [Tr] - which resolves its key
/// here, and registers the locale as something this build depends on.
String? _stringOf(Widget? widget, _Owner owner) {
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is Tr) return widget.resolve(owner);
  return null;
}

/// The words in [widget], looked for a little harder than [_stringOf] does:
/// through the wrappers a label is commonly dressed in. For the places that
/// can only carry a string - a snackbar, a dropdown item, a swipe action.
String? _plainText(Widget? widget, _Owner owner) {
  final direct = _stringOf(widget, owner);
  if (direct != null) return direct;
  return switch (widget) {
    RichText() => widget.text.toPlainText(),
    SelectableText() => widget.data,
    Padding() => _plainText(widget.child, owner),
    Center() => _plainText(widget.child, owner),
    Align() => _plainText(widget.child, owner),
    SizedBox() => _plainText(widget.child, owner),
    Container() => _plainText(widget.child, owner),
    Flexible() => _plainText(widget.child, owner),
    DefaultTextStyle() => _plainText(widget.child, owner),
    Row() => _firstText(widget.children, owner),
    Column() => _firstText(widget.children, owner),
    Wrap() => _firstText(widget.children, owner),
    _ => null,
  };
}

String? _firstText(List<Widget> children, _Owner owner) {
  final found = [
    for (final child in children) _plainText(child, owner),
  ].whereType<String>();
  return found.isEmpty ? null : found.join(' ');
}

/// What becomes of text that does not fit in the lines it is allowed.
///
/// Flutter's four. `ellipsis` ends the last line with `…` and `clip` cuts it
/// off, on every renderer. `fade` is a gradient mask that UIKit, Android's
/// TextView and CSS each spell differently enough that the same text would
/// look like three different things, so it is drawn as `clip`. `visible`
/// lets the text run on, which is the absence of any of this.
enum TextOverflow { clip, fade, ellipsis, visible }

/// How wide a line of text is measured to be. Accepted for Flutter's
/// signature; the renderers measure text their own way.
enum TextWidthBasis { parent, longestLine }

/// A run of text in a [Text.rich] or a [RichText], or a widget set among
/// them.
abstract class InlineSpan {
  const InlineSpan({this.style});
  final TextStyle? style;

  /// The words alone.
  String toPlainText();
}

/// What a [TextSpan] does when it is touched. Flutter's is in
/// `package:flutter/gestures.dart`; here it comes with the widgets.
abstract class GestureRecognizer {
  /// Flutter asks for this once the recogniser is done with. There is nothing
  /// held here to let go of, so it does nothing and is safe to call.
  void dispose() {}
}

/// A tap, on a run of text: a link inside a paragraph.
///
/// ```dart
/// Text.rich(TextSpan(text: 'By signing up you accept the ', children: [
///   TextSpan(
///     text: 'terms',
///     style: const TextStyle(decoration: TextDecoration.underline),
///     recognizer: TapGestureRecognizer()..onTap = _showTerms,
///   ),
/// ]))
/// ```
///
/// Only `onTap` is heard. The run is not styled for it - colour and underline
/// are the span's `style`, as in Flutter.
class TapGestureRecognizer extends GestureRecognizer {
  TapGestureRecognizer({this.debugOwner});
  final Object? debugOwner;
  VoidCallback? onTap;
}

/// A long press on a run of text: a word to define, a link to copy.
///
/// Only `onLongPress` is heard, when the press has been held for the
/// platform's long-press time; a run can have this or a tap, as a span has
/// one recogniser in Flutter.
class LongPressGestureRecognizer extends GestureRecognizer {
  LongPressGestureRecognizer({this.debugOwner, this.duration});
  final Object? debugOwner;

  /// Flutter's own hold before a press is long; the platform's is used.
  final Duration? duration;
  VoidCallback? onLongPress;
}

/// One run of a line of text: words with the style they inherit and what a
/// touch on them does, or a widget among them.
class _Run {
  const _Run.text(this.text, this.style, this.tap, this.longPress)
    : widget = null;
  const _Run.widget(Widget this.widget)
    : text = null,
      style = null,
      tap = null,
      longPress = null;
  final String? text;
  final TextStyle? style;
  final VoidCallback? tap;
  final VoidCallback? longPress;
  final Widget? widget;
}

/// Text with a style, and runs of text inside it with styles of their own.
class TextSpan extends InlineSpan {
  const TextSpan({
    this.text,
    this.children,
    super.style,
    this.recognizer,
    this.semanticsLabel,
  });

  final String? text;
  final List<InlineSpan>? children;

  /// What a touch on this span's own [text] does - not on its children's,
  /// which is Flutter's rule too. A [TapGestureRecognizer] and a
  /// [LongPressGestureRecognizer] are the kinds that are heard.
  final GestureRecognizer? recognizer;
  final String? semanticsLabel;

  VoidCallback? get _onTap {
    final recognizer = this.recognizer;
    return recognizer is TapGestureRecognizer ? recognizer.onTap : null;
  }

  VoidCallback? get _onLongPress {
    final recognizer = this.recognizer;
    return recognizer is LongPressGestureRecognizer
        ? recognizer.onLongPress
        : null;
  }

  @override
  String toPlainText() {
    final buffer = StringBuffer(text ?? '');
    for (final child in children ?? const <InlineSpan>[]) {
      buffer.write(child.toPlainText());
    }
    return buffer.toString();
  }

  /// Every run, with the style it inherits from the spans around it.
  void _flatten(TextStyle? inherited, List<_Run> into) {
    final own = inherited == null ? style : inherited.merge(style);
    final text = this.text;
    if (text != null && text.isNotEmpty) {
      into.add(_Run.text(text, own, _onTap, _onLongPress));
    }
    for (final child in children ?? const <InlineSpan>[]) {
      switch (child) {
        case TextSpan():
          child._flatten(own, into);
        case WidgetSpan(:final child):
          into.add(_Run.widget(child));
      }
    }
  }
}

/// A widget in a line of text: an icon among the words, a badge.
///
/// It sits on the line, its middle level with the middle of the text
/// ([alignment] and [baseline] are accepted and not read). In the
/// browser and the Flutter host it is the widget itself; on iOS and Android
/// it is a picture of the widget as it was first laid out - a network image
/// in it shows what had loaded by then, which is nothing - and a tap on the
/// picture is a tap on the first thing in it that takes one.
class WidgetSpan extends InlineSpan {
  const WidgetSpan({
    required this.child,
    this.alignment,
    this.baseline,
    super.style,
  });
  final Widget child;
  final Object? alignment;
  final Object? baseline;

  /// One object-replacement character, as Flutter's is.
  @override
  String toPlainText() => '\uFFFC';
}

/// The event of the first thing in [node] a tap is heard by.
String? _firstTap(WidgetNode node) {
  final props = node.props;
  final tap = props['tapEventId'];
  if (tap is String) return tap;
  final event = props['eventId'];
  if (event is String && node.type.contains('Button')) return event;
  for (final child in node.children ?? const <WidgetNode>[]) {
    final found = _firstTap(child);
    if (found != null) return found;
  }
  return null;
}

/// The protocol's name for [align] where [owner] is building.
///
/// The protocol's 'left' and 'right' are physical and its silence means "the
/// screen's start", so the side is worked out here - start and end against
/// the ambient [Directionality] - and then left unsaid wherever it is the
/// side silence already means.
String? _textAlignName(TextAlign? align, _Owner owner) {
  final rtl = owner._direction == TextDirection.rtl;
  final side = switch (align) {
    TextAlign.center => 'center',
    TextAlign.justify => 'justify',
    TextAlign.left => 'left',
    TextAlign.right => 'right',
    TextAlign.end => rtl ? 'left' : 'right',
    null || TextAlign.start => rtl ? 'right' : 'left',
  };
  final unsaid = owner._screenDirection == TextDirection.rtl ? 'right' : 'left';
  return side == unsaid ? null : side;
}

/// The one place text becomes a node.
///
/// A style reaches the node only as far as someone gave one: with no
/// [DefaultTextStyle] above and no style of its own a text carries nothing
/// but its words, and each renderer draws it in its theme's body style.
WidgetNode _textNode(
  _Owner owner,
  String content, {
  TextStyle? style,
  InlineSpan? span,
  TextAlign? textAlign,
  bool? softWrap,
  TextOverflow? overflow,
  int? maxLines,
  bool selectable = false,
  String? id,
}) {
  final inherited = owner._inherited<DefaultTextStyle>();
  var effective = style;
  if (inherited != null && (style == null || style.inherit)) {
    effective = inherited.style.merge(style);
  }
  final fit = overflow ?? (inherited == null ? null : inherited.overflow);
  var lines = maxLines ?? inherited?.maxLines;
  if (lines == null) {
    if (softWrap == false || inherited?.softWrap == false) {
      lines = 1;
    } else if (overflow != null && overflow != TextOverflow.visible) {
      // An overflow without a maxLines caps the text at one line, which is
      // what asking for an ellipsis means to someone coming from Flutter.
      lines = 1;
    }
  }
  List<Map<String, dynamic>>? spans;
  if (span is TextSpan) {
    final runs = <_Run>[];
    // The root span's style is the node's; its children inherit from there.
    for (final child in span.children ?? const <InlineSpan>[]) {
      switch (child) {
        case TextSpan():
          child._flatten(null, runs);
        case WidgetSpan(:final child):
          runs.add(_Run.widget(child));
      }
    }
    final root = span.text;
    final rootTap = root == null || root.isEmpty ? null : span._onTap;
    final rootPress = root == null || root.isEmpty ? null : span._onLongPress;
    if (runs.isNotEmpty || rootTap != null || rootPress != null) {
      // A run that can be tapped carries the event its tap sends, and one
      // that can be held the event its long press sends. Named by the
      // node's id and the run's place when the node has one, so that a link
      // keeps its event from one build to the next.
      var place = 0;
      String? event(VoidCallback? handler, int index, String kind) {
        if (handler == null) return null;
        final bindings = EventBindings.required;
        final eventId = bindings.allocate(
          key: id == null ? null : '$id.span$index$kind',
        );
        bindings.onTap(eventId, handler);
        return eventId;
      }

      Map<String, dynamic> run(
        String text,
        VoidCallback? onTap,
        VoidCallback? onLongPress, [
        TextStyle? runStyle,
      ]) {
        final index = place++;
        return {
          'text': text,
          'eventId': ?event(onTap, index, ''),
          'longPressEventId': ?event(onLongPress, index, '.long'),
          if (runStyle?.color != null) 'color': runStyle!.color!._hex,
          if (runStyle?.fontSize != null) 'fontSize': runStyle!.fontSize,
          if (runStyle?.fontWeight != null)
            'fontWeight': runStyle!.fontWeight!.value,
          if (runStyle?.decoration != null)
            'decoration': runStyle!.decoration!._name,
          if (runStyle?.fontStyle == FontStyle.italic) 'italic': true,
        };
      }

      spans = [
        if (root != null && root.isNotEmpty) run(root, rootTap, rootPress),
        for (final item in runs)
          if (item.widget case final widget?)
            _widgetRun(owner, widget, place++)
          else
            run(item.text!, item.tap, item.longPress, item.style),
      ];
    }
    effective = effective == null ? span.style : effective.merge(span.style);
  }
  return UIBuilder.text(
    content,
    fontSize: effective?.fontSize,
    fontWeight: effective?.fontWeight?.value,
    color: effective?.color?._hex,
    decoration: effective?.decoration?._name,
    maxLines: lines,
    overflow: lines == null || fit == null || fit == TextOverflow.visible
        ? null
        : (fit == TextOverflow.ellipsis ? 'ellipsis' : 'clip'),
    textAlign: _textAlignName(textAlign ?? inherited?.textAlign, owner),
    letterSpacing: effective?.letterSpacing,
    lineHeight: effective?.height,
    fontFamily: effective?.fontFamily,
    italic: effective?.fontStyle == FontStyle.italic,
    selectable: selectable,
    spans: spans,
    id: id,
  );
}

/// A [WidgetSpan]'s run: the widget's tree, which a renderer that cannot
/// put a widget in a line draws as a picture - with, for that picture, the
/// event of the first thing in it a tap is heard by.
Map<String, dynamic> _widgetRun(_Owner owner, Widget widget, int index) {
  final node = _renderChild(owner, widget, 'span$index');
  return {
    'text': '\uFFFC',
    'widget': node.toJson(),
    'eventId': ?_firstTap(node),
  };
}

/// Text from the translation table, redrawn when the locale changes.
///
/// The framework does the two things an app used to do by hand: look the key
/// up, and repaint when someone calls `setLocale`. A screen no longer keeps a
/// listener of its own.
///
/// ```dart
/// AppBar(title: const Tr('navigation.settings')),
/// const Tr('plurals.items', count: 3),
/// Tr('messages.welcome', params: {'name': user.name}),
/// ```
///
/// Resolves against the global [I18n] unless given another. A key with no
/// translation falls back to [defaultValue], then to the key itself, which is
/// [I18n.t]'s own behaviour - a missing string shows up on screen rather than
/// crashing a release build.
class Tr extends Widget {
  const Tr(
    this.translationKey, {
    super.key,
    this.params,
    this.count,
    this.defaultValue,
    this.style,
    this.i18n,
  });

  /// The key to look up, nested keys included (`forms.email`).
  final String translationKey;

  /// Values for the placeholders in the translation.
  final Map<String, dynamic>? params;

  /// How many, for a key whose translation is a plural table.
  final int? count;

  /// Drawn when no locale has this key.
  final String? defaultValue;

  final TextStyle? style;

  /// The table to translate against. The global one by default.
  final I18n? i18n;

  /// The translated string, and the locale this build now follows.
  String resolve(_Owner owner) {
    final table = i18n ?? getI18n();
    owner._watch(table);
    final count = this.count;
    if (count != null) {
      return table.plural(
        translationKey,
        count,
        params: params,
        defaultValue: defaultValue,
      );
    }
    return table.t(translationKey, params: params, defaultValue: defaultValue);
  }

  @override
  WidgetNode _render(_Owner owner) =>
      _textNode(owner, resolve(owner), style: style, id: _idOf(key));
}

class Text extends Widget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.textDirection,
    this.locale,
    this.textScaler,
    this.semanticsLabel,
    this.textWidthBasis,
    this.selectionColor,
  }) : textSpan = null;

  /// Text in runs of different styles - see [TextSpan].
  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.textDirection,
    this.locale,
    this.textScaler,
    this.semanticsLabel,
    this.textWidthBasis,
    this.selectionColor,
  }) : data = null;

  /// The words, for a plain text; null for a [Text.rich].
  final String? data;

  /// The runs, for a [Text.rich]; null for a plain text.
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// False keeps the text on one line, whatever its length.
  final bool? softWrap;

  /// What happens to the text that does not fit - see [TextOverflow]. An
  /// overflow without a [maxLines] caps the text at one line.
  final TextOverflow? overflow;

  /// The most lines this text may take. Without one it wraps as far as it
  /// likes, which is what a row of unknown text will do to a fixed height.
  final int? maxLines;

  /// Accepted for Flutter's signature and not carried: the platform draws
  /// text in its own direction, locale and scale.
  final TextDirection? textDirection;
  final Locale? locale;
  final TextScaler? textScaler;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final Color? selectionColor;

  @override
  WidgetNode _render(_Owner owner) => _textNode(
    owner,
    data ?? textSpan!.toPlainText(),
    style: style,
    span: textSpan,
    textAlign: textAlign,
    softWrap: softWrap,
    overflow: overflow,
    maxLines: maxLines,
    id: _idOf(key),
  );
}

/// Text in runs of different styles, without a [DefaultTextStyle]'s help:
/// Flutter's `RichText`.
class RichText extends Widget {
  const RichText({
    super.key,
    required this.text,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.textScaler = TextScaler.noScaling,
    this.maxLines,
  });
  final InlineSpan text;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;

  @override
  WidgetNode _render(_Owner owner) => _textNode(
    owner,
    text.toPlainText(),
    span: text,
    textAlign: textAlign,
    softWrap: softWrap,
    // Flutter's default here is clip, which without a line limit is no
    // limit at all; passing it on would cap the text at one line.
    overflow: maxLines == null ? null : overflow,
    maxLines: maxLines,
    id: _idOf(key),
  );
}

/// Text the user can select and copy.
///
/// [SelectableText.rich] takes runs with styles of their own, and a run with
/// a recogniser can be tapped or held as in a [Text.rich] - on every
/// renderer, the touch going to the run as well as to the selection.
class SelectableText extends Widget {
  const SelectableText(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.onTap,
  }) : textSpan = null;

  const SelectableText.rich(
    TextSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.onTap,
  }) : data = null;

  final String? data;
  final TextSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  /// Accepted and not wired: a selectable text takes the touches itself.
  final VoidCallback? onTap;

  @override
  WidgetNode _render(_Owner owner) => _textNode(
    owner,
    data ?? textSpan!.toPlainText(),
    style: style,
    span: textSpan,
    textAlign: textAlign,
    maxLines: maxLines,
    selectable: true,
    id: _idOf(key),
  );
}

// ---------------------------------------------------------------------------
// Icons and images.
// ---------------------------------------------------------------------------

/// One glyph of the Material Icons font.
class Icon extends Widget {
  const Icon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
  });

  /// Null draws an empty box of the icon's size, as in Flutter.
  final IconData? icon;

  /// 24 unless an [IconTheme] says otherwise.
  final double? size;

  /// The surrounding text colour unless this or an [IconTheme] says
  /// otherwise.
  final Color? color;

  /// What a screen reader says for it.
  final String? semanticLabel;

  /// Accepted for Flutter's signature. They steer a variable font, and the
  /// bundled icon font is not one.
  final TextDirection? textDirection;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final List<Shadow>? shadows;

  @override
  WidgetNode _render(_Owner owner) {
    final theme = owner._inherited<IconTheme>()?.data;
    final resolvedSize = size ?? theme?.size;
    final icon = this.icon;
    if (icon == null) {
      return UIBuilder.sizedBox(
        width: resolvedSize ?? 24,
        height: resolvedSize ?? 24,
      );
    }
    return UIBuilder.icon(
      codepoint: icon.codePoint,
      size: resolvedSize,
      color: (color ?? theme?.color)?._hex,
      semanticLabel: semanticLabel,
      id: _idOf(key),
    );
  }
}

/// Where an image comes from. The node takes a URL or an asset path, so a
/// provider is whichever of those it names.
abstract class ImageProvider {
  const ImageProvider();
  String get _src;
}

class AssetImage extends ImageProvider {
  const AssetImage(this.assetName, {this.package});
  final String assetName;

  /// Accepted and not consulted: assets are resolved by the platform host.
  final String? package;
  @override
  String get _src => assetName;
}

class NetworkImage extends ImageProvider {
  const NetworkImage(this.url, {this.scale = 1.0, this.headers});
  final String url;
  final double scale;

  /// Accepted and not sent: the platform's image loader makes the request.
  final Map<String, String>? headers;
  @override
  String get _src => url;
}

/// Image bytes held in memory, carried to the renderer as a `data:` URL -
/// which suits an icon or a thumbnail and is a poor way to move a photograph.
class MemoryImage extends ImageProvider {
  const MemoryImage(this.bytes, {this.scale = 1.0});
  final List<int> bytes;
  final double scale;
  @override
  String get _src => 'data:${_mimeOf(bytes)};base64,${base64Encode(bytes)}';
}

/// The image type, from the first bytes of the file.
String _mimeOf(List<int> bytes) {
  bool starts(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts(const [0x47, 0x49, 0x46])) return 'image/gif';
  if (starts(const [0x52, 0x49, 0x46, 0x46])) return 'image/webp';
  if (starts(const [0x3C])) return 'image/svg+xml';
  return 'image/png';
}

/// Builds what is shown in place of an image that could not be loaded.
typedef ImageErrorWidgetBuilder =
    Widget Function(BuildContext context, Object error, StackTrace? stackTrace);

/// Flutter's signature for a builder called as an image's bytes arrive:
/// with an [ImageChunkEvent] while the image is on its way, and with null
/// once it is there - see [Image].
typedef ImageLoadingBuilder =
    Widget Function(
      BuildContext context,
      Widget child,
      ImageChunkEvent? loadingProgress,
    );

/// How much of an image has arrived, as an [ImageLoadingBuilder] is told.
///
/// The bytes are counted by the renderer that fetches them, which says how
/// many have come a few times a second - and how many there are, when the
/// server said. The browser fetches an `<img>` itself and says neither, so
/// there the image is on its way with nothing loaded and no total.
class ImageChunkEvent {
  const ImageChunkEvent({
    required this.cumulativeBytesLoaded,
    required this.expectedTotalBytes,
  });

  final int cumulativeBytesLoaded;
  final int? expectedTotalBytes;
}

/// Flutter's signature for a builder called as an image's frames arrive:
/// with no frame while the image is on its way and with frame 0 once it is
/// showing - see [Image].
typedef ImageFrameBuilder =
    Widget Function(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    );

/// What an [Image.errorBuilder] is handed for its `error`.
///
/// The image is loaded by a renderer, on the far side of a channel, which
/// says that it failed and not why - so there is no real error to hand
/// over, only the fact that this is what to draw now that
/// there turns out to be one. A builder that prints its error says this.
class ImageLoadFailure implements Exception {
  const ImageLoadFailure(this.src);

  /// The source that would not load.
  final String src;

  @override
  String toString() => 'ImageLoadFailure: $src could not be loaded';
}

/// An image.
///
/// A remote image is cached by the renderer that draws it - the browser,
/// Flutter's image cache, a decoded-bitmap cache over the platform's HTTP
/// cache on Android and iOS - so a rebuild does not fetch it again.
///
/// [semanticLabel] is what a screen reader announces, and what a renderer
/// shows if the image cannot be loaded and there is no [errorBuilder].
///
/// The three builders are Flutter's, and follow the load as the renderer
/// reports it - an image given any of them is told when its picture is
/// showing and when it has failed:
///
/// - [loadingBuilder] is called with an [ImageChunkEvent] while a remote
///   image is on its way, and what it returns is drawn in the image's place
///   until the picture arrives - a spinner, a progress bar, called again as
///   the bytes come (not on the web, whose browser does not say). Once the
///   picture is there it is called with null, around the image.
/// - [errorBuilder] is called when the load has failed, and not before, with
///   an [ImageLoadFailure] and no stack trace: the renderer says that it
///   failed, not why.
/// - [frameBuilder] is called with no frame while the image is on its way
///   and with frame 0 once it is showing, so a fade-in written the usual way
///   fades in. `wasSynchronouslyLoaded` is true of an image that needs no
///   fetching - an asset, bytes - and of a remote one this run of the app
///   has already shown.
///
/// One difference from Flutter while loading: the image has to be in the
/// tree for a renderer to fetch it, so the `child` a [loadingBuilder] is
/// handed then is an empty box, and what the builder returns stands in the
/// image's place rather than around it.
class Image extends Widget {
  const Image({
    super.key,
    required this.image,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
  });

  Image.asset(
    String name, {
    super.key,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
    String? package,
  }) : image = AssetImage(name, package: package);

  Image.network(
    String src, {
    super.key,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
    Map<String, String>? headers,
  }) : image = NetworkImage(src, headers: headers);

  Image.memory(
    List<int> bytes, {
    super.key,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
  }) : image = MemoryImage(bytes);

  final ImageProvider image;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final double? width;
  final double? height;

  /// A tint: blended with the picture as [colorBlendMode] says.
  final Color? color;

  /// How [color] is blended with the picture - left null, as its own shape
  /// filled with the colour (`BlendMode.srcIn`), as in Flutter. Every mode
  /// is carried; on the web the picture's transparent parts stay clear
  /// whichever is asked, where Flutter would fill them for some.
  final BlendMode? colorBlendMode;

  /// How the picture fills its box. Left null it is fitted inside, whole,
  /// which is the nearest thing to Flutter's default.
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageFrameBuilder? frameBuilder;

  @override
  WidgetNode _render(_Owner owner) =>
      frameBuilder == null && loadingBuilder == null && errorBuilder == null
      ? _image(owner)
      // Something of the app's depends on how the load goes: follow it.
      : owner.inSlot('load', () => _ImageLoad(this)._render(owner));

  /// The image's node, with [standIn] to draw in its place until the picture
  /// is there and [onLoad] to hear how the load ended.
  WidgetNode _image(
    _Owner owner, {
    Widget? standIn,
    void Function(bool loaded)? onLoad,
    void Function(int loaded, int? expected)? onProgress,
    int? loadAsk,
  }) => UIBuilder.image(
    src: image._src,
    alt: semanticLabel ?? '',
    fallback: standIn == null
        ? null
        : owner.inSlot('standIn', () => standIn._render(owner)),
    onLoad: onLoad,
    onProgress: onProgress,
    loadAsk: loadAsk,
    width: width,
    height: height,
    fillWidth:
        width != null && height == null && identical(owner._tightWidth, this),
    color: color?._hex,
    blend: color == null || colorBlendMode == null
        ? null
        : colorBlendMode!.name,
    fit: switch (fit) {
      null || BoxFit.contain || BoxFit.fitWidth || BoxFit.fitHeight => 'contain',
      BoxFit.cover => 'cover',
      BoxFit.fill => 'fill',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scaleDown',
    },
    id: _idOf(key),
  );
}

/// An [Image] with builders, and where its load has got to.
class _ImageLoad extends StatefulWidget {
  const _ImageLoad(this.image);
  final Image image;

  @override
  State<_ImageLoad> createState() => _ImageLoadState();
}

class _ImageLoadState extends State<_ImageLoad> {
  /// The remote images that have been seen to load, this run of the app: a
  /// renderer keeps what it fetched, so one of these is there at once.
  static final Set<String> _arrived = {};

  /// Null while the image is on its way; then whether it loaded.
  bool? _loaded;

  /// How much of it has come, as the renderer last said.
  ImageChunkEvent _chunk = const ImageChunkEvent(
    cumulativeBytesLoaded: 0,
    expectedTotalBytes: null,
  );

  void _progressed(int loaded, int? expected) {
    if (!mounted || _loaded != null) return;
    setState(
      () => _chunk = ImageChunkEvent(
        cumulativeBytesLoaded: loaded,
        expectedTotalBytes: expected,
      ),
    );
  }

  /// Whether the image was there from the start, with nothing to wait for.
  bool _atOnce = true;

  /// A number for this wait, so the renderer answers it and not an earlier
  /// one for the same picture in the same place.
  static int _asks = 0;
  int _ask = 0;

  String get _src => widget.image.image._src;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void didUpdateWidget(_ImageLoad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.image._src != _src) _begin();
  }

  void _begin() {
    final src = _src;
    final fetched = src.startsWith('http://') || src.startsWith('https://');
    _atOnce = !fetched || _arrived.contains(src);
    _loaded = _atOnce ? true : null;
    _ask = ++_asks;
    _chunk = const ImageChunkEvent(
      cumulativeBytesLoaded: 0,
      expectedTotalBytes: null,
    );
  }

  void _heard(bool loaded) {
    if (loaded && _src.startsWith('http')) {
      // A long-lived app sees many pictures; the set is only a hint.
      if (_arrived.length > 4000) _arrived.clear();
      _arrived.add(_src);
    }
    if (!mounted || _loaded == loaded) return;
    setState(() => _loaded = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final loaded = _loaded;
    if (loaded == false) {
      // Failed: the app's own word for it, or - with none - the renderer's,
      // which is the description.
      final standIn = image.errorBuilder?.call(
        context,
        ImageLoadFailure(_src),
        null,
      );
      return _NodeWidget(
        (owner) => image._image(
          owner,
          standIn: standIn,
          onLoad: _heard,
          loadAsk: _ask,
        ),
      );
    }
    final waiting = loaded == null;
    // Always a stand-in, if only an empty one: it is what a renderer draws
    // until the picture is there, where it would otherwise write the
    // description - and the same node, whichever way the load goes.
    final standIn = waiting
        ? image.loadingBuilder?.call(context, const SizedBox.shrink(), _chunk)
        : null;
    Widget built = _NodeWidget(
      (owner) => image._image(
        owner,
        standIn: standIn ?? const SizedBox.shrink(),
        onLoad: _heard,
        onProgress: image.loadingBuilder == null ? null : _progressed,
        loadAsk: _ask,
      ),
    );
    // In Flutter's order: the frame builder wraps the image, and the loading
    // builder wraps what that made.
    final frame = image.frameBuilder;
    if (frame != null) {
      built = frame(context, built, waiting ? null : 0, _atOnce);
    }
    final loading = image.loadingBuilder;
    if (loading != null && !waiting) built = loading(context, built, null);
    return built;
  }
}
