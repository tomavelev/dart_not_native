part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Slivers.
//
// Flutter's slivers lay themselves out lazily inside a viewport. There is no
// viewport here - a scroller is the platform's, around a column - so a
// sliver is the boxes it would have laid out, and a CustomScrollView is a
// list of them. What that keeps is the structure an app was written in; what
// it gives up is laziness (every child of every sliver is built) and
// anything that depends on how far the view has scrolled: a floating app
// bar scrolls away with the rest, and nothing collapses. A bar or header
// pinned at the very top is the exception - it is held above the scroller.
// ---------------------------------------------------------------------------

/// A sliver: something a [CustomScrollView] lays out among its others.
abstract class _Sliver extends StatelessWidget {
  const _Sliver({super.key});

  /// The boxes this sliver puts into the scroll view, in order.
  List<Widget> _boxes(BuildContext context);

  /// Outside a [CustomScrollView] - where Flutter would not allow it - a
  /// sliver is still its boxes, one under another.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: _boxes(context),
  );
}

List<Widget> _boxesOf(BuildContext context, Widget sliver) =>
    sliver is _Sliver ? sliver._boxes(context) : [sliver];

/// Rows a builder makes, for a scroll view to build only near the screen.
class _BuiltRun {
  const _BuiltRun(this.count, this.builder);
  final int count;
  final NullableIndexedWidgetBuilder builder;
}

/// What [sliver] puts into a scroll view: a [_BuiltRun] for a list a builder
/// makes, its boxes otherwise.
List<Object> _entriesOf(BuildContext context, Widget sliver) {
  if (sliver is SliverList) {
    final delegate = sliver.delegate;
    final count = delegate is SliverChildBuilderDelegate
        ? delegate.childCount
        : null;
    if (delegate is SliverChildBuilderDelegate && count != null) {
      final extent = sliver is SliverFixedExtentList ? sliver.itemExtent : null;
      return [
        _BuiltRun(
          count,
          extent == null
              ? delegate.builder
              : (context, index) => SizedBox(
                  height: extent,
                  child: delegate.builder(context, index),
                ),
        ),
      ];
    }
  }
  return _boxesOf(context, sliver);
}

/// A list view of [entries]: built whole, unless a builder makes some of
/// them and nothing among them is held part-way down - then a builder view,
/// which builds only the rows near the screen once there are many.
Widget _viewOf(
  BuildContext context,
  List<Object> entries, {
  required Axis scrollDirection,
  bool reverse = false,
  ScrollController? controller,
  ScrollPhysics? physics,
  bool shrinkWrap = false,
}) {
  final runs = entries.whereType<_BuiltRun>();
  final sticky = entries.any((entry) => entry is _Sticky);
  if (runs.isEmpty || sticky) {
    return ListView(
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      children: [
        for (final entry in entries)
          if (entry is _BuiltRun)
            for (var i = 0; i < entry.count; i++)
              ?entry.builder(context, i)
          else
            entry as Widget,
      ],
    );
  }
  // Where each entry starts among the rows.
  final starts = <int>[];
  var total = 0;
  for (final entry in entries) {
    starts.add(total);
    total += entry is _BuiltRun ? entry.count : 1;
  }
  return ListView.builder(
    scrollDirection: scrollDirection,
    reverse: reverse,
    controller: controller,
    physics: physics,
    shrinkWrap: shrinkWrap,
    itemCount: total,
    itemBuilder: (context, index) {
      var at = starts.length - 1;
      while (at > 0 && starts[at] > index) {
        at--;
      }
      final entry = entries[at];
      return entry is _BuiltRun
          ? entry.builder(context, index - starts[at])
          : entry as Widget;
    },
  );
}

/// A scroll view made of slivers - see the note at the top of this file for
/// what a sliver is here.
class CustomScrollView extends StatelessWidget {
  const CustomScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.slivers = const [],
    this.center,
    this.anchor = 0.0,
    this.cacheExtent,
    this.semanticChildCount,
    this.clipBehavior = Clip.hardEdge,
  });
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final List<Widget> slivers;

  /// Accepted and not carried.
  final bool? primary;
  final Key? center;
  final double anchor;
  final double? cacheExtent;
  final int? semanticChildCount;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    // What is pinned at the very top is held there by not being in the
    // scroller at all: it stands above it. That needs a height to share
    // out, and only says the right thing for a view that scrolls down.
    var top =
        scrollDirection == Axis.vertical &&
        !reverse &&
        !shrinkWrap &&
        !_ownerOf(context)._unboundedHeight;
    // A pinned bar taller than its toolbar, first: it collapses as the view
    // scrolls, over the content rather than above it.
    final first = slivers.isEmpty ? null : slivers.first;
    if (top &&
        first is SliverAppBar &&
        ((first.pinned && first._collapses) || (first.floating && !first.pinned))) {
      return _CollapsingScrollView(
        bar: first,
        controller: controller,
        physics: physics,
        rest: [
          for (final sliver in slivers.skip(1)) ..._entriesOf(context, sliver),
        ],
      );
    }
    final held = <Widget>[];
    final scrolled = <Object>[];
    for (final sliver in slivers) {
      if (top && sliver is SliverAppBar && sliver.pinned) {
        final (bar, space) = sliver._pinnedParts(context);
        held.add(bar);
        if (space != null) {
          scrolled.add(space);
          top = false;
        }
        continue;
      }
      if (top && sliver is SliverPersistentHeader && sliver.pinned) {
        held.addAll(sliver._boxes(context));
        continue;
      }
      top = false;
      // Pinned further down, it scrolls up to the top and stays there.
      final vertical = scrollDirection == Axis.vertical && !reverse;
      if (vertical &&
          ((sliver is SliverPersistentHeader && sliver.pinned) ||
              (sliver is SliverAppBar && sliver.pinned))) {
        scrolled.addAll([
          for (final box in _boxesOf(context, sliver)) _Sticky(child: box),
        ]);
        continue;
      }
      scrolled.addAll(_entriesOf(context, sliver));
    }
    final view = _viewOf(
      context,
      scrolled,
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
    );
    if (held.isEmpty) return view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...held, Expanded(child: view)],
    );
  }
}

/// Where a sliver's children come from.
abstract class SliverChildDelegate {
  const SliverChildDelegate();
  List<Widget> _children(BuildContext context);
}

/// A sliver's children, given as a list.
class SliverChildListDelegate extends SliverChildDelegate {
  const SliverChildListDelegate(
    this.children, {
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
  });

  /// Flutter's fixed-length spelling of the same.
  const SliverChildListDelegate.fixed(
    this.children, {
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
  });
  final List<Widget> children;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;

  @override
  List<Widget> _children(BuildContext context) => children;
}

/// A sliver's children, built from an index: [childCount] of them, or until
/// the builder answers null - and no further than five hundred, since all of
/// them are built.
class SliverChildBuilderDelegate extends SliverChildDelegate {
  const SliverChildBuilderDelegate(
    this.builder, {
    this.childCount,
    this.findChildIndexCallback,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
  });
  final NullableIndexedWidgetBuilder builder;
  final int? childCount;
  final Object? findChildIndexCallback;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;

  static const int _most = 500;

  @override
  List<Widget> _children(BuildContext context) {
    final built = <Widget>[];
    final count = childCount ?? _most;
    for (var index = 0; index < count; index++) {
      final child = builder(context, index);
      if (child == null) break;
      built.add(child);
    }
    return built;
  }
}

/// One box among the slivers.
class SliverToBoxAdapter extends _Sliver {
  const SliverToBoxAdapter({super.key, this.child});
  final Widget? child;
  @override
  List<Widget> _boxes(BuildContext context) => [?child];
}

/// A run of children, one under another.
class SliverList extends _Sliver {
  const SliverList({super.key, required this.delegate});

  SliverList.list({
    super.key,
    required List<Widget> children,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : delegate = SliverChildListDelegate(children);

  SliverList.builder({
    super.key,
    required NullableIndexedWidgetBuilder itemBuilder,
    int? itemCount,
    Object? findChildIndexCallback,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : delegate = SliverChildBuilderDelegate(itemBuilder, childCount: itemCount);

  /// Children with something between each two.
  SliverList.separated({
    super.key,
    required NullableIndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder separatorBuilder,
    required int itemCount,
    Object? findChildIndexCallback,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : delegate = SliverChildBuilderDelegate(
         (context, index) => index.isEven
             ? itemBuilder(context, index ~/ 2)
             : separatorBuilder(context, index ~/ 2),
         childCount: itemCount == 0 ? 0 : itemCount * 2 - 1,
       );

  final SliverChildDelegate delegate;

  @override
  List<Widget> _boxes(BuildContext context) => delegate._children(context);
}

/// A [SliverList] whose children are each [itemExtent] tall.
class SliverFixedExtentList extends SliverList {
  const SliverFixedExtentList({
    super.key,
    required super.delegate,
    required this.itemExtent,
  });
  final double itemExtent;

  @override
  List<Widget> _boxes(BuildContext context) => [
    for (final child in delegate._children(context))
      SizedBox(height: itemExtent, child: child),
  ];
}

/// Children in a grid.
class SliverGrid extends _Sliver {
  const SliverGrid({
    super.key,
    required this.delegate,
    required this.gridDelegate,
  });

  SliverGrid.count({
    super.key,
    required int crossAxisCount,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    List<Widget> children = const [],
  }) : delegate = SliverChildListDelegate(children),
       gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
         crossAxisCount: crossAxisCount,
         mainAxisSpacing: mainAxisSpacing,
         crossAxisSpacing: crossAxisSpacing,
         childAspectRatio: childAspectRatio,
       );

  SliverGrid.extent({
    super.key,
    required double maxCrossAxisExtent,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    List<Widget> children = const [],
  }) : delegate = SliverChildListDelegate(children),
       gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
         maxCrossAxisExtent: maxCrossAxisExtent,
         mainAxisSpacing: mainAxisSpacing,
         crossAxisSpacing: crossAxisSpacing,
         childAspectRatio: childAspectRatio,
       );

  SliverGrid.builder({
    super.key,
    required this.gridDelegate,
    required NullableIndexedWidgetBuilder itemBuilder,
    int? itemCount,
    Object? findChildIndexCallback,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : delegate = SliverChildBuilderDelegate(itemBuilder, childCount: itemCount);

  final SliverChildDelegate delegate;
  final SliverGridDelegate gridDelegate;

  @override
  List<Widget> _boxes(BuildContext context) => [
    // As tall as its cells and going nowhere: the scroll view around it is
    // what scrolls.
    GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: gridDelegate,
      children: delegate._children(context),
    ),
  ];
}

/// Room around another sliver.
class SliverPadding extends _Sliver {
  const SliverPadding({super.key, required this.padding, this.sliver});
  final EdgeInsetsGeometry padding;
  final Widget? sliver;

  @override
  List<Widget> _boxes(BuildContext context) {
    final inner = sliver;
    return [
      Padding(
        padding: padding,
        child: inner == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: _boxesOf(context, inner),
              ),
      ),
    ];
  }
}

/// Another sliver, clear of the notch and the system's bars.
class SliverSafeArea extends _Sliver {
  const SliverSafeArea({
    super.key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.minimum = EdgeInsets.zero,
    required this.sliver,
  });
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final EdgeInsets minimum;
  final Widget sliver;

  @override
  List<Widget> _boxes(BuildContext context) => _boxesOf(context, sliver);
}

/// A child that fills what the slivers before it left. Nothing here knows
/// how much that is, so it is its child at the child's own size.
class SliverFillRemaining extends _Sliver {
  const SliverFillRemaining({
    super.key,
    this.child,
    this.hasScrollBody = true,
    this.fillOverscroll = false,
  });
  final Widget? child;
  final bool hasScrollBody;
  final bool fillOverscroll;

  @override
  List<Widget> _boxes(BuildContext context) => [?child];
}

/// Another sliver, shown or not.
class SliverVisibility extends _Sliver {
  const SliverVisibility({
    super.key,
    required this.sliver,
    this.replacementSliver = const SliverToBoxAdapter(),
    this.visible = true,
    this.maintainState = false,
  });
  final Widget sliver;
  final Widget replacementSliver;
  final bool visible;
  final bool maintainState;

  @override
  List<Widget> _boxes(BuildContext context) =>
      _boxesOf(context, visible ? sliver : replacementSliver);
}

/// Another sliver, faded.
class SliverOpacity extends _Sliver {
  const SliverOpacity({
    super.key,
    required this.opacity,
    this.alwaysIncludeSemantics = false,
    this.sliver,
  });
  final double opacity;
  final bool alwaysIncludeSemantics;
  final Widget? sliver;

  @override
  List<Widget> _boxes(BuildContext context) {
    final inner = sliver;
    if (inner == null) return const [];
    return [
      for (final box in _boxesOf(context, inner))
        Opacity(opacity: opacity, child: box),
    ];
  }
}

/// What a [SliverPersistentHeader] draws.
abstract class SliverPersistentHeaderDelegate {
  const SliverPersistentHeaderDelegate();
  double get minExtent;
  double get maxExtent;

  /// Always asked at rest: [shrinkOffset] is zero and [overlapsContent]
  /// false, since the header does not shrink as the view scrolls.
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent);
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate);
}

/// A header at its full height. [pinned], it is held above the scroll view
/// when it is the first sliver, or follows only other pinned ones with
/// nothing that scrolls between; further down, it scrolls up to the top of
/// the view and stays there - under the ones pinned before it, as Flutter
/// stacks them - until the list scrolls back. A [floating] one scrolls away.
class SliverPersistentHeader extends _Sliver {
  const SliverPersistentHeader({
    super.key,
    required this.delegate,
    this.pinned = false,
    this.floating = false,
  });
  final SliverPersistentHeaderDelegate delegate;
  final bool pinned;
  final bool floating;

  @override
  List<Widget> _boxes(BuildContext context) => [
    SizedBox(
      height: delegate.maxExtent,
      child: delegate.build(context, 0, false),
    ),
  ];
}

/// How a [FlexibleSpaceBar] collapses. Accepted for Flutter's signature.
enum CollapseMode { parallax, pin, none }

/// The tall part of a [SliverAppBar]: a background, with a title over its
/// bottom edge. It does not collapse.
class FlexibleSpaceBar extends StatelessWidget {
  const FlexibleSpaceBar({
    super.key,
    this.title,
    this.background,
    this.centerTitle,
    this.titlePadding,
    this.collapseMode = CollapseMode.parallax,
    this.stretchModes = const [],
    this.expandedTitleScale = 1.5,
  });
  final Widget? title;
  final Widget? background;
  final bool? centerTitle;
  final EdgeInsetsGeometry? titlePadding;
  final CollapseMode collapseMode;
  final List<Object> stretchModes;
  final double expandedTitleScale;

  @override
  Widget build(BuildContext context) {
    final heading = title;
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (settings != null) return _collapsing(context, settings);
    return Stack(
      fit: StackFit.expand,
      children: [
        ?background,
        if (heading != null)
          Align(
            alignment: centerTitle == true
                ? Alignment.bottomCenter
                : Alignment.bottomLeft,
            child: Padding(
              padding:
                  titlePadding ??
                  const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                child: heading,
              ),
            ),
          ),
      ],
    );
  }
}

/// What a [FlexibleSpaceBar] is told by the app bar it is in: how tall the
/// bar is now, between [minExtent] and [maxExtent].
class FlexibleSpaceBarSettings extends InheritedWidget {
  const FlexibleSpaceBarSettings({
    super.key,
    required this.toolbarOpacity,
    required this.minExtent,
    required this.maxExtent,
    required this.currentExtent,
    required super.child,
    this.isScrolledUnder,
  });
  final double toolbarOpacity;
  final double minExtent;
  final double maxExtent;
  final double currentExtent;
  final bool? isScrolledUnder;

  /// How far the bar has collapsed, 0 open to 1 shut.
  double get _t {
    final range = maxExtent - minExtent;
    return range <= 0
        ? 1
        : ((maxExtent - currentExtent) / range).clamp(0.0, 1.0);
  }

  @override
  bool updateShouldNotify(FlexibleSpaceBarSettings oldWidget) =>
      currentExtent != oldWidget.currentExtent ||
      minExtent != oldWidget.minExtent ||
      maxExtent != oldWidget.maxExtent;
}

extension on FlexibleSpaceBar {
  /// The space as it is in a bar that has collapsed by [settings]: the
  /// background drifting up a quarter of the way and fading out over the
  /// last toolbar's height, the title shrinking from [expandedTitleScale]
  /// to its own size against its start - Flutter's parallax.
  Widget _collapsing(BuildContext context, FlexibleSpaceBarSettings settings) {
    final t = settings._t;
    final delta = settings.maxExtent - settings.minExtent;
    final fadeStart = delta <= 0
        ? 0.0
        : math.max(0.0, 1 - settings.minExtent / delta);
    final shown = fadeStart >= 1
        ? 1 - t
        : 1 - ((t - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);
    final drift = switch (collapseMode) {
      CollapseMode.parallax => -delta / 4 * t,
      CollapseMode.pin => -delta * t,
      CollapseMode.none => 0.0,
    };
    final scale = expandedTitleScale + (1 - expandedTitleScale) * t;
    final heading = title;
    final style = const TextStyle(fontSize: 22, fontWeight: FontWeight.w500);
    // Turned about its middle, as a box here is: moved so that its start
    // and its foot stay where they are, as Flutter's turns about them.
    var width = 0.0;
    if (heading is Text && heading.data != null && centerTitle != true) {
      final painter = TextPainter(
        text: TextSpan(text: heading.data, style: heading.style ?? style),
      )..layout();
      width = painter.width;
    }
    final height = (heading is Text ? heading.style?.fontSize : null) ?? 22;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (background case final picture?)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: settings.maxExtent,
              child: Opacity(
                opacity: shown,
                child: Transform.translate(
                  offset: Offset(0, drift),
                  child: picture,
                ),
              ),
            ),
          if (heading != null)
            Align(
              alignment: centerTitle == true
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              child: Padding(
                padding:
                    titlePadding ??
                    const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(
                      (scale - 1) * width / 2,
                      -(scale - 1) * height * 1.2 / 2,
                    )
                    ..scale(scale),
                  child: DefaultTextStyle(style: style, child: heading),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A scroll view under a pinned app bar that collapses: the content starts
/// below the bar at its full height and scrolls under it, and the bar is
/// built from the offset - [_followingScroll] moves it each frame.
class _CollapsingScrollView extends StatefulWidget {
  const _CollapsingScrollView({
    required this.bar,
    required this.rest,
    this.controller,
    this.physics,
  });
  final SliverAppBar bar;
  final List<Object> rest;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  @override
  State<_CollapsingScrollView> createState() => _CollapsingScrollViewState();
}

class _CollapsingScrollViewState extends State<_CollapsingScrollView> {
  ScrollController? _own;
  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = widget.bar;
    final controller = _controller;
    final under = bar.bottom?.preferredSize.height ?? 0;
    return Stack(
      children: [
        Positioned.fill(
          child: _viewOf(
            context,
            [SizedBox(height: bar._tall + under), ...widget.rest],
            scrollDirection: Axis.vertical,
            controller: controller,
            physics: widget.physics,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: bar.floating && !bar.pinned
              // Floating: the whole bar, slid up as the list goes down and
              // back as soon as it comes up - by the renderer, which keeps
              // where it is from the scrolling itself.
              ? _Floating(
                  controller: controller,
                  extent: bar._tall + under,
                  snap: bar.snap,
                  child: bar._collapsed(context, 0),
                )
              : AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => bar._collapsed(
                    context,
                    controller.hasClients ? controller.offset : 0,
                  ),
                ),
        ),
      ],
    );
  }
}

/// An app bar among the slivers.
///
/// Drawn at its full height - [expandedHeight], or a toolbar's - with its
/// [flexibleSpace] behind the toolbar.
///
/// [pinned], first among the slivers and taller than its toolbar, it
/// collapses as the view scrolls - down to its toolbar and [bottom], which
/// stay - with a [FlexibleSpaceBar] doing what Flutter's does on the way:
/// its background drifts and fades, its title shrinks. It moves each frame
/// (see `ScrollController`). Pinned and no taller than its toolbar, it is
/// held above the scroll view; pinned further down, it scrolls up to the top
/// and stays there, under any pinned before it; not pinned, it scrolls away
/// with the content. [floating] and not pinned, first among the slivers, it
/// floats over the content: up and away as the view scrolls down, back as
/// soon as it scrolls up, and with [snap] the rest of the way in or out when
/// the scrolling stops (`scrollFloat`). [stretch] makes a collapsing bar
/// taller than its full height by as far as the view is pulled past its top,
/// where the platform's scrolling bounces - iOS.
class SliverAppBar extends _Sliver {
  const SliverAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.flexibleSpace,
    this.bottom,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.centerTitle,
    this.titleSpacing,
    this.collapsedHeight,
    this.expandedHeight,
    this.floating = false,
    this.pinned = false,
    this.snap = false,
    this.stretch = false,
    this.toolbarHeight = 56.0,
  });
  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool? centerTitle;
  final double? expandedHeight;
  final double toolbarHeight;

  /// Accepted and not carried.
  final bool automaticallyImplyLeading;
  final double? elevation;
  final double? titleSpacing;
  final double? collapsedHeight;
  final bool floating;
  final bool pinned;
  final bool snap;
  final bool stretch;

  @override
  List<Widget> _boxes(BuildContext context) => _parts(context);

  /// Its full height.
  double get _tall => math.max(expandedHeight ?? toolbarHeight, toolbarHeight);

  /// The height it collapses to, less [bottom].
  double get _short => math.max(collapsedHeight ?? toolbarHeight, toolbarHeight);

  bool get _collapses => _tall > _short;

  /// The bar after the view has scrolled [offset]: as tall as it is less
  /// that, down to its toolbar.
  Widget _collapsed(BuildContext context, double offset) {
    final scheme = Theme.of(context).colorScheme;
    final ink = foregroundColor ?? scheme.onSurface;
    // Pulled past the top, a bar that stretches is taller than its full
    // height by as much.
    final height = stretch && offset < 0
        ? _tall - offset
        : (_tall - offset.clamp(0.0, _tall - _short)).toDouble();
    final space = flexibleSpace;
    final under = bottom;
    return Container(
      color: backgroundColor ?? scheme.surface,
      child: DefaultTextStyle(
        style: TextStyle(color: ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (space != null)
                    FlexibleSpaceBarSettings(
                      toolbarOpacity: 1,
                      minExtent: _short,
                      maxExtent: _tall,
                      currentExtent: height,
                      child: space,
                    ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: _toolbar(ink),
                  ),
                ],
              ),
            ),
            ?under,
          ],
        ),
      ),
    );
  }

  /// The bar as two: what stays - the toolbar and [bottom] - and what
  /// scrolls away under it, when the bar is taller than its toolbar.
  (Widget, Widget?) _pinnedParts(BuildContext context) {
    final parts = _parts(context, pinnedOnly: true);
    return (parts.first, parts.length > 1 ? parts[1] : null);
  }

  List<Widget> _parts(BuildContext context, {bool pinnedOnly = false}) {
    final scheme = Theme.of(context).colorScheme;
    final ink = foregroundColor ?? scheme.onSurface;
    final space = flexibleSpace;
    final under = bottom;
    final toolbar = _toolbar(ink);
    final tall = _tall;
    if (pinnedOnly) {
      return _pinned(scheme, ink, toolbar, tall, space, under);
    }
    return _whole(scheme, ink, toolbar, tall, space, under);
  }

  Widget _toolbar(Color ink) {
    final heading = title;
    return SizedBox(
      height: toolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: heading == null
                    ? const SizedBox.shrink()
                    : Align(
                        // At the start of the line: the right, read from
                        // the right.
                        alignment: centerTitle == true
                            ? AlignmentDirectional.center
                            : AlignmentDirectional.centerStart,
                        child: DefaultTextStyle(
                          style: TextStyle(
                            color: ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                          child: heading,
                        ),
                      ),
              ),
            ),
            ...?actions,
          ],
        ),
      ),
    );
  }

  List<Widget> _pinned(
    ColorScheme scheme,
    Color ink,
    Widget toolbar,
    double tall,
    Widget? space,
    Widget? under,
  ) {
    final fill = backgroundColor ?? scheme.surface;
    Widget dressed(Widget child) => Container(
      color: fill,
      child: DefaultTextStyle(style: TextStyle(color: ink), child: child),
    );
    return [
      dressed(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [toolbar, ?under],
        ),
      ),
      if (tall > toolbarHeight)
        dressed(
          SizedBox(
            height: tall - toolbarHeight,
            child: space ?? const SizedBox.shrink(),
          ),
        ),
    ];
  }

  List<Widget> _whole(
    ColorScheme scheme,
    Color ink,
    Widget toolbar,
    double tall,
    Widget? space,
    Widget? under,
  ) {
    return [
      Container(
        color: backgroundColor ?? scheme.surface,
        child: DefaultTextStyle(
          style: TextStyle(color: ink),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (space == null)
                SizedBox(
                  height: tall,
                  child: Align(alignment: Alignment.topCenter, child: toolbar),
                )
              else
                SizedBox(
                  height: tall,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      space,
                      Align(alignment: Alignment.topCenter, child: toolbar),
                    ],
                  ),
                ),
              ?under,
            ],
          ),
        ),
      ),
    ];
  }
}


/// [child], slid up by as much as the scroller [controller] drives has gone
/// down since it last came up, up to [extent] - a floating app bar. The
/// renderer keeps that from the scrolling itself (`scrollFloat`); with
/// [snap], a bar left part of the way when the scroller comes to rest goes
/// the rest, in or out.
class _Floating extends Widget {
  const _Floating({
    required this.controller,
    required this.extent,
    required this.snap,
    required this.child,
  });
  final ScrollController controller;
  final double extent;
  final bool snap;
  final Widget child;

  @override
  WidgetNode _render(_Owner owner) {
    if (!controller._linked) {
      // Its scroller says its name from the next build on.
      controller._linked = true;
      owner._requestRebuild();
    }
    return _withProps(
      UIBuilder.box(expand: 'width', child: _renderChild(owner, child)),
      {
        'scrollFloat': {
          'source': controller._link,
          'extent': extent,
          if (snap) 'snap': true,
        },
      },
    );
  }
}

/// [child], held at the top of the scroller it is in once the content has
/// scrolled past it - see `UIBuilder.box`'s `sticky`.
class _Sticky extends Widget {
  const _Sticky({required this.child});
  final Widget child;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    sticky: true,
    expand: 'width',
    child: _renderChild(owner, child),
  );
}
