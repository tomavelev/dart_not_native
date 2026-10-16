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

/// How a blur treats the shape it blurs: [normal] blurs it inside and out,
/// [solid] keeps it sharp inside the blur, [outer] leaves only the blur
/// outside it and [inner] only the blur within it. A stroked shape is
/// blurred [normal] or [solid]; asked for either of the other two, it is
/// blurred [normal].
enum BlurStyle { normal, solid, outer, inner }

/// A blur for a [Paint] - a glow, a soft shadow.
///
/// [sigma] is the blur's standard deviation in logical pixels, as in
/// Flutter; the edge spreads about twice that far.
class MaskFilter {
  const MaskFilter.blur(this.style, double sigma) : _sigma = sigma;
  final BlurStyle style;
  final double _sigma;

  @override
  bool operator ==(Object other) =>
      other is MaskFilter && other.style == style && other._sigma == _sigma;
  @override
  int get hashCode => Object.hash(style, _sigma);
}

/// How a shape is drawn: its colour, and whether it is filled or stroked.
///
/// What travels is [color], [style], [strokeWidth], [strokeCap],
/// [strokeJoin], a [shader] that is a gradient
/// (`LinearGradient(...).createShader(rect)`, a `RadialGradient`'s or a
/// `SweepGradient`'s, or one made by [Gradient.linear] and its kin), a
/// [maskFilter] that is a blur, in any [BlurStyle], and a [blendMode].
/// [colorFilter] and [isAntiAlias] can be set, so a painter written for
/// Flutter compiles, and are not carried.
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

  /// A gradient to draw with in place of [color]: what
  /// [Gradient.createShader] returns. Anything else is ignored.
  Object? shader;

  /// A blur over what this paint draws: `MaskFilter.blur(BlurStyle.normal,
  /// sigma)`. Anything else is ignored.
  Object? maskFilter;

  /// Ignored - see the class doc.
  Object? colorFilter;

  /// How what this paint draws is laid over what is there already.
  BlendMode blendMode = BlendMode.srcOver;

  /// Ignored: a mitred corner is each platform's default limit.
  double strokeMiterLimit = 4;

  /// This paint without its blur.
  Paint get _sharp => Paint()
    ..color = color
    ..style = style
    ..strokeWidth = strokeWidth
    ..strokeCap = strokeCap
    ..strokeJoin = strokeJoin
    ..shader = shader
    ..blendMode = blendMode;

  /// The paint as the protocol spells it, defaults left out so two paints
  /// that draw the same are the same entry. [stroke] forces an outline, for a
  /// line - which has no inside to fill, whatever [style] says.
  Map<String, dynamic> _json({bool? stroke}) {
    final stroked = stroke ?? style == PaintingStyle.stroke;
    final shader = this.shader;
    final blur = maskFilter;
    return {
      'color': color._hex,
      if (shader is Shader) 'gradient': shader._paintJson,
      if (blur is MaskFilter && blur._sigma > 0) 'blur': blur._sigma,
      if (stroked) 'style': 'stroke',
      if (stroked) 'strokeWidth': strokeWidth <= 0 ? 1.0 : strokeWidth,
      if (stroked && strokeCap != StrokeCap.butt) 'cap': strokeCap.name,
      if (stroked && strokeJoin != StrokeJoin.miter) 'join': strokeJoin.name,
      if (blendMode != BlendMode.srcOver) 'blend': blendMode.name,
    };
  }
}

/// An outline built up from lines, curves and shapes, for [Canvas.drawPath].
///
/// Recorded as the protocol's path segments. The segment list has no rounded
/// rectangle and no arc given by its end point, so [addRRect] and
/// [arcToPoint] are written as the curves that draw them.
class Path {
  final List<List<Object?>> _segments = [];

  /// Every point the path was told about, for [getBounds]. Control points are
  /// included, so the bounds of a curve are a little generous.
  final List<double> _xs = [];
  final List<double> _ys = [];

  double _x = 0;
  double _y = 0;

  /// Which parts of the path are inside: by default every part the outline
  /// goes round, and with [PathFillType.evenOdd] - a ring, a frame - the
  /// parts it goes round an odd number of times.
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

  /// An arc of an ellipse with [radius], turned by [rotation] degrees, from
  /// where the path is to [arcEnd] - the long way round when [largeArc].
  ///
  /// Drawn as cubic curves, a quarter turn or less each. With no radius it is
  /// a straight line, and radii too small to reach [arcEnd] are grown until
  /// they do - both as an SVG arc, which this is.
  void arcToPoint(
    Offset arcEnd, {
    Radius radius = Radius.zero,
    double rotation = 0,
    bool largeArc = false,
    bool clockwise = true,
  }) {
    final x0 = _x, y0 = _y;
    final x1 = arcEnd.dx, y1 = arcEnd.dy;
    var rx = radius.x.abs(), ry = radius.y.abs();
    if (rx == 0 || ry == 0 || (x0 == x1 && y0 == y1)) {
      lineTo(x1, y1);
      return;
    }
    final phi = rotation * math.pi / 180;
    final cosPhi = math.cos(phi), sinPhi = math.sin(phi);
    // The end points seen from half way between them, with the ellipse's
    // axes as the axes.
    final hx = (x0 - x1) / 2, hy = (y0 - y1) / 2;
    final px = cosPhi * hx + sinPhi * hy;
    final py = -sinPhi * hx + cosPhi * hy;
    final reach = px * px / (rx * rx) + py * py / (ry * ry);
    if (reach > 1) {
      final grow = math.sqrt(reach);
      rx *= grow;
      ry *= grow;
    }
    final top = rx * rx * ry * ry - rx * rx * py * py - ry * ry * px * px;
    final bottom = rx * rx * py * py + ry * ry * px * px;
    var k = bottom == 0 ? 0.0 : math.sqrt(math.max(0, top / bottom));
    if (largeArc == clockwise) k = -k;
    final cxp = k * rx * py / ry;
    final cyp = -k * ry * px / rx;
    final cx = cosPhi * cxp - sinPhi * cyp + (x0 + x1) / 2;
    final cy = sinPhi * cxp + cosPhi * cyp + (y0 + y1) / 2;
    final start = math.atan2((py - cyp) / ry, (px - cxp) / rx);
    var sweep = math.atan2((-py - cyp) / ry, (-px - cxp) / rx) - start;
    if (clockwise && sweep < 0) sweep += 2 * math.pi;
    if (!clockwise && sweep > 0) sweep -= 2 * math.pi;

    final pieces = math.max(1, (sweep.abs() / (math.pi / 2)).ceil());
    final step = sweep / pieces;
    // How far a control point sits along the tangent, for a piece this wide.
    final handle = 4 / 3 * math.tan(step / 4);
    (double, double) at(double angle, double tangent) {
      final ex = rx * (math.cos(angle) - tangent * math.sin(angle));
      final ey = ry * (math.sin(angle) + tangent * math.cos(angle));
      return (cx + cosPhi * ex - sinPhi * ey, cy + sinPhi * ex + cosPhi * ey);
    }

    for (var i = 0; i < pieces; i++) {
      final from = start + step * i;
      final to = from + step;
      final (c1x, c1y) = at(from, handle);
      final (c2x, c2y) = at(to, -handle);
      // The last piece ends on the point asked for, not a rounding of it.
      final (ex, ey) = i == pieces - 1 ? (x1, y1) : at(to, 0);
      cubicTo(c1x, c1y, c2x, c2y, ex, ey);
    }
  }

  /// [arcToPoint], with the end given from where the path is.
  void relativeArcToPoint(
    Offset arcEndDelta, {
    Radius radius = Radius.zero,
    double rotation = 0,
    bool largeArc = false,
    bool clockwise = true,
  }) => arcToPoint(
    Offset(_x + arcEndDelta.dx, _y + arcEndDelta.dy),
    radius: radius,
    rotation: rotation,
    largeArc: largeArc,
    clockwise: clockwise,
  );

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

  /// Adds [rrect] with its corners, each a quarter of its own ellipse. Radii
  /// that would overlap along a side are shrunk together until they fit.
  void addRRect(RRect rrect) {
    final l = rrect.left, t = rrect.top;
    final r = l + rrect.width, b = t + rrect.height;
    var fit = 1.0;
    void within(double first, double second, double room) {
      final wanted = first + second;
      if (wanted > room && wanted > 0) fit = math.min(fit, room / wanted);
    }

    within(rrect.tlRadiusX, rrect.trRadiusX, rrect.width);
    within(rrect.blRadiusX, rrect.brRadiusX, rrect.width);
    within(rrect.tlRadiusY, rrect.blRadiusY, rrect.height);
    within(rrect.trRadiusY, rrect.brRadiusY, rrect.height);
    final tlx = rrect.tlRadiusX * fit, tly = rrect.tlRadiusY * fit;
    final trx = rrect.trRadiusX * fit, try_ = rrect.trRadiusY * fit;
    final brx = rrect.brRadiusX * fit, bry = rrect.brRadiusY * fit;
    final blx = rrect.blRadiusX * fit, bly = rrect.blRadiusY * fit;
    // How much of a radius a control point keeps for a quarter turn.
    const c = 1 - 0.5522847498;
    moveTo(l + tlx, t);
    lineTo(r - trx, t);
    cubicTo(r - trx * c, t, r, t + try_ * c, r, t + try_);
    lineTo(r, b - bry);
    cubicTo(r, b - bry * c, r - brx * c, b, r - brx, b);
    lineTo(l + blx, b);
    cubicTo(l + blx * c, b, l, b - bly * c, l, b - bly);
    lineTo(l, t + tly);
    cubicTo(l, t + tly * c, l + tlx * c, t, l + tlx, t);
    close();
  }

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
    final gradient = json['gradient'];
    if (gradient is Map<String, dynamic> && gradient['tile'] != null) {
      // Far enough to cover the canvas from anywhere on it, at any turn.
      final reach = 2 * (_size.width.abs() + _size.height.abs()) + 1;
      json['gradient'] = _tiledGradient(gradient, reach);
    }
    final key =
        '${json['color']}|${json['style']}|${json['strokeWidth']}|'
        '${json['cap']}|${json['join']}|${json['gradient']}|${json['blur']}|'
        '${json['blend']}';
    return _paintIndex.putIfAbsent(key, () {
      _paints.add(json);
      return _paints.length - 1;
    });
  }

  /// Adds the command [build] makes for [paint]'s index - drawn in the
  /// paint's [BlurStyle]: [solid] is the blur with the shape drawn sharp
  /// over it, and [inner] and [outer] are the blur clipped to [outline], or
  /// to everything but it.
  void _draw(
    Paint paint,
    List<Object?> Function(int paint) build, {
    Path Function()? outline,
    bool? stroke,
  }) {
    final blur = paint.maskFilter;
    final stroked = stroke ?? paint.style == PaintingStyle.stroke;
    if (blur is! MaskFilter ||
        blur._sigma <= 0 ||
        blur.style == BlurStyle.normal) {
      _commands.add(build(_paint(paint, stroke: stroke)));
      return;
    }
    if (blur.style == BlurStyle.solid) {
      _commands
        ..add(build(_paint(paint, stroke: stroke)))
        ..add(build(_paint(paint._sharp, stroke: stroke)));
      return;
    }
    if (stroked || outline == null) {
      _commands.add(build(_paint(paint, stroke: stroke)));
      return;
    }
    final shape = outline();
    final Path clip;
    if (blur.style == BlurStyle.inner) {
      clip = shape;
    } else {
      // Everything but the shape: a frame far wider than any blur, with the
      // shape cut out of it.
      clip = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTRB(-1e5, -1e5, 1e5, 1e5))
        ..addPath(shape, Offset.zero);
    }
    save();
    clipPath(clip);
    _commands.add(build(_paint(paint, stroke: stroke)));
    restore();
  }

  void drawRect(Rect rect, Paint paint) => _draw(
    paint,
    (index) => ['rect', rect.left, rect.top, rect.width, rect.height, index],
    outline: () => Path()..addRect(rect),
  );

  /// A rounded rectangle. The protocol rounds every corner alike, so the
  /// top-left radius speaks for all four.
  void drawRRect(RRect rrect, Paint paint) => _draw(
    paint,
    (index) => [
      'rrect',
      rrect.left,
      rrect.top,
      rrect.width,
      rrect.height,
      rrect.tlRadiusX,
      index,
    ],
    outline: () => Path()..addRRect(rrect),
  );

  void drawCircle(Offset c, double radius, Paint paint) => _draw(
    paint,
    (index) => ['circle', c.dx, c.dy, radius, index],
    outline: () =>
        Path()..addOval(Rect.fromCircle(center: c, radius: radius)),
  );

  void drawOval(Rect rect, Paint paint) => _draw(
    paint,
    (index) => ['oval', rect.left, rect.top, rect.width, rect.height, index],
    outline: () => Path()..addOval(rect),
  );

  /// A line is always stroked, as in Flutter, whatever the paint's style.
  void drawLine(Offset p1, Offset p2, Paint paint) => _draw(
    paint,
    (index) => ['line', p1.dx, p1.dy, p2.dx, p2.dy, index],
    stroke: true,
  );

  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => _draw(
    paint,
    (index) => [
      'arc',
      rect.left,
      rect.top,
      rect.width,
      rect.height,
      startAngle,
      sweepAngle,
      useCenter,
      index,
    ],
    outline: () {
      final path = Path();
      if (useCenter) path.moveTo(rect.center.dx, rect.center.dy);
      path.arcTo(rect, startAngle, sweepAngle, !useCenter);
      return path..close();
    },
  );

  /// The path's segments are copied, so a painter can go on to reuse or
  /// reset the path without changing what was already drawn.
  void drawPath(Path path, Paint paint) {
    final segments = [
      for (final segment in path._segments) List<Object?>.of(segment),
    ];
    final evenOdd = path.fillType == PathFillType.evenOdd;
    _draw(
      paint,
      (index) => ['path', segments, index, if (evenOdd) 'evenOdd'],
      outline: () => Path()
        ..fillType = path.fillType
        ..addPath(path, Offset.zero),
    );
  }

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

  /// Fills the surface with [color], laid over it in [blendMode].
  void drawColor(Color color, [BlendMode blendMode = BlendMode.srcOver]) =>
      drawPaint(
        Paint()
          ..color = color
          ..blendMode = blendMode,
      );

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

  /// A layer: what is drawn until the matching [restore] is drawn on its
  /// own and then laid over the canvas at [paint]'s opacity, in its
  /// [Paint.blendMode] - so shapes that overlap inside it are not darker
  /// where they do. [bounds] is accepted and not carried.
  void saveLayer(Rect? bounds, Paint paint) {
    _saves++;
    _commands.add([
      'saveLayer',
      paint.color.alpha / 255,
      if (paint.blendMode != BlendMode.srcOver) paint.blendMode.name,
    ]);
  }

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

  /// Keeps what follows inside [path], until the matching [restore].
  void clipPath(Path path, {bool doAntiAlias = true}) => _commands.add([
    'clipPath',
    [for (final segment in path._segments) List<Object?>.of(segment)],
    if (path.fillType == PathFillType.evenOdd) 'evenOdd',
  ]);
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

/// What a character is measured by: its font size, line-height multiple,
/// whether it is bold, and the spacing after it.
typedef _Measure = ({double size, double height, bool bold, double spacing});

/// Measures and draws text on a [Canvas] - Flutter's `TextPainter`.
///
/// **The measurements are Roboto's.** Flutter asks its text engine how wide a
/// string is; pure Dart has no engine to ask, so each character is given its
/// advance width in Roboto - the font Android and a Flutter app draw in -
/// regular, or bold from weight 600 up, plus the style's `letterSpacing`
/// (`glyph_widths.dart`, generated from the font files). That covers Latin,
/// Greek, Cyrillic and their punctuation; iOS's and a browser's own fonts
/// come out within a few per cent of it. Anything else is an estimate: 0.55
/// × the font size, and 1.1 × for emoji and CJK (code points from U+2E80
/// up). Kerning and ligatures are not counted. A line is 1.2 × the font size
/// tall (or the style's own `height` multiple). Lines break at `\n` and, past
/// `maxWidth`, at the last space that fits. The default font size is 14.
///
/// To keep the estimate from showing, [paint] sends the box it measured along
/// with the text: the command carries `maxWidth` - the estimated width - and
/// the [textAlign]. A painter that centres text by `(size.width - tp.width) /
/// 2` with `textAlign: TextAlign.center` therefore gets text centred on the
/// same point with the real glyphs, however far off the estimate was. The
/// text goes broken into the lines it was measured as (`wrap: false`), so a
/// platform font a little wider than Roboto - SF on iOS - stands out past
/// the box by a few points rather than wrapping onto a line nobody measured.
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

  /// The text as [layout] broke it into lines.
  List<String> _lines = const [];

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

  /// How wide [codePoint] is at [fontSize]: Roboto's own width where the
  /// table has it, the estimate where it does not.
  static double _advance(int codePoint, double fontSize, {bool bold = false}) {
    final known = _glyphWidth(codePoint, bold: bold);
    if (known != null) return known * fontSize / 1000;
    return (codePoint >= 0x2E80 ? 1.1 : 0.55) * fontSize;
  }

  /// Roboto's width for [rune] in thousandths of an em, or null where the
  /// table has none.
  static int? _glyphWidth(int rune, {required bool bold}) {
    for (final (start, regular, heavy) in glyphWidthRuns) {
      final index = rune - start;
      if (index < 0 || index >= regular.length) continue;
      final width = (bold ? heavy : regular)[index];
      return width == 0 ? null : width;
    }
    return null;
  }

  /// The span tree as characters, each with the font size, line-height
  /// multiple, weight and letter spacing it inherits.
  static void _flatten(
    InlineSpan span,
    _Measure inherited,
    List<(int, _Measure)> out,
  ) {
    if (span is! TextSpan) return;
    final style = span.style;
    final measure = (
      size: style?.fontSize ?? inherited.size,
      height: style?.height ?? inherited.height,
      bold: style?.fontWeight == null
          ? inherited.bold
          : style!.fontWeight!.value >= 600,
      spacing: style?.letterSpacing ?? inherited.spacing,
    );
    final own = span.text;
    if (own != null) {
      for (final rune in own.runes) {
        out.add((rune, measure));
      }
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      _flatten(child, measure, out);
    }
  }

  /// Works out [width] and [height] for text given between [minWidth] and
  /// [maxWidth] of room.
  void layout({double minWidth = 0, double maxWidth = double.infinity}) {
    _laidOut = true;
    final root = text;
    final rootSize = root?.style?.fontSize ?? _defaultFontSize;
    final rootHeight = root?.style?.height ?? 1.2;
    final characters = <(int, _Measure)>[];
    if (root != null) {
      _flatten(
        root,
        (size: rootSize, height: rootHeight, bold: false, spacing: 0),
        characters,
      );
    }

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
    // Where each line starts among the characters, and where the current
    // line's last space is: the words each line holds, for [paint].
    final starts = <int>[0];
    final ends = <int>[];
    int? spaceAt;

    void endLine() {
      lineHeights.add(lineHeight);
      longest = math.max(longest, lineWidth);
      lineWidth = 0;
      lineHeight = rootSize * rootHeight;
      hasInk = false;
      widthAtSpace = null;
      afterSpace = 0;
    }

    for (var i = 0; i < characters.length; i++) {
      final (rune, measure) = characters[i];
      final (:size, :height, :bold, :spacing) = measure;
      if (rune == 0x0A) {
        longestUnwrapped = math.max(longestUnwrapped, unwrapped);
        unwrapped = 0;
        endLine();
        ends.add(i);
        starts.add(i + 1);
        spaceAt = null;
        continue;
      }
      final advance = _advance(rune, size, bold: bold) + spacing;
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
          ends.add(spaceAt!);
          starts.add(spaceAt + 1);
        } else {
          endLine();
          ends.add(i);
          starts.add(i);
        }
        spaceAt = null;
      }
      lineWidth += advance;
      lineHeight = hasInk
          ? math.max(lineHeight, size * height)
          : size * height;
      hasInk = true;
      if (rune == 0x20) {
        widthAtSpace = lineWidth;
        afterSpace = 0;
        spaceAt = i;
      } else if (widthAtSpace != null) {
        afterSpace += advance;
      }
    }
    longestUnwrapped = math.max(longestUnwrapped, unwrapped);
    endLine();
    ends.add(characters.length);
    _lines = [
      for (var line = 0; line < starts.length; line++)
        String.fromCharCodes([
          for (var at = starts[line]; at < ends[line]; at++) characters[at].$1,
        ]),
    ];

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
    final limit = maxLines;
    final lines = limit != null && limit > 0 && _lines.length > limit
        ? _lines.sublist(0, limit)
        : _lines;
    canvas._commands.add([
      'text',
      // Broken where the measuring broke it, and not again: a renderer's
      // glyphs a little wider than the measure stand out past the box
      // rather than wrap onto a line nobody measured.
      lines.join('\n'),
      offset.dx,
      offset.dy,
      <String, dynamic>{
        'wrap': false,
        'size': style?.fontSize ?? _defaultFontSize,
        if (style?.color != null) 'color': style!.color!._hex,
        if (style?.fontWeight != null) 'weight': style!.fontWeight!.value,
        if (style?.letterSpacing != null && style!.letterSpacing != 0)
          'letterSpacing': style.letterSpacing,
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
