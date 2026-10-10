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

/// Text with a style, and runs of text inside it with styles of their own.
class TextSpan extends InlineSpan {
  const TextSpan({this.text, this.children, super.style, this.semanticsLabel});

  final String? text;
  final List<InlineSpan>? children;
  final String? semanticsLabel;

  @override
  String toPlainText() {
    final buffer = StringBuffer(text ?? '');
    for (final child in children ?? const <InlineSpan>[]) {
      buffer.write(child.toPlainText());
    }
    return buffer.toString();
  }

  /// Every run, with the style it inherits from the spans around it.
  void _flatten(TextStyle? inherited, List<(String, TextStyle?)> into) {
    final own = inherited == null ? style : inherited.merge(style);
    final text = this.text;
    if (text != null && text.isNotEmpty) into.add((text, own));
    for (final child in children ?? const <InlineSpan>[]) {
      if (child is TextSpan) child._flatten(own, into);
    }
  }
}

/// A widget in a line of text. The protocol's runs are text only, so the
/// widget is left out of the line - put it beside the text in a [Row].
class WidgetSpan extends InlineSpan {
  const WidgetSpan({required this.child, super.style});
  final Widget child;
  @override
  String toPlainText() => '';
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
    final runs = <(String, TextStyle?)>[];
    // The root span's style is the node's; its children inherit from there.
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) child._flatten(null, runs);
    }
    if (runs.isNotEmpty) {
      final root = span.text;
      spans = [
        if (root != null && root.isNotEmpty) {'text': root},
        for (final (text, runStyle) in runs)
          {
            'text': text,
            if (runStyle?.color != null) 'color': runStyle!.color!._hex,
            if (runStyle?.fontSize != null) 'fontSize': runStyle!.fontSize,
            if (runStyle?.fontWeight != null)
              'fontWeight': runStyle!.fontWeight!.value,
            if (runStyle?.decoration != null)
              'decoration': runStyle!.decoration!._name,
            if (runStyle?.fontStyle == FontStyle.italic) 'italic': true,
          },
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
class SelectableText extends Widget {
  const SelectableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.onTap,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  /// Accepted and not wired: a selectable text takes the touches itself.
  final VoidCallback? onTap;

  @override
  WidgetNode _render(_Owner owner) => _textNode(
    owner,
    data,
    style: style,
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

/// Flutter's signature for a builder called as an image's bytes arrive.
/// Called by [Image] once, as for an image that has arrived - see there.
typedef ImageLoadingBuilder =
    Widget Function(BuildContext context, Widget child, Object? loadingProgress);

/// Flutter's signature for a builder called as an image's frames arrive.
/// Called by [Image] once, as for an image already loaded - see there.
typedef ImageFrameBuilder =
    Widget Function(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    );

/// What an [Image.errorBuilder] is handed for its `error`.
///
/// The image is loaded by a renderer, on the far side of a channel, and the
/// stand-in has to be in the tree before anything has been tried - so there is
/// no real error to hand over, only the fact that this is what to draw if
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
/// [errorBuilder] is Flutter's, with one difference that follows from where
/// the loading happens. A renderer cannot call back into a build that is
/// long over, so the builder is called *once, up front*, with an
/// [ImageLoadFailure] and no stack trace, and what it returns travels with
/// the image as its fallback: drawn in the image's place if loading fails -
/// and also while it is still loading, since a renderer has the one stand-in
/// for both. A builder that inspects the error, or that expects only to run
/// after a failure, will find neither true here.
///
/// [frameBuilder] and [loadingBuilder] are called once per build, as Flutter
/// calls them for an image that is already there: the first with frame 0 and
/// `wasSynchronouslyLoaded` true, the second with no progress. So what they
/// put around the image - a frame, a clip, a background - is drawn, and the
/// part of them that is for the wait is never seen: the progress and the
/// frames stay in the renderer. What shows while an image loads is the
/// [errorBuilder]'s widget, or nothing.
class Image extends Widget {
  const Image({
    super.key,
    required this.image,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
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

  /// Accepted and not applied: tinting an image is not something the node
  /// carries.
  final Color? color;

  /// How the picture fills its box. Left null it is fitted inside, whole,
  /// which is the nearest thing to Flutter's default.
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageFrameBuilder? frameBuilder;

  @override
  WidgetNode _render(_Owner owner) {
    final frame = frameBuilder;
    final loading = loadingBuilder;
    if (frame == null && loading == null) return _image(owner);
    // In Flutter's order: the frame builder wraps the image, and the loading
    // builder wraps what that made.
    final context = owner._context();
    Widget built = _NodeWidget(_image);
    if (frame != null) built = frame(context, built, 0, true);
    if (loading != null) built = loading(context, built, null);
    return owner.inSlot('built', () => built._render(owner));
  }

  WidgetNode _image(_Owner owner) => UIBuilder.image(
    src: image._src,
    alt: semanticLabel ?? '',
    fallback: switch (errorBuilder) {
      null => null,
      final build => owner.inSlot(
        'error',
        () => build(
          owner._context(),
          ImageLoadFailure(image._src),
          null,
        )._render(owner),
      ),
    },
    width: width,
    height: height,
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
