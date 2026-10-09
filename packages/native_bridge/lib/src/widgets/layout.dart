part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Layout.
// ---------------------------------------------------------------------------

List<WidgetNode> _renderAll(List<Widget> children, _Owner owner) => [
  for (var i = 0; i < children.length; i++)
    owner.inSlot(i, () => children[i]._render(owner)),
];

WidgetNode _renderChild(_Owner owner, Widget child, [Object slot = 'child']) =>
    owner.inSlot(slot, () => child._render(owner));

/// The names the protocol knows a main-axis alignment by.
String _mainAxis(MainAxisAlignment alignment) => alignment.name;

/// The names the protocol knows a cross-axis alignment by. A baseline needs
/// font metrics from two children at once, which no node carries; `start` is
/// what it looks like for text of one size, so that is what it becomes.
String _crossAxis(CrossAxisAlignment alignment) =>
    alignment == CrossAxisAlignment.baseline ? 'start' : alignment.name;

class Column extends Widget {
  const Column({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.verticalDirection = VerticalDirection.down,
    this.textBaseline,
    this.spacing = 0.0,
    this.children = const [],
  });
  final List<Widget> children;

  /// How the children are distributed down the column. Like Flutter's, it
  /// shows only where the column has height to spare.
  final MainAxisAlignment mainAxisAlignment;

  /// Whether the column takes all the height it is offered (`max`, Flutter's
  /// default) or only what its children need. Where the height on offer has
  /// no end - in a scroller, in another column - there is nothing to take and
  /// the column hugs its children either way, as it would in Flutter.
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;

  /// Accepted and not consulted: a column's children run the same way in
  /// either direction of text.
  final TextDirection? textDirection;

  /// `up` lays the children out from the bottom, which is the same children
  /// in the opposite order.
  final VerticalDirection verticalDirection;

  /// Accepted for [CrossAxisAlignment.baseline], which is drawn as `start`.
  final TextBaseline? textBaseline;

  /// A gap between each child and the next.
  final double spacing;

  @override
  WidgetNode _render(_Owner owner) {
    final bounded = !owner._unboundedHeight;
    final nodes = owner._withLayout(
      () => _renderAll(children, owner),
      unboundedHeight: true,
      flexAxis: Axis.vertical,
    );
    // Bottom to top turns the main axis round: the children run the other
    // way, and so do its start and its end - a column that stacks upwards
    // from `start` stands on the floor of its box, as in Flutter.
    final up = verticalDirection == VerticalDirection.up;
    final mainAlignment = !up
        ? mainAxisAlignment
        : switch (mainAxisAlignment) {
            MainAxisAlignment.start => MainAxisAlignment.end,
            MainAxisAlignment.end => MainAxisAlignment.start,
            _ => mainAxisAlignment,
          };
    return UIBuilder.column(
      crossAxisAlignment: _crossAxis(crossAxisAlignment),
      mainAxisAlignment: _mainAxis(mainAlignment),
      mainAxisSize: mainAxisSize == MainAxisSize.min
          ? 'min'
          // An alignment other than start already fills; saying so twice
          // would only be noise in the tree.
          : (bounded && mainAlignment == MainAxisAlignment.start
                ? 'max'
                : null),
      spacing: spacing,
      children: up ? nodes.reversed.toList() : nodes,
    );
  }
}

class Row extends Widget {
  const Row({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.verticalDirection = VerticalDirection.down,
    this.textBaseline,
    this.spacing = 0.0,
    this.children = const [],
  });
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;

  /// `min` makes the row as wide as its children rather than as wide as it is
  /// allowed.
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;

  /// The direction the children run in; the ambient [Directionality]'s when
  /// null. A renderer lays a row out the way the *screen* reads, so a row
  /// that runs the other way is the same children in the opposite order.
  final TextDirection? textDirection;

  /// Accepted and not consulted; it only matters to a row whose children are
  /// aligned to a baseline.
  final VerticalDirection verticalDirection;
  final TextBaseline? textBaseline;
  final double spacing;

  @override
  WidgetNode _render(_Owner owner) {
    final bounded = !owner._unboundedWidth;
    final nodes = owner._withLayout(
      () => _renderAll(children, owner),
      unboundedWidth: true,
      flexAxis: Axis.horizontal,
    );
    return UIBuilder.row(
      mainAxisAlignment: _mainAxis(mainAxisAlignment),
      // Centre is what every renderer does unasked, so it is left out.
      crossAxisAlignment: crossAxisAlignment == CrossAxisAlignment.center
          ? null
          : _crossAxis(crossAxisAlignment),
      // Said outright, as Flutter's default is: a row is as wide as it is
      // allowed, which is what gives `spaceBetween` something to share out
      // and puts a trailing child at the far edge. Where the width on offer
      // has no end - a row inside a row, a horizontal scroller - there is
      // nothing to fill, and Flutter's row is as wide as its children too.
      mainAxisSize: mainAxisSize == MainAxisSize.min
          ? 'min'
          : (bounded ? 'max' : null),
      spacing: spacing,
      children:
          (textDirection ?? owner._direction) != owner._screenDirection
          ? nodes.reversed.toList()
          : nodes,
    );
  }
}

/// A [Row] or a [Column], chosen by [direction] - for a layout that turns
/// with the width of the window.
class Flex extends StatelessWidget {
  const Flex({
    super.key,
    required this.direction,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing = 0.0,
    this.children = const [],
  });
  final Axis direction;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => direction == Axis.vertical
      ? Column(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: mainAxisSize,
          crossAxisAlignment: crossAxisAlignment,
          spacing: spacing,
          children: children,
        )
      : Row(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: mainAxisSize,
          crossAxisAlignment: crossAxisAlignment,
          spacing: spacing,
          children: children,
        );
}

/// Lays its [children] out in a horizontal run that wraps onto the next line
/// when it runs out of width. [spacing] separates children on a line,
/// [runSpacing] separates the lines.
class Wrap extends Widget {
  const Wrap({
    super.key,
    this.direction = Axis.horizontal,
    this.alignment = WrapAlignment.start,
    this.spacing = 0.0,
    this.runAlignment = WrapAlignment.start,
    this.runSpacing = 0.0,
    this.crossAxisAlignment = WrapCrossAlignment.start,
    this.children = const [],
  });

  /// Accepted for Flutter's signature. The node wraps horizontal runs only,
  /// so a vertical wrap is drawn as a horizontal one.
  final Axis direction;

  /// Where the children sit along each line.
  final WrapAlignment alignment;
  final double spacing;

  /// Accepted and not carried: the lines are stacked from the top.
  final WrapAlignment runAlignment;
  final double runSpacing;

  /// Where a child shorter than its line sits within it.
  final WrapCrossAlignment crossAxisAlignment;
  final List<Widget> children;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.wrap(
    spacing: spacing,
    runSpacing: runSpacing,
    // The node has the four a renderer can lay out; the two "space around"
    // forms are nearest to centring.
    alignment: switch (alignment) {
      WrapAlignment.start => 'start',
      WrapAlignment.end => 'end',
      WrapAlignment.center => 'center',
      WrapAlignment.spaceBetween => 'spaceBetween',
      WrapAlignment.spaceAround || WrapAlignment.spaceEvenly => 'center',
    },
    crossAxisAlignment: crossAxisAlignment.name,
    children: owner._withLayout(
      () => _renderAll(children, owner),
      unboundedWidth: true,
      unboundedHeight: true,
    ),
  );
}

class Center extends Widget {
  const Center({
    super.key,
    this.widthFactor,
    this.heightFactor,
    this.child,
  });

  /// Accepted and not carried: the node centres in the room it is given.
  final double? widthFactor;
  final double? heightFactor;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.center(
    child: _renderChild(owner, child ?? const SizedBox.shrink()),
  );
}

/// Places [child] inside the room it is given: Flutter's `Align`.
///
/// It fills that room along every axis that has an end - it has to, for there
/// to be somewhere to place the child - and hugs the child along one that does
/// not, as Flutter's does in a Column.
class Align extends Widget {
  const Align({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    this.child,
  });
  final AlignmentGeometry alignment;

  /// Accepted and not carried; a factor on an axis only stops the box from
  /// filling it.
  final double? widthFactor;
  final double? heightFactor;
  final Widget? child;

  @override
  WidgetNode _render(_Owner owner) {
    var expand = owner._expandBounded;
    if (widthFactor != null) {
      expand = expand == 'both' ? 'height' : (expand == 'width' ? null : expand);
    }
    if (heightFactor != null) {
      expand = expand == 'both' ? 'width' : (expand == 'height' ? null : expand);
    }
    return UIBuilder.box(
      alignment: alignment._resolved._xy,
      expand: expand,
      id: _idOf(key),
      child: child == null ? null : _renderChild(owner, child!),
    );
  }
}

class Padding extends Widget {
  const Padding({super.key, required this.padding, this.child});
  final EdgeInsetsGeometry padding;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) {
    final insets = padding._resolved;
    return UIBuilder.padding(
      left: insets.left,
      top: insets.top,
      right: insets.right,
      bottom: insets.bottom,
      child: _renderChild(owner, child ?? const SizedBox.shrink()),
    );
  }
}

class Expanded extends Flexible {
  const Expanded({super.key, super.flex, required super.child})
    : super(fit: FlexFit.tight);
}

/// How a [Flexible] child uses its share of a Row or Column.
enum FlexFit {
  /// It is stretched to fill the share - an [Expanded].
  tight,

  /// It may be smaller than the share.
  loose,
}

/// Gives [child] a share of the room left over in a Row or Column, without
/// forcing it to fill that share unless [fit] is tight.
class Flexible extends Widget {
  const Flexible({
    super.key,
    this.flex = 1,
    this.fit = FlexFit.loose,
    required this.child,
  });
  final int flex;
  final FlexFit fit;
  final Widget child;
  @override
  WidgetNode _render(_Owner owner) {
    // Its share has an end, which is the whole point of it.
    final vertical = owner._flexAxis == Axis.vertical;
    final horizontal = owner._flexAxis == Axis.horizontal;
    return UIBuilder.expanded(
      flex: flex,
      fit: fit.name,
      child: owner._withLayout(
        () => _renderChild(owner, child),
        unboundedHeight: vertical ? false : null,
        unboundedWidth: horizontal ? false : null,
      ),
    );
  }
}

/// A box of a given size, around a child or around nothing.
///
/// `double.infinity` on an axis fills the room offered there, as in Flutter.
class SizedBox extends Widget {
  const SizedBox({super.key, this.width, this.height, this.child});

  /// As large as its parent allows.
  const SizedBox.expand({super.key, this.child})
    : width = double.infinity,
      height = double.infinity;

  /// As small as its parent allows.
  const SizedBox.shrink({super.key, this.child}) : width = 0, height = 0;

  const SizedBox.square({super.key, double? dimension, this.child})
    : width = dimension,
      height = dimension;

  SizedBox.fromSize({super.key, Size? size, this.child})
    : width = size?.width,
      height = size?.height;

  final double? width;
  final double? height;
  final Widget? child;

  @override
  WidgetNode _render(_Owner owner) {
    final child = this.child;
    final width = this.width;
    final height = this.height;
    final fillsWidth = width == double.infinity;
    final fillsHeight = height == double.infinity;
    // A spinner has a size of its own on the wire, so a box put around one to
    // make it small - Flutter's way of fitting a spinner in a button - has to
    // hand that size on.
    if (child is CircularProgressIndicator &&
        width != null &&
        height != null &&
        !fillsWidth &&
        !fillsHeight) {
      return UIBuilder.box(
        width: width,
        height: height,
        id: _idOf(key),
        child: child._spinner(owner, math.min(width, height)),
      );
    }
    // The plain spacer every renderer has always drawn.
    if (child == null && !fillsWidth && !fillsHeight) {
      return UIBuilder.sizedBox(width: width, height: height);
    }
    return UIBuilder.box(
      width: fillsWidth ? null : width,
      height: fillsHeight ? null : height,
      expand: _expandOf(
        fillsWidth ||
            (width == null &&
                !owner._unboundedWidth &&
                _takesOfferedWidth(child)),
        fillsHeight ||
            (height == null &&
                !owner._unboundedHeight &&
                _takesOfferedHeight(child)),
      ),
      id: _idOf(key),
      child: child == null
          ? null
          : owner._withLayout(
              () => _renderChild(owner, child),
              unboundedWidth: width == null ? null : false,
              unboundedHeight: height == null ? null : false,
            ),
    );
  }
}

/// Whether [child] takes all the width it is offered, which makes a box
/// around it that wide too.
///
/// A `Center` does, and a `Row` that was not asked to hug. Neither node can
/// say so itself - each is laid out in whatever it is given - so a box that
/// hugged gave it the child's own size: a panel of a stated height came out
/// as wide as its message, and a strip of weekday names as wide as the names.
bool _takesOfferedWidth(Widget? child) =>
    (child is Center && child.widthFactor == null) ||
    (child is Row && child.mainAxisSize == MainAxisSize.max);

/// The same along the height, which only a `Center` takes: a `Column` already
/// says whether it fills.
bool _takesOfferedHeight(Widget? child) =>
    child is Center && child.heightFactor == null;

String? _expandOf(bool width, bool height) =>
    width ? (height ? 'both' : 'width') : (height ? 'height' : null);

/// A flexible gap in a Row or Column - an [Expanded] with an empty child.
class Spacer extends Widget {
  const Spacer({super.key, this.flex = 1});
  final int flex;
  @override
  WidgetNode _render(_Owner owner) =>
      UIBuilder.expanded(flex: flex, child: UIBuilder.sizedBox());
}

/// A soft shadow standing in for Material's elevation, which is a number the
/// protocol's shadow has no word for.
Map<String, dynamic>? _elevationShadow(double? elevation, [Color? color]) {
  if (elevation == null || elevation <= 0) return null;
  return {
    'color': (color ?? const Color(0x33000000))._hex,
    'blur': elevation * 2.5,
    'dx': 0.0,
    'dy': elevation / 2,
  };
}

/// The one place Flutter's box vocabulary - a size, constraints, insets, a
/// decoration, a transform - becomes a `Box` node.
WidgetNode _box(
  _Owner owner, {
  Widget? child,
  WidgetNode? childNode,
  double? width,
  double? height,
  BoxConstraints? constraints,
  EdgeInsetsGeometry? padding,
  EdgeInsetsGeometry? margin,
  AlignmentGeometry? alignment,
  Color? color,
  Decoration? decoration,
  Decoration? foregroundDecoration,
  Matrix4? transform,
  bool clip = false,
  double? opacity,
  String? expand,
  bool fillWhenEmpty = false,
  int? animateMs,
  String? curve,
  void Function(double x, double y)? onTap,
  void Function(double x, double y)? onLongPress,
  bool ripple = false,
  String? semanticLabel,
  String? tooltip,
  String? id,
}) {
  final box = decoration is BoxDecoration ? decoration : null;
  final foreground = foregroundDecoration is BoxDecoration
      ? foregroundDecoration
      : null;

  // Size: an explicit dimension wins, then tight constraints; an infinite one
  // of either kind means "fill".
  var w = width;
  var h = height;
  double? minW, maxW, minH, maxH;
  if (constraints != null) {
    if (w == null && constraints.minWidth == constraints.maxWidth) {
      w = constraints.maxWidth;
    } else {
      if (constraints.minWidth > 0) minW = constraints.minWidth;
      if (constraints.maxWidth.isFinite) maxW = constraints.maxWidth;
    }
    if (h == null && constraints.minHeight == constraints.maxHeight) {
      h = constraints.maxHeight;
    } else {
      if (constraints.minHeight > 0) minH = constraints.minHeight;
      if (constraints.maxHeight.isFinite) maxH = constraints.maxHeight;
    }
    if (minW == double.infinity) {
      w = double.infinity;
      minW = null;
    }
    if (minH == double.infinity) {
      h = double.infinity;
      minH = null;
    }
  }
  var fillsWidth = w == double.infinity;
  var fillsHeight = h == double.infinity;
  if (fillsWidth) w = null;
  if (fillsHeight) h = null;
  // An aligned box, or an empty one, takes the room that has an end - which
  // is what Flutter's Container does with both.
  final hasChild = child != null || childNode != null;
  if (alignment != null || (fillWhenEmpty && !hasChild)) {
    if (w == null && !owner._unboundedWidth) fillsWidth = true;
    if (h == null && !owner._unboundedHeight) fillsHeight = true;
  } else {
    if (w == null && !owner._unboundedWidth && _takesOfferedWidth(child)) {
      fillsWidth = true;
    }
    if (h == null && !owner._unboundedHeight && _takesOfferedHeight(child)) {
      fillsHeight = true;
    }
  }

  final border = box?.border;
  final uniform = border is Border && border.isUniform ? border.top : null;
  final sides = border is Border && !border.isUniform ? border : null;
  final radius = box?.borderRadius?._resolved;
  final shadows = box?.boxShadow;

  var node = UIBuilder.box(
    width: w,
    height: h,
    minWidth: minW,
    maxWidth: maxW,
    minHeight: minH,
    maxHeight: maxH,
    expand: expand ?? _expandOf(fillsWidth, fillsHeight),
    padding: padding?._resolved._ltrb,
    margin: sides == null && foreground == null
        ? margin?._resolved._ltrb
        : null,
    alignment: alignment?._resolved._xy,
    color: (color ?? box?.color)?._hex,
    gradient: box?.gradient?._json,
    borderWidth: uniform != null && uniform.width > 0 ? uniform.width : null,
    borderColor: uniform != null && uniform.width > 0
        ? uniform.color._hex
        : null,
    borderRadius: radius?._uniform,
    borderRadii: radius != null && radius._uniform == null
        ? radius._radii
        : null,
    shape: box?.shape == BoxShape.circle ? 'circle' : null,
    shadow: shadows == null || shadows.isEmpty ? null : shadows.first._json,
    clip: clip,
    opacity: opacity,
    transform: transform?._transform,
    onTap: onTap,
    onLongPress: onLongPress,
    ripple: ripple,
    animateMs: animateMs,
    curve: curve,
    semanticLabel: semanticLabel,
    tooltip: tooltip,
    id: id,
    child:
        childNode ??
        (child == null
            ? null
            : owner._withLayout(
                () => _renderChild(owner, child),
                unboundedWidth: w != null || fillsWidth ? false : null,
                unboundedHeight: h != null || fillsHeight ? false : null,
              )),
  );
  if (sides == null && foreground == null) return node;

  // A border with sides of its own - a rule along the bottom, say - has no
  // word in the protocol, which outlines a box all the way round or not at
  // all. So each side that has a width is a thin box of that colour pinned
  // over that edge; the same layering draws a foreground decoration.
  final layers = <WidgetNode>[
    node,
    if (sides != null) ...[
      if (sides.top.width > 0 && sides.top.style != BorderStyle.none)
        UIBuilder.positioned(
          left: 0,
          top: 0,
          right: 0,
          height: sides.top.width,
          child: UIBuilder.box(color: sides.top.color._hex),
        ),
      if (sides.bottom.width > 0 && sides.bottom.style != BorderStyle.none)
        UIBuilder.positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: sides.bottom.width,
          child: UIBuilder.box(color: sides.bottom.color._hex),
        ),
      if (sides.left.width > 0 && sides.left.style != BorderStyle.none)
        UIBuilder.positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: sides.left.width,
          child: UIBuilder.box(color: sides.left.color._hex),
        ),
      if (sides.right.width > 0 && sides.right.style != BorderStyle.none)
        UIBuilder.positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: sides.right.width,
          child: UIBuilder.box(color: sides.right.color._hex),
        ),
    ],
    if (foreground != null)
      UIBuilder.positioned(
        fill: true,
        child: _box(owner, decoration: foreground, expand: 'both'),
      ),
  ];
  node = UIBuilder.stack(
    children: layers,
    fit: fillsWidth && fillsHeight ? 'expand' : 'loose',
  );
  final outside = margin?._resolved._ltrb;
  if (outside != null || fillsWidth || fillsHeight) {
    node = UIBuilder.box(
      margin: outside,
      expand: _expandOf(fillsWidth, fillsHeight),
      child: node,
    );
  }
  return node;
}

/// Flutter's `Container`: size, space, paint and a transform around one
/// child, as a single `Box` node.
///
/// What the node cannot say is said some other way or left out: a border
/// whose sides differ is drawn as thin boxes over the edges, only the first
/// of several [BoxShadow]s is drawn, and a [BoxShadow.spreadRadius] is not.
class Container extends Widget {
  Container({
    super.key,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    double? width,
    double? height,
    BoxConstraints? constraints,
    this.margin,
    this.transform,
    this.transformAlignment,
    this.child,
    this.clipBehavior = Clip.none,
  }) : assert(
         color == null || decoration == null,
         'Cannot provide both a color and a decoration; put the color in the '
         'decoration.',
       ),
       constraints = (width != null || height != null)
           ? (constraints?.tighten(width: width, height: height) ??
                 BoxConstraints.tightFor(width: width, height: height))
           : constraints;

  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Decoration? decoration;
  final Decoration? foregroundDecoration;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;

  /// The translation, rotation about z and uniform scale of the matrix are
  /// what travel; the box turns about its centre.
  final Matrix4? transform;

  /// Accepted and not consulted: see [transform].
  final AlignmentGeometry? transformAlignment;
  final Widget? child;
  final Clip clipBehavior;

  @override
  WidgetNode _render(_Owner owner) => _box(
    owner,
    child: child,
    constraints: constraints,
    padding: padding,
    margin: margin,
    alignment: alignment,
    color: color,
    decoration: decoration,
    foregroundDecoration: foregroundDecoration,
    transform: transform,
    clip: clipBehavior != Clip.none,
    fillWhenEmpty: true,
    id: _idOf(key),
  );
}

/// Paints a [decoration] behind (or, with [position], over) its child.
class DecoratedBox extends Widget {
  const DecoratedBox({
    super.key,
    required this.decoration,
    this.position = DecorationPosition.background,
    this.child,
  });
  final Decoration decoration;
  final DecorationPosition position;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => _box(
    owner,
    child: child,
    decoration: position == DecorationPosition.background ? decoration : null,
    foregroundDecoration: position == DecorationPosition.foreground
        ? decoration
        : null,
    id: _idOf(key),
  );
}

/// Whether a [DecoratedBox] paints behind its child or in front of it.
enum DecorationPosition { background, foreground }

/// Fills the space behind its child with one colour.
class ColoredBox extends Widget {
  const ColoredBox({super.key, required this.color, this.child});
  final Color color;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) =>
      _box(owner, child: child, color: color, id: _idOf(key));
}

/// Bounds its child's size.
class ConstrainedBox extends Widget {
  const ConstrainedBox({super.key, required this.constraints, this.child});
  final BoxConstraints constraints;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) =>
      _box(owner, child: child, constraints: constraints, id: _idOf(key));
}

/// Sizes its child to a width-over-height ratio, from whichever of the two
/// the parent decides.
class AspectRatio extends Widget {
  const AspectRatio({super.key, required this.aspectRatio, this.child});
  final double aspectRatio;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    aspectRatio: aspectRatio,
    // The width is the axis Flutter takes first; the height is derived.
    expand: !owner._unboundedWidth
        ? 'width'
        : (owner._unboundedHeight ? null : 'height'),
    id: _idOf(key),
    child: child == null
        ? null
        : owner._withLayout(
            () => _renderChild(owner, child!),
            unboundedWidth: false,
            unboundedHeight: false,
          ),
  );
}

/// Flutter scales a child to fit; the protocol has no scale-to-fit, so this
/// draws its child as it is. That is exactly right for the common
/// `BoxFit.scaleDown` on a child that already fits, and merely unscaled
/// otherwise.
class FittedBox extends Widget {
  const FittedBox({
    super.key,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.none,
    this.child,
  });
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final Clip clipBehavior;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) =>
      _renderChild(owner, child ?? const SizedBox.shrink());
}

/// Keeps its child clear of the status bar, the notch and the home indicator.
///
/// Inside a [Scaffold] it does nothing, because the platform's scaffold has
/// already inset its body; anywhere else it pads by the insets the renderer
/// reported.
class SafeArea extends Widget {
  const SafeArea({
    super.key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.minimum = EdgeInsets.zero,
    this.maintainBottomViewPadding = false,
    required this.child,
  });
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final EdgeInsets minimum;
  final bool maintainBottomViewPadding;
  final Widget child;

  @override
  WidgetNode _render(_Owner owner) {
    final node = _renderChild(owner, child);
    final insets = owner._scaffoldDepth > 0
        ? EdgeInsets.zero
        : _mediaOf(owner).padding;
    final l = math.max(left ? insets.left : 0.0, minimum.left);
    final t = math.max(top ? insets.top : 0.0, minimum.top);
    final r = math.max(right ? insets.right : 0.0, minimum.right);
    final b = math.max(bottom ? insets.bottom : 0.0, minimum.bottom);
    if (l == 0 && t == 0 && r == 0 && b == 0) return node;
    return UIBuilder.padding(left: l, top: t, right: r, bottom: b, child: node);
  }
}

/// Cuts its child to a rounded rectangle.
class ClipRRect extends Widget {
  const ClipRRect({
    super.key,
    this.borderRadius = BorderRadius.zero,
    this.clipBehavior = Clip.antiAlias,
    this.child,
  });
  final BorderRadiusGeometry borderRadius;
  final Clip clipBehavior;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => _box(
    owner,
    child: child,
    decoration: BoxDecoration(borderRadius: borderRadius),
    clip: clipBehavior != Clip.none,
    id: _idOf(key),
  );
}

/// Cuts its child to its bounds.
class ClipRect extends Widget {
  const ClipRect({super.key, this.clipBehavior = Clip.hardEdge, this.child});
  final Clip clipBehavior;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => _box(
    owner,
    child: child,
    clip: clipBehavior != Clip.none,
    id: _idOf(key),
  );
}

/// Cuts its child to an oval - a circle, when the child is square.
class ClipOval extends Widget {
  const ClipOval({super.key, this.clipBehavior = Clip.antiAlias, this.child});
  final Clip clipBehavior;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => _box(
    owner,
    child: child,
    decoration: const BoxDecoration(shape: BoxShape.circle),
    clip: clipBehavior != Clip.none,
    id: _idOf(key),
  );
}

/// Fades its child. For a fade that animates, see [AnimatedOpacity].
class Opacity extends Widget {
  const Opacity({super.key, required this.opacity, this.child});
  final double opacity;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) =>
      _box(owner, child: child, opacity: opacity, id: _idOf(key));
}

/// Turns, scales or moves its child without changing the room it takes.
///
/// The protocol's transform is a rotation, one scale and an offset, about the
/// centre: that covers the three named constructors exactly, and of a general
/// [Matrix4] it carries those same parts.
class Transform extends Widget {
  const Transform({
    super.key,
    required this.transform,
    this.origin,
    this.alignment,
    this.child,
  }) : _map = null;

  Transform.rotate({
    super.key,
    required double angle,
    this.origin,
    this.alignment = Alignment.center,
    this.child,
  }) : transform = null,
       _map = angle == 0 ? null : {'rotate': angle};

  Transform.scale({
    super.key,
    double? scale,
    double? scaleX,
    double? scaleY,
    this.origin,
    this.alignment = Alignment.center,
    this.child,
  }) : transform = null,
       // One number is all the node has; two that differ are averaged, which
       // keeps the size about right and gives up the stretch.
       _map = {
         'scale':
             scale ??
             ((scaleX ?? 1.0) + (scaleY ?? 1.0)) / 2,
       };

  Transform.translate({super.key, required Offset offset, this.child})
    : transform = null,
      origin = null,
      alignment = null,
      _map = {'dx': offset.dx, 'dy': offset.dy};

  final Matrix4? transform;

  /// Accepted and not consulted: the box turns about its centre.
  final Offset? origin;
  final AlignmentGeometry? alignment;
  final Widget? child;
  final Map<String, dynamic>? _map;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    transform: _map ?? transform?._transform,
    id: _idOf(key),
    child: child == null ? null : _renderChild(owner, child!),
  );
}

/// Turns its child by quarter turns.
class RotatedBox extends Widget {
  const RotatedBox({super.key, required this.quarterTurns, this.child});
  final int quarterTurns;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    transform: quarterTurns % 4 == 0
        ? null
        : {'rotate': quarterTurns * math.pi / 2},
    id: _idOf(key),
    child: child == null ? null : _renderChild(owner, child!),
  );
}

/// What kind of surface a [Material] is.
enum MaterialType { canvas, card, circle, button, transparency }

/// A piece of Material: a surface with a colour, a shape and a shadow.
class Material extends Widget {
  const Material({
    super.key,
    this.type = MaterialType.canvas,
    this.elevation = 0.0,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.textStyle,
    this.borderRadius,
    this.shape,
    this.clipBehavior = Clip.none,
    this.child,
  });
  final MaterialType type;
  final double elevation;

  /// The fill. Left null, a raised surface takes the theme's surface colour
  /// and a flat one is not painted at all, so it shows whatever is behind it.
  final Color? color;
  final Color? shadowColor;

  /// Accepted and not drawn: Material 3's tint is a blend no node carries.
  final Color? surfaceTintColor;
  final TextStyle? textStyle;
  final BorderRadiusGeometry? borderRadius;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final Widget? child;

  @override
  WidgetNode _render(_Owner owner) {
    final transparent = type == MaterialType.transparency;
    final fill = transparent
        ? null
        : color ??
              (elevation > 0 ? _themeOf(owner).colorScheme.surface : null);
    final shaped = _shapeDecoration(
      shape ?? (type == MaterialType.circle ? const CircleBorder() : null),
      color: fill,
      borderRadius: borderRadius,
      shadow: transparent ? null : _elevationShadow(elevation, shadowColor),
    );
    WidgetNode build() => _box(
      owner,
      child: child,
      decoration: shaped.decoration,
      clip: clipBehavior != Clip.none,
      id: _idOf(key),
    );
    final node = textStyle == null
        ? build()
        : _withTextStyle(owner, textStyle!, build);
    return shaped.shadow == null
        ? node
        : _withProps(node, {'shadow': shaped.shadow});
  }
}

/// A node with a few props added - for the one a helper does not take.
WidgetNode _withProps(WidgetNode node, Map<String, dynamic> extra) =>
    WidgetNode(
      type: node.type,
      props: {...node.props, ...extra},
      children: node.children,
    );

/// A [ShapeBorder] as the decoration a box can draw: the fill, the corners
/// and the outline. A stadium is a radius large enough to be one.
({BoxDecoration decoration, Map<String, dynamic>? shadow}) _shapeDecoration(
  ShapeBorder? shape, {
  Color? color,
  BorderRadiusGeometry? borderRadius,
  Map<String, dynamic>? shadow,
}) {
  final side = shape is OutlinedBorder ? shape.side : BorderSide.none;
  final border = side.width > 0 && side.style != BorderStyle.none
      ? Border.all(color: side.color, width: side.width)
      : null;
  final BorderRadiusGeometry? radius = switch (shape) {
    RoundedRectangleBorder() => shape.borderRadius,
    StadiumBorder() => BorderRadius.circular(999),
    _ => borderRadius,
  };
  return (
    decoration: BoxDecoration(
      color: color,
      border: border,
      borderRadius: shape is CircleBorder ? null : radius,
      shape: shape is CircleBorder ? BoxShape.circle : BoxShape.rectangle,
    ),
    shadow: shadow,
  );
}

/// Children drawn over one another, first at the back.
class Stack extends Widget {
  const Stack({
    super.key,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.fit = StackFit.loose,
    this.clipBehavior = Clip.hardEdge,
    this.children = const [],
  });

  /// Where the children that are not [Positioned] sit.
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;

  /// `expand` makes those children fill the stack. `passthrough` is drawn as
  /// `loose`.
  final StackFit fit;
  final Clip clipBehavior;
  final List<Widget> children;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.stack(
    alignment: alignment._resolved._xy,
    fit: fit == StackFit.expand ? 'expand' : 'loose',
    clip: clipBehavior != Clip.none,
    id: _idOf(key),
    children: owner._withLayout(() => _renderAll(children, owner)),
  );
}

/// Pins its child to the edges of a [Stack] it names.
class Positioned extends Widget {
  const Positioned({
    super.key,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    required this.child,
  });

  /// Pinned to all four edges, each [left], [top], [right] and [bottom] in
  /// from it - zero unless said otherwise.
  const Positioned.fill({
    super.key,
    this.left = 0.0,
    this.top = 0.0,
    this.right = 0.0,
    this.bottom = 0.0,
    required this.child,
  }) : width = null,
       height = null;

  /// [start] and [end] for [left] and [right], whichever [textDirection]
  /// makes them. Flutter's constructor of the same name, which is likewise
  /// told the direction rather than finding it:
  /// `Positioned.directional(textDirection: Directionality.of(context), …)`.
  factory Positioned.directional({
    Key? key,
    required TextDirection textDirection,
    double? start,
    double? top,
    double? end,
    double? bottom,
    double? width,
    double? height,
    required Widget child,
  }) {
    final rtl = textDirection == TextDirection.rtl;
    return Positioned(
      key: key,
      left: rtl ? end : start,
      top: top,
      right: rtl ? start : end,
      bottom: bottom,
      width: width,
      height: height,
      child: child,
    );
  }

  Positioned.fromRect({super.key, required Rect rect, required this.child})
    : left = rect.left,
      top = rect.top,
      width = rect.width,
      height = rect.height,
      right = null,
      bottom = null;

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;
  final Widget child;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.positioned(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: width,
    height: height,
    child: owner._withLayout(
      () => _renderChild(owner, child),
      unboundedWidth: false,
      unboundedHeight: false,
    ),
  );
}

/// Shows one of its [children] and keeps the rest alive.
///
/// The others are built and their nodes thrown away, so a tab that is not
/// showing keeps its `State` - a scroll position in a field, a half-typed
/// form - exactly as Flutter's does. One difference: Flutter's stack is as
/// large as its largest child, and this one is as large as the child showing.
class IndexedStack extends Widget {
  const IndexedStack({
    super.key,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.clipBehavior = Clip.hardEdge,
    this.sizing = StackFit.loose,
    this.index = 0,
    this.children = const [],
  });
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  final Clip clipBehavior;
  final StackFit sizing;

  /// Which child shows; null shows none of them.
  final int? index;
  final List<Widget> children;

  @override
  WidgetNode _render(_Owner owner) =>
      _renderOneOf(owner, children, index) ?? UIBuilder.sizedBox();
}

/// Renders the child at [index] and builds the others only for their state.
WidgetNode? _renderOneOf(_Owner owner, List<Widget> children, int? index) {
  WidgetNode? shown;
  for (var i = 0; i < children.length; i++) {
    if (i == index) {
      shown = owner.inSlot(i, () => children[i]._render(owner));
    } else {
      owner._offstage(i, children[i]);
    }
  }
  return shown;
}

/// Shows or hides its child.
///
/// Hidden, it draws [replacement] - nothing, by default - and the child is
/// gone along with its state, unless [maintainState] keeps it alive unseen.
class Visibility extends Widget {
  const Visibility({
    super.key,
    required this.child,
    this.replacement = const SizedBox.shrink(),
    this.visible = true,
    this.maintainState = false,
    this.maintainAnimation = false,
    this.maintainSize = false,
  });
  final Widget child;
  final Widget replacement;
  final bool visible;
  final bool maintainState;
  final bool maintainAnimation;

  /// Keeps the child's room while it is hidden, by drawing it see-through and
  /// deaf to touches.
  final bool maintainSize;

  @override
  WidgetNode _render(_Owner owner) {
    if (visible) return _renderChild(owner, child);
    if (maintainSize) {
      return UIBuilder.box(
        opacity: 0,
        ignorePointer: true,
        child: _renderChild(owner, child),
      );
    }
    if (maintainState) owner._offstage('child', child);
    return _renderChild(owner, replacement, 'replacement');
  }
}

/// Keeps its child built, with its state, but off the screen while
/// [offstage] is true.
class Offstage extends Widget {
  const Offstage({super.key, this.offstage = true, this.child});
  final bool offstage;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) {
    final child = this.child;
    if (child == null) return UIBuilder.sizedBox();
    if (!offstage) return _renderChild(owner, child);
    owner._offstage('child', child);
    return UIBuilder.sizedBox();
  }
}

/// Makes its child deaf to touches, which fall through to what is behind.
class IgnorePointer extends Widget {
  const IgnorePointer({super.key, this.ignoring = true, this.child});
  final bool ignoring;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) {
    final node = _renderChild(owner, child ?? const SizedBox.shrink());
    return ignoring ? UIBuilder.box(ignorePointer: true, child: node) : node;
  }
}

/// Makes its child deaf to touches. Flutter's also stops them reaching what
/// is behind; the protocol has the one flag, so here they fall through as
/// they do for [IgnorePointer].
class AbsorbPointer extends Widget {
  const AbsorbPointer({super.key, this.absorbing = true, this.child});
  final bool absorbing;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) {
    final node = _renderChild(owner, child ?? const SizedBox.shrink());
    return absorbing ? UIBuilder.box(ignorePointer: true, child: node) : node;
  }
}

/// Says what its child is to a screen reader.
///
/// [label], [value] and [hint] are what is said. [header], [button] and
/// [image] say what the child is, [liveRegion] has its changes announced,
/// and [excludeSemantics] leaves the label in place of everything inside.
/// `selected`, `enabled` and [onTap] are accepted and not carried: the
/// platform's own controls announce their state, and a tap belongs on a
/// `GestureDetector`, which a screen reader can activate.
class Semantics extends Widget {
  const Semantics({
    super.key,
    this.child,
    this.container = false,
    this.explicitChildNodes = false,
    this.excludeSemantics = false,
    this.label,
    this.value,
    this.hint,
    this.button,
    this.header,
    this.selected,
    this.enabled,
    this.image,
    this.liveRegion,
    this.onTap,
  });
  final Widget? child;
  final bool container;
  final bool explicitChildNodes;
  final bool excludeSemantics;
  final String? label;
  final String? value;
  final String? hint;
  final bool? button;
  final bool? header;
  final bool? selected;
  final bool? enabled;
  final bool? image;
  final bool? liveRegion;
  final VoidCallback? onTap;

  @override
  WidgetNode _render(_Owner owner) {
    final node = child == null ? null : _renderChild(owner, child!);
    final spoken = [label, value, hint].whereType<String>().join(', ');
    final role = header == true
        ? 'heading'
        : button == true
        ? 'button'
        : image == true
        ? 'image'
        : null;
    final id = _idOf(key);
    final live = liveRegion == true;
    if (spoken.isEmpty && !live && !excludeSemantics) {
      if (node == null) return UIBuilder.sizedBox();
      // Only a role, or a key: both are said of the child itself, so a
      // heading is the text a reader lands on rather than a box around it.
      if (role == null && id == null) return node;
      return _withProps(node, {
        'semanticRole': ?role,
        if (id != null && node.props['id'] == null) 'id': id,
      });
    }
    // A name for something that takes a tap belongs on the thing that takes
    // it: a box around the box would be a second stop for a screen reader,
    // with the name on the one that does nothing.
    if (node != null && _takesTouch(node) && !live && !excludeSemantics) {
      return _withProps(node, {
        if (spoken.isNotEmpty && node.props['semanticLabel'] == null)
          'semanticLabel': spoken,
        'semanticRole': ?role,
        if (id != null && node.props['id'] == null) 'id': id,
      });
    }
    return UIBuilder.box(
      semanticLabel: spoken.isEmpty ? null : spoken,
      semanticRole: role,
      liveRegion: live,
      excludeSemantics: excludeSemantics,
      id: id,
      child: node,
    );
  }
}

/// Whether [node] is a box a finger - or a screen reader - can activate.
bool _takesTouch(WidgetNode node) =>
    node.type == 'Box' &&
    (node.props['tapEventId'] != null || node.props['longPressEventId'] != null);

/// Flutter merges the semantics of a subtree into one announcement; each
/// platform control already is one here, so this is its child.
class MergeSemantics extends Widget {
  const MergeSemantics({super.key, this.child});
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) =>
      _renderChild(owner, child ?? const SizedBox.shrink());
}

/// Hides its child from screen readers - decoration that would only be noise.
class ExcludeSemantics extends Widget {
  const ExcludeSemantics({super.key, this.excluding = true, this.child});
  final bool excluding;
  final Widget? child;
  @override
  WidgetNode _render(_Owner owner) {
    final node = _renderChild(owner, child ?? const SizedBox.shrink());
    return excluding ? UIBuilder.box(excludeSemantics: true, child: node) : node;
  }
}

/// A widget that says how big it would like to be - what an [AppBar]'s
/// `bottom` has to be.
class PreferredSize extends Widget implements PreferredSizeWidget {
  const PreferredSize({
    super.key,
    required this.preferredSize,
    required this.child,
  });
  @override
  final Size preferredSize;
  final Widget child;
  @override
  WidgetNode _render(_Owner owner) => _renderChild(owner, child);
}

/// A hint shown on hover or long press, where the platform has such a thing.
class Tooltip extends Widget {
  const Tooltip({
    super.key,
    this.message,
    this.richMessage,
    this.child,
    this.waitDuration,
    this.showDuration,
    this.preferBelow,
  });
  final String? message;
  final InlineSpan? richMessage;
  final Widget? child;
  final Duration? waitDuration;
  final Duration? showDuration;
  final bool? preferBelow;
  @override
  WidgetNode _render(_Owner owner) {
    final text = message ?? richMessage?.toPlainText() ?? '';
    final node = child == null ? null : _renderChild(owner, child!);
    final id = _idOf(key);
    // Around something that takes a tap, the hint is that thing's own: it is
    // then its name when it has no text, on the node a reader activates.
    if (node != null && _takesTouch(node) && node.props['tooltip'] == null) {
      return _withProps(node, {
        'tooltip': text,
        if (id != null && node.props['id'] == null) 'id': id,
      });
    }
    return UIBuilder.box(tooltip: text, id: id, child: node);
  }
}

/// Marks a widget that flies between two pages, in Flutter.
///
/// Pages here are shown without a transition, so there is no flight: the
/// [child] is drawn where it stands on each page. Everything else is accepted
/// so a screen written with heroes compiles and reads as it did.
class Hero extends StatelessWidget {
  const Hero({
    super.key,
    required this.tag,
    this.createRectTween,
    this.flightShuttleBuilder,
    this.placeholderBuilder,
    this.transitionOnUserGestures = false,
    required this.child,
  });

  /// What pairs this hero with the one on the other page.
  final Object tag;
  final Object? createRectTween;
  final Object? flightShuttleBuilder;
  final Object? placeholderBuilder;
  final bool transitionOnUserGestures;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The pointer a mouse shows over a [MouseRegion].
class MouseCursor {
  const MouseCursor._(this.kind);

  /// The CSS name of the cursor.
  final String kind;

  /// Whatever the region beneath would show.
  static const MouseCursor defer = MouseCursor._('auto');

  /// No decision: the platform's own.
  static const MouseCursor uncontrolled = MouseCursor._('auto');

  @override
  String toString() => 'MouseCursor($kind)';
}

/// The cursors a system has, by Flutter's names.
abstract final class SystemMouseCursors {
  static const MouseCursor none = MouseCursor._('none');
  static const MouseCursor basic = MouseCursor._('default');
  static const MouseCursor click = MouseCursor._('pointer');
  static const MouseCursor forbidden = MouseCursor._('not-allowed');
  static const MouseCursor wait = MouseCursor._('wait');
  static const MouseCursor progress = MouseCursor._('progress');
  static const MouseCursor contextMenu = MouseCursor._('context-menu');
  static const MouseCursor help = MouseCursor._('help');
  static const MouseCursor text = MouseCursor._('text');
  static const MouseCursor verticalText = MouseCursor._('vertical-text');
  static const MouseCursor cell = MouseCursor._('cell');
  static const MouseCursor precise = MouseCursor._('crosshair');
  static const MouseCursor move = MouseCursor._('move');
  static const MouseCursor grab = MouseCursor._('grab');
  static const MouseCursor grabbing = MouseCursor._('grabbing');
  static const MouseCursor noDrop = MouseCursor._('no-drop');
  static const MouseCursor alias = MouseCursor._('alias');
  static const MouseCursor copy = MouseCursor._('copy');
  static const MouseCursor allScroll = MouseCursor._('all-scroll');
  static const MouseCursor resizeLeftRight = MouseCursor._('ew-resize');
  static const MouseCursor resizeUpDown = MouseCursor._('ns-resize');
  static const MouseCursor resizeColumn = MouseCursor._('col-resize');
  static const MouseCursor resizeRow = MouseCursor._('row-resize');
  static const MouseCursor zoomIn = MouseCursor._('zoom-in');
  static const MouseCursor zoomOut = MouseCursor._('zoom-out');
}

/// A region that follows the mouse, in Flutter.
///
/// No renderer reports the pointer entering, leaving or moving, so [onEnter],
/// [onExit] and [onHover] are accepted and never called, and [cursor] is not
/// carried: a box that takes a tap already shows the platform's pointing hand
/// in a browser. The [child] is drawn as it is.
class MouseRegion extends StatelessWidget {
  const MouseRegion({
    super.key,
    this.onEnter,
    this.onExit,
    this.onHover,
    this.cursor = MouseCursor.defer,
    this.opaque = true,
    this.hitTestBehavior,
    this.child,
  });
  final void Function(Object event)? onEnter;
  final void Function(Object event)? onExit;
  final void Function(Object event)? onHover;
  final MouseCursor cursor;
  final bool opaque;
  final Object? hitTestBehavior;
  final Widget? child;

  @override
  Widget build(BuildContext context) => child ?? const SizedBox.shrink();
}

/// A circle for a user: initials or an icon as [child], or a picture.
class CircleAvatar extends Widget {
  const CircleAvatar({
    super.key,
    this.child,
    this.backgroundColor,
    this.backgroundImage,
    this.foregroundColor,
    this.radius,
    this.minRadius,
    this.maxRadius,
  });
  final Widget? child;
  final Color? backgroundColor;
  final ImageProvider? backgroundImage;
  final Color? foregroundColor;

  /// Half the avatar's width; 20 by default, as in Flutter.
  final double? radius;
  final double? minRadius;
  final double? maxRadius;

  @override
  WidgetNode _render(_Owner owner) {
    final scheme = _themeOf(owner).colorScheme;
    final size = (radius ?? minRadius ?? maxRadius ?? 20) * 2;
    final foreground = foregroundColor ?? scheme.onPrimaryContainer;
    final image = backgroundImage;
    final content = child == null
        ? null
        : _withForeground(
            owner,
            foreground,
            () => _renderChild(owner, child!),
          );
    return UIBuilder.box(
      width: size,
      height: size,
      shape: 'circle',
      clip: true,
      color: (backgroundColor ?? scheme.primaryContainer)._hex,
      alignment: const [0, 0],
      id: _idOf(key),
      child: image == null
          ? content
          : UIBuilder.stack(
              alignment: const [0, 0],
              children: [
                UIBuilder.image(
                  src: image._src,
                  alt: '',
                  width: size,
                  height: size,
                ),
                if (content != null) content,
              ],
            ),
    );
  }
}

/// A Material card: a raised, rounded surface around [child].
///
/// A card with nothing changed is the platform's own card. One that asks for
/// a [color], a [shape] or an [elevation] of its own is composed from a box,
/// since those are things the card node does not carry.
class Card extends Widget {
  const Card({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.child,
    this.semanticContainer = true,
  }) : _variant = 'elevated';
  const Card.outlined({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.child,
    this.semanticContainer = true,
  }) : _variant = 'outlined';
  const Card.filled({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.child,
    this.semanticContainer = true,
  }) : _variant = 'filled';

  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final ShapeBorder? shape;
  final bool borderOnForeground;

  /// The space around the card; 4 on every side by default, as in Flutter.
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;
  final Widget? child;
  final bool semanticContainer;
  final String _variant;

  @override
  WidgetNode _render(_Owner owner) {
    final outside = (margin ?? const EdgeInsets.all(4))._resolved;
    final custom = color != null || shape != null || elevation != null;
    final WidgetNode card;
    if (custom) {
      final scheme = _themeOf(owner).colorScheme;
      final shaped = _shapeDecoration(
        shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: _variant == 'outlined'
                  ? BorderSide(color: scheme.outlineVariant)
                  : BorderSide.none,
            ),
        color:
            color ??
            (_variant == 'filled'
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainerLow),
      );
      final node = _box(
        owner,
        child: child,
        decoration: shaped.decoration,
        clip: (clipBehavior ?? Clip.none) != Clip.none,
        id: _idOf(key),
      );
      final shadow = _elevationShadow(
        elevation ?? (_variant == 'elevated' ? 1 : 0),
        shadowColor,
      );
      card = shadow == null ? node : _withProps(node, {'shadow': shadow});
    } else {
      // Flutter's card adds no padding of its own, and neither does this.
      final content = owner.inSlot(
        'content',
        () => (child ?? const SizedBox())._render(owner),
      );
      card = switch (_variant) {
        'outlined' => DSCard.outlined(content: content, padding: 0),
        'filled' => DSCard.filled(content: content, padding: 0),
        _ => DSCard.elevated(content: content, padding: 0),
      };
    }
    if (outside.left == 0 &&
        outside.top == 0 &&
        outside.right == 0 &&
        outside.bottom == 0) {
      return card;
    }
    return UIBuilder.padding(
      left: outside.left,
      top: outside.top,
      right: outside.right,
      bottom: outside.bottom,
      child: card,
    );
  }
}

/// A thin horizontal rule, in a strip [height] tall.
class Divider extends Widget {
  const Divider({
    super.key,
    this.height,
    this.thickness,
    this.indent,
    this.endIndent,
    this.color,
  });

  /// The height of the strip the rule is centred in; 16 by default.
  final double? height;

  /// How thick the rule itself is; 1 by default.
  final double? thickness;

  /// Empty space before and after the rule.
  final double? indent;
  final double? endIndent;

  /// Left null, the renderer draws its theme's divider colour.
  final Color? color;

  @override
  WidgetNode _render(_Owner owner) {
    final line = DSDivider.horizontal(
      color: color?._hex,
      thickness: thickness ?? 1,
      // The node's margin is the space above and below the line.
      margin: math.max(0, ((height ?? 16) - (thickness ?? 1)) / 2),
    );
    final before = indent ?? 0;
    final after = endIndent ?? 0;
    if (before == 0 && after == 0) return line;
    // `indent` is the gap before the line and `endIndent` the one after it,
    // so they change sides with the reading direction.
    final rtl = owner._direction == TextDirection.rtl;
    return UIBuilder.padding(
      left: rtl ? after : before,
      right: rtl ? before : after,
      top: 0,
      bottom: 0,
      child: line,
    );
  }
}

/// A thin vertical rule, in a strip [width] wide.
class VerticalDivider extends Widget {
  const VerticalDivider({
    super.key,
    this.width,
    this.thickness,
    this.indent,
    this.endIndent,
    this.color,
  });
  final double? width;
  final double? thickness;
  final double? indent;
  final double? endIndent;
  final Color? color;

  @override
  WidgetNode _render(_Owner owner) {
    final strip = width ?? 16;
    final line = thickness ?? 1;
    final side = math.max(0.0, (strip - line) / 2);
    // A box rather than the divider node: a vertical rule has to be as tall
    // as the row it sits in, and that node has a fixed height.
    return UIBuilder.box(
      width: line,
      expand: 'height',
      margin: [side, indent ?? 0, side, endIndent ?? 0],
      color: (color ?? _themeOf(owner).dividerColor)._hex,
    );
  }
}
