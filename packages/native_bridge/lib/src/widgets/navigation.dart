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

  /// Shows [snackBar], replacing the one showing if there is one. Flutter
  /// queues them; one bar at a time is all a platform shows, so the newest
  /// wins here.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar,
  ) {
    _owner.showSnackBar(snackBar);
    return ScaffoldFeatureController._(
      snackBar,
      _owner._snackBarClosed!.future,
      () => _owner._closeSnackBar(SnackBarClosedReason.hide),
    );
  }

  void hideCurrentSnackBar({
    SnackBarClosedReason reason = SnackBarClosedReason.hide,
  }) => _owner._closeSnackBar(reason);

  void removeCurrentSnackBar({
    SnackBarClosedReason reason = SnackBarClosedReason.remove,
  }) => _owner._closeSnackBar(reason);

  /// The same as hiding the current one: there is no queue to clear.
  void clearSnackBars() => _owner._closeSnackBar(SnackBarClosedReason.remove);
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

  /// Accepted and not carried: the button is the platform's.
  final Color? textColor;
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

  /// What Flutter wraps the page in to animate it on and off the screen.
  /// Pages here are shown without a transition, so this is never called; it
  /// is declared so that a route written to override it compiles as it is.
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
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

/// Builds a route's page. The two animations are always complete: pages do
/// not transition.
typedef RoutePageBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    );

/// Wraps a page in its transition; accepted and never called.
typedef RouteTransitionsBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    );

/// A page with a transition of its own, in Flutter. The page is shown without
/// one here: [transitionsBuilder] and the durations are accepted and unused.
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
  final Duration transitionDuration;
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
    final entry = _navigator?._owner?.routerNav?.router.state.current;
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

/// The route a page is being built in.
class _RouteScope extends InheritedWidget {
  const _RouteScope({required this.route, required super.child});
  final Route<dynamic> route;
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
  /// route moves the history, and the future completes with null once it has.
  Future<T?> pushNamed<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) async {
    _host._closeDrawers();
    if (_routes.isNotEmpty || _host.routerNav == null) {
      final route = _namedRoute<T>(routeName, arguments);
      if (route != null) return push<T>(route);
    }
    await _navigateNamed(routeName, arguments);
    return null;
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
      await _navigateNamed(routeName, arguments);
      return null;
    }
    nav.router.replaceWith(
      routeName,
      params: arguments is Map<String, dynamic> ? arguments : null,
    );
    _rememberArguments(arguments);
    return null;
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
    final navigated = await nav.router.navigateAndRemoveUntil(
      newRouteName,
      (entry) => predicate(_HistoryRoute(entry)),
      params: arguments is Map<String, dynamic> ? arguments : null,
    );
    if (navigated) _rememberArguments(arguments);
    return null;
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

  Future<void> _navigateNamed(String routeName, Object? arguments) async {
    final navigated = await _host.routerNav?.navigate(
      routeName,
      params: arguments is Map<String, dynamic> ? arguments : null,
    );
    if (navigated ?? false) _rememberArguments(arguments);
  }

  void _rememberArguments(Object? arguments) {
    final entry = _host.routerNav?.router.state.current;
    if (entry != null) _namedArguments[entry] = arguments;
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
    host.routerNav?.goBack();
  }

  /// Pops if there is something to pop, and says whether it did.
  Future<bool> maybePop<T extends Object?>([T? result]) async {
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
      _complete(_routes.removeLast(), null);
      popped = true;
    }
    if (popped) _host._requestRebuild();
  }

  bool _popRoute(Object? result) {
    if (_routes.length <= (_baseReplaced ? 1 : 0)) return false;
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
  }

  Widget _page(Route<dynamic> route) => _RouteScope(
    route: route,
    child: Builder(builder: route._buildPage),
  );

  @override
  Widget build(BuildContext context) => _NodeWidget((owner) {
    owner._navigators.add(this);
    _base.child = widget.child;
    final pages = [if (!_baseReplaced) _base, ..._routes];
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
    nav.router.onRouteChange((_) {
      if (mounted) setState(() {});
    });
    nav.bindSystemBack();
    _nav = nav;
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
      // The current route's node, built inside this build's binding scope.
      first = _NodeWidget((_) => nav.router.buildCurrentRoute());
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
    final node = UIBuilder.column(
      crossAxisAlignment: 'stretch',
      mainAxisSize: 'max',
      children: [
        if (bar is AppBar)
          owner.inSlot('appBar', () => bar._renderComposed(owner)),
        UIBuilder.expanded(
          child: _body(owner, above: _underBar(owner), fab: _fab(owner)),
        ),
        if (bottom != null) bottom,
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
/// [leading], [trailing] and [extended] are accepted and not drawn: the rail
/// is the platform's own list of destinations.
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
/// `vsync` is accepted for Flutter's signature; tabs switch without an
/// animation here, so there is nothing to synchronise.
class TabController extends ChangeNotifier {
  TabController({
    int initialIndex = 0,
    Duration? animationDuration,
    required this.length,
    TickerProvider? vsync,
  }) : _index = initialIndex,
       _previousIndex = initialIndex;

  final int length;
  int _index;
  int _previousIndex;

  int get index => _index;
  set index(int value) {
    if (value == _index || value < 0 || value >= length) return;
    _previousIndex = _index;
    _index = value;
    notifyListeners();
  }

  int get previousIndex => _previousIndex;

  /// Always false: a tab change lands at once.
  bool get indexIsChanging => false;

  /// Selects tab [value]. It does not animate; see the class doc.
  void animateTo(int value, {Duration? duration, Curve curve = Curves.ease}) =>
      index = value;
}

class _TabControllerScope extends InheritedWidget {
  const _TabControllerScope({required this.controller, required super.child});
  final TabController controller;
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
/// of Flutter's does once it has been visited. There is no swipe between
/// pages: the strip is how a tab is chosen.
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
    owner._watch(controller);
    return _renderOneOf(owner, children, controller.index) ??
        UIBuilder.sizedBox();
  }
}
