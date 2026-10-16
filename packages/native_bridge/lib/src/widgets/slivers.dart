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
    final held = <Widget>[];
    final scrolled = <Widget>[];
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
      scrolled.addAll(_boxesOf(context, sliver));
    }
    final view = ListView(
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      children: scrolled,
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

/// An app bar among the slivers.
///
/// Drawn at its full height - [expandedHeight], or a toolbar's - with its
/// [flexibleSpace] behind the toolbar, and it does not collapse.
///
/// [pinned], and first among the slivers, its toolbar and [bottom] are held
/// above the scroll view and what is left of the tall part - the
/// [flexibleSpace], less a toolbar's height - scrolls away beneath them: the
/// bar ends up as a collapsed one would, without the title moving up into
/// it. Pinned further down, it scrolls up to the top and stays there, under
/// any pinned before it; not pinned, it scrolls away with the content.
/// [floating], [snap] and [stretch] are accepted and not carried.
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

  /// The bar as two: what stays - the toolbar and [bottom] - and what
  /// scrolls away under it, when the bar is taller than its toolbar.
  (Widget, Widget?) _pinnedParts(BuildContext context) {
    final parts = _parts(context, pinnedOnly: true);
    return (parts.first, parts.length > 1 ? parts[1] : null);
  }

  List<Widget> _parts(BuildContext context, {bool pinnedOnly = false}) {
    final scheme = Theme.of(context).colorScheme;
    final ink = foregroundColor ?? scheme.onSurface;
    final heading = title;
    final space = flexibleSpace;
    final under = bottom;
    final toolbar = SizedBox(
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
    final tall = math.max(expandedHeight ?? toolbarHeight, toolbarHeight);
    if (pinnedOnly) {
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
