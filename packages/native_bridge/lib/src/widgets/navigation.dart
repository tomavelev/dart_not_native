part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Overlays: showDialog / showModalBottomSheet / ScaffoldMessenger, backed by
// the owner's overlay stack. Each returns a Future that completes when the
// overlay is dismissed - by Navigator.pop, a tap on the scrim or the back
// gesture - exactly like Flutter's.
// ---------------------------------------------------------------------------

enum _OverlayKind { dialog, sheet, picker }

class _OverlayEntry {
  _OverlayEntry(
    this.kind,
    this.build, {
    this.scope,
    this.barrierDismissible = true,
    this.isDrawer = false,
  });
  final _OverlayKind kind;

  /// A scaffold's drawer, which belongs to the page it was opened on and so
  /// closes when the app moves to another.
  final bool isDrawer;
  final WidgetBuilder build;

  /// What was above the context that asked for the overlay, so the overlay is
  /// built under the same theme and the same providers.
  final _Scope? scope;
  final bool barrierDismissible;
  final Completer<Object?> completer = Completer<Object?>();
  final String id = 'overlay_${_nextOverlayId++}';

  /// The overlay node around what the builder made.
  WidgetNode wrap(_Owner owner, WidgetNode node) {
    switch (kind) {
      case _OverlayKind.picker:
        return node;
      case _OverlayKind.sheet:
        return UIBuilder.bottomSheet(
          id: id,
          content: [node],
          dismissible: barrierDismissible,
          onDismiss: () => owner._dismiss(this, null),
        );
      case _OverlayKind.dialog:
        // An AlertDialog, a SimpleDialog or a Dialog is the dialog node
        // already. Anything else an app builds is put in one, so it is still
        // modal, still over a scrim and still closed by the back gesture.
        if (node.type == 'Dialog') return node;
        return UIBuilder.dialog(
          content: [node],
          dismissible: barrierDismissible,
          onDismiss: () => owner._dismiss(this, null),
          id: id,
        );
    }
  }
}

int _nextOverlayId = 0;

/// Shows a modal dialog (usually an [AlertDialog]) over the app.
///
/// [barrierDismissible] false makes the dialog one that only its own buttons
/// close. The barrier's colour and label, and `useRootNavigator`, are accepted
/// for Flutter's signature: the scrim is the platform's.
Future<T?> showDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) => _ownerOf(context).pushOverlay<T>(
  _OverlayEntry(
    _OverlayKind.dialog,
    builder,
    scope: (context as _Context)._scope,
    barrierDismissible: barrierDismissible,
  ),
);

/// Shows a modal sheet rising from the bottom edge.
///
/// [isDismissible] false keeps a tap on the scrim from closing it. The
/// parameters about the sheet's look and size are accepted for Flutter's
/// signature: the sheet is the platform's own.
Future<T?> showModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
}) => _ownerOf(context).pushOverlay<T>(
  _OverlayEntry(
    _OverlayKind.sheet,
    builder,
    scope: (context as _Context)._scope,
    barrierDismissible: isDismissible,
  ),
);

/// Why a snackbar went away.
enum SnackBarClosedReason { action, dismiss, swipe, hide, remove, timeout }

/// What `showSnackBar` hands back: a way to close the snackbar early, and a
/// future for when it has gone.
class ScaffoldFeatureController<T, U> {
  const ScaffoldFeatureController._(this._widget, this.closed, this.close);
  final T _widget;

  /// Completes when the snackbar has gone, with the reason.
  final Future<U> closed;

  /// Takes the snackbar down now.
  final VoidCallback close;

  /// The snackbar this controls.
  T get widget => _widget;
}

/// Shows snackbars, like Flutter's `ScaffoldMessenger.of(context)`.
abstract final class ScaffoldMessenger {
  static ScaffoldMessengerState of(BuildContext context) =>
      ScaffoldMessengerState._(_ownerOf(context));

  static ScaffoldMessengerState? maybeOf(BuildContext context) => of(context);
}

class ScaffoldMessengerState {
  const ScaffoldMessengerState._(this._owner);
  final _Owner _owner;

  /// Shows [snackBar] - now if no other is showing, and otherwise once the
  /// ones asked for before it have gone, as in Flutter. A screen that wants
  /// its newest message at once calls [hideCurrentSnackBar] or
  /// [clearSnackBars] first.
  ///
  /// The controller's `close` takes this bar down if it is showing and out
  /// of the queue if it is still waiting; `closed` completes either way.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar,
  ) {
    final queued = _owner.showSnackBar(snackBar);
    return ScaffoldFeatureController._(
      snackBar,
      queued.closed.future,
      () => _owner._closeQueuedSnackBar(queued, SnackBarClosedReason.hide),
    );
  }

  void hideCurrentSnackBar({
    SnackBarClosedReason reason = SnackBarClosedReason.hide,
  }) => _owner._closeSnackBar(reason);

  void removeCurrentSnackBar({
    SnackBarClosedReason reason = SnackBarClosedReason.remove,
  }) => _owner._closeSnackBar(reason);

  /// Drops every snackbar waiting its turn and hides the one showing. The
  /// ones dropped close with [SnackBarClosedReason.remove].
  void clearSnackBars() => _owner._clearSnackBars();
}

/// A snackbar asked for, and the future that says how it went.
class _QueuedSnackBar {
  _QueuedSnackBar(this.snackBar);

  final SnackBar snackBar;
  final Completer<SnackBarClosedReason> closed =
      Completer<SnackBarClosedReason>();
}

/// A transient message along the bottom edge. [content] is usually a [Text];
/// an optional [action] adds one button (an "Undo").
///
/// The bar is the platform's own, which takes a message and a button: so the
/// words are read out of [content], and [backgroundColor], [behavior] and the
/// other parameters about its look are accepted and not carried.
class SnackBar {
  const SnackBar({
    this.key,
    required this.content,
    this.backgroundColor,
    this.elevation,
    this.margin,
    this.padding,
    this.width,
    this.shape,
    this.behavior,
    this.action,
    this.showCloseIcon,
    this.duration = const Duration(seconds: 4),
    this.dismissDirection,
  });
  final Key? key;
  final Widget content;
  final Color? backgroundColor;
  final double? elevation;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final ShapeBorder? shape;
  final SnackBarBehavior? behavior;
  final SnackBarAction? action;
  final bool? showCloseIcon;
  final Duration duration;
  final DismissDirection? dismissDirection;
}

class SnackBarAction {
  const SnackBarAction({
    this.key,
    required this.label,
    required this.onPressed,
    this.textColor,
    this.backgroundColor,
  });
  final Key? key;
  final String label;
  final VoidCallback onPressed;

  /// The colour the action is written in.
  final Color? textColor;

  /// Accepted and not carried: the action is words, on the bar's own fill.
  final Color? backgroundColor;
}

/// A Material dialog: a [title], some [content] and a row of [actions].
///
/// The dialog is the platform's own, whose title is a string: a [title] that
/// is a [Text] becomes it, and any other widget - like an [icon] - is laid
/// out at the top of the content instead.
class AlertDialog extends Widget {
  const AlertDialog({
    super.key,
    this.icon,
    this.iconColor,
    this.title,
    this.titlePadding,
    this.titleTextStyle,
    this.content,
    this.contentPadding,
    this.contentTextStyle,
    this.actions,
    this.actionsPadding,
    this.actionsAlignment,
    this.backgroundColor,
    this.elevation,
    this.insetPadding,
    this.shape,
    this.scrollable = false,
  });

  /// Flutter's dialog that looks native on each platform - the only kind
  /// there is here.
  const AlertDialog.adaptive({
    super.key,
    this.icon,
    this.iconColor,
    this.title,
    this.titlePadding,
    this.titleTextStyle,
    this.content,
    this.contentPadding,
    this.contentTextStyle,
    this.actions,
    this.actionsPadding,
    this.actionsAlignment,
    this.backgroundColor,
    this.elevation,
    this.insetPadding,
    this.shape,
    this.scrollable = false,
  });

  final Widget? icon;
  final Color? iconColor;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// Accepted and not carried: the dialog's surface, insets and type are the
  /// platform's own.
  final EdgeInsetsGeometry? titlePadding;
  final TextStyle? titleTextStyle;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? contentTextStyle;
  final EdgeInsetsGeometry? actionsPadding;
  final MainAxisAlignment? actionsAlignment;
  final Color? backgroundColor;
  final double? elevation;
  final EdgeInsets? insetPadding;
  final ShapeBorder? shape;

  /// Flutter needs this for content taller than the screen. The platform's
  /// dialog scrolls its content when it has to, so it changes nothing here.
  final bool scrollable;

  @override
  WidgetNode _render(_Owner owner) => _dialogNode(
    owner,
    key: key,
    title: title,
    top: icon,
    content: content == null ? const [] : [content!],
    actions: actions ?? const [],
  );
}

/// A dialog offering a list of choices.
class SimpleDialog extends Widget {
  const SimpleDialog({
    super.key,
    this.title,
    this.children,
    this.backgroundColor,
    this.elevation,
    this.shape,
  });
  final Widget? title;
  final List<Widget>? children;
  final Color? backgroundColor;
  final double? elevation;
  final ShapeBorder? shape;

  @override
  WidgetNode _render(_Owner owner) => _dialogNode(
    owner,
    key: key,
    title: title,
    content: children ?? const [],
  );
}

/// One choice of a [SimpleDialog].
class SimpleDialogOption extends StatelessWidget {
  const SimpleDialogOption({super.key, this.onPressed, this.padding, this.child});
  final VoidCallback? onPressed;
  final EdgeInsets? padding;
  final Widget? child;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: Padding(
      padding:
          padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: child,
    ),
  );
}

/// Builds the entries of a [PopupMenuButton]'s menu.
typedef PopupMenuItemBuilder<T> =
    List<PopupMenuEntry<T>> Function(BuildContext context);

/// Called with the value of the entry that was chosen.
typedef PopupMenuItemSelected<T> = void Function(T value);

/// Called when a menu is closed without a choice.
typedef PopupMenuCanceled = void Function();

/// Where Flutter puts the menu relative to its button. Accepted and not
/// carried: the menu here is a dialog, in the dialog's place.
enum PopupMenuPosition { over, under }

/// One row of a popup menu: a [PopupMenuItem], a [CheckedPopupMenuItem] or a
/// [PopupMenuDivider].
abstract class PopupMenuEntry<T> extends StatelessWidget {
  const PopupMenuEntry({super.key});

  /// The row's height in Flutter, which lays the menu out from it. The rows
  /// here are as tall as what is in them.
  double get height;

  /// Whether this entry stands for [value].
  bool represents(T? value);
}

/// A line between two groups of a popup menu's entries.
class PopupMenuDivider extends PopupMenuEntry<Never> {
  const PopupMenuDivider({super.key, this.height = 16});
  @override
  final double height;
  @override
  bool represents(void value) => false;
  @override
  Widget build(BuildContext context) => Divider(height: height);
}

/// One choice of a popup menu.
class PopupMenuItem<T> extends PopupMenuEntry<T> {
  const PopupMenuItem({
    super.key,
    this.value,
    this.onTap,
    this.enabled = true,
    this.height = 48,
    this.padding,
    this.textStyle,
    this.labelTextStyle,
    this.mouseCursor,
    required this.child,
  });

  /// What [PopupMenuButton.onSelected] is called with.
  final T? value;

  /// Called when the row is tapped, before the menu's own callback.
  final VoidCallback? onTap;

  /// False leaves the row in the menu, dimmed and deaf to taps.
  final bool enabled;
  @override
  final double height;
  final EdgeInsets? padding;
  final TextStyle? textStyle;
  final Widget? child;

  /// Accepted and not carried.
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final Object? mouseCursor;

  @override
  bool represents(T? value) => value == this.value;

  /// What goes before the child; a [CheckedPopupMenuItem] puts its tick here.
  Widget? _leading(BuildContext context) => null;

  @override
  Widget build(BuildContext context) {
    final leading = _leading(context);
    Widget row = Padding(
      padding:
          padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          if (child != null) Expanded(child: child!),
        ],
      ),
    );
    final style = textStyle;
    if (style != null) row = DefaultTextStyle(style: style, child: row);
    return enabled ? row : Opacity(opacity: 0.38, child: row);
  }
}

/// A choice of a popup menu with a tick beside it when [checked].
class CheckedPopupMenuItem<T> extends PopupMenuItem<T> {
  const CheckedPopupMenuItem({
    super.key,
    super.value,
    this.checked = false,
    super.enabled,
    super.padding,
    super.height,
    super.onTap,
    super.child,
  });
  final bool checked;

  @override
  Widget? _leading(BuildContext context) => checked
      ? const Icon(Icons.check, size: 20)
      : const SizedBox(width: 20, height: 20);
}

/// Shows [items] as a menu and completes with the value of the one chosen, or
/// with null when the menu is closed without a choice.
///
/// Flutter anchors the menu at [position]. No platform here has a menu that
/// takes arbitrary rows, so it is a dialog of them - the [SimpleDialog] an app
/// would write by hand - and [position] is accepted and not used. The entry
/// that [PopupMenuEntry.represents] [initialValue] is marked with a tick,
/// where Flutter scrolls the menu to it and highlights it.
Future<T?> showMenu<T>({
  required BuildContext context,
  Object? position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  Color? shadowColor,
  Color? surfaceTintColor,
  String? semanticLabel,
  ShapeBorder? shape,
  Color? color,
  bool useRootNavigator = false,
  BoxConstraints? constraints,
  Clip clipBehavior = Clip.none,
  RouteSettings? routeSettings,
}) async {
  final picked = await _pickFromMenu<T>(
    context,
    items,
    initialValue: initialValue,
    title: semanticLabel,
    routeSettings: routeSettings,
  );
  picked?.onTap?.call();
  return picked?.value;
}

/// The menu itself: a dialog of [items], completing with the entry tapped.
Future<PopupMenuItem<T>?> _pickFromMenu<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> items, {
  T? initialValue,
  String? title,
  RouteSettings? routeSettings,
}) => showDialog<PopupMenuItem<T>>(
  context: context,
  routeSettings: routeSettings,
  builder: (menu) => SimpleDialog(
    title: title == null ? null : Text(title),
    children: [
      for (final entry in items)
        if (entry is PopupMenuItem<T>)
          InkWell(
            onTap: entry.enabled ? () => Navigator.pop(menu, entry) : null,
            child: initialValue != null && entry.represents(initialValue)
                ? Row(
                    children: [
                      Expanded(child: entry),
                      const Icon(Icons.check, size: 20),
                      const SizedBox(width: 8),
                    ],
                  )
                : entry,
          )
        else
          entry,
    ],
  ),
);

/// A button that opens a menu of choices: the three dots of an app bar, or
/// any [child] an app would rather show.
///
/// The menu is [showMenu]'s - a dialog listing the entries, not a card
/// anchored to the button - so the parameters about where the menu goes and
/// what its surface looks like ([offset], [position], [elevation], [shape],
/// [color], [constraints]) are accepted and not carried. What it does is
/// Flutter's: [onOpened] when the menu opens, an entry's own `onTap` and then
/// [onSelected] with its value when one is chosen, [onCanceled] when the menu
/// is closed without a choice. An entry with no value calls only its `onTap`.
class PopupMenuButton<T> extends StatelessWidget {
  const PopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.initialValue,
    this.onOpened,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.padding = const EdgeInsets.all(8),
    this.menuPadding,
    this.splashRadius,
    this.child,
    this.borderRadius,
    this.icon,
    this.iconSize,
    this.offset = Offset.zero,
    this.enabled = true,
    this.shape,
    this.color,
    this.iconColor,
    this.enableFeedback,
    this.constraints,
    this.position,
    this.clipBehavior = Clip.none,
    this.useRootNavigator = false,
    this.routeSettings,
    this.style,
  }) : assert(
         child == null || icon == null,
         'A PopupMenuButton takes a child or an icon, not both.',
       );

  final PopupMenuItemBuilder<T> itemBuilder;

  /// The value whose entry is marked when the menu opens.
  final T? initialValue;
  final VoidCallback? onOpened;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;

  /// What a long press or a screen reader says of the button. Flutter's
  /// default is the localised "Show menu".
  final String? tooltip;

  /// What is tapped to open the menu, in place of the icon button.
  final Widget? child;

  /// The button's icon; three vertical dots when neither this nor [child] is
  /// given.
  final Widget? icon;
  final double? iconSize;
  final Color? iconColor;

  /// False draws the button and opens nothing.
  final bool enabled;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;
  final ButtonStyle? style;
  final RouteSettings? routeSettings;

  /// Accepted and not carried: the menu is a dialog, in the dialog's place
  /// and with the dialog's surface.
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final EdgeInsetsGeometry? menuPadding;
  final double? splashRadius;
  final Offset offset;
  final ShapeBorder? shape;
  final Color? color;
  final bool? enableFeedback;
  final BoxConstraints? constraints;
  final PopupMenuPosition? position;
  final Clip clipBehavior;
  final bool useRootNavigator;

  Future<void> _open(BuildContext context) async {
    final items = itemBuilder(context);
    // Flutter opens nothing for an empty menu, and says nothing either.
    if (items.isEmpty) return;
    onOpened?.call();
    final picked = await _pickFromMenu<T>(
      context,
      items,
      initialValue: initialValue,
      routeSettings: routeSettings,
    );
    if (picked == null) return onCanceled?.call();
    picked.onTap?.call();
    final value = picked.value;
    if (value != null) onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final open = enabled ? () => _open(context) : null;
    final child = this.child;
    if (child != null) {
      return Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          key: key,
          borderRadius: borderRadius,
          onTap: open,
          child: child,
        ),
      );
    }
    // The button's key is the node's id, so a test - or a renderer keeping
    // focus across a rebuild - can address the thing that is tapped.
    return IconButton(
      key: key,
      icon: icon ?? const Icon(Icons.more_vert),
      iconSize: iconSize,
      color: iconColor,
      padding: padding,
      style: style,
      tooltip: tooltip ?? 'Show menu',
      onPressed: open,
    );
  }
}

/// A dialog around anything at all.
class Dialog extends Widget {
  const Dialog({
    super.key,
    this.backgroundColor,
    this.elevation,
    this.insetPadding,
    this.clipBehavior,
    this.shape,
    this.alignment,
    this.child,
  });

  /// A dialog that covers the screen, in Flutter. Here it is the platform's
  /// dialog at the platform's size.
  const Dialog.fullscreen({super.key, this.backgroundColor, this.child})
    : elevation = null,
      insetPadding = EdgeInsets.zero,
      clipBehavior = null,
      shape = null,
      alignment = null;

  final Color? backgroundColor;
  final double? elevation;
  final EdgeInsets? insetPadding;
  final Clip? clipBehavior;
  final ShapeBorder? shape;
  final AlignmentGeometry? alignment;
  final Widget? child;

  @override
  WidgetNode _render(_Owner owner) => _dialogNode(
    owner,
    key: key,
    content: child == null ? const [] : [child!],
  );
}

WidgetNode _dialogNode(
  _Owner owner, {
  required Key? key,
  Widget? title,
  Widget? top,
  List<Widget> content = const [],
  List<Widget> actions = const [],
}) {
  final entry = owner._buildingOverlay;
  final titleText = _stringOf(title, owner);
  // A dialog is as tall as what is in it: its content has no height to fill.
  return owner._withLayout(
    () => UIBuilder.dialog(
      title: titleText,
      content: [
        if (top != null) _renderChild(owner, top, 'icon'),
        if (title != null && titleText == null)
          _renderChild(owner, title, 'title'),
        for (var i = 0; i < content.length; i++)
          owner.inSlot('content$i', () => content[i]._render(owner)),
      ],
      actions: owner.inSlot('actions', () => _renderAll(actions, owner)),
      dismissible: entry?.barrierDismissible ?? true,
      onDismiss: entry == null ? null : () => owner._dismiss(entry, null),
      id: _idOf(key),
    ),
    unboundedHeight: true,
  );
}

// ---------------------------------------------------------------------------
// Routes and the Navigator.
// ---------------------------------------------------------------------------

/// What a route was pushed with: a name and arguments.
class RouteSettings {
  const RouteSettings({this.name, this.arguments});
  final String? name;
  final Object? arguments;
}

/// A page on a [Navigator]'s stack.
abstract class Route<T> {
  Route({RouteSettings? settings})
    : settings = settings ?? const RouteSettings();

  final RouteSettings settings;
  NavigatorState? _navigator;
  final Completer<T?> _popped = Completer<T?>();
  final String _id = 'route_${_nextRouteId++}';

  /// Completes with the value the route was popped with.
  Future<T?> get popped => _popped.future;

  /// The navigator showing this route, while it is on a stack.
  NavigatorState? get navigator => _navigator;

  /// Whether this is the bottom of the stack: the page the app started on.
  bool get isFirst => _navigator == null || _navigator!._isFirst(this);

  /// Whether this is the page on screen.
  bool get isCurrent => _navigator != null && _navigator!._isCurrent(this);

  /// Whether the route is on a stack at all.
  bool get isActive => _navigator != null;

  Widget _buildPage(BuildContext context);
}

int _nextRouteId = 0;

/// A route that covers the screen.
abstract class PageRoute<T> extends ModalRoute<T> {
  PageRoute({super.settings, this.fullscreenDialog = false});

  /// In Flutter, a page that slides up and shows a close button. Here it is a
  /// page like any other.
  final bool fullscreenDialog;

  /// How long the page takes to arrive, and to leave. A renderer moves from
  /// the old page to the new one over this ([RootProps.pageTransition]);
  /// zero shows the page at once.
  Duration get transitionDuration => const Duration(milliseconds: 300);
  Duration get reverseTransitionDuration => transitionDuration;
}

/// A route that blocks what is beneath it - every route here.
abstract class ModalRoute<T> extends Route<T> {
  ModalRoute({super.settings});

  /// The route whose page [context] was built in, or null outside any page.
  static ModalRoute<T>? of<T extends Object?>(BuildContext context) {
    final route = context
        .dependOnInheritedWidgetOfExactType<_RouteScope>()
        ?.route;
    return route is ModalRoute<T> ? route : null;
  }

  /// A predicate that is true of the route named [name], for `popUntil` and
  /// `pushNamedAndRemoveUntil`.
  static RoutePredicate withName(String name) =>
      (route) => route.settings.name == name;

  bool get canPop => !isFirst;

  /// The page, for a route written as Flutter's are: built with its
  /// animation complete, since the move is the renderer's (see
  /// [buildTransitions]). The routes here build theirs another way; a route
  /// of an app's own overrides this.
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => throw UnimplementedError('$runtimeType does not build a page.');

  @override
  Widget _buildPage(BuildContext context) =>
      buildPage(context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation);

  /// What Flutter wraps the page in to animate it on and off the screen.
  ///
  /// The route moves by it where it says something: it is asked what it
  /// does to the page at the start of its animation - how faded, moved,
  /// scaled and turned the [FadeTransition], [SlideTransition],
  /// [ScaleTransition] and [RotationTransition] it returns leave it - and
  /// the renderer moves the page from there to its place as the route
  /// arrives, and the picture of it back there as the route leaves
  /// ([RootProps.pageTransition]). A route that returns the page as it is
  /// leaves the move to the renderer, which slides it in.
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

  /// Whether the page is moved by [buildTransitions] even when it returns
  /// the page as it is - which is then no move at all.
  bool get _ownTransition => false;

  /// How [buildTransitions] leaves the page at the start of its animation
  /// (see [_pageMotion]), or null when the renderer's own move is wanted.
  Map<String, Object>? _motion(BuildContext context, {required bool arriving}) {
    final page = _Probe();
    Widget at(double value) => buildTransitions(
      context,
      _FixedAnimation(
        value,
        arriving ? AnimationStatus.forward : AnimationStatus.reverse,
      ),
      kAlwaysDismissedAnimation,
      page,
    );
    final built = at(0);
    if (identical(built, page) && !_ownTransition) return null;
    final motion = _pageMotion(built, page);
    // A turn is told from where it ends, which need not be upright: a whole
    // turn starts and ends at the same angle, and still turns.
    final ends = _pageMotion(at(1), page)['rotate'];
    if (ends is double) {
      final from = (motion['rotate'] as double? ?? 0) - ends;
      if (from == 0) {
        motion.remove('rotate');
      } else {
        motion['rotate'] = from;
      }
    }
    return motion;
  }
}

/// Stands for the page in a route's transition, to be found again.
class _Probe extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// What the transition widgets from [built] down to [page] do to it, put
/// together: `opacity`, `dx` and `dy` - in parts of the page's own size, as
/// a [SlideTransition] says - `scale` and `rotate` (radians), with only the
/// ones that move anything, and the `curve` the first that names one runs
/// along. Anything else in the way ends the reading there.
Map<String, Object> _pageMotion(Widget built, Widget page) {
  var opacity = 1.0;
  var dx = 0.0;
  var dy = 0.0;
  var scale = 1.0;
  var rotate = 0.0;
  Curve? curve;
  Widget? at = built;
  for (
    var depth = 0;
    at != null && !identical(at, page) && depth < 64;
    depth++
  ) {
    switch (at) {
      case final FadeTransition fade:
        opacity *= fade.opacity.value.clamp(0.0, 1.0);
        curve ??= _curveIn(fade.opacity);
        at = fade.child;
      case final SlideTransition slide:
        final offset = slide.position.value;
        dx += slide.textDirection == TextDirection.rtl ? -offset.dx : offset.dx;
        dy += offset.dy;
        curve ??= _curveIn(slide.position);
        at = slide.child;
      case final ScaleTransition grow:
        scale *= grow.scale.value;
        curve ??= _curveIn(grow.scale);
        at = grow.child;
      case final RotationTransition turn:
        rotate += turn.turns.value * 2 * math.pi;
        curve ??= _curveIn(turn.turns);
        at = turn.child;
      case final Opacity faded:
        opacity *= faded.opacity;
        at = faded.child;
      default:
        at = null;
    }
  }
  return {
    if (opacity != 1) 'opacity': opacity,
    if (dx != 0) 'dx': dx,
    if (dy != 0) 'dy': dy,
    if (scale != 1) 'scale': scale,
    if (rotate != 0) 'rotate': rotate,
    if (curve != null) 'curve': curve.name,
  };
}

/// A page built by [builder]. Flutter slides it in with the platform's
/// transition; here the page is simply shown.
class MaterialPageRoute<T> extends PageRoute<T> {
  MaterialPageRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
  });
  final WidgetBuilder builder;

  /// Flutter keeps a covered route's state in memory or not; here the pages
  /// beneath always keep theirs.
  final bool maintainState;

  @override
  Widget _buildPage(BuildContext context) => builder(context);
}

/// Flutter's iOS-styled page route; a [MaterialPageRoute] by another name
/// here, where the platform draws the page.
class CupertinoPageRoute<T> extends MaterialPageRoute<T> {
  CupertinoPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });
}

/// Builds a route's page. The two animations stand still - the first
/// complete, the second not begun: the transition is the renderer's.
typedef RoutePageBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    );

/// Wraps a page in the transition widgets it moves by - see
/// [ModalRoute.buildTransitions].
typedef RouteTransitionsBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    );

/// A page with a transition of its own: [transitionsBuilder] wraps the page
/// in the transition widgets it moves by (see [ModalRoute.buildTransitions]),
/// over [transitionDuration] as it arrives and [reverseTransitionDuration]
/// as it leaves. Without one, as in Flutter, the page does not move - it is
/// simply there.
class PageRouteBuilder<T> extends PageRoute<T> {
  PageRouteBuilder({
    super.settings,
    required this.pageBuilder,
    this.transitionsBuilder,
    this.transitionDuration = const Duration(milliseconds: 300),
    this.reverseTransitionDuration = const Duration(milliseconds: 300),
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.maintainState = true,
    super.fullscreenDialog,
  });
  final RoutePageBuilder pageBuilder;
  final RouteTransitionsBuilder? transitionsBuilder;
  @override
  final Duration transitionDuration;
  @override
  final Duration reverseTransitionDuration;
  final bool opaque;
  final bool barrierDismissible;
  final Color? barrierColor;
  final bool maintainState;

  @override
  Widget _buildPage(BuildContext context) => pageBuilder(
    context,
    kAlwaysCompleteAnimation,
    kAlwaysDismissedAnimation,
  );

  @override
  bool get _ownTransition => true;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      transitionsBuilder?.call(context, animation, secondaryAnimation, child) ??
      child;
}

/// The page the app started on, as a route - so `route.isFirst` has something
/// to be true of.
class _BaseRoute extends ModalRoute<Object?> {
  _BaseRoute(this.child) : super(settings: const RouteSettings(name: '/'));
  Widget child;

  /// The named route on screen and the arguments it was reached with, in an
  /// app with `MaterialApp(routes:)`; `/` otherwise.
  @override
  RouteSettings get settings {
    final owner = _navigator?._owner;
    // A named page kept beneath the one on screen is still its own route.
    final entry = owner?._namedEntry ?? owner?.routerNav?.router.state.current;
    if (entry == null) return super.settings;
    return RouteSettings(name: entry.path, arguments: _namedArguments[entry]);
  }

  @override
  Widget _buildPage(BuildContext context) => child;
}

/// What a named route was pushed with, for `ModalRoute.of(context).settings`.
final Expando<Object> _namedArguments = Expando<Object>('route arguments');

/// A place in the named history, as the route a [RoutePredicate] is asked
/// about.
class _HistoryRoute extends ModalRoute<Object?> {
  _HistoryRoute(RouteEntry entry)
    : super(
        settings: RouteSettings(
          name: entry.path,
          arguments: _namedArguments[entry],
        ),
      );
  @override
  Widget _buildPage(BuildContext context) => const SizedBox.shrink();
}

/// Has a say in whether the page it is on may be left, and hears when it is:
/// Flutter's `PopScope`.
///
/// With [canPop] false, the back gesture - Android's button, the iOS edge
/// swipe, the browser's Back - an app bar's back arrow and
/// `Navigator.maybePop` leave the page where it is and call
/// [onPopInvokedWithResult] with `didPop` false, which is where a screen
/// asks "discard your changes?" and pops itself if the answer is yes.
/// `Navigator.pop` is the app saying go, and goes whatever [canPop] says, as
/// in Flutter. On an app's first screen a refused back gesture keeps the app
/// open instead of closing it.
///
/// When the page is popped - by a [Navigator], a `GoRouter` or the named
/// routes - [onPopInvokedWithResult] is called with `didPop` true and what
/// it was popped with.
///
/// A dialog is not a page here: one that should not close on Back is
/// `barrierDismissible: false`.
class PopScope<T> extends Widget {
  const PopScope({
    super.key,
    required this.child,
    this.canPop = true,
    this.onPopInvokedWithResult,
    this.onPopInvoked,
  });

  final Widget child;

  /// Whether the page may be left by the back gesture and `maybePop`.
  final bool canPop;

  /// Called after a pop was asked for: `didPop` says whether it happened.
  final void Function(bool didPop, T? result)? onPopInvokedWithResult;

  /// Flutter's older spelling of [onPopInvokedWithResult], without the result.
  final void Function(bool didPop)? onPopInvoked;

  void _invoked(bool didPop, Object? result) {
    onPopInvokedWithResult?.call(didPop, result is T ? result : null);
    onPopInvoked?.call(didPop);
  }

  /// For a router: says that the page it was showing has been popped with
  /// [result], so the scopes on that page hear it. Called before the page is
  /// rebuilt away. `GoRouter` and the named routes call it; a router of an
  /// app's own does the same from its `pop`.
  static void notifyPopped(BuildContext context, [Object? result]) =>
      _ownerOf(context)._notifyRouterPagePopped(result);

  @override
  WidgetNode _render(_Owner owner) {
    owner._popScopes.add(
      _PopEntry(
        this,
        owner._inherited<_RouteScope>()?.route,
        onStage: owner._hidden == 0,
      ),
    );
    return _renderChild(owner, child);
  }
}

/// Asks before the page it is on is left: Flutter's `WillPopScope`, which
/// [PopScope] replaced and older screens still use.
///
/// With an [onWillPop], the back gesture, an app bar's back arrow and
/// `Navigator.maybePop` call it and leave the page only if it answers true.
/// With none, the page is left as usual. `Navigator.pop` goes without
/// asking, as in Flutter.
///
/// One thing it cannot do: on an app's first screen, where Flutter would
/// close the app on a true, the app stays open. The gesture has to be
/// answered before the question is, and by then it is too late to hand it
/// back to the platform. A first screen that should close on Back uses
/// `PopScope(canPop: true)`, or no scope at all.
class WillPopScope extends StatelessWidget {
  const WillPopScope({super.key, required this.child, required this.onWillPop});

  final Widget child;

  /// Whether the page may be left; asked each time something tries.
  final Future<bool> Function()? onWillPop;

  @override
  Widget build(BuildContext context) {
    final ask = onWillPop;
    return PopScope<Object?>(
      canPop: ask == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || ask == null) return;
        if (await ask() && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

/// A [PopScope] the build came across: the page it is on, and whether that
/// page is the one showing.
class _PopEntry {
  const _PopEntry(this.scope, this.route, {required this.onStage});
  final PopScope<dynamic> scope;
  final Route<dynamic>? route;
  final bool onStage;
}

/// The route a page is being built in.
class _RouteScope extends InheritedWidget {
  const _RouteScope({required this.route, required super.child});
  final Route<dynamic> route;

  @override
  bool updateShouldNotify(_RouteScope oldWidget) =>
      !identical(oldWidget.route, route);
}

/// Decides whether `popUntil` has gone far enough.
typedef RoutePredicate = bool Function(Route<dynamic> route);

/// Moves between pages, like Flutter's `Navigator`.
///
/// `Navigator.of(context)` answers the nearest one. A [MaterialApp] has one,
/// and so does the app's root, which is why pushing a page works from a
/// widget tree with no `MaterialApp` in it at all.
///
/// A pushed page replaces what its navigator shows. The pages beneath are
/// still built - their nodes thrown away - so each keeps its `State` and is
/// exactly as it was when the page above is popped. `push` answers with a
/// future that completes with the value given to `pop`, and the platform's
/// back gesture pops as the back button would.
class Navigator extends StatefulWidget {
  const Navigator._({super.key, required this.child});

  /// The first page: the app's home, or its router.
  final Widget child;

  /// The nearest navigator above [context].
  static NavigatorState of(BuildContext context, {bool rootNavigator = false}) {
    final owner = _ownerOf(context);
    final nearest = rootNavigator
        ? null
        : context.findAncestorStateOfType<NavigatorState>();
    // A context from above every navigator - the one a test hands to
    // showDialog, say - still means the app's own.
    return nearest ?? owner._navigators.firstOrNull ?? NavigatorState._detached(owner);
  }

  static NavigatorState? maybeOf(
    BuildContext context, {
    bool rootNavigator = false,
  }) => of(context, rootNavigator: rootNavigator);

  static Future<T?> push<T extends Object?>(
    BuildContext context,
    Route<T> route,
  ) => of(context).push<T>(route);

  static Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    BuildContext context,
    Route<T> newRoute, {
    TO? result,
  }) => of(context).pushReplacement<T, TO>(newRoute, result: result);

  static Future<T?> pushAndRemoveUntil<T extends Object?>(
    BuildContext context,
    Route<T> newRoute,
    RoutePredicate predicate,
  ) => of(context).pushAndRemoveUntil<T>(newRoute, predicate);

  static Future<T?> pushNamed<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) => of(context).pushNamed<T>(routeName, arguments: arguments);

  static Future<T?> pushReplacementNamed<
    T extends Object?,
    TO extends Object?
  >(
    BuildContext context,
    String routeName, {
    TO? result,
    Object? arguments,
  }) => of(context).pushReplacementNamed<T, TO>(
    routeName,
    result: result,
    arguments: arguments,
  );

  static Future<T?> pushNamedAndRemoveUntil<T extends Object?>(
    BuildContext context,
    String newRouteName,
    RoutePredicate predicate, {
    Object? arguments,
  }) => of(context).pushNamedAndRemoveUntil<T>(
    newRouteName,
    predicate,
    arguments: arguments,
  );

  static Future<T?> popAndPushNamed<T extends Object?, TO extends Object?>(
    BuildContext context,
    String routeName, {
    TO? result,
    Object? arguments,
  }) => of(context).popAndPushNamed<T, TO>(
    routeName,
    result: result,
    arguments: arguments,
  );

  static void pop<T extends Object?>(BuildContext context, [T? result]) =>
      of(context).pop<T>(result);

  static Future<bool> maybePop<T extends Object?>(
    BuildContext context, [
    T? result,
  ]) => of(context).maybePop<T>(result);

  static bool canPop(BuildContext context) => of(context).canPop();

  static void popUntil(BuildContext context, RoutePredicate predicate) =>
      of(context).popUntil(predicate);

  @override
  NavigatorState createState() => NavigatorState();
}

class NavigatorState extends State<Navigator> {
  NavigatorState();

  /// For a context no navigator is above and an app that has not built one:
  /// overlays and the named router still work through it.
  NavigatorState._detached(_Owner owner) {
    _owner = owner;
  }

  /// The pages pushed over the first, oldest first.
  final List<Route<dynamic>> _routes = [];

  /// The first page, as a route.
  late final _BaseRoute _base = _BaseRoute(const SizedBox.shrink())
    .._navigator = this;

  /// True once `pushReplacement` has replaced the first page itself: what the
  /// app started on is then gone, and the oldest pushed page is the first.
  bool _baseReplaced = false;

  _Owner get _host => _owner!;

  bool _isFirst(Route<dynamic> route) => _baseReplaced
      ? (_routes.isNotEmpty && identical(_routes.first, route))
      : identical(route, _base);

  bool _isCurrent(Route<dynamic> route) =>
      identical(_routes.isEmpty ? _base : _routes.last, route);

  /// Shows [route] over the page on screen. The future completes when it is
  /// popped, with the value it was popped with.
  Future<T?> push<T extends Object?>(Route<T> route) {
    _host._closeDrawers();
    route._navigator = this;
    _routes.add(route);
    _host._requestRebuild();
    return route.popped;
  }

  /// Shows [newRoute] in place of the page on screen, whose future completes
  /// with [result].
  Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    Route<T> newRoute, {
    TO? result,
  }) {
    if (_routes.isEmpty) {
      _baseReplaced = true;
    } else {
      _complete(_routes.removeLast(), result);
    }
    return push<T>(newRoute);
  }

  /// Shows [newRoute] after popping every page until [predicate] is true.
  Future<T?> pushAndRemoveUntil<T extends Object?>(
    Route<T> newRoute,
    RoutePredicate predicate,
  ) {
    while (_routes.isNotEmpty && !predicate(_routes.last)) {
      _complete(_routes.removeLast(), null);
    }
    if (_routes.isEmpty && !_baseReplaced && !predicate(_base)) {
      _baseReplaced = true;
    }
    return push<T>(newRoute);
  }

  /// Navigates the routed [MaterialApp] to a named route (a path, which may
  /// carry parameters).
  ///
  /// The named routes are a history of their own beneath the pages pushed
  /// with [push] - it is what the browser's address bar and the platform's
  /// back gesture follow. So a named route asked for while a pushed page is
  /// on screen is pushed over it as a page, where it can be seen, and the
  /// future completes with what it is popped with; one asked for from a named
  /// route moves the history, and the future completes when that page is
  /// popped, with what it was popped with - null when it was the platform's
  /// back gesture or the browser's button that did it.
  Future<T?> pushNamed<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) async {
    _host._closeDrawers();
    if (_routes.isNotEmpty || _host.routerNav == null) {
      final route = _namedRoute<T>(routeName, arguments);
      if (route != null) return push<T>(route);
    }
    return _whenNamedPopped<T>(await _navigateNamed(routeName, arguments));
  }

  /// What the named page [entry] is popped with, once it is.
  Future<T?> _whenNamedPopped<T extends Object?>(RouteEntry? entry) async {
    if (entry == null) return null;
    final popped = _namedWaiting[entry] ??= Completer<Object?>();
    return (await popped.future) as T?;
  }

  /// The named pages somebody is waiting to hear the end of, and the one
  /// that was just popped by name with what it was popped with.
  final Map<RouteEntry, Completer<Object?>> _namedWaiting = {};
  RouteEntry? _poppedEntry;
  Object? _poppedResult;

  /// Answers whoever pushed a named page that is no longer on the way to the
  /// one on screen.
  void _settleNamed() {
    if (_namedWaiting.isEmpty) return;
    final state = _host.routerNav?.router.state;
    final live = state == null
        ? const <RouteEntry>[]
        : state.history.sublist(0, state.index + 1);
    _namedWaiting.removeWhere((entry, popped) {
      if (live.any((kept) => identical(kept, entry))) return false;
      popped.complete(identical(entry, _poppedEntry) ? _poppedResult : null);
      return true;
    });
    _poppedEntry = null;
    _poppedResult = null;
  }

  /// Shows the named route in place of the page on screen, whose future
  /// completes with [result].
  Future<T?> pushReplacementNamed<T extends Object?, TO extends Object?>(
    String routeName, {
    TO? result,
    Object? arguments,
  }) async {
    _host._closeDrawers();
    final nav = _host.routerNav;
    // A page pushed over another pushed page, or over a first page that is
    // not a named route: the new one takes its place on the same stack.
    if (nav == null || _baseReplaced || _routes.length > 1) {
      final route = _namedRoute<T>(routeName, arguments);
      if (route == null) return null;
      return pushReplacement<T, TO>(route, result: result);
    }
    if (_routes.isNotEmpty) {
      // The one pushed page goes, and the named history gains the route.
      _complete(_routes.removeLast(), result);
      _host._requestRebuild();
      return _whenNamedPopped<T>(await _navigateNamed(routeName, arguments));
    }
    _poppedEntry = nav.router.state.current;
    _poppedResult = result;
    return _whenNamedPopped<T>(
      await _moveNamed(arguments, (nav) async {
        final replaced = nav.router.state.current;
        nav.router.replaceWith(
          routeName,
          params: arguments is Map<String, dynamic> ? arguments : null,
        );
        return !identical(nav.router.state.current, replaced);
      }),
    );
  }

  /// Shows the named route after removing every page until [predicate] is
  /// true of one - `(route) => false` removes them all, which leaves the new
  /// page with nothing to go back to.
  Future<T?> pushNamedAndRemoveUntil<T extends Object?>(
    String newRouteName,
    RoutePredicate predicate, {
    Object? arguments,
  }) async {
    _host._closeDrawers();
    final nav = _host.routerNav;
    var removed = false;
    while (_routes.isNotEmpty && !predicate(_routes.last)) {
      _complete(_routes.removeLast(), null);
      removed = true;
    }
    if (removed) _host._requestRebuild();
    if (nav == null || _baseReplaced || _routes.isNotEmpty) {
      final route = _namedRoute<T>(newRouteName, arguments);
      if (route == null) return null;
      if (_routes.isEmpty && !_baseReplaced && !predicate(_base)) {
        _baseReplaced = true;
      }
      return push<T>(route);
    }
    return _whenNamedPopped<T>(
      await _moveNamed(
        arguments,
        (nav) => nav.router.navigateAndRemoveUntil(
          newRouteName,
          (entry) => predicate(_HistoryRoute(entry)),
          params: arguments is Map<String, dynamic> ? arguments : null,
        ),
      ),
    );
  }

  /// Pops the page on screen and shows the named route.
  Future<T?> popAndPushNamed<T extends Object?, TO extends Object?>(
    String routeName, {
    TO? result,
    Object? arguments,
  }) {
    pop<TO>(result);
    return pushNamed<T>(routeName, arguments: arguments);
  }

  /// Moves the named history to [routeName] and answers the entry it made,
  /// or null when it did not move.
  Future<RouteEntry?> _navigateNamed(String routeName, Object? arguments) =>
      _moveNamed(
        arguments,
        (nav) => nav.navigate(
          routeName,
          params: arguments is Map<String, dynamic> ? arguments : null,
        ),
      );

  /// Runs [move] on the named history and answers the entry it arrived at,
  /// or null when it did not move. The entry has its [arguments] from the
  /// moment it exists: the page is built as the history changes, and reads
  /// them in that first build.
  Future<RouteEntry?> _moveNamed(
    Object? arguments,
    Future<bool> Function(NavigationApp nav) move,
  ) async {
    final nav = _host.routerNav;
    if (nav == null) return null;
    RouteEntry? made;
    void note(RouterEvent event) {
      made = event.to;
      _namedArguments[event.to] = arguments;
    }

    // First among the listeners: the one that rebuilds comes after.
    nav.router.listeners.insert(0, note);
    try {
      if (!await move(nav)) return null;
    } finally {
      nav.router.listeners.remove(note);
    }
    return made;
  }

  /// The named route [name] of the [MaterialApp] above as a page to push, or
  /// null when the app has no route of exactly that name.
  Route<T>? _namedRoute<T>(String name, Object? arguments) {
    final builder = _host._namedRoutes?[name];
    if (builder == null) return null;
    return MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: arguments),
      builder: (context) {
        if (builder is Widget Function(BuildContext)) return builder(context);
        if (builder is Widget Function(BuildContext, Map<String, dynamic>)) {
          return builder(
            context,
            arguments is Map<String, dynamic> ? arguments : const {},
          );
        }
        throw ArgumentError(
          'The route "$name" must be a (context) => Widget or a '
          '(context, params) => Widget.',
        );
      },
    );
  }

  /// Closes the topmost dialog or sheet if one is open; otherwise pops the
  /// page on screen, completing its `push` future with [result]; otherwise
  /// steps the named router back.
  void pop<T extends Object?>([T? result]) {
    final host = _host;
    if (host._overlays.isNotEmpty) {
      host.popOverlay(result);
      return;
    }
    if (_popRoute(result)) return;
    final router = host._router;
    if (router != null && router.canPop()) {
      router.pop<T>(result);
      return;
    }
    _poppedEntry = host.routerNav?.router.state.current;
    _poppedResult = result;
    host.routerNav?.goBack();
  }

  /// Pops if there is something to pop and the page allows it, and says
  /// whether the request was dealt with - which it was, as in Flutter, when
  /// a [PopScope] refused it.
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    if (_host._refusePop()) return true;
    if (!canPop() && _host._overlays.isEmpty) return false;
    pop<T>(result);
    return true;
  }

  /// Whether there is a page to go back to.
  bool canPop() =>
      (_baseReplaced ? _routes.length > 1 : _routes.isNotEmpty) ||
      (_host._router?.canPop() ?? false) ||
      (_host.routerNav?.router.state.canGoBack ?? false);

  /// Pops pages until [predicate] is true of the one on screen.
  void popUntil(RoutePredicate predicate) {
    var popped = false;
    while (_routes.length > (_baseReplaced ? 1 : 0) &&
        !predicate(_routes.last)) {
      _host._notifyPopped(_routes.last, null);
      _complete(_routes.removeLast(), null);
      popped = true;
    }
    if (popped) _host._requestRebuild();
  }

  bool _popRoute(Object? result) {
    if (_routes.length <= (_baseReplaced ? 1 : 0)) return false;
    _host._notifyPopped(_routes.last, result);
    _complete(_routes.removeLast(), result);
    _host._requestRebuild();
    return true;
  }

  void _complete(Route<dynamic> route, Object? result) {
    route._navigator = null;
    if (!route._popped.isCompleted) route._popped.complete(result);
  }

  // What the named router answers, kept from before there were pages.
  String get currentPath => _host.routerNav?.currentPath ?? '/';
  List<String> get history => _host.routerNav?.history ?? const [];
  bool get canGoBack => _host.routerNav?.router.state.canGoBack ?? false;
  bool get canGoForward => _host.routerNav?.router.state.canGoForward ?? false;

  @override
  void dispose() {
    for (final route in _routes) {
      _complete(route, null);
    }
    _routes.clear();
    for (final popped in _namedWaiting.values) {
      popped.complete(null);
    }
    _namedWaiting.clear();
  }

  /// The page the last build showed, and how many were under it.
  Route<dynamic>? _shownTop;
  int _shownDepth = 0;

  /// The named route the last build showed, and how far along the way it
  /// was - its place, not the length: a push after going back cuts off what
  /// was ahead and leaves the way as long as it was.
  Object? _shownEntry;
  int _shownTrail = 0;

  /// Tells the renderer when the page on top is not the one it drew last:
  /// pushed if the stack grew, popped if it shrank, swapped otherwise.
  void _noteTransition(_Owner owner, List<Route<dynamic>> pages) {
    final top = pages.lastOrNull;
    final before = _shownTop;
    final depth = _shownDepth;
    _shownTop = top;
    _shownDepth = pages.length;
    // A named route is the first page showing something else: the page is
    // the same route, and what tells one from another is the router's entry.
    final router = _host.routerNav;
    final entry = router?.router.state.current;
    final entryBefore = _shownEntry;
    final trail = router?.router.state.index ?? 0;
    final trailBefore = _shownTrail;
    _shownEntry = entry;
    _shownTrail = trail;
    if (before != null &&
        identical(before, top) &&
        top is _BaseRoute &&
        entryBefore != null &&
        !identical(entryBefore, entry)) {
      owner._pageTransition = {
        'kind': trail > trailBefore
            ? 'push'
            : trail < trailBefore
            ? 'pop'
            : 'fade',
        'ms': 300,
      };
      return;
    }
    if (before == null || top == null || identical(before, top)) return;
    final pushed = pages.length > depth;
    final popped = pages.length < depth;
    // The page that moves is the one whose time it is: arriving, the new
    // one's; leaving, the old one's way back.
    final time = popped
        ? (before is PageRoute ? before.reverseTransitionDuration : null)
        : (top is PageRoute ? top.transitionDuration : null);
    final ms = (time ?? const Duration(milliseconds: 300)).inMilliseconds;
    if (ms <= 0) return;
    // A route with a transition of its own moves by it: the arriving page
    // from where it starts, the leaving one's picture back there.
    final moving = popped ? before : top;
    final motion = moving is ModalRoute
        ? moving._motion(owner._context(), arriving: !popped)
        : null;
    owner._pageTransition = {
      'kind': pushed ? 'push' : popped ? 'pop' : 'fade',
      'ms': ms,
      if (motion != null) popped ? 'picture' : 'page': motion,
    };
  }

  Widget _page(Route<dynamic> route) => _RouteScope(
    route: route,
    child: Builder(builder: route._buildPage),
  );

  @override
  Widget build(BuildContext context) => _NodeWidget((owner) {
    owner._navigators.add(this);
    _settleNamed();
    _base.child = widget.child;
    final pages = [if (!_baseReplaced) _base, ..._routes];
    if (owner._hidden == 0) _noteTransition(owner, pages);
    WidgetNode? shown;
    for (final (index, route) in pages.indexed) {
      // Each page has its own keys: the same screen twice on the stack is
      // two screens.
      owner._withKeyScope(route._id, () {
        if (index == pages.length - 1) {
          shown = owner.inSlot(route._id, () => _page(route)._render(owner));
        } else {
          owner._offstage(route._id, _page(route));
        }
      });
    }
    return shown ?? UIBuilder.sizedBox();
  });
}

// ---------------------------------------------------------------------------
// App scaffolding.
// ---------------------------------------------------------------------------

/// Builds the page for a named route, given its parameters (e.g. the `:id` in
/// `/users/:id`).
typedef RouteWidgetBuilder =
    Widget Function(BuildContext context, Map<String, dynamic> params);

/// For a router: says that the page the build in progress shows is another
/// one from the last, and how it was reached - `'push'`, `'pop'` or `'fade'`
/// ([RootProps.pageTransition]) - so the renderer moves from the one to the
/// other. A [Navigator] says so for its own pages; a [RouterConfig] that
/// swaps what it builds calls this from its `build`, once, on the first
/// build of the new page. Outside a build it does nothing.
void announcePageTransition(
  BuildContext context,
  String kind, {
  Duration duration = const Duration(milliseconds: 300),
}) {
  if (context is! _Context || duration <= Duration.zero) return;
  final owner = context._owner;
  if (!owner._building || owner._hidden > 0) return;
  owner._pageTransition ??= {'kind': kind, 'ms': duration.inMilliseconds};
}

/// What decides the page a `MaterialApp.router` shows.
///
/// One method has to be written: build the current page. A router package
/// implements it - it owns its own location, history and back handling, and
/// asks for a rebuild (through a [Listenable] its page listens to, or
/// `setState`) when the location changes. Pages pushed with [Navigator] sit
/// above whatever it builds.
///
/// [canPop] and [pop] are how `Navigator.of(context).pop()` reaches the
/// router's own stack of pages: with no dialog open and no page pushed on the
/// navigator itself, a pop goes to the router. A router with no stack leaves
/// them as they are.
abstract class RouterConfig {
  const RouterConfig();

  /// The page to show now.
  Widget build(BuildContext context);

  /// Whether the router has a page of its own to go back from.
  bool canPop() => false;

  /// Goes back one page of the router's own, handing [result] to whoever
  /// pushed it.
  void pop<T extends Object?>([T? result]) {}
}

/// The app shell. Pass [home] for a single-screen app, [routes] (and
/// [initialRoute]) for named ones - `Navigator.of(context).pushNamed` then
/// moves between them, the history stack and the platform back gesture come
/// with it - or use [MaterialApp.router] with a router package.
///
/// **Themes.** [theme], [darkTheme] and [themeMode] decide what
/// `Theme.of(context)` answers: the dark theme when the mode is dark, or when
/// it is `system` and the device is dark. That is what the widgets composed
/// here - chips, list tiles, cards with a colour - are drawn with. The
/// platform's own chrome is coloured by the renderers from the `AppTheme`
/// handed to [runApp] at start-up, before any widget is built, so an app with
/// a theme passes it to both:
///
/// ```dart
/// runApp(
///   MaterialApp(theme: light, darkTheme: dark, home: const Home()),
///   appTheme: light.toAppTheme(dark: dark),
/// );
/// ```
///
/// **Routes.** With [routes], [home] is the route named `/` unless the map
/// has one of its own. A route builder is Flutter's `(context) => Page()`.
/// One that takes a second parameter is given the path's parameters as a
/// map, which is how a route like `/users/:id` reads its id.
///
/// **Localisation.** [locale] and [supportedLocales] decide
/// `Localizations.localeOf(context)`. Of the [localizationsDelegates], the
/// ones that are this library's [LocalizationsDelegate] are loaded for that
/// locale and answer `Localizations.of<T>(context, T)`; Flutter's own -
/// `GlobalMaterialLocalizations.delegates` and the like, which localise
/// Flutter's widgets - are accepted and passed over, there being no Material
/// strings to localise here. The framework's own table is `I18n` - see [Tr].
class MaterialApp extends StatefulWidget {
  const MaterialApp({
    super.key,
    this.navigatorKey,
    this.scaffoldMessengerKey,
    this.home,
    this.routes,
    this.initialRoute,
    this.builder,
    this.title,
    this.onGenerateTitle,
    this.color,
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.localizationsDelegates,
    this.supportedLocales = const <Locale>[Locale('en', 'US')],
    this.debugShowCheckedModeBanner = true,
  }) : routerConfig = null;

  /// An app whose pages are decided by [routerConfig].
  const MaterialApp.router({
    super.key,
    this.scaffoldMessengerKey,
    required RouterConfig this.routerConfig,
    this.builder,
    this.title,
    this.onGenerateTitle,
    this.color,
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.localizationsDelegates,
    this.supportedLocales = const <Locale>[Locale('en', 'US')],
    this.debugShowCheckedModeBanner = true,
  }) : navigatorKey = null,
       home = null,
       routes = null,
       initialRoute = null;

  final GlobalKey<NavigatorState>? navigatorKey;

  /// Accepted for Flutter's signature; `ScaffoldMessenger.of(context)` is the
  /// way to a snackbar here.
  final Key? scaffoldMessengerKey;
  final Widget? home;

  /// The named routes: each a `(context) => Widget`, or a
  /// `(context, params) => Widget` for a path with parameters.
  final Map<String, Function>? routes;
  final String? initialRoute;
  final RouterConfig? routerConfig;

  /// Wraps every page: the place for something that has to sit above the
  /// navigator.
  final TransitionBuilder? builder;

  /// Accepted and not used: the window's title is `runApp(title:)`, which
  /// the platform host needs before the first build.
  final String? title;
  final String Function(BuildContext context)? onGenerateTitle;
  final Color? color;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode themeMode;
  final Locale? locale;

  /// The app's string loaders - see the class doc. Typed loosely so a list
  /// that also holds Flutter's own delegates is accepted as written.
  final Iterable<Object>? localizationsDelegates;
  final Iterable<Locale> supportedLocales;

  /// Accepted and unused: there is no banner to hide.
  final bool debugShowCheckedModeBanner;

  @override
  State<MaterialApp> createState() => _MaterialAppState();
}

class _MaterialAppState extends State<MaterialApp> {
  NavigationApp? _nav;
  _Owner? _renderOwner;

  /// A number for each entry of the named history, to keep its page by.
  final Expando<int> _entryIds = Expando<int>('named page');
  int _entries = 0;

  /// What the delegates loaded, and the locale and delegates they loaded it
  /// for. Kept while a newer load is under way, so a change of language shows
  /// the old strings until the new ones are there rather than none.
  Map<Type, Object?> _resources = const {};
  Locale? _loadedFor;
  List<LocalizationsDelegate<dynamic>> _loadedWith = const [];
  int _loads = 0;

  /// Starts loading the app's delegates for [locale] unless that is what is
  /// loaded, or loading, already.
  void _ensureLocalizations(Locale locale) {
    final delegates = [
      ...?widget.localizationsDelegates
          ?.whereType<LocalizationsDelegate<dynamic>>(),
    ];
    var stale = locale != _loadedFor || delegates.length != _loadedWith.length;
    for (var i = 0; !stale && i < delegates.length; i++) {
      final now = delegates[i];
      final before = _loadedWith[i];
      stale =
          now.runtimeType != before.runtimeType ||
          (!identical(now, before) && now.shouldReload(before));
    }
    if (!stale) return;
    _loadedFor = locale;
    _loadedWith = delegates;
    final load = ++_loads;
    // The first delegate of a type that supports the locale is the one that
    // answers for it, as in Flutter.
    final chosen = <Type, LocalizationsDelegate<dynamic>>{};
    for (final delegate in delegates) {
      if (chosen.containsKey(delegate.type)) continue;
      if (delegate.isSupported(locale)) chosen[delegate.type] = delegate;
    }
    if (chosen.isEmpty) {
      _resources = const {};
      return;
    }
    Future.wait([
      for (final delegate in chosen.values)
        // One delegate failing leaves its type unanswered, not the rest.
        delegate.load(locale).then<Object?>((value) => value).catchError((
          Object _,
        ) {
          return null;
        }),
    ]).then((loaded) {
      if (load != _loads || !mounted) return;
      setState(() {
        _resources = {
          for (final (index, type) in chosen.keys.indexed)
            if (loaded[index] != null) type: loaded[index],
        };
      });
    });
  }

  /// The named routes, with [MaterialApp.home] as `/` when the app gave a
  /// home beside its routes and no `/` among them - as Flutter reads the two.
  Map<String, Function>? _routeTable;

  @override
  void initState() {
    final named = widget.routes;
    if (named == null || named.isEmpty) return;
    final routes = <String, Function>{
      if (widget.home != null && !named.containsKey('/'))
        '/': (BuildContext _) => widget.home ?? const SizedBox.shrink(),
      ...named,
    };
    _routeTable = routes;
    var builder = NavigationAppBuilder();
    routes.forEach((path, routeBuilder) {
      builder = builder.addRoute(
        path: path,
        name: path,
        builder: (params) {
          final owner = _renderOwner!;
          return owner.inSlot('route:$path', () {
            final context = owner._context();
            final Widget page;
            if (routeBuilder is Widget Function(BuildContext)) {
              page = routeBuilder(context);
            } else if (routeBuilder
                is Widget Function(BuildContext, Map<String, dynamic>)) {
              page = routeBuilder(context, params);
            } else {
              throw ArgumentError(
                'The route "$path" must be a (context) => Widget or a '
                '(context, params) => Widget.',
              );
            }
            return page._render(owner);
          });
        },
      );
    });
    final nav = builder.setInitialPath(widget.initialRoute ?? '/').build();
    nav.router.onRouteChange((event) {
      // Before the rebuild, which is when the page that was popped goes.
      if (event.type == 'pop') _owner?._notifyRouterPagePopped(null);
      if (mounted) setState(() {});
    });
    // Into the platform's history, where it keeps one: in a browser each
    // named route is an entry and a fragment in the URL, so Back pops a page
    // instead of leaving the site.
    final history =
        HistoryAdapter.platform ?? platform_binding.platformHistory();
    // Read before binding, which writes the first route over it.
    final asked = history.currentPath;
    nav.bindSystemBack(adapter: history);
    _nav = nav;
    // A reload, or a link straight to a page: that page, over the first
    // one, so Back from it is the app's first screen - as Flutter builds it.
    if (asked != null &&
        asked != nav.router.currentPath &&
        nav.router.config.findByPath(asked) != null) {
      unawaited(nav.router.navigate(asked));
    }
  }

  @override
  void dispose() => _nav?.unbindSystemBack();

  /// The theme to show, from the three the app may have given.
  ThemeData? _theme(_Owner owner) {
    final light = widget.theme;
    final dark = widget.darkTheme;
    final wantsDark = switch (widget.themeMode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        _mediaOf(owner).platformBrightness == Brightness.dark,
    };
    // An app that declared neither keeps the theme above it: the palette
    // handed to runApp.
    if (wantsDark) return dark ?? light;
    return light;
  }

  @override
  Widget build(BuildContext context) => _NodeWidget((owner) {
    final nav = _nav;
    final router = widget.routerConfig;
    final Widget first;
    // Only an app with routes of its own says so: a MaterialApp nested in
    // one of another's pages has none, and must not take the outer's away.
    if (_routeTable != null) owner._namedRoutes = _routeTable;
    if (nav != null) {
      owner.routerNav = nav;
      _renderOwner = owner;
      // The current route's node, built inside this build's binding scope -
      // and under it the ones on the way there, built only to keep what
      // they hold: a page that is gone back to is as it was left.
      first = _NodeWidget((owner) {
        final state = nav.router.state;
        final outer = owner._namedEntry;
        WidgetNode? shown;
        try {
          for (var i = 0; i <= state.index; i++) {
            final entry = state.history[i];
            final id = 'named#${_entryIds[entry] ??= ++_entries}';
            final page = _NodeWidget((_) => entry.route.builder(entry.params));
            owner._namedEntry = entry;
            // Its own keys and its own place: the same route twice on the
            // way is two pages.
            owner._withKeyScope(id, () {
              if (i == state.index) {
                shown = owner.inSlot(id, () => page._render(owner));
              } else {
                owner._offstage(id, page);
              }
            });
          }
        } finally {
          owner._namedEntry = outer;
        }
        return shown ?? UIBuilder.sizedBox();
      });
    } else if (router != null) {
      owner._router = router;
      first = Builder(builder: router.build);
    } else {
      first = widget.home ?? const SizedBox.shrink();
    }
    final navigator = Navigator._(key: widget.navigatorKey, child: first);
    // The pages are what the screen is, so the direction in force around
    // them is the screen's - whether that is the locale's, below, or one the
    // app's `builder` put in between.
    Widget app = _NodeWidget((owner) {
      owner._appDirection ??= owner._direction;
      return navigator._render(owner);
    });
    final wrap = widget.builder;
    if (wrap != null) {
      final inner = app;
      app = Builder(builder: (context) => wrap(context, inner));
    }
    final locale = _resolveLocale(widget.locale, widget.supportedLocales);
    _ensureLocalizations(locale);
    // Outside `builder`, where Flutter's `Localizations` puts its own: the
    // locale's direction is the default and the app's own word overrides it.
    app = _LocaleScope(
      locale: locale,
      resources: _resources,
      child: Directionality(textDirection: _directionOf(locale), child: app),
    );
    final theme = _theme(owner);
    if (theme != null) app = Theme(data: theme, child: app);
    return owner.inSlot('app', () => app._render(owner));
  });
}

/// The bar across the top of a [Scaffold].
///
/// The bar is the platform's own. Its title is a string, so a [title] that is
/// a [Text] becomes it and any other widget is drawn in its place as a
/// subtree. Its leading button is one of three the platform knows how to draw
/// - back, close, menu - so a [leading] that is an [IconButton] with one of
/// those icons becomes it; a back button appears on its own on a page that
/// can be popped, unless [automaticallyImplyLeading] is false.
///
/// [bottom] - a [TabBar], usually - is laid out under the bar, as the first
/// row of the scaffold's body.
class AppBar extends Widget implements PreferredSizeWidget {
  const AppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.centerTitle,
    this.titleSpacing,
    this.toolbarHeight,
    this.leadingWidth,
    this.titleTextStyle,
  });
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double? elevation;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool? centerTitle;

  /// Accepted and not carried: the bar keeps the platform's own metrics.
  final double? scrolledUnderElevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final IconThemeData? iconTheme;
  final double? titleSpacing;
  final double? toolbarHeight;
  final double? leadingWidth;
  final TextStyle? titleTextStyle;

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? 56) + (bottom?.preferredSize.height ?? 0),
  );

  /// The leading button, as the protocol names it, and what it does.
  (String?, VoidCallback?, Widget?) _leading(_Owner owner) {
    final leading = this.leading;
    if (leading is IconButton) {
      final icon = leading.icon;
      final glyph = icon is Icon ? icon.icon : null;
      final kind = glyph == null
          ? null
          : switch (glyph.name) {
              'arrow_back' ||
              'arrow_back_ios' ||
              'arrow_back_ios_new' ||
              'chevron_left' => 'back',
              'close' || 'clear' => 'close',
              'menu' => 'menu',
              _ => null,
            };
      if (kind != null) return (kind, leading.onPressed ?? () {}, null);
    }
    if (leading is BackButton) {
      return ('back', leading.onPressed ?? () => _popFrom(owner), null);
    }
    if (leading is CloseButton) {
      return ('close', leading.onPressed ?? () => _popFrom(owner), null);
    }
    if (leading != null) return (null, null, leading);
    if (!automaticallyImplyLeading) return (null, null, null);
    final drawer = owner._inherited<_ScaffoldScope>()?.openDrawer;
    if (drawer != null) return ('menu', drawer, null);
    final route = owner._inherited<_RouteScope>()?.route;
    final canPop =
        (route != null && !route.isFirst) ||
        (owner._router?.canPop() ?? false) ||
        (owner.routerNav?.router.state.canGoBack ?? false);
    if (canPop) return ('back', () => _popFrom(owner), null);
    return (null, null, null);
  }

  static void _popFrom(_Owner owner) {
    if (owner._refusePop()) return;
    for (final navigator in owner._navigators.reversed) {
      if (navigator._popRoute(null)) return;
    }
    final router = owner._router;
    if (router != null && router.canPop()) return router.pop();
    owner.routerNav?.goBack();
  }

  @override
  WidgetNode _render(_Owner owner) {
    final data = _themeOf(owner);
    final theme = data.appBarTheme;
    final (background, foreground) = _colors(data);
    final (kind, onLeading, custom) = _leading(owner);
    final text = _stringOf(title, owner);
    final actionNodes = owner.inSlot(
      'actions',
      () => _renderAll(actions ?? const [], owner),
    );
    WidgetNode? titleNode;
    if (custom != null || (title != null && text == null)) {
      final pieces = [
        if (custom != null) _renderChild(owner, custom, 'leading'),
        if (title != null) _renderChild(owner, title!, 'title'),
      ];
      titleNode = pieces.length == 1
          ? pieces.single
          : UIBuilder.row(spacing: 8, children: pieces);
    }
    return UIBuilder.appBar(
      title: text ?? '',
      leading: kind,
      onLeading: onLeading,
      actions: actionNodes,
      titleNode: titleNode,
      centerTitle: centerTitle ?? theme.centerTitle,
      backgroundColor: background._hex,
      foregroundColor: foreground._hex,
      elevation: elevation ?? theme.elevation,
    );
  }

  /// The bar's fill and what is drawn on it, decided here as Flutter decides
  /// them and always stated on the node - a renderer left to its own default
  /// paints the bar in the primary, which is not what a Material 3 app's bar
  /// looks like. The bar's own colours, then the theme's `appBarTheme`, then
  /// Material's: the surface under Material 3, and under Material 2 the
  /// primary in a light theme and the surface in a dark one.
  (Color, Color) _colors(ThemeData data) {
    final scheme = data.colorScheme;
    final onSurface =
        data.useMaterial3 || scheme.brightness == Brightness.dark;
    return (
      backgroundColor ??
          data.appBarTheme.backgroundColor ??
          (onSurface ? scheme.surface : scheme.primary),
      foregroundColor ??
          data.appBarTheme.foregroundColor ??
          (onSurface ? scheme.onSurface : scheme.onPrimary),
    );
  }

  /// The bar as boxes, for a scaffold that is not the platform's own frame.
  WidgetNode _renderComposed(_Owner owner) {
    // The same colours the platform's bar is sent, so a page's own bar and
    // the bar of a scaffold inside it are one app's.
    final (fill, ink) = _colors(_themeOf(owner));
    final (kind, onLeading, custom) = _leading(owner);
    return UIBuilder.box(
      height: toolbarHeight ?? 56,
      padding: const [4, 0, 4, 0],
      color: fill._hex,
      child: _withForeground(
        owner,
        ink,
        () => UIBuilder.row(
          spacing: 4,
          children: [
            if (kind != null)
              UIBuilder.iconButton(
                icon: switch (kind) {
                  'close' => 'close',
                  'menu' => 'menu',
                  _ => 'arrow_back',
                },
                onPressed: onLeading,
                tooltip: '',
                color: ink._hex,
              )
            else if (custom != null)
              _renderChild(owner, custom, 'leading')
            else
              UIBuilder.sizedBox(width: 12),
            UIBuilder.expanded(
              child: title == null
                  ? UIBuilder.sizedBox()
                  : _renderChild(owner, title!, 'title'),
            ),
            ...owner.inSlot(
              'actions',
              () => _renderAll(actions ?? const [], owner),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 22),
      ),
    );
  }
}

/// The back arrow, popping the page it is on unless told to do otherwise.
class BackButton extends StatelessWidget {
  const BackButton({super.key, this.color, this.onPressed});
  final Color? color;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    color: color,
    tooltip: 'Back',
    onPressed: onPressed ?? () => Navigator.maybePop(context),
  );
}

/// The close cross, popping the page it is on unless told to do otherwise.
class CloseButton extends StatelessWidget {
  const CloseButton({super.key, this.color, this.onPressed});
  final Color? color;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.close),
    color: color,
    tooltip: 'Close',
    onPressed: onPressed ?? () => Navigator.maybePop(context),
  );
}

/// What a scaffold tells the bar it frames.
class _ScaffoldScope extends InheritedWidget {
  const _ScaffoldScope({required this.openDrawer, required super.child});

  /// Opens the scaffold's drawer, or null when it has none.
  final VoidCallback? openDrawer;

  // The callback is a new closure on every build; what a bar can learn from
  // it is whether there is a drawer at all.
  @override
  bool updateShouldNotify(_ScaffoldScope oldWidget) =>
      (oldWidget.openDrawer == null) != (openDrawer == null);
}

/// Where a scaffold puts its floating button. Accepted for Flutter's
/// signature: the platform's scaffold has one place for it.
enum FloatingActionButtonLocation {
  endFloat,
  centerFloat,
  startFloat,
  endDocked,
  centerDocked,
  endTop,
  startTop,
}

/// The frame of a screen: an app bar, a body, a floating button, a bar along
/// the bottom.
///
/// **The body does not scroll**, as in Flutter. A screen taller than the
/// window puts its content in a [SingleChildScrollView] or a [ListView].
///
/// The outermost scaffold is the platform's own frame. One built inside
/// another's body - a feature screen with its own floating button, inside a
/// shell that owns the app bar - is composed from a column and a stack
/// instead, because a platform has one frame per screen.
///
/// [drawer] is shown as a sheet, opened by the menu button the app bar gains
/// - the nearest the protocol has to a panel sliding in from the side - or by
/// `Scaffold.of(context).openDrawer()`. It closes when the app moves to
/// another page, as a drawer left behind on its own page does in Flutter.
/// [endDrawer] is the same sheet, opened only by
/// `Scaffold.of(context).openEndDrawer()`: the bar gains no button for it.
class Scaffold extends StatefulWidget {
  const Scaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.onDrawerChanged,
    this.endDrawer,
    this.onEndDrawerChanged,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.drawerEnableOpenDragGesture = true,
    this.endDrawerEnableOpenDragGesture = true,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
  });
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? drawer;
  final Widget? endDrawer;

  /// Called with true when the drawer opens and false when it has closed.
  final ValueChanged<bool>? onDrawerChanged;
  final ValueChanged<bool>? onEndDrawerChanged;

  /// A [NavigationBar] or a [BottomNavigationBar] becomes the platform's own
  /// bottom navigation; any other widget is pinned along the bottom edge.
  final Widget? bottomNavigationBar;

  /// Laid out under the body, above the bottom bar.
  final Widget? bottomSheet;
  final Color? backgroundColor;

  /// Accepted and not consulted: the renderers keep a focused field clear of
  /// the keyboard themselves.
  final bool? resizeToAvoidBottomInset;

  /// Accepted and not consulted: a sheet is not dragged in from an edge.
  final bool drawerEnableOpenDragGesture;
  final bool endDrawerEnableOpenDragGesture;
  final bool extendBody;
  final bool extendBodyBehindAppBar;

  /// The state of the nearest scaffold above [context], for opening its
  /// drawer. As in Flutter, the context of the widget that *builds* the
  /// scaffold is above it and finds none: use a `Builder`, or a
  /// `GlobalKey<ScaffoldState>`.
  static ScaffoldState of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'Scaffold.of() was called with a context that has no Scaffold above '
        'it. Use the context of a widget built inside the scaffold - a '
        'Builder will do - or a GlobalKey<ScaffoldState>.',
      ));

  static ScaffoldState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ScaffoldState>();

  @override
  ScaffoldState createState() => ScaffoldState();
}

/// What `Scaffold.of(context)` and a `GlobalKey<ScaffoldState>` answer: the
/// way to a scaffold's drawer from code.
class ScaffoldState extends State<Scaffold> {
  _OverlayEntry? _drawer;
  _OverlayEntry? _endDrawer;

  bool get hasAppBar => widget.appBar != null;
  bool get hasDrawer => widget.drawer != null;
  bool get hasEndDrawer => widget.endDrawer != null;
  bool get hasFloatingActionButton => widget.floatingActionButton != null;
  bool get isDrawerOpen => _drawer != null;
  bool get isEndDrawerOpen => _endDrawer != null;

  /// Shows the scaffold's [Scaffold.drawer]; nothing when it has none or it
  /// is open already.
  void openDrawer() {
    if (widget.drawer == null || _drawer != null) return;
    final entry = _open((_) => widget.drawer ?? const SizedBox.shrink());
    _drawer = entry;
    widget.onDrawerChanged?.call(true);
    entry.completer.future.whenComplete(() {
      if (identical(_drawer, entry)) _drawer = null;
      if (mounted) widget.onDrawerChanged?.call(false);
    });
  }

  /// Shows the scaffold's [Scaffold.endDrawer].
  void openEndDrawer() {
    if (widget.endDrawer == null || _endDrawer != null) return;
    final entry = _open((_) => widget.endDrawer ?? const SizedBox.shrink());
    _endDrawer = entry;
    widget.onEndDrawerChanged?.call(true);
    entry.completer.future.whenComplete(() {
      if (identical(_endDrawer, entry)) _endDrawer = null;
      if (mounted) widget.onEndDrawerChanged?.call(false);
    });
  }

  void closeDrawer() {
    final entry = _drawer;
    if (entry != null) _owner?._dismiss(entry, null);
  }

  void closeEndDrawer() {
    final entry = _endDrawer;
    if (entry != null) _owner?._dismiss(entry, null);
  }

  _OverlayEntry _open(WidgetBuilder builder) {
    final entry = _OverlayEntry(
      _OverlayKind.sheet,
      builder,
      scope: _context?._scope,
      isDrawer: true,
    );
    _owner!.pushOverlay<void>(entry);
    return entry;
  }

  @override
  void dispose() {
    // A drawer does not outlive the page it was opened from.
    closeDrawer();
    closeEndDrawer();
  }

  @override
  Widget build(BuildContext context) => _ScaffoldFrame(widget, this);
}

/// The scaffold's nodes.
class _ScaffoldFrame extends Widget {
  const _ScaffoldFrame(this._scaffold, this._state);
  final Scaffold _scaffold;
  final ScaffoldState _state;

  PreferredSizeWidget? get appBar => _scaffold.appBar;
  Widget? get body => _scaffold.body;
  Widget? get floatingActionButton => _scaffold.floatingActionButton;
  Widget? get bottomNavigationBar => _scaffold.bottomNavigationBar;
  Widget? get bottomSheet => _scaffold.bottomSheet;
  Color? get backgroundColor => _scaffold.backgroundColor;

  @override
  WidgetNode _render(_Owner owner) {
    final nested = owner._scaffoldDepth > 0;
    final scope = _ScaffoldScope(
      openDrawer: _scaffold.drawer == null ? null : _state.openDrawer,
      child: const SizedBox.shrink(),
    );
    owner._scaffoldDepth++;
    try {
      return owner._withInherited(
        scope,
        // Whatever the scaffold sits in, its own parts are bounded: it has
        // the screen, or the room the scaffold around it gave its body.
        () => owner._withLayout(
          () => nested ? _renderNested(owner) : _renderFrame(owner),
          unboundedHeight: false,
          unboundedWidth: false,
        ),
      );
    } finally {
      owner._scaffoldDepth--;
    }
  }

  /// The body, with what the platform's frame has no slot for laid around it.
  WidgetNode _body(_Owner owner, {WidgetNode? above, WidgetNode? fab}) {
    final body = this.body;
    var node = body == null
        ? UIBuilder.sizedBox()
        : owner.inSlot('body', () => body._render(owner));
    if (fab != null) {
      node = UIBuilder.stack(
        fit: 'expand',
        children: [
          UIBuilder.positioned(fill: true, child: node),
          // The end corner: bottom right, and bottom left in a screen that
          // reads from the right.
          owner._direction == TextDirection.rtl
              ? UIBuilder.positioned(left: 16, bottom: 16, child: fab)
              : UIBuilder.positioned(right: 16, bottom: 16, child: fab),
        ],
      );
    }
    final sheet = bottomSheet;
    if (above == null && sheet == null) return node;
    return UIBuilder.column(
      crossAxisAlignment: 'stretch',
      mainAxisSize: 'max',
      children: [
        if (above != null) above,
        UIBuilder.expanded(child: node),
        if (sheet != null)
          owner._withLayout(
            () => _renderChild(owner, sheet, 'bottomSheet'),
            unboundedHeight: true,
          ),
      ],
    );
  }

  WidgetNode? _bottomBar(_Owner owner) {
    final bar = bottomNavigationBar;
    if (bar == null) return null;
    return owner._withLayout(
      () => _renderChild(owner, bar, 'bottomBar'),
      unboundedHeight: true,
    );
  }

  WidgetNode? _fab(_Owner owner) {
    final fab = floatingActionButton;
    return fab == null ? null : owner.inSlot('fab', () => fab._render(owner));
  }

  /// What sits between the bar and the body: the bar's `bottom`, and a whole
  /// app bar that is not an [AppBar] and so cannot be the platform's.
  WidgetNode? _underBar(_Owner owner) {
    final bar = appBar;
    if (bar == null) return null;
    final Widget? under = bar is AppBar ? bar.bottom : bar;
    if (under == null) return null;
    return owner._withLayout(
      () => _renderChild(owner, under, 'appBarBottom'),
      unboundedHeight: true,
    );
  }

  WidgetNode _renderFrame(_Owner owner) {
    final bar = appBar;
    final fab = _fab(owner);
    // The frame knows its button by type. A button wrapped in something else
    // - padding, a column of two - is laid over the body instead.
    final native = fab != null && fab.type == 'FloatingActionButton';
    final bottom = _bottomBar(owner);
    return UIBuilder.scaffold(
      appBar: bar is AppBar
          ? owner.inSlot('appBar', () => bar._render(owner))
          : null,
      body: _body(owner, above: _underBar(owner), fab: native ? null : fab),
      floatingActionButton: native ? fab : null,
      bottomBar: bottom == null ? null : UIBuilder.bottomBar(child: bottom),
      bodyScrolls: false,
      backgroundColor: backgroundColor?._hex,
    );
  }

  WidgetNode _renderNested(_Owner owner) {
    final bar = appBar;
    final bottom = _bottomBar(owner);
    // A renderer keeps a snackbar clear of the button of the scaffold it
    // knows about. This one's is a box in a stack, so the snackbar is told.
    if (floatingActionButton != null && owner._hidden == 0) {
      owner._nestedFab = true;
    }
    // Nor does one know this scaffold's bottom bar, so the bar is measured.
    // Until it has been, a navigation bar is as tall as it says or as
    // Material makes it, and anything else a bar of the usual height.
    var under = bottom;
    if (under != null) {
      final place = owner._positionId('NestedBar');
      if (owner._hidden == 0) {
        owner._nestedBar =
            owner._barHeights[place] ??
            switch (bottomNavigationBar) {
              NavigationBar(:final height) => height ?? 80,
              _ => 56,
            };
      }
      under = UIBuilder.box(
        onSize: (width, height) {
          if ((owner._barHeights[place] ?? -1) == height) return;
          owner._barHeights[place] = height;
          owner._requestRebuild();
        },
        child: under,
      );
    }
    final node = UIBuilder.column(
      crossAxisAlignment: 'stretch',
      mainAxisSize: 'max',
      children: [
        if (bar is AppBar)
          owner.inSlot('appBar', () => bar._renderComposed(owner)),
        UIBuilder.expanded(
          child: _body(owner, above: _underBar(owner), fab: _fab(owner)),
        ),
        ?under,
      ],
    );
    final fill = backgroundColor;
    return fill == null
        ? node
        : UIBuilder.box(color: fill._hex, expand: 'both', child: node);
  }
}

/// The panel a [Scaffold] shows as its `drawer`.
///
/// The surface is the sheet the scaffold opens it in, so this is the [child]
/// - a [ListView] of destinations, usually - over a [backgroundColor] if one
/// is given. [width], [elevation] and [shape] are accepted and not carried.
class Drawer extends StatelessWidget {
  const Drawer({
    super.key,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.shape,
    this.width,
    this.child,
    this.semanticLabel,
    this.clipBehavior,
  });
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final ShapeBorder? shape;
  final double? width;
  final Widget? child;
  final String? semanticLabel;
  final Clip? clipBehavior;

  @override
  Widget build(BuildContext context) {
    final child = this.child ?? const SizedBox.shrink();
    final fill = backgroundColor;
    return fill == null ? child : ColoredBox(color: fill, child: child);
  }
}

/// The block at the top of a [Drawer]: the app's name over a colour.
///
/// Flutter fixes its height at 160 and adds the status bar's; in a sheet
/// there is no status bar to clear, so it is as tall as its [child] and
/// [padding], and as wide as the drawer.
class DrawerHeader extends StatelessWidget {
  const DrawerHeader({
    super.key,
    this.decoration,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.fastOutSlowIn,
    required this.child,
  });
  final Decoration? decoration;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;

  /// Accepted and not used: the decoration changes at once.
  final Duration duration;
  final Curve curve;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: margin,
    padding: padding,
    decoration: decoration,
    child: child,
  );
}

// ---------------------------------------------------------------------------
// Destinations: bottom navigation, a rail, tabs.
// ---------------------------------------------------------------------------

/// The codepoint of a destination's icon. The platform's bar draws glyphs, so
/// an icon that is not an [Icon] is drawn as a plain dot.
int _glyph(Widget? widget) =>
    (widget is Icon ? widget.icon?.codePoint : null) ??
    Icons.circle.codePoint;

int? _maybeGlyph(Widget? widget) =>
    widget is Icon ? widget.icon?.codePoint : null;

/// One destination of a [NavigationBar].
class NavigationDestination extends Widget {
  const NavigationDestination({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
    this.enabled = true,
  });
  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;
  final bool enabled;
  @override
  WidgetNode _render(_Owner owner) => _renderChild(owner, icon);
}

/// Whether a bar shows its labels. Accepted for Flutter's signature: the
/// platform's bar decides.
enum NavigationDestinationLabelBehavior {
  alwaysShow,
  alwaysHide,
  onlyShowSelected,
}

/// Material 3's bar of destinations along the bottom: the platform's own
/// bottom navigation on Android, a tab bar on iOS.
class NavigationBar extends Widget {
  const NavigationBar({
    super.key,
    this.selectedIndex = 0,
    required this.destinations,
    this.onDestinationSelected,
    this.backgroundColor,
    this.elevation,
    this.indicatorColor,
    this.height,
    this.labelBehavior,
  });
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;

  /// Accepted and not carried: the bar is the platform's own, in the theme's
  /// colours.
  final Color? backgroundColor;
  final double? elevation;
  final Color? indicatorColor;
  final double? height;
  final NavigationDestinationLabelBehavior? labelBehavior;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.bottomNavigation(
    items: [
      for (final destination in destinations)
        if (destination is NavigationDestination)
          (
            label: destination.label,
            icon: _glyph(destination.icon),
            selectedIcon: _maybeGlyph(destination.selectedIcon),
          ),
    ],
    selectedIndex: selectedIndex,
    onChanged: onDestinationSelected ?? (_) {},
    id: _idOf(key),
  );
}

/// One item of a [BottomNavigationBar].
class BottomNavigationBarItem {
  const BottomNavigationBarItem({
    required this.icon,
    this.label,
    Widget? activeIcon,
    this.backgroundColor,
    this.tooltip,
  }) : activeIcon = activeIcon ?? icon;
  final Widget icon;
  final String? label;
  final Widget activeIcon;
  final Color? backgroundColor;
  final String? tooltip;
}

/// How a [BottomNavigationBar] lays out its items. Accepted for Flutter's
/// signature.
enum BottomNavigationBarType { fixed, shifting }

/// Material 2's bar of destinations along the bottom; the same platform bar
/// as a [NavigationBar].
class BottomNavigationBar extends Widget {
  const BottomNavigationBar({
    super.key,
    required this.items,
    this.onTap,
    this.currentIndex = 0,
    this.elevation,
    this.type,
    this.backgroundColor,
    this.selectedItemColor,
    this.unselectedItemColor,
    this.showSelectedLabels,
    this.showUnselectedLabels,
  });
  final List<BottomNavigationBarItem> items;
  final ValueChanged<int>? onTap;
  final int currentIndex;

  /// Accepted and not carried: the bar is the platform's own.
  final double? elevation;
  final BottomNavigationBarType? type;
  final Color? backgroundColor;
  final Color? selectedItemColor;
  final Color? unselectedItemColor;
  final bool? showSelectedLabels;
  final bool? showUnselectedLabels;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.bottomNavigation(
    items: [
      for (final item in items)
        (
          label: item.label ?? '',
          icon: _glyph(item.icon),
          selectedIcon: identical(item.activeIcon, item.icon)
              ? null
              : _maybeGlyph(item.activeIcon),
        ),
    ],
    selectedIndex: currentIndex,
    onChanged: onTap ?? (_) {},
    id: _idOf(key),
  );
}

/// One destination of a [NavigationRail].
class NavigationRailDestination {
  const NavigationRailDestination({
    required this.icon,
    Widget? selectedIcon,
    required this.label,
    this.padding,
    this.disabled = false,
  }) : selectedIcon = selectedIcon ?? icon;
  final Widget icon;
  final Widget selectedIcon;

  /// A widget in Flutter; its text is what the rail shows.
  final Widget label;
  final EdgeInsetsGeometry? padding;
  final bool disabled;
}

/// Whether a rail shows its labels. Accepted for Flutter's signature.
enum NavigationRailLabelType { none, selected, all }

/// The destinations of an app down its leading edge, for a wide window.
///
/// [leading] is drawn above the destinations and [trailing] below them, and
/// an [extended] rail is wide, with each label beside its icon. The rest of
/// its look is the platform's own.
class NavigationRail extends Widget {
  const NavigationRail({
    super.key,
    this.backgroundColor,
    this.extended = false,
    this.leading,
    this.trailing,
    required this.destinations,
    required this.selectedIndex,
    this.onDestinationSelected,
    this.elevation,
    this.groupAlignment,
    this.labelType,
    this.minWidth,
    this.minExtendedWidth,
    this.indicatorColor,
  });
  final Color? backgroundColor;
  final bool extended;
  final Widget? leading;
  final Widget? trailing;
  final List<NavigationRailDestination> destinations;
  final int? selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final double? elevation;
  final double? groupAlignment;
  final NavigationRailLabelType? labelType;
  final double? minWidth;
  final double? minExtendedWidth;
  final Color? indicatorColor;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.bottomNavigation(
    rail: true,
    items: [
      for (final destination in destinations)
        (
          label: _plainText(destination.label, owner) ?? '',
          icon: _glyph(destination.icon),
          selectedIcon: identical(destination.selectedIcon, destination.icon)
              ? null
              : _maybeGlyph(destination.selectedIcon),
        ),
    ],
    selectedIndex: selectedIndex ?? 0,
    onChanged: onDestinationSelected ?? (_) {},
    extended: extended,
    leading: leading == null ? null : _renderChild(owner, leading!, 'leading'),
    trailing: trailing == null
        ? null
        : _renderChild(owner, trailing!, 'trailing'),
    id: _idOf(key),
  );
}

/// A strip of labels, one of them selected.
///
/// Framework-specific, like [Tr]: the selection lives in the app like every
/// other piece of state, with no controller. Flutter's `TabBar` with a
/// `TabController` is here as well - [TabBar], [TabBarView],
/// [DefaultTabController] - and draws this same strip.
///
/// What it draws is each platform's own way of choosing one of a few things -
/// Material tabs on Android, a segmented control on iOS, a tab strip on web.
///
/// ```dart
/// Tabs(
///   tabs: const ['All', 'Unread'],
///   selectedIndex: _tab,
///   onChanged: (index) => setState(() => _tab = index),
/// ),
/// if (_tab == 0) const _AllMail() else const _Unread(),
/// ```
class Tabs extends Widget {
  const Tabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selectedIndex;
  final void Function(int index) onChanged;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.tabs(
    tabs: tabs,
    selectedIndex: selectedIndex,
    onChanged: onChanged,
    id: _idOf(key),
  );
}

/// Which tab is selected, shared by a [TabBar] and its [TabBarView].
///
/// A [TabBarView] slides to the tab selected over [animationDuration].
/// `vsync` is accepted for Flutter's signature; there is nothing here for it
/// to synchronise.
class TabController extends ChangeNotifier {
  TabController({
    int initialIndex = 0,
    Duration? animationDuration,
    required this.length,
    TickerProvider? vsync,
  }) : _index = initialIndex,
       _previousIndex = initialIndex,
       animationDuration = animationDuration ?? const Duration(milliseconds: 300);

  final int length;

  /// How long a [TabBarView] takes to slide to a tab selected.
  final Duration animationDuration;
  int _index;
  int _previousIndex;

  /// How the next change of tab travels, when [animateTo] said.
  ({Duration duration, Curve curve})? _travel;

  int get index => _index;
  set index(int value) {
    if (value == _index || value < 0 || value >= length) return;
    _previousIndex = _index;
    _index = value;
    notifyListeners();
  }

  int get previousIndex => _previousIndex;

  /// Always false: the selected tab is the new one from the moment it
  /// changes, while the view slides to it.
  bool get indexIsChanging => false;

  /// Selects tab [value], the view sliding there over [duration] - the
  /// controller's [animationDuration] when not said.
  void animateTo(int value, {Duration? duration, Curve curve = Curves.ease}) {
    _travel = (duration: duration ?? animationDuration, curve: curve);
    index = value;
    _travel = null;
  }
}

class _TabControllerScope extends InheritedWidget {
  const _TabControllerScope({required this.controller, required super.child});
  final TabController controller;

  @override
  bool updateShouldNotify(_TabControllerScope oldWidget) =>
      !identical(oldWidget.controller, controller);
}

/// Gives the [TabBar] and [TabBarView] below it one [TabController] to share,
/// without the app keeping one.
class DefaultTabController extends StatefulWidget {
  const DefaultTabController({
    super.key,
    required this.length,
    this.initialIndex = 0,
    required this.child,
    this.animationDuration,
  });
  final int length;
  final int initialIndex;
  final Widget child;
  final Duration? animationDuration;

  static TabController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TabControllerScope>()
      ?.controller;

  static TabController of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'DefaultTabController.of() called with no DefaultTabController above '
        'the context.',
      ));

  @override
  State<DefaultTabController> createState() => _DefaultTabControllerState();
}

class _DefaultTabControllerState extends State<DefaultTabController> {
  late TabController _controller = TabController(
    length: widget.length,
    initialIndex: widget.initialIndex,
  );

  @override
  void didUpdateWidget(DefaultTabController oldWidget) {
    if (oldWidget.length == widget.length) return;
    // A different number of tabs is a different set of tabs; keep the
    // selection where it still means something.
    final old = _controller;
    _controller = TabController(
      length: widget.length,
      initialIndex: math.min(old.index, math.max(0, widget.length - 1)),
    );
    old.dispose();
  }

  @override
  void dispose() => _controller.dispose();

  @override
  Widget build(BuildContext context) =>
      _TabControllerScope(controller: _controller, child: widget.child);
}

/// One tab of a [TabBar]. The strip shows text, so [text] - or the text of
/// [child] - is what is drawn; an [icon] alone is named by its semantic
/// label.
class Tab extends Widget implements PreferredSizeWidget {
  const Tab({super.key, this.text, this.icon, this.iconMargin, this.height, this.child});
  final String? text;
  final Widget? icon;
  final EdgeInsetsGeometry? iconMargin;
  final double? height;
  final Widget? child;

  @override
  Size get preferredSize => Size.fromHeight(height ?? 46);

  String _label(_Owner owner) =>
      text ??
      _plainText(child, owner) ??
      (icon is Icon ? (icon as Icon).semanticLabel : null) ??
      '';

  @override
  WidgetNode _render(_Owner owner) =>
      _textNode(owner, _label(owner), id: _idOf(key));
}

/// A strip of [Tab]s driven by a [TabController] - its own, or the one a
/// [DefaultTabController] above provides.
class TabBar extends Widget implements PreferredSizeWidget {
  const TabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.isScrollable = false,
    this.onTap,
    this.indicatorColor,
    this.labelColor,
    this.unselectedLabelColor,
    this.labelStyle,
    this.unselectedLabelStyle,
    this.indicatorWeight = 2.0,
    this.tabAlignment,
    this.dividerColor,
  });
  final List<Widget> tabs;
  final TabController? controller;
  final ValueChanged<int>? onTap;

  /// Accepted and not carried: the strip is the platform's own.
  final bool isScrollable;
  final Color? indicatorColor;
  final Color? labelColor;
  final Color? unselectedLabelColor;
  final TextStyle? labelStyle;
  final TextStyle? unselectedLabelStyle;
  final double indicatorWeight;
  final Object? tabAlignment;
  final Color? dividerColor;

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  WidgetNode _render(_Owner owner) {
    final controller =
        this.controller ?? owner._inherited<_TabControllerScope>()?.controller;
    if (controller == null) {
      throw StateError(
        'A TabBar needs a TabController: pass one, or put a '
        'DefaultTabController above it.',
      );
    }
    owner._watch(controller);
    return UIBuilder.tabs(
      tabs: [
        for (final tab in tabs)
          tab is Tab ? tab._label(owner) : (_plainText(tab, owner) ?? ''),
      ],
      selectedIndex: controller.index,
      onChanged: (index) {
        controller.index = index;
        onTap?.call(index);
      },
      id: _idOf(key),
    );
  }
}

/// Shows the child for the selected tab, and keeps the others alive.
///
/// The children that are not showing are still built - their nodes thrown
/// away - so a tab keeps its `State` while another is in front, as each page
/// of Flutter's does once it has been visited.
///
/// It is a [PageView] kept in step with the [TabController]: the page
/// follows a finger across it and the tab beside it is selected when it is
/// let go far or fast enough, and a tab selected elsewhere - on the
/// [TabBar] - slides into view over the controller's `animationDuration`.
/// A [NeverScrollableScrollPhysics] leaves the tabs the only way to move.
class TabBarView extends Widget {
  const TabBarView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
  });
  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;

  @override
  WidgetNode _render(_Owner owner) {
    final controller =
        this.controller ?? owner._inherited<_TabControllerScope>()?.controller;
    if (controller == null) {
      throw StateError(
        'A TabBarView needs a TabController: pass one, or put a '
        'DefaultTabController above it.',
      );
    }
    return _renderChild(
      owner,
      _TabPages(controller: controller, physics: physics, children: children),
    );
  }
}

/// A [TabBarView]'s pages: a [PageView] whose page is the controller's tab.
class _TabPages extends StatefulWidget {
  const _TabPages({
    required this.controller,
    required this.children,
    this.physics,
  });
  final TabController controller;
  final List<Widget> children;
  final ScrollPhysics? physics;

  @override
  State<_TabPages> createState() => _TabPagesState();
}

class _TabPagesState extends State<_TabPages> {
  late final PageController _pages = PageController(
    initialPage: widget.controller.index,
  );
  late TabController _tabs = widget.controller;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_tabChanged);
  }

  @override
  void didUpdateWidget(_TabPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _tabs.removeListener(_tabChanged);
      _tabs = widget.controller..addListener(_tabChanged);
      _pages.jumpToPage(_tabs.index);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _pages.dispose();
    super.dispose();
  }

  /// A tab selected elsewhere: the view slides there. One the view itself
  /// selected - a swipe - is there already.
  void _tabChanged() {
    final to = _tabs.index;
    if (_pages._page == to) return;
    final travel = _tabs._travel;
    unawaited(
      _pages.animateToPage(
        to,
        duration: travel?.duration ?? _tabs.animationDuration,
        curve: travel?.curve ?? Curves.ease,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageView(
    controller: _pages,
    physics: widget.physics,
    onPageChanged: (page) => _tabs.index = page,
    children: widget.children,
  );
}

/// Where each swipe in progress began, by what is being swiped - a
/// controller. Kept there rather than in the closure, which a rebuild in
/// mid-swipe replaces.
final Expando<double> _swipeFrom = Expando('pageSwipe');
const double _swipeDistance = 80;
const double _swipeSpeed = 300;

/// [page] in a box that hears a swipe along [axis] and calls [onStep] with
/// +1 for the page after and -1 for the page before, once the finger lifts
/// having gone far enough or fast enough - or [onStep] with 0, when it
/// did neither and [onMove] was following it. [onMove] hears how far the
/// finger has gone, in pixels along the axis, as it goes. A movement that
/// sets off across the axis is not the box's, so a list in the page still
/// scrolls.
WidgetNode _swipePages(
  _Owner owner,
  WidgetNode page, {
  required Object token,
  required void Function(int step)? onStep,
  Axis axis = Axis.horizontal,
  bool reverse = false,
  void Function(double width, double height)? onSize,
  void Function(double moved)? onMove,
}) {
  final vertical = axis == Axis.vertical;
  // Towards the start of the line - or up the page - is the next one,
  // whichever way the line reads.
  var forward = !vertical && owner._direction == TextDirection.rtl ? 1 : -1;
  if (reverse) forward = -forward;
  return UIBuilder.box(
    // The page's own size, so that a short page is still swiped over all the
    // room the view has - and none is invented where there is no end to the
    // height.
    expand: owner._unboundedHeight ? 'width' : 'both',
    // A page sliding in or out is drawn beyond the view's edges.
    clip: onSize != null,
    onSize: onSize,
    panAxis: onStep == null ? null : (vertical ? 'vertical' : 'horizontal'),
    onPan: onStep == null ? null : (phase, data) {
      double n(String key) => (data[key] as num?)?.toDouble() ?? 0;
      final at = n(vertical ? 'y' : 'x');
      switch (phase) {
        case 'start':
          _swipeFrom[token] = at;
        case 'update':
          final from = _swipeFrom[token];
          if (from != null) onMove?.call(at - from);
        case 'end':
          final from = _swipeFrom[token];
          _swipeFrom[token] = null;
          if (from == null) return;
          final moved = at - from;
          final speed = n(vertical ? 'vy' : 'vx');
          // Far enough, or flung - and a fling against the way the finger
          // went is a change of mind.
          final far = moved.abs() > _swipeDistance;
          final flung = speed.abs() > _swipeSpeed && speed.sign == moved.sign;
          if (!far && !flung) {
            if (onMove != null) onStep(0);
            return;
          }
          onStep(moved.sign.toInt() * forward);
      }
    },
    child: page,
  );
}

/// Which page a [PageView] shows.
///
/// [page] is always a whole number here: the view slides from one page to
/// the next, and [page] is the one it is going to from the moment it sets
/// off.
class PageController extends ChangeNotifier {
  PageController({
    this.initialPage = 0,
    this.keepPage = true,
    this.viewportFraction = 1.0,
  }) : _page = initialPage;

  final int initialPage;
  final bool keepPage;

  /// Accepted and not carried: a page is as wide as the view.
  final double viewportFraction;

  int _page;
  int? _count;
  int _attachedPass = -1;
  _Owner? _owner;

  /// How the next change of page travels, when it is to: set by
  /// [animateToPage] and taken by the view that shows the change.
  ({Duration duration, Curve curve, Completer<void> arrived})? _travel;

  ({Duration duration, Curve curve, Completer<void> arrived})? _takeTravel() {
    final travel = _travel;
    _travel = null;
    return travel;
  }

  /// The page showing, as Flutter spells it.
  double? get page => _page.toDouble();

  /// Whether a [PageView] built with this controller is on screen.
  bool get hasClients => _owner != null && _attachedPass == _owner!._pass;

  void _attach(_Owner owner, int? count) {
    _owner = owner;
    _attachedPass = owner._pass;
    _count = count;
    // A view that lost pages from under the one it was on shows its last.
    if (count != null && count > 0 && _page >= count) _page = count - 1;
  }

  /// Shows [page] at once.
  void jumpToPage(int page) {
    _travel?.arrived.complete();
    _travel = null;
    _move(page);
  }

  void _move(int page) {
    final count = _count;
    final held = count == null ? math.max(0, page) : page.clamp(0, count - 1);
    if (held == _page) return;
    _page = held;
    notifyListeners();
  }

  /// Slides to [page] over [duration], and completes when it is there. The
  /// pages between are not passed through: the one showing slides out as
  /// [page] slides in.
  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) {
    final arrived = Completer<void>();
    _travel?.arrived.complete();
    _travel = (duration: duration, curve: curve, arrived: arrived);
    final before = _page;
    _move(page);
    // Nowhere to go, or no view to show it going: it is there already.
    if (_page == before || !hasClients) {
      _travel = null;
      arrived.complete();
    }
    return arrived.future;
  }

  Future<void> nextPage({required Duration duration, required Curve curve}) =>
      animateToPage(_page + 1, duration: duration, curve: curve);

  Future<void> previousPage({
    required Duration duration,
    required Curve curve,
  }) => animateToPage(_page - 1, duration: duration, curve: curve);

  @override
  void dispose() {
    _owner = null;
    super.dispose();
  }
}

/// Pages, one at a time, swiped between.
///
/// A swipe along [scrollDirection] moves to the page beside the one showing,
/// and [onPageChanged] says which. As with a [TabBarView], the page changes
/// when the finger lifts - it does not follow the finger - and then slides
/// in, as it does for [PageController.animateToPage]; a
/// [PageController.jumpToPage] arrives at once.
///
/// With [children] every page keeps its `State` while another is in front.
/// With [PageView.builder] only the page showing is built, so a page's state
/// goes when it is left.
class PageView extends StatefulWidget {
  const PageView({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    List<Widget> this.children = const [],
    this.padEnds = true,
  }) : itemBuilder = null,
       itemCount = null;

  /// Pages built when they are shown: [itemCount] of them, or without end.
  const PageView.builder({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required NullableIndexedWidgetBuilder this.itemBuilder,
    this.itemCount,
    this.padEnds = true,
  }) : children = null;

  final Axis scrollDirection;
  final bool reverse;
  final PageController? controller;

  /// [NeverScrollableScrollPhysics] leaves the controller the only way to
  /// change the page.
  final ScrollPhysics? physics;
  final ValueChanged<int>? onPageChanged;
  final List<Widget>? children;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final int? itemCount;

  /// Accepted and not carried: a page always snaps, and is as wide as the
  /// view.
  final bool pageSnapping;
  final bool padEnds;

  @override
  State<PageView> createState() => _PageViewState();
}

/// A [PageView] on its way from one page to another.
class _PageSlide {
  _PageSlide(
    this.from,
    this.to,
    this.duration,
    this.curve,
    this.arrived, {
    this.start = 0,
    this.beside,
  });
  final int from;
  final int to;
  final Duration duration;
  final Curve curve;
  final Completer<void>? arrived;

  /// Where the page left stands when the slide sets off, in pixels along the
  /// axis: where the finger let go of it, for a swipe.
  final double start;

  /// For a page that goes back to its place ([from] is [to]): the page the
  /// finger had pulled in beside it, which goes back out.
  final int? beside;

  /// Drawn at the start first, so that a renderer has somewhere to move it
  /// from; set once that has been drawn.
  bool moving = false;
  final List<Timer> timers = [];

  void end() {
    for (final timer in timers) {
      timer.cancel();
    }
    if (!(arrived?.isCompleted ?? true)) arrived!.complete();
  }
}

class _PageViewState extends State<PageView> {
  PageController? _own;

  PageController get _controller =>
      widget.controller ?? (_own ??= PageController());

  /// The view's length along its axis, as the renderer last reported it -
  /// how far a page slides.
  double? _extent;

  /// The page drawn last, to tell a change of page by.
  int? _shown;
  _PageSlide? _slide;

  /// Whether the change of page coming is a swipe's, which slides as a
  /// page let go of does.
  bool _swiped = false;

  /// How far the finger has pulled the page, in pixels along the axis, while
  /// it is on it; null when it is not.
  double? _drag;

  // A renderer that is handed both ends in one frame shows only the last.
  static const _settle = Duration(milliseconds: 32);
  static const _swipeTravel = Duration(milliseconds: 300);

  @override
  void dispose() {
    _slide?.end();
    _own?.dispose();
    super.dispose();
  }

  /// Sets off from page [from] to page [to], if there is room known to
  /// slide across and time to do it in; otherwise the page is simply there.
  void _setOff(int from, int to) {
    final travel = _controller._takeTravel();
    final swiped = _swiped;
    _swiped = false;
    _slide?.end();
    _slide = null;
    final drag = swiped ? (_drag ?? 0) : 0.0;
    _drag = null;
    // A swipe has only the rest of the way to go.
    final rest = _extent == null || _extent! <= 0
        ? 1.0
        : (1 - drag.abs() / _extent!).clamp(0.3, 1.0);
    final duration =
        travel?.duration ?? (swiped ? _swipeTravel * rest : null);
    if (duration == null ||
        duration <= Duration.zero ||
        _extent == null ||
        _extent! <= 0) {
      travel?.arrived.complete();
      return;
    }
    final slide = _PageSlide(
      from,
      to,
      duration,
      travel?.curve ?? Curves.easeOut,
      travel?.arrived,
      start: drag,
    );
    _run(slide);
  }

  /// Draws [slide] where it starts, then sets it moving.
  void _run(_PageSlide slide) {
    _slide = slide;
    slide.timers
      ..add(
        Timer(_settle, () {
          if (!mounted || _slide != slide) return;
          setState(() => slide.moving = true);
        }),
      )
      ..add(
        Timer(_settle + slide.duration, () {
          if (!mounted || _slide != slide) return;
          slide.end();
          setState(() => _slide = null);
        }),
      );
  }

  void _measured(double width, double height) {
    _extent = widget.scrollDirection == Axis.vertical ? height : width;
  }

  /// Page [index]'s node, kept in its own slot.
  WidgetNode _pageNode(_Owner owner, int index) {
    final children = widget.children;
    if (children != null) {
      return index >= 0 && index < children.length
          ? owner.inSlot(index, () => children[index]._render(owner))
          : UIBuilder.sizedBox();
    }
    final built = widget.itemBuilder!(owner._context(), index);
    return built == null
        ? UIBuilder.sizedBox()
        : owner.inSlot(index, () => built._render(owner));
  }

  /// The two pages of [slide] side by side, moved along the axis: at the
  /// start the one left in place and the one arriving just beyond it, then
  /// the one arriving in place and the one left just beyond the other side.
  WidgetNode _sliding(_Owner owner, _PageSlide slide) {
    final vertical = widget.scrollDirection == Axis.vertical;
    // Which way the page after comes from: the end of the line, which is
    // the left in a right-to-left one, or the bottom.
    var after = !vertical && owner._direction == TextDirection.rtl ? -1 : 1;
    if (widget.reverse) after = -after;
    final extent = _extent!;
    final children = widget.children;
    final beside = slide.beside;
    final other = slide.from == slide.to ? beside : slide.to;
    if (children != null) {
      for (var i = 0; i < children.length; i++) {
        if (i != slide.from && i != other) owner._offstage(i, children[i]);
      }
    }
    WidgetNode at(int index, double offset) => UIBuilder.box(
      expand: owner._unboundedHeight ? 'width' : 'both',
      transform: {vertical ? 'dy' : 'dx': offset},
      animateMs: slide.moving ? slide.duration.inMilliseconds : 0,
      curve: slide.curve.name,
      id: 'page-${identityHashCode(this)}-$index',
      child: _pageNode(owner, index),
    );
    final start = slide.start;
    if (slide.from == slide.to) {
      // Back to its place, and the page beside it back out of sight.
      final out = start > 0 ? -extent : extent;
      return UIBuilder.stack(
        fit: 'expand',
        children: [
          at(slide.from, slide.moving ? 0 : start),
          if (beside != null) at(beside, slide.moving ? out : start + out),
        ],
      );
    }
    final sign = (slide.to > slide.from ? 1 : -1) * after;
    return UIBuilder.stack(
      fit: 'expand',
      children: [
        at(slide.from, slide.moving ? -sign * extent : start),
        at(slide.to, slide.moving ? 0 : start + sign * extent),
      ],
    );
  }

  /// The page the finger pulls in beside page [now] when it has gone
  /// [moved] pixels - the one after, from the end of the line, or the one
  /// before - or null at either end.
  int? _besideFor(_Owner owner, int now, double moved) {
    if (moved == 0) return null;
    final vertical = widget.scrollDirection == Axis.vertical;
    var after = !vertical && owner._direction == TextDirection.rtl ? -1 : 1;
    if (widget.reverse) after = -after;
    // A finger going towards the start of the line brings in the page after.
    final index = now + (moved < 0 ? after : -after);
    final count = widget.children?.length ?? widget.itemCount;
    if (index < 0 || (count != null && index >= count)) return null;
    if (widget.children == null &&
        widget.itemBuilder!(owner._context(), index) == null) {
      return null;
    }
    return index;
  }

  /// The page under the finger at [moved], and the one it pulls in beside.
  WidgetNode _following(_Owner owner, int now, double moved) {
    final extent = _extent ?? 0;
    final beside = _besideFor(owner, now, moved);
    // At either end the page gives a little and no more.
    final shown = beside == null ? moved / 3 : moved;
    final vertical = widget.scrollDirection == Axis.vertical;
    final children = widget.children;
    if (children != null) {
      for (var i = 0; i < children.length; i++) {
        if (i != now && i != beside) owner._offstage(i, children[i]);
      }
    }
    WidgetNode at(int index, double offset) => UIBuilder.box(
      expand: owner._unboundedHeight ? 'width' : 'both',
      transform: {vertical ? 'dy' : 'dx': offset},
      id: 'page-${identityHashCode(this)}-$index',
      child: _pageNode(owner, index),
    );
    return UIBuilder.stack(
      fit: 'expand',
      children: [
        at(now, shown),
        if (beside != null)
          at(beside, shown + (shown < 0 ? extent : -extent)),
      ],
    );
  }

  void _moved(double moved) {
    if (_extent == null || _extent! <= 0) return;
    // A page still sliding is where it was going.
    if (_slide != null) {
      _slide!.end();
      _slide = null;
    }
    setState(() => _drag = moved);
  }

  void _step(int step) {
    final controller = _controller;
    final before = controller._page;
    if (step == 0) {
      _settleBack();
      return;
    }
    // Pages built without a count end where the builder has none to give.
    final builder = widget.itemBuilder;
    if (builder != null &&
        widget.itemCount == null &&
        before + step >= 0 &&
        builder(context, before + step) == null) {
      return;
    }
    _swiped = true;
    controller.jumpToPage(before + step);
    if (controller._page != before) {
      widget.onPageChanged?.call(controller._page);
    } else {
      _swiped = false;
      _settleBack();
    }
  }

  /// Puts a page the finger let go of short of the next back where it was.
  void _settleBack() {
    final drag = _drag;
    _drag = null;
    if (drag == null || drag == 0 || _extent == null) {
      setState(() {});
      return;
    }
    final owner = _owner;
    final now = _controller._page;
    final beside = owner == null ? null : _besideFor(owner, now, drag);
    final rest = (drag.abs() / _extent!).clamp(0.3, 1.0);
    _run(
      _PageSlide(
        now,
        now,
        _swipeTravel * rest,
        Curves.easeOut,
        null,
        start: beside == null ? drag / 3 : drag,
        beside: beside,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => _NodeWidget((owner) {
    final controller = _controller;
    final children = widget.children;
    final count = children?.length ?? widget.itemCount;
    controller._attach(owner, count);
    owner._watch(controller);
    final now = controller._page;
    final shown = _shown;
    if (shown != null && shown != now) {
      _setOff(_slide?.to ?? shown, now);
    } else {
      // A jump that went nowhere, or the first build: nothing travels.
      controller._takeTravel()?.arrived.complete();
      _swiped = false;
    }
    _shown = now;
    final slide = _slide;
    final drag = _drag;
    final WidgetNode page;
    if (slide != null) {
      page = _sliding(owner, slide);
    } else if (drag != null) {
      page = _following(owner, now, drag);
    } else {
      // At rest as on the move: the page in its own box in a stack, so that
      // the finger setting off changes what is in the stack and not what the
      // finger is on - a renderer that made that anew would lose the touch.
      if (children != null) {
        for (var i = 0; i < children.length; i++) {
          if (i != now) owner._offstage(i, children[i]);
        }
      }
      page = UIBuilder.stack(
        fit: 'expand',
        children: [
          UIBuilder.box(
            expand: owner._unboundedHeight ? 'width' : 'both',
            id: 'page-${identityHashCode(this)}-$now',
            child: _pageNode(owner, now),
          ),
        ],
      );
    }
    final still = count == 1 || (widget.physics?._never ?? false);
    return _swipePages(
      owner,
      page,
      token: controller,
      axis: widget.scrollDirection,
      reverse: widget.reverse,
      onStep: still ? null : _step,
      onSize: _measured,
      onMove: still ? null : _moved,
    );
  });
}
