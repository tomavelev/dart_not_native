part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Custom painting: Flutter's CustomPaint / CustomPainter / Canvas, recorded.
//
// A Flutter painter draws into an engine canvas, frame by frame. There is no
// engine here: the painter runs during the build, the Canvas it is handed
// writes down what it was asked to draw, and that list travels in a `Canvas`
// node for each renderer to replay into its own surface (Android's Canvas,
// Core Graphics, a <canvas> element, a Flutter CustomPaint).
// ---------------------------------------------------------------------------

/// Whether a shape is filled or outlined.
enum PaintingStyle { fill, stroke }

/// How the ends of a stroked line are finished.
enum StrokeCap { butt, round, square }

/// How two stroked segments meet.
enum StrokeJoin { miter, round, bevel }

/// What [Canvas.drawPoints] makes of its list of points.
enum PointMode {
  /// Each point is a dot.
  points,

  /// Each pair of points is a segment.
  lines,

  /// Each point is joined to the next.
  polygon,
}

/// Whether a clip keeps the inside or the outside of its shape. Accepted for
/// Flutter's signature; every clip here keeps the inside.
enum ClipOp { difference, intersect }

/// Which points count as inside a self-crossing [Path]. Accepted and ignored:
/// each renderer fills with its platform's default rule.
enum PathFillType { nonZero, evenOdd }

/// How a shape is drawn: its colour, and whether it is filled or stroked.
///
/// What travels is [color], [style], [strokeWidth], [strokeCap] and
/// [strokeJoin]. [shader], [maskFilter], [colorFilter], [blendMode] and
/// [isAntiAlias] can be set, so a painter written for Flutter compiles, and
/// are not carried: a gradient or a blur has no place in the paint table, and
/// a shape painted with one is drawn in its plain [color].
class Paint {
  Color color = const Color(0xFF000000);
  PaintingStyle style = PaintingStyle.fill;

  /// The width of a stroke. Flutter's zero means "one device pixel"; here it
  /// is sent as one logical pixel, the thinnest line every renderer agrees on.
  double strokeWidth = 0;
  StrokeCap strokeCap = StrokeCap.butt;
  StrokeJoin strokeJoin = StrokeJoin.miter;

  /// Ignored - see the class doc.
  bool isAntiAlias = true;

  /// Ignored - see the class doc.
  Object? shader;

  /// Ignored - see the class doc.
  Object? maskFilter;

  /// Ignored - see the class doc.
  Object? colorFilter;

  /// Ignored - see the class doc.
  BlendMode blendMode = BlendMode.srcOver;

  /// Ignored: a mitred corner is each platform's default limit.
  double strokeMiterLimit = 4;

  /// The paint as the protocol spells it, defaults left out so two paints
  /// that draw the same are the same entry. [stroke] forces an outline, for a
  /// line - which has no inside to fill, whatever [style] says.
  Map<String, dynamic> _json({bool? stroke}) {
    final stroked = stroke ?? style == PaintingStyle.stroke;
    return {
      'color': color._hex,
      if (stroked) 'style': 'stroke',
      if (stroked) 'strokeWidth': strokeWidth <= 0 ? 1.0 : strokeWidth,
      if (stroked && strokeCap != StrokeCap.butt) 'cap': strokeCap.name,
      if (stroked && strokeJoin != StrokeJoin.miter) 'join': strokeJoin.name,
    };
  }
}

/// An outline built up from lines, curves and shapes, for [Canvas.drawPath].
///
/// Recorded as the protocol's path segments. Two things are approximated:
/// [addRRect] adds the rounded rectangle's plain rectangle (the segment list
/// has no rounded one - use [Canvas.drawRRect] for the real shape), and
/// [arcToPoint] draws a straight line to its end point.
class Path {
  final List<List<Object?>> _segments = [];

  /// Every point the path was told about, for [getBounds]. Control points are
  /// included, so the bounds of a curve are a little generous.
  final List<double> _xs = [];
  final List<double> _ys = [];

  double _x = 0;
  double _y = 0;

  /// Accepted and ignored - see [PathFillType].
  PathFillType fillType = PathFillType.nonZero;

  void _seen(double x, double y) {
    _xs.add(x);
    _ys.add(y);
  }

  void _to(double x, double y) {
    _x = x;
    _y = y;
    _seen(x, y);
  }

  void moveTo(double x, double y) {
    _segments.add(['M', x, y]);
    _to(x, y);
  }

  void relativeMoveTo(double dx, double dy) => moveTo(_x + dx, _y + dy);

  void lineTo(double x, double y) {
    _segments.add(['L', x, y]);
    _to(x, y);
  }

  void relativeLineTo(double dx, double dy) => lineTo(_x + dx, _y + dy);

  void quadraticBezierTo(double x1, double y1, double x2, double y2) {
    _segments.add(['Q', x1, y1, x2, y2]);
    _seen(x1, y1);
    _to(x2, y2);
  }

  void relativeQuadraticBezierTo(
    double x1,
    double y1,
    double x2,
    double y2,
  ) => quadraticBezierTo(_x + x1, _y + y1, _x + x2, _y + y2);

  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _segments.add(['C', x1, y1, x2, y2, x3, y3]);
    _seen(x1, y1);
    _seen(x2, y2);
    _to(x3, y3);
  }

  void relativeCubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => cubicTo(_x + x1, _y + y1, _x + x2, _y + y2, _x + x3, _y + y3);

  /// Where an arc of the oval in [rect] is at [angle].
  static (double, double) _onOval(Rect rect, double angle) => (
    rect.left + rect.width / 2 + rect.width / 2 * math.cos(angle),
    rect.top + rect.height / 2 + rect.height / 2 * math.sin(angle),
  );

  /// An arc of the oval in [rect], joined to the path so far with a line -
  /// or started afresh when [forceMoveTo] says so.
  void arcTo(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool forceMoveTo,
  ) {
    if (forceMoveTo || _segments.isEmpty) {
      final (sx, sy) = _onOval(rect, startAngle);
      moveTo(sx, sy);
    }
    _segments.add([
      'A',
      rect.left,
      rect.top,
      rect.width,
      rect.height,
      startAngle,
      sweepAngle,
    ]);
    _seen(rect.left, rect.top);
    _seen(rect.right, rect.bottom);
    final (ex, ey) = _onOval(rect, startAngle + sweepAngle);
    _x = ex;
    _y = ey;
  }

  /// An arc on its own, not joined to what came before.
  void addArc(Rect oval, double startAngle, double sweepAngle) =>
      arcTo(oval, startAngle, sweepAngle, true);

  /// Flutter draws an elliptical arc to [arcEnd]; the segment list has no
  /// arc given by its end point, so this is a straight line there. A painter
  /// that needs the curve can use [arcTo] with the oval's rectangle.
  void arcToPoint(
    Offset arcEnd, {
    Radius radius = Radius.zero,
    double rotation = 0,
    bool largeArc = false,
    bool clockwise = true,
  }) => lineTo(arcEnd.dx, arcEnd.dy);

  void addRect(Rect rect) {
    _segments.add(['R', rect.left, rect.top, rect.width, rect.height]);
    _seen(rect.left, rect.top);
    _seen(rect.right, rect.bottom);
    _x = rect.left;
    _y = rect.top;
  }

  void addOval(Rect oval) {
    _segments.add(['O', oval.left, oval.top, oval.width, oval.height]);
    _seen(oval.left, oval.top);
    _seen(oval.right, oval.bottom);
  }

  /// Adds the rectangle [rrect] rounds - without the rounding; see the class
  /// doc.
  void addRRect(RRect rrect) => addRect(
    Rect.fromLTWH(rrect.left, rrect.top, rrect.width, rrect.height),
  );

  /// Straight lines through [points], closed back to the first when [close].
  void addPolygon(List<Offset> points, bool close) {
    if (points.isEmpty) return;
    moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      lineTo(point.dx, point.dy);
    }
    if (close) this.close();
  }

  /// Appends [path], moved by [offset].
  void addPath(Path path, Offset offset) {
    final dx = offset.dx;
    final dy = offset.dy;
    for (final segment in path._segments) {
      final name = segment.first as String;
      final moved = <Object?>[name];
      // Coordinates come in x, y pairs from the front. A rectangle, an oval
      // and an arc are a corner followed by a size (and angles), so only
      // their first pair is a position.
      final pairs = switch (name) {
        'R' || 'O' || 'A' => 1,
        _ => (segment.length - 1) ~/ 2,
      };
      for (var i = 1; i < segment.length; i++) {
        final value = segment[i] as double;
        final isPosition = i <= pairs * 2;
        moved.add(isPosition ? value + (i.isOdd ? dx : dy) : value);
      }
      _segments.add(moved);
    }
    for (var i = 0; i < path._xs.length; i++) {
      _seen(path._xs[i] + dx, path._ys[i] + dy);
    }
    _x = path._x + dx;
    _y = path._y + dy;
  }

  void close() => _segments.add(['Z']);

  void reset() {
    _segments.clear();
    _xs.clear();
    _ys.clear();
    _x = 0;
    _y = 0;
  }

  /// The box around every point the path was given. A best effort: a curve's
  /// control points count, so the box can be larger than the ink, and an arc
  /// counts as its whole oval.
  Rect getBounds() {
    if (_xs.isEmpty) return Rect.fromLTRB(0, 0, 0, 0);
    return Rect.fromLTRB(
      _xs.reduce(math.min),
      _ys.reduce(math.min),
      _xs.reduce(math.max),
      _ys.reduce(math.max),
    );
  }
}

/// The surface a [CustomPainter] draws on - a recording one.
///
/// Each call appends a command to the list a `Canvas` node carries; nothing
/// is drawn in Dart. What Flutter's canvas has and this one leaves out is
/// what the command list has no word for: `drawImage`, `drawParagraph`,
/// `drawVertices`, `drawShadow`, `drawDRRect`, and a free-form `transform`.
/// [clipPath] is accepted and does nothing; [saveLayer] is a plain [save].
class Canvas {
  Canvas._(this._size);

  /// The surface being drawn, which is what [drawColor] and [drawPaint] fill.
  final Size _size;

  final List<List<Object?>> _commands = [];
  final List<Map<String, dynamic>> _paints = [];

  /// Where each distinct paint sits in [_paints]. Painters make a `Paint()`
  /// per call as a matter of habit, and a board of sixty-four squares in two
  /// colours should send two paints rather than sixty-four.
  final Map<String, int> _paintIndex = {};

  int _saves = 1;

  int _paint(Paint paint, {bool? stroke}) {
    final json = paint._json(stroke: stroke);
    final key =
        '${json['color']}|${json['style']}|${json['strokeWidth']}|'
        '${json['cap']}|${json['join']}';
    return _paintIndex.putIfAbsent(key, () {
      _paints.add(json);
      return _paints.length - 1;
    });
  }

  void drawRect(Rect rect, Paint paint) => _commands.add([
    'rect',
    rect.left,
    rect.top,
    rect.width,
    rect.height,
    _paint(paint),
  ]);

  /// A rounded rectangle. The protocol rounds every corner alike, so the
  /// top-left radius speaks for all four.
  void drawRRect(RRect rrect, Paint paint) => _commands.add([
    'rrect',
    rrect.left,
    rrect.top,
    rrect.width,
    rrect.height,
    rrect.tlRadiusX,
    _paint(paint),
  ]);

  void drawCircle(Offset c, double radius, Paint paint) =>
      _commands.add(['circle', c.dx, c.dy, radius, _paint(paint)]);

  void drawOval(Rect rect, Paint paint) => _commands.add([
    'oval',
    rect.left,
    rect.top,
    rect.width,
    rect.height,
    _paint(paint),
  ]);

  /// A line is always stroked, as in Flutter, whatever the paint's style.
  void drawLine(Offset p1, Offset p2, Paint paint) => _commands.add([
    'line',
    p1.dx,
    p1.dy,
    p2.dx,
    p2.dy,
    _paint(paint, stroke: true),
  ]);

  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => _commands.add([
    'arc',
    rect.left,
    rect.top,
    rect.width,
    rect.height,
    startAngle,
    sweepAngle,
    useCenter,
    _paint(paint),
  ]);

  /// The path's segments are copied, so a painter can go on to reuse or
  /// reset the path without changing what was already drawn.
  void drawPath(Path path, Paint paint) => _commands.add([
    'path',
    [for (final segment in path._segments) List<Object?>.of(segment)],
    _paint(paint),
  ]);

  /// Dots or segments. There is no points command, so [PointMode.points]
  /// draws each as a filled circle as wide as the stroke, and the other two
  /// modes draw lines.
  void drawPoints(PointMode pointMode, List<Offset> points, Paint paint) {
    switch (pointMode) {
      case PointMode.points:
        final radius = (paint.strokeWidth <= 0 ? 1.0 : paint.strokeWidth) / 2;
        final fill = _paint(paint, stroke: false);
        for (final point in points) {
          _commands.add(['circle', point.dx, point.dy, radius, fill]);
        }
      case PointMode.lines:
        for (var i = 0; i + 1 < points.length; i += 2) {
          drawLine(points[i], points[i + 1], paint);
        }
      case PointMode.polygon:
        for (var i = 0; i + 1 < points.length; i++) {
          drawLine(points[i], points[i + 1], paint);
        }
    }
  }

  /// Fills the surface with [color]. [blendMode] is not carried.
  void drawColor(Color color, [BlendMode blendMode = BlendMode.srcOver]) =>
      drawPaint(Paint()..color = color);

  /// Fills the surface with [paint]: a rectangle the size the canvas was
  /// given, since the command list has no "everything".
  void drawPaint(Paint paint) => _commands.add([
    'rect',
    0.0,
    0.0,
    _size.width,
    _size.height,
    _paint(paint, stroke: false),
  ]);

  void save() {
    _saves++;
    _commands.add(['save']);
  }

  /// A plain [save]: a layer's paint (its opacity, its blend) is not carried.
  void saveLayer(Rect? bounds, Paint paint) => save();

  /// As in Flutter, a restore with nothing saved does nothing.
  void restore() {
    if (_saves <= 1) return;
    _saves--;
    _commands.add(['restore']);
  }

  int getSaveCount() => _saves;

  void restoreToCount(int count) {
    while (_saves > count && _saves > 1) {
      restore();
    }
  }

  void translate(double dx, double dy) =>
      _commands.add(['translate', dx, dy]);

  void rotate(double radians) => _commands.add(['rotate', radians]);

  void scale(double sx, [double? sy]) => _commands.add(['scale', sx, sy ?? sx]);

  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _commands.add([
    'clipRect',
    rect.left,
    rect.top,
    rect.width,
    rect.height,
  ]);

  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => _commands.add([
    'clipRRect',
    rrect.left,
    rrect.top,
    rrect.width,
    rrect.height,
    rrect.tlRadiusX,
  ]);

  /// Accepted and ignored: the command list clips to rectangles only, so what
  /// follows is drawn unclipped.
  void clipPath(Path path, {bool doAntiAlias = true}) {}
}

/// Draws a picture for a [CustomPaint] - Flutter's `CustomPainter`.
///
/// ```dart
/// class Dial extends CustomPainter {
///   Dial(this.value);
///   final double value;
///
///   @override
///   void paint(Canvas canvas, Size size) {
///     final paint = Paint()
///       ..color = Colors.blue
///       ..style = PaintingStyle.stroke
///       ..strokeWidth = 6;
///     canvas.drawArc(Offset.zero & size, -1.57, 6.28 * value, false, paint);
///   }
///
///   @override
///   bool shouldRepaint(Dial old) => old.value != value;
/// }
/// ```
///
/// [paint] runs on every build, and what it recorded is the picture. That is
/// the one real difference from Flutter: [shouldRepaint] is accepted and not
/// consulted, because the tree is rebuilt from the root anyway and a renderer
/// only repaints a surface whose commands changed. [repaint] is honoured -
/// the picture is drawn again whenever that listenable says so.
abstract class CustomPainter extends Listenable {
  const CustomPainter({Listenable? repaint}) : _repaint = repaint;

  final Listenable? _repaint;

  @override
  void addListener(VoidCallback listener) => _repaint?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _repaint?.removeListener(listener);

  /// Draw the picture on [canvas], whose surface is [size].
  void paint(Canvas canvas, Size size);

  /// Accepted for compatibility; see the class doc.
  bool shouldRepaint(covariant CustomPainter oldDelegate);

  /// Null, as Flutter's default is: touches go to whatever is around the
  /// canvas. Wrap the [CustomPaint] in a `GestureDetector` to receive them.
  bool? hitTest(Offset position) => null;
}

/// A surface drawn by a [CustomPainter] - Flutter's `CustomPaint`.
///
/// How big it is follows Flutter's rule as far as the protocol goes:
///
/// * with a [child], the surface is the child's size and [size] is not used;
/// * with a `SizedBox.expand()` child - the idiom for "fill what I am in" -
///   it fills its parent, and the empty box itself is not drawn;
/// * otherwise it is [size], an infinite dimension of which fills that axis.
///
/// The painter needs to be told the size it is drawing on, and Dart does not
/// lay anything out. So the renderer reports the size the surface was given
/// and the picture is painted again against it. Until that first report the
/// painter is handed [size] if there is one and the viewport otherwise -
/// one frame drawn to an estimate, then the real thing.
///
/// [foregroundPainter] is recorded after [painter] into the same surface. In
/// Flutter it is drawn over the child; here there is one command list, so on
/// a renderer that lays the child above the canvas the foreground is under
/// it. [isComplex] and [willChange] are raster-cache hints with nothing to
/// hint at.
class CustomPaint extends StatefulWidget {
  const CustomPaint({
    super.key,
    this.painter,
    this.foregroundPainter,
    this.size = Size.zero,
    this.isComplex = false,
    this.willChange = false,
    this.child,
  });

  final CustomPainter? painter;
  final CustomPainter? foregroundPainter;
  final Size size;
  final bool isComplex;
  final bool willChange;
  final Widget? child;

  @override
  State<CustomPaint> createState() => _CustomPaintState();
}

class _CustomPaintState extends State<CustomPaint> {
  /// The size the renderer last said the surface has.
  Size? _reported;

  /// The event the surface's size arrives on, as of the last build.
  String? _sizeEvent;

  void _onSize(double width, double height) {
    // A surface that is not on screen can report nothing at all; painting
    // against zero would throw the real picture away for an empty one.
    if (!(width > 0 && height > 0)) return;
    final event = _sizeEvent;
    if (event != null) _owner?._sizeReports[event] = Size(width, height);
    final reported = _reported;
    if (reported != null &&
        reported.width == width &&
        reported.height == height) {
      return;
    }
    if (!mounted) return;
    setState(() => _reported = Size(width, height));
  }

  WidgetNode _node(_Owner owner) {
    final widget = this.widget;
    final child = widget.child;
    final size = widget.size;

    final fillsParent =
        child is SizedBox &&
        child.child == null &&
        child.width == double.infinity &&
        child.height == double.infinity;
    final wrapsChild = child != null && !fillsParent;

    double? fixed(double value) =>
        wrapsChild || fillsParent || !value.isFinite || value <= 0
        ? null
        : value;
    final width = fixed(size.width);
    final height = fixed(size.height);
    final expandWidth =
        fillsParent || (!wrapsChild && size.width == double.infinity);
    final expandHeight =
        fillsParent || (!wrapsChild && size.height == double.infinity);
    final expand = expandWidth && expandHeight
        ? 'both'
        : expandWidth
        ? 'width'
        : expandHeight
        ? 'height'
        : null;

    // What to paint against before the renderer has spoken: the size asked
    // for where it is a real one, the viewport where it is not.
    final viewport = owner._media.size;
    final surface =
        _reported ??
        Size(width ?? viewport.width, height ?? viewport.height);

    final canvas = _paintOn(owner, surface);

    final node = UIBuilder.canvas(
      commands: canvas._commands,
      paints: canvas._paints,
      width: width,
      height: height,
      expand: expand,
      onSize: _onSize,
      child: wrapsChild
          ? owner.inSlot('child', () => child._render(owner))
          : null,
      id: _idOf(widget.key),
    );
    final event = node.props['sizeEventId'];
    _sizeEvent = event is String ? event : null;

    // A state made anew for a surface the renderer has measured already - a
    // chart that gave way to a spinner and came back - is not told its size
    // again, because the size has not changed. What was said last stands.
    final known = _reported == null ? owner._sizeReports[_sizeEvent] : null;
    if (known == null) return node;
    _reported = known;
    if (known == surface) return node;
    final repainted = _paintOn(owner, known);
    return WidgetNode(
      type: node.type,
      props: {
        ...node.props,
        'paints': repainted._paints,
        'commands': repainted._commands,
      },
      children: node.children,
    );
  }

  /// What the painters draw on a surface of [surface].
  Canvas _paintOn(_Owner owner, Size surface) {
    final canvas = Canvas._(surface);
    for (final painter in [widget.painter, widget.foregroundPainter]) {
      if (painter == null) continue;
      final repaint = painter._repaint;
      if (repaint != null) owner._watch(repaint);
      // Each painter starts from a clean transform, whatever the one before
      // left unrestored.
      final saves = canvas.getSaveCount();
      painter.paint(canvas, surface);
      canvas.restoreToCount(saves);
    }
    return canvas;
  }

  @override
  Widget build(BuildContext context) => _NodeWidget(_node);
}

/// Measures and draws text on a [Canvas] - Flutter's `TextPainter`.
///
/// **The measurements are estimates.** Flutter asks its text engine how wide
/// a string is; pure Dart has no font to ask. So a character is taken to be
/// 0.55 × its font size wide - twice that for emoji and CJK (code points from
/// U+2E80 up) - and a line 1.2 × the font size tall (or the style's own
/// `height` multiple). Lines break at `\n` and, past `maxWidth`, at the last
/// space that fits. The default font size is 14.
///
/// To keep the estimate from showing, [paint] sends the box it measured along
/// with the text: the command carries `maxWidth` - the estimated width - and
/// the [textAlign]. A painter that centres text by `(size.width - tp.width) /
/// 2` with `textAlign: TextAlign.center` therefore gets text centred on the
/// same point with the real glyphs, however far off the estimate was.
///
/// Child spans are measured with their own font sizes and then drawn as one
/// run in the root span's style: the `text` command has one style. [maxLines]
/// limits the measured height; [ellipsis] and [textScaler] are accepted and
/// ignored.
class TextPainter {
  TextPainter({
    this.text,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.maxLines,
    this.ellipsis,
    this.textScaler,
  });

  TextSpan? text;
  TextAlign textAlign;
  TextDirection? textDirection;
  int? maxLines;

  /// Accepted and ignored.
  String? ellipsis;

  /// Accepted and ignored.
  Object? textScaler;

  static const double _defaultFontSize = 14;

  double _width = 0;
  double _height = 0;
  bool _laidOut = false;

  /// The estimated width - see the class doc.
  double get width => _width;

  /// The estimated height - see the class doc.
  double get height => _height;

  Size get size => Size(_width, _height);

  /// Always false: nothing here knows where the real glyphs end.
  bool get didExceedMaxLines => false;

  double get minIntrinsicWidth => _width;
  double get maxIntrinsicWidth => _width;
  double get preferredLineHeight =>
      (text?.style?.fontSize ?? _defaultFontSize) *
      (text?.style?.height ?? 1.2);

  static double _advance(int codePoint, double fontSize) =>
      (codePoint >= 0x2E80 ? 1.1 : 0.55) * fontSize;

  /// The span tree as characters, each with the font size and line-height
  /// multiple it inherits.
  static void _flatten(
    InlineSpan span,
    double fontSize,
    double lineHeight,
    List<(int, double, double)> out,
  ) {
    if (span is! TextSpan) return;
    final size = span.style?.fontSize ?? fontSize;
    final height = span.style?.height ?? lineHeight;
    final own = span.text;
    if (own != null) {
      for (final rune in own.runes) {
        out.add((rune, size, height));
      }
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      _flatten(child, size, height, out);
    }
  }

  /// Works out [width] and [height] for text given between [minWidth] and
  /// [maxWidth] of room.
  void layout({double minWidth = 0, double maxWidth = double.infinity}) {
    _laidOut = true;
    final root = text;
    final rootSize = root?.style?.fontSize ?? _defaultFontSize;
    final rootHeight = root?.style?.height ?? 1.2;
    final characters = <(int, double, double)>[];
    if (root != null) _flatten(root, rootSize, rootHeight, characters);

    // One pass, breaking as it goes. `lineWidths` are as wrapped;
    // `longestUnwrapped` is what the text would take with all the room in
    // the world, which is what the painter's own width follows.
    final lineHeights = <double>[];
    var longest = 0.0;
    var longestUnwrapped = 0.0;
    var unwrapped = 0.0;
    var lineWidth = 0.0;
    var lineHeight = rootSize * rootHeight;
    var hasInk = false;
    // The width and height of the line up to and including its last space,
    // which is where a line that runs out of room is cut.
    double? widthAtSpace;
    var afterSpace = 0.0;

    void endLine() {
      lineHeights.add(lineHeight);
      longest = math.max(longest, lineWidth);
      lineWidth = 0;
      lineHeight = rootSize * rootHeight;
      hasInk = false;
      widthAtSpace = null;
      afterSpace = 0;
    }

    for (final (rune, size, height) in characters) {
      if (rune == 0x0A) {
        longestUnwrapped = math.max(longestUnwrapped, unwrapped);
        unwrapped = 0;
        endLine();
        continue;
      }
      final advance = _advance(rune, size);
      unwrapped += advance;
      if (hasInk && lineWidth + advance > maxWidth) {
        final cut = widthAtSpace;
        if (cut != null) {
          // Break at the space: what followed it starts the next line.
          final carried = afterSpace;
          lineWidth = cut;
          endLine();
          lineWidth = carried;
          hasInk = carried > 0;
        } else {
          endLine();
        }
      }
      lineWidth += advance;
      lineHeight = hasInk
          ? math.max(lineHeight, size * height)
          : size * height;
      hasInk = true;
      if (rune == 0x20) {
        widthAtSpace = lineWidth;
        afterSpace = 0;
      } else if (widthAtSpace != null) {
        afterSpace += advance;
      }
    }
    longestUnwrapped = math.max(longestUnwrapped, unwrapped);
    endLine();

    final limit = maxLines;
    final lines = limit != null && limit > 0 && lineHeights.length > limit
        ? lineHeights.sublist(0, limit)
        : lineHeights;
    _height = lines.fold(0.0, (sum, h) => sum + h);
    // Flutter's rule: as wide as the text wants to be, within what it was
    // offered.
    final upper = math.max(minWidth, maxWidth);
    _width = longestUnwrapped.clamp(minWidth, upper).toDouble();
  }

  /// Draws the text with its top-left corner at [offset].
  ///
  /// Flutter insists on a [layout] first; a painter that forgot gets one with
  /// no width limit rather than an exception in the middle of a frame.
  void paint(Canvas canvas, Offset offset) {
    final root = text;
    if (root == null) return;
    if (!_laidOut) layout();
    final style = root.style;
    final rtl = textDirection == TextDirection.rtl;
    final align = switch (textAlign) {
      TextAlign.center => 'center',
      TextAlign.right => 'right',
      TextAlign.left || TextAlign.justify => 'left',
      TextAlign.start => rtl ? 'right' : 'left',
      TextAlign.end => rtl ? 'left' : 'right',
    };
    canvas._commands.add([
      'text',
      root.toPlainText(),
      offset.dx,
      offset.dy,
      <String, dynamic>{
        'size': style?.fontSize ?? _defaultFontSize,
        if (style?.color != null) 'color': style!.color!._hex,
        if (style?.fontWeight != null) 'weight': style!.fontWeight!.value,
        'align': align,
        'maxWidth': _width,
        if (style?.fontFamily != null) 'family': style!.fontFamily,
      },
    ]);
  }

  /// Nothing to release; here so a painter that disposes its TextPainter, as
  /// Flutter asks, compiles.
  void dispose() {}
}
