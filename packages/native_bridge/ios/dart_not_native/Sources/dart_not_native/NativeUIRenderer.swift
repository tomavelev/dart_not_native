import CoreText
import Flutter
import AVFoundation
import MapKit
import UIKit
import WebKit

/**
 iOS Native UI Renderer.

 Turns the widget tree the Dart side sends into UIKit views, and sends the
 events those views produce back. The node vocabulary is the one every renderer
 implements, so a screen written for the web DOM renderer renders here
 unchanged.

 Constructed by `DartNotNativePlugin` once the root view controller exists, so
 an app gets it from the dependency rather than by copying this file.
 */
class NativeUIRenderer {
  /// Text over a light colour the app stated, and over a dark one. The same
  /// two the Dart renderers use - see `lib/src/contrast.dart`.
  private static let onLight = "#212121"
  private static let onDark = "#ffffff"

  /// The colour text takes when the tree states none, while the children of a
  /// container that stated its own background are being rendered or patched.
  ///
  /// A render is depth-first and synchronous, so saving and restoring around
  /// those children is enough; `over(_:_:)` does both.
  private var textInForce: UIColor?

  static let methodChannelName = "com.programtom.dart_not_native/renderer"

  /// Dart's method for an event coming back from a native view.
  private static let eventMethod = "event"

  private let controller: UIViewController
  private let messenger: FlutterBinaryMessenger
  /// One appearance's colours, sent by Dart with `initialize`.
  private struct Palette {
    var primary = "#1976d2"
    var onPrimary = "#ffffff"
    var secondary = "#f57c00"
    var surface = "#ffffff"
    var surfaceVariant = "#f5f5f5"
    var text = "#212121"
    var textSecondary = "#757575"
    var divider = "#e0e0e0"
    var error = "#d32f2f"
    var success = "#388e3c"
    var warning = "#fbc02d"
    var info = "#0288d1"

    init() {}

    init(_ json: [String: Any], or fallback: Palette) {
      primary = json["primary"] as? String ?? fallback.primary
      onPrimary = json["onPrimary"] as? String ?? fallback.onPrimary
      secondary = json["secondary"] as? String ?? fallback.secondary
      surface = json["surface"] as? String ?? fallback.surface
      surfaceVariant = json["surfaceVariant"] as? String ?? fallback.surfaceVariant
      text = json["text"] as? String ?? fallback.text
      textSecondary = json["textSecondary"] as? String ?? fallback.textSecondary
      divider = json["divider"] as? String ?? fallback.divider
      error = json["error"] as? String ?? fallback.error
      success = json["success"] as? String ?? fallback.success
      warning = json["warning"] as? String ?? fallback.warning
      info = json["info"] as? String ?? fallback.info
    }

    static let darkDefault: Palette = {
      var p = Palette()
      p.primary = "#90caf9"
      p.onPrimary = "#00325b"
      p.secondary = "#ffb74d"
      p.surface = "#121212"
      p.surfaceVariant = "#1e1e1e"
      p.text = "#ececec"
      p.textSecondary = "#a8a8a8"
      p.divider = "#323232"
      p.error = "#ef5350"
      p.success = "#66bb6a"
      p.warning = "#ffca28"
      p.info = "#4fc3f7"
      return p
    }()
  }

  private var lightPalette = Palette()
  private var darkPalette = Palette.darkDefault

  /// "light", "dark" or "system" - which appearance to paint.
  private var themeMode: String = "light"

  /// The appearance last painted, so a render can notice the device changing
  /// its mind and rebuild instead of patching stale colours in place.
  private var paintedDark: Bool?

  /// Whether the screen reads right to left - the root node's `textDirection`.
  ///
  /// It is stated once, at the top of the tree, and can change from one render
  /// to the next (the app switched to Arabic). Like the appearance, it is not a
  /// prop any view below the root carries, so a change rebuilds: every stack
  /// has to turn round, and patching would keep the ones it has.
  private var isRTL = false

  /// Decoded remote images, by URL.
  ///
  /// `URLSession.shared` already keeps the *bytes* on disk (its `URLCache`
  /// honours the response's cache headers), but a rebuild still paid for a
  /// request and a decode, and showed the alt text in between. With the bitmap
  /// in memory an image the screen has already drawn is drawn again at once.
  /// NSCache lets go of entries by itself under memory pressure.
  private static let imageCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 32 * 1024 * 1024
    return cache
  }()

  /// Who is waiting for each URL being fetched, so ten rows showing the same
  /// avatar make one request between them. Main thread only.
  private static var imageWaiters: [String: [(UIImage?) -> Void]] = [:]

  /// Whether the dark palette is in force.
  ///
  /// In `system` mode this asks the host view controller, never the renderer's
  /// own container: the container carries an `overrideUserInterfaceStyle` (set
  /// from this very answer), so reading its traits would only ever report back
  /// what was last decided.
  private var isDarkAppearance: Bool {
    switch themeMode {
    case "dark": return true
    case "system": return controller.traitCollection.userInterfaceStyle == .dark
    default: return false
    }
  }

  /// The palette in force, and the other one - which the snackbar is drawn on,
  /// so it reads as a message over the app rather than vanishing into it.
  private var palette: Palette { isDarkAppearance ? darkPalette : lightPalette }
  private var inversePalette: Palette { isDarkAppearance ? lightPalette : darkPalette }

  private var themePrimary: String { palette.primary }
  private var themeOnPrimary: String { palette.onPrimary }
  private var themeSecondary: String { palette.secondary }
  private var themeSurface: String { palette.surface }
  private var themeSurfaceVariant: String { palette.surfaceVariant }
  private var themeText: String { palette.text }
  private var themeTextSecondary: String { palette.textSecondary }
  private var themeDivider: String { palette.divider }
  private var themeError: String { palette.error }
  private var themeSuccess: String { palette.success }
  private var themeWarning: String { palette.warning }
  private var themeInfo: String { palette.info }
  /// How see-through the Liquid Glass modal surfaces are, 0 (solid frost) to 1
  /// (barely there). The app sets it through the theme; see `applyModalSurface`
  /// and the modal scrim.
  private var themeGlassTransparency: CGFloat = 0
  /// Whether the app bar and FAB use Liquid Glass (the default) or a flat fill.
  /// Set false through the theme for, say, a solid branded app bar.
  private var themeGlassChrome: Bool = true

  /// The semantic colour for a node's `variant`, themed where it maps to a
  /// palette entry.
  private func variantColor(_ variant: Any?) -> String {
    switch variant as? String {
    case "secondary": return themeSecondary
    case "success": return themeSuccess
    case "error": return themeError
    case "warning": return themeWarning
    case "info": return themeInfo
    default: return themePrimary
    }
  }

  /// The surface colour of the appearance in force.
  private func surfaceColor() -> UIColor {
    color(themeSurface, fallback: themeSurface)
  }

  /// The raised-surface colour - cards, and a modal panel.
  private func surfaceVariantColor() -> UIColor {
    color(themeSurfaceVariant, fallback: themeSurfaceVariant)
  }

  private var rootContainer: DnnRootContainerView?
  private var methodChannel: FlutterMethodChannel?

  /// The `FlutterSlot` views the last render left on screen, what was last
  /// said about each, and whether a modal overlay is drawn above them - see
  /// `updateSlotRects`.
  private var slotViews: [DnnFlutterSlotView] = []
  private var slotReports: [String: String] = [:]
  private var slotsCovered = false

  /// A `Scroll`'s offset by its id, which survives its view being rebuilt, and
  /// the `scrollVersion` each scroller (or lazy list) has already obeyed.
  private var scrollOffsets: [String: CGFloat] = [:]
  private var scrollVersions: [String: Int] = [:]

  /// The viewport last reported to Dart, and how much of the host view the
  /// keyboard covers - see `sendViewport`.
  private var lastViewport: NSDictionary?
  private var keyboardInset: CGFloat = 0

  /// The app-lifecycle observers, kept so `dispose` can take them down.
  private var lifecycleObservers: [NSObjectProtocol] = []

  /// The container's bottom, held off the host view's bottom by however much of
  /// it the keyboard covers. UIKit does not move anything out from under the
  /// keyboard by itself, so this is what keeps a focused field reachable; see
  /// `keyboardChanged`.
  private var containerBottom: NSLayoutConstraint?

  /// The keyboard observers, kept so `dispose` can take them down.
  private var keyboardObservers: [NSObjectProtocol] = []

  /// Views that report a value carry the node they came from, so the handler
  /// can send the right event without capturing the whole tree.
  private var bindings: [Int: [String: Any]] = [:]

  /// Snackbars outlive the views that draw them, since every render rebuilds
  /// the views: these are keyed by the snackbar's identity, so its timeout
  /// runs once however often it is rendered meanwhile.
  private var shownSnackbars: Set<String> = []
  private var renderedSnackbars: Set<String> = []
  private var snackbarTimers: [String: DispatchWorkItem] = [:]

  /// A long list's scroll offset and last reported range, by list id, which
  /// survive the list's views being rebuilt.
  private var listOffsets: [String: CGFloat] = [:]
  private var listRanges: [String: (first: Int, last: Int)] = [:]

  /// The focus ask each field has already carried out, by event id, so the
  /// same one is not obeyed twice. "Focus this" is a moment, and a tree only
  /// carries states - the version is how the moment travels.
  private var focusVersions: [String: Int] = [:]

  /// The version an `autofocus` counts as, which is asked once.
  private static let autofocusVersion = -1

  /// The pixels each list of rows of their own heights last reported.
  private var listOffsetReports: [String: (offset: CGFloat, viewport: CGFloat)] = [:]

  /// Node types the render in progress could not draw; reported back to Dart.
  private var unknownTypes: Set<String> = []

  /// True while a render is tearing the focused field down and standing it back
  /// up. The focus and blur that churn causes are the renderer's doing, not the
  /// user's, so they are suppressed - otherwise restoring first responder fires
  /// a focus event that re-renders, which refocuses, which re-renders, forever.
  private var restoringFocus = false

  /// The normalised tree the views currently show, and the view that shows it.
  /// The next render diffs against them; a nil tree forces a full rebuild.
  private var currentTree: [String: Any]?
  private var currentRoot: UIView?

  /// The Material Icons font, which `uses-material-design: true` already bundles
  /// into every build, so an icon is drawn as the real glyph rather than an
  /// approximate SF Symbol. Nil if the font is not where it is expected.
  private lazy var iconFont: UIFont? = {
    let key = FlutterDartProject.lookupKey(forAsset: "fonts/MaterialIcons-Regular.otf")
    guard let path = Bundle.main.path(forResource: key, ofType: nil),
      let data = NSData(contentsOfFile: path),
      let provider = CGDataProvider(data: data),
      let cgFont = CGFont(provider),
      let name = cgFont.postScriptName as String?
    else { return nil }
    CTFontManagerRegisterGraphicsFont(cgFont, nil)  // harmless if already registered
    return UIFont(name: name, size: 24)
  }()

  init(controller: UIViewController, messenger: FlutterBinaryMessenger) {
    self.controller = controller
    self.messenger = messenger
    setupChannels()
  }

  private func setupChannels() {
    let channel = FlutterMethodChannel(
      name: NativeUIRenderer.methodChannelName,
      binaryMessenger: messenger
    )
    methodChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "initialize":
        if let t = call.arguments as? [String: Any] {
          // The light palette is the message's own fields; the dark one is
          // nested, and absent means the built-in dark palette.
          self?.lightPalette = Palette(t, or: Palette())
          self?.darkPalette = Palette(
            t["dark"] as? [String: Any] ?? [:], or: Palette.darkDefault)
          self?.themeMode = t["mode"] as? String ?? "light"
          if let raw = self?.number(t["glassTransparency"]) {
            self?.themeGlassTransparency = max(0, min(1, raw))
          }
          if let chrome = t["glassChrome"] as? Bool {
            self?.themeGlassChrome = chrome
          }
        }
        self?.initialize()
        // Every initialise is a Dart side that has not heard the viewport yet
        // - a hot restart keeps the container and loses everything else.
        self?.sendViewport(force: true)
        result(nil)
      case "render":
        guard let args = call.arguments as? [String: Any] else {
          return result("Error: invalid arguments")
        }
        result(self?.renderTree(args))
      case "startFrameProbe":
        self?.startFrameProbe()
        result(nil)
      case "stopFrameProbe":
        result(self?.stopFrameProbe())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func initialize() {
    guard rootContainer == nil else { return }

    // A view of its own kind, because a `FlutterSlot` needs a hole in it: see
    // `DnnRootContainerView`.
    let container = DnnRootContainerView()
    container.onLayout = { [weak self] in
      self?.sendViewport()
      self?.scheduleSlotUpdate()
    }
    container.translatesAutoresizingMaskIntoConstraints = false
    // Pin the rendered subtree to the appearance the theme asked for, so the
    // system controls the renderer does not paint itself - a switch, a text
    // field's rounded border, a system image - match the palette rather than
    // following the device somewhere else. In `system` mode this is the
    // device's own answer, so the two agree.
    paintedDark = isDarkAppearance
    container.overrideUserInterfaceStyle = isDarkAppearance ? .dark : .light
    container.backgroundColor = surfaceColor()
    controller.view.addSubview(container)

    // Constraints rather than an autoresizing mask, because the bottom one is
    // the keyboard avoidance: `keyboardChanged` shortens the container by the
    // covered height, and everything inside - a scaffold's body scroll view, a
    // lazy list, a bottom sheet anchored to the container's bottom edge - moves
    // up with it, which is what `resizeToAvoidBottomInset` does on Flutter.
    let bottom = container.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
    containerBottom = bottom
    NSLayoutConstraint.activate([
      container.topAnchor.constraint(equalTo: controller.view.topAnchor),
      container.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      bottom,
    ])
    // A FlutterView answers `accessibilityElements` with Flutter's own
    // semantics, and UIKit takes that list *instead of* the view's real
    // subviews - so every native view this renderer draws was invisible to
    // VoiceOver, and to anything driving the app through the accessibility
    // tree. Naming the container as the one element puts the subtree back.
    controller.view.accessibilityElements = [container]
    rootContainer = container
    observeKeyboard()
    observeLifecycle()
  }

  // MARK: - Renderer events

  /**
   Tells Dart how much room there is: `dnn:viewport`, sent once the renderer is
   up and again whenever any of it changes.

   The size is the host view's - the whole window - rather than the
   container's, which the keyboard shortens: the keyboard is reported as
   `keyboardInset` instead, the way Flutter's `MediaQuery` separates the two,
   so an app subtracting the inset does not subtract it twice.
   */
  private func sendViewport(force: Bool = false) {
    guard rootContainer != nil, let host = controller.view else { return }
    let size = host.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    let safe = host.safeAreaInsets
    let data: [String: Any] = [
      "width": Double(size.width),
      "height": Double(size.height),
      "paddingTop": Double(safe.top),
      "paddingBottom": Double(safe.bottom),
      "paddingLeft": Double(safe.left),
      "paddingRight": Double(safe.right),
      "keyboardInset": Double(keyboardInset),
      "devicePixelRatio": Double(UIScreen.main.scale),
      // The content size category, as the factor it scales body text by.
      "textScale": Double(UIFontMetrics.default.scaledValue(for: 100) / 100),
      "dark": controller.traitCollection.userInterfaceStyle == .dark,
    ]
    let boxed = data as NSDictionary
    if !force, let last = lastViewport, last.isEqual(boxed) { return }
    lastViewport = boxed
    send(eventId: "dnn:viewport", data: data)
  }

  /// Forwards the application's lifecycle as `dnn:lifecycle`, and re-reads the
  /// viewport when the text size setting changes.
  private func observeLifecycle() {
    guard lifecycleObservers.isEmpty else { return }
    let centre = NotificationCenter.default
    let states: [(NSNotification.Name, String)] = [
      (UIApplication.didBecomeActiveNotification, "resumed"),
      (UIApplication.willResignActiveNotification, "inactive"),
      (UIApplication.willEnterForegroundNotification, "inactive"),
      (UIApplication.didEnterBackgroundNotification, "paused"),
      (UIApplication.willTerminateNotification, "detached"),
    ]
    for (name, state) in states {
      let token = centre.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in
        self?.send(eventId: "dnn:lifecycle", data: ["state": state])
        if state == "resumed" { self?.sendViewport() }
      }
      lifecycleObservers.append(token)
    }
    let sizeToken = centre.addObserver(
      forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.sendViewport()
    }
    lifecycleObservers.append(sizeToken)
  }

  // MARK: - Frame probe

  private var frameProbeLink: CADisplayLink?
  private var frameProbeLast: CFTimeInterval = 0
  private var frameProbeNominal: CFTimeInterval = 0
  private var frameProbeIntervals: [Double] = []

  /**
   Records the gap between display refreshes while the probe runs.

   A `CADisplayLink` fires on the main thread once per refresh, so it measures
   the thing that matters here: the renderer's own work - laying out a lazy
   list's window, rebuilding a subtree - runs on that same thread, and anything
   that overruns a frame delays the next callback by exactly as much as a viewer
   would see. An idle screen reads as a clean run of nominal intervals, which is
   the answer one wants when nothing is happening.

   Nothing is recorded, and no link exists, until `startFrameProbe` is called.
   */
  private func startFrameProbe() {
    releaseFrameProbe()
    frameProbeIntervals.removeAll()
    frameProbeLast = 0
    frameProbeNominal = 0
    let link = CADisplayLink(target: self, selector: #selector(frameProbeTick(_:)))
    link.add(to: .main, forMode: .common)
    frameProbeLink = link
  }

  @objc private func frameProbeTick(_ link: CADisplayLink) {
    // The nominal duration is the display's own frame length, which is where
    // the budget comes from - no need to ask UIScreen, and correct on a
    // ProMotion display that is not running at its maximum.
    if link.duration > 0 { frameProbeNominal = link.duration }
    if frameProbeLast > 0 {
      frameProbeIntervals.append((link.timestamp - frameProbeLast) * 1000)
    }
    frameProbeLast = link.timestamp
  }

  private func stopFrameProbe() -> [String: Any]? {
    guard frameProbeLink != nil else { return nil }
    releaseFrameProbe()
    let hz = frameProbeNominal > 0 ? 1 / frameProbeNominal : 60
    return ["intervalsMs": frameProbeIntervals, "refreshHz": hz]
  }

  private func releaseFrameProbe() {
    frameProbeLink?.invalidate()
    frameProbeLink = nil
  }

  // MARK: - Keyboard avoidance

  private func observeKeyboard() {
    guard keyboardObservers.isEmpty else { return }
    let centre = NotificationCenter.default
    for name in [
      UIResponder.keyboardWillChangeFrameNotification,
      UIResponder.keyboardWillHideNotification,
    ] {
      let token = centre.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] note in
        self?.keyboardChanged(note, hiding: name == UIResponder.keyboardWillHideNotification)
      }
      keyboardObservers.append(token)
    }
  }

  /**
   Shortens the container by however much of the host view the keyboard covers,
   in step with the keyboard's own animation, then brings the focused field into
   view inside whatever scrolls it.

   The overlap is measured against `controller.view`, which the keyboard never
   moves, rather than against the container this is about to resize - measuring
   against the container would read its own shrinking as the keyboard going
   away and oscillate. A hardware or floating keyboard overlaps nothing, so the
   arithmetic leaves the container alone, and so does an already-inset host.
   */
  private func keyboardChanged(_ note: Notification, hiding: Bool) {
    guard let container = rootContainer, let bottom = containerBottom,
      let host = controller.view, let window = container.window
    else { return }

    var overlap: CGFloat = 0
    if !hiding,
      let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    {
      // Screen coordinates → window → host, the conversion that stays correct
      // in a split-screen or Stage Manager window.
      let inHost = host.convert(window.convert(end, from: nil), from: window)
      overlap = max(0, host.bounds.maxY - inHost.minY)
    }
    if keyboardInset != overlap {
      keyboardInset = overlap
      sendViewport()
    }
    guard bottom.constant != -overlap else { return }
    bottom.constant = -overlap

    let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
    let curve = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int)
      .map { UIView.AnimationOptions(rawValue: UInt($0) << 16) } ?? []
    UIView.animate(withDuration: duration, delay: 0, options: curve) {
      host.layoutIfNeeded()
    } completion: { _ in
      self.scrollFirstResponderIntoView()
    }
  }

  /**
   Scrolls the focused field into view inside its nearest scroll view.

   A plain UIScrollView does nothing about the first responder on its own (only
   a table view does), so a field low in a scaffold's body would sit under the
   keyboard even after the container shrinks.
   */
  private func scrollFirstResponderIntoView() {
    guard let container = rootContainer,
      let responder = firstResponder(in: container)
    else { return }
    var view: UIView? = responder.superview
    while let current = view, !(current is UIScrollView) { view = current.superview }
    guard let scroll = view as? UIScrollView else { return }
    // A little margin, so the field does not land flush against the keyboard.
    let rect = scroll.convert(responder.bounds, from: responder).insetBy(dx: 0, dy: -12)
    scroll.scrollRectToVisible(rect, animated: true)
  }

  private func firstResponder(in view: UIView) -> UIView? {
    if view.isFirstResponder { return view }
    for child in view.subviews {
      if let found = firstResponder(in: child) { return found }
    }
    return nil
  }

  /// Removes the container this renderer added to the view controller.
  func dispose() {
    releaseFrameProbe()
    keyboardObservers.forEach(NotificationCenter.default.removeObserver)
    keyboardObservers.removeAll()
    lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    lifecycleObservers.removeAll()
    slotViews.removeAll()
    slotReports.removeAll()
    scrollOffsets.removeAll()
    scrollVersions.removeAll()
    lastViewport = nil
    containerBottom = nil
    rootContainer?.removeFromSuperview()
    rootContainer = nil
    currentTree = nil
    currentRoot = nil
    methodChannel?.setMethodCallHandler(nil)
    methodChannel = nil
    bindings.removeAll()
    snackbarTimers.values.forEach { $0.cancel() }
    snackbarTimers.removeAll()
    shownSnackbars.removeAll()
    listOffsets.removeAll()
    listRanges.removeAll()
    listOffsetReports.removeAll()
    focusVersions.removeAll()
  }

  /**
   Renders a tree, diffing it against the one already on screen.

   Two paths, in order:

    1. `tryPatch` walks the old and new trees together. A node whose type and
       props match keeps its view and recurses into its children; a changed leaf
       is re-derived in place (`patchText`/`patchButton`/`patchAppBar`/
       `patchTextField` and the rest); a stacking container reconciles its
       children by `id` so a list that gains, loses or reorders a row moves the
       views it already has, and `reconcileLazyList` does the same by
       `<id>/<index>` for the windowed rows. A focused text field is left
       entirely alone.
    2. Anything `tryPatch` cannot express - a different type, a different child
       count, a prop only a rebuild can apply - returns false and falls through
       to the full rebuild below, which is always correct. So the diff can only
       ever make a render faster, never wrong.

   The shape is the web renderer's `_syncChildren`
   (packages/native_bridge/lib/web_ui/web_renderer.dart), ported to UIKit, where
   the saving is larger because creating a UIView costs far more than creating a
   DOM element.

   Neither path is covered by the test suite - `renderer_coverage_test` only
   pins that every node type appears in the dispatch - so changes here need a
   device or simulator to develop against.
   */
  private func renderTree(_ tree: [String: Any]) -> [String: Any]? {
    guard let container = rootContainer else {
      return ["error": "Error: container not initialized"]
    }
    var next = normalized(tree)
    unknownTypes.removeAll()

    // From here on an event is this tree's: a patch can raise one before it
    // returns. The number rides beside the tree, not in it, so it is taken
    // off before the diff - a root that differs only by it has not changed.
    treeBuild = (tree["build"] as? NSNumber)?.intValue
    next.removeValue(forKey: "build")

    // The reading direction belongs to the screen, so it rides on the root and
    // is taken off again here: nothing below needs to see it as a prop, and a
    // root that differs only by it should not look changed to the diff. A
    // change of direction rebuilds, for the reason a change of appearance does.
    let rtl = (next["textDirection"] as? String) == "rtl"
    next.removeValue(forKey: "textDirection")
    if isRTL != rtl {
      isRTL = rtl
      currentTree = nil
    }
    container.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight

    // A colour is not a prop, so nothing in the tree changes when the device
    // switches appearance: the patch below would happily keep every view it
    // has, still painted in the old palette. Notice the switch here and force
    // the rebuild instead. (Dart sends the render: the Flutter host watches
    // `didChangePlatformBrightness`, which fires for the same event that moved
    // the trait collection this reads.)
    let dark = isDarkAppearance
    if paintedDark != dark {
      paintedDark = dark
      container.overrideUserInterfaceStyle = dark ? .dark : .light
      container.backgroundColor = surfaceColor()
      currentTree = nil
    }

    // Fast path: the tree kept its shape, so patch the changed leaves in place
    // and leave every other view - with the first responder, caret and scroll
    // it holds - untouched. This is what lets a field be typed into and a list
    // keep its position across a re-render. Any mismatch returns false and
    // falls through to the full rebuild, which is always correct.
    if let old = currentTree, let oldRoot = currentRoot,
      tryPatch(oldRoot, old, next)
    {
      currentTree = next
      // A patch builds new views too, and they need turning like the rest.
      applyDirection(oldRoot)
      finishRender(next)
      // A patch builds new views too - a lazy list's newly visible rows - so it
      // can meet an unknown type as readily as a rebuild can.
      return unknownTypes.isEmpty ? nil : ["unknownTypes": unknownTypes.sorted()]
    }

    // Full rebuild. It tears down the focused field, so remember which one (by
    // its event id) and whether the caret was at the end, and restore both to
    // the rebuilt field - otherwise the render a keystroke triggers would drop
    // the first responder. Restoring it fires the platform's own focus event,
    // which would re-render and refocus forever, so restoringFocus suppresses
    // the focus/blur the renderer itself causes.
    let focused = container.firstResponderTextField()
    let focusKey = focused?.accessibilityIdentifier
    let caretAtEnd =
      focused.map { field -> Bool in
        guard let caret = field.selectedTextRange?.end else { return false }
        return field.compare(caret, to: field.endOfDocument) == .orderedSame
      } ?? false
    restoringFocus = focusKey != nil

    container.subviews.forEach { $0.removeFromSuperview() }
    bindings.removeAll()
    renderedSnackbars.removeAll()

    let rendered = renderWidget(next)
    // Only once the whole tree is built is it known which snackbars left it.
    forgetRemovedSnackbars()
    guard let view = rendered else {
      currentRoot = nil
      currentTree = nil
      finishRender(next)
      return nil
    }
    view.frame = container.bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(view)
    applyDirection(view)
    currentRoot = view
    currentTree = next

    if let focusKey, let field = container.textField(withIdentifier: focusKey) {
      field.becomeFirstResponder()
      // Caret to the end, so appended characters keep their order.
      if caretAtEnd {
        let end = field.endOfDocument
        field.selectedTextRange = field.textRange(from: end, to: end)
      }
    }
    restoringFocus = false
    finishRender(next)

    // An unknown node type draws a placeholder rather than throwing, so report
    // it here instead of leaving it as a silent surprise. Structured, so Dart
    // can list the types rather than parse the sentence.
    return unknownTypes.isEmpty ? nil : ["unknownTypes": unknownTypes.sorted()]
  }

  /**
   Tells [view] and everything under it which way the screen reads.

   UIKit does not hand `semanticContentAttribute` down: each view answers for
   itself, and one that was never told follows the *app's* language, which is
   not the tree's. So every view is told, after each render - a stack view
   then runs its arranged subviews from the right, leading and trailing
   anchors swap sides, and a control puts its image on the other side of its
   title. It is forced both ways, so a left-to-right screen on a phone set to
   Arabic stays left to right, as the tree asked.

   Text that states no alignment starts where reading starts. `.natural` means
   the app's language rather than the view's, so it is spelt out.

   A control, a label, a web page and a map are told and not entered: what is
   inside them is theirs to arrange.
   */
  private func applyDirection(_ view: UIView) {
    let wanted: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
    if view.semanticContentAttribute != wanted { view.semanticContentAttribute = wanted }
    if let label = view as? UILabel {
      if isRTL, label.textAlignment == .natural { label.textAlignment = .right }
      return
    }
    if let field = view as? UITextField {
      if isRTL, field.textAlignment == .natural { field.textAlignment = .right }
      return
    }
    if let text = view as? UITextView {
      if isRTL, text.textAlignment == .natural { text.textAlignment = .right }
      return
    }
    if view is UIControl || view is UITabBar || view is WKWebView || view is MKMapView {
      return
    }
    for sub in view.subviews { applyDirection(sub) }
  }

  // MARK: - Reconciliation (the shape-preserving fast path)

  /// Patches [view] from [oldNode] to [newNode] in place, returning true only
  /// if the whole subtree kept its shape and every change was one this knows
  /// how to apply. A false return means "rebuild".
  private func tryPatch(_ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any])
    -> Bool
  {
    // An app bar's children are drawn in its foreground colour, which is not
    // always the one that contrasts with its background: the app can state it.
    let type = newNode["type"] as? String
    if type == "AppBar" || type == "NavigationBar" {
      let saved = textInForce
      textInForce = appBarForeground(newNode)
      defer { textInForce = saved }
      return patchNode(view, oldNode, newNode)
    }
    // The colour in force inside the node changed - a card went from a light
    // fill to a dark one. Everything below that states no colour of its own
    // was painted in the old one, and a node whose own props did not change
    // is not painted again. So this is a rebuild.
    let stated = statedBackground(newNode) as? String
    let before = statedBackground(oldNode) as? String
    if stated != before {
      let now = stated.map { textOn(color($0, fallback: $0)) }
      let was = before.map { textOn(color($0, fallback: $0)) }
      if now != was { return false }
    }
    return over(statedBackground(newNode)) { patchNode(view, oldNode, newNode) }
  }

  private func patchNode(_ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any])
    -> Bool
  {
    if (oldNode["type"] as? String) != (newNode["type"] as? String) { return false }
    // The id and role the view was last given are taken off before anything is
    // patched, and the new ones put on after: an id is not a prop the patch
    // below looks at, and it can arrive, change or go on a view that is kept.
    releaseIdentity(view, oldNode, newNode)
    // A lazy list frames its windowed rows by index rather than stacking them,
    // so it has its own keyed reconcile.
    if (newNode["type"] as? String) == "LazyList" {
      guard reconcileLazyList(view, oldNode, newNode) else { return false }
      identify(view, newNode)
      return true
    }
    let type = newNode["type"] as? String
    // The spinner of a pull-to-refresh stays for as long as the tree says so,
    // and the tree that ends it need not differ from the one before the pull.
    if type == "Scroll" {
      (view as? DnnScrollView)?.setRefreshing(newNode["refreshing"] as? Bool ?? false)
    }
    if !patchSelf(view, oldNode, newNode) { return false }
    identify(view, newNode)
    // A live region says what it now reads as - once its children have been
    // patched too, which is when this function returns.
    defer { (view as? DnnBoxView)?.announceChanges() }
    // A slot's child is its fallback, which this renderer never draws.
    if type == "FlutterSlot" { return true }

    let oldKids = childNodes(oldNode)
    let newKids = childNodes(newNode)
    if oldKids.isEmpty && newKids.isEmpty { return true }

    // A view that holds one child can swap it, so a child that cannot be
    // patched is rebuilt where it stands rather than taking the screen with it.
    if type == "Box" || type == "Canvas" || type == "Positioned" || type == "Scroll" {
      guard let host = view as? DnnSingleChildHost else { return false }
      return patchHostedChild(host, oldKids, newKids, in: newNode)
    }
    if type == "Stack" {
      guard let layers = view as? DnnStackView else { return false }
      return reconcileLayers(layers, oldKids, newKids)
    }

    // A stacking container reconciles its children by id, so a row inserted,
    // removed or reordered moves the views already there instead of every row
    // after it being rebuilt.
    if let stack = keyedListContainer(view, newNode) {
      reconcileChildren(stack, oldKids, newKids)
      return true
    }

    // Everything else (a Scaffold, a single-child wrapper) lines its children up
    // by position, and the count cannot change without a rebuild.
    if oldKids.count != newKids.count { return false }
    guard let views = childViews(view, newNode), views.count == newKids.count else {
      return false
    }
    for i in newKids.indices where !tryPatch(views[i], oldKids[i], newKids[i]) {
      return false
    }
    return true
  }

  /// The stack whose arranged subviews are [node]'s children one to one, or nil
  /// if this node is not a plain stacking list.
  private func keyedListContainer(_ view: UIView, _ node: [String: Any]) -> UIStackView? {
    // A stack that spaces its children out carries a spacer *between* each
    // pair, so its arranged subviews no longer line up with the children one
    // to one; `childViews` filters those out and patches by position instead.
    switch node["mainAxisAlignment"] as? String {
    case "spaceBetween", "spaceAround", "spaceEvenly":
      if node["mainAxisSize"] as? String != "min" { return nil }
    default:
      break
    }
    switch node["type"] as? String {
    case "Column", "Row", "VStack", "HStack", "List", "ListView":
      return view as? UIStackView
    default:
      return nil
    }
  }

  /// Reconciles [stack]'s arranged subviews from [oldKids] to [newKids], matching
  /// children that carry an `id` by it so a row keeps (and moves) the view it
  /// already has; children without an id fall back to matching by position.
  /// Mirrors the web renderer's `_syncChildren` (and the Kotlin renderer).
  private func reconcileChildren(
    _ stack: UIStackView, _ oldKids: [[String: Any]], _ newKids: [[String: Any]]
  ) {
    var standing = oldKids
    // A stack that aligns its children carries a spacer before them, and
    // center one after as well; neither is a child, so every index into the
    // stack is shifted past the leading one and nothing is appended after the
    // trailing one.
    let lead = stack.arrangedSubviews.first is FlexibleSpacer ? 1 : 0
    let trail = stack.arrangedSubviews.count > lead
      && stack.arrangedSubviews.last is FlexibleSpacer ? 1 : 0
    var count: Int { stack.arrangedSubviews.count - lead - trail }

    for i in newKids.indices {
      let node = newKids[i]
      var existing: UIView? = i < count ? stack.arrangedSubviews[i + lead] : nil
      var before: [String: Any]? = i < standing.count ? standing[i] : nil

      if let id = node["id"] as? String, (before?["id"] as? String) != id {
        if let found = indexOfId(standing, id, from: i) {
          // The row is further down: move its view up to here.
          let moved = stack.arrangedSubviews[found + lead]
          stack.removeArrangedSubview(moved)
          stack.insertArrangedSubview(moved, at: i + lead)
          standing.insert(standing.remove(at: found), at: i)
          existing = moved
          before = standing[i]
        } else if (before?["id"] as? String) != nil {
          // A new keyed row among keyed ones: insert rather than overwrite a row
          // still wanted further down.
          let inserted = buildChild(node)
          stack.insertArrangedSubview(inserted, at: i + lead)
          takeWidthOffered(inserted, node, in: stack)
          standing.insert(node, at: i)
          continue
        }
      }

      if let existing, let before,
        (before["type"] as? String) == (node["type"] as? String),
        tryPatch(existing, before, node)
      {
        standing[i] = node
        continue
      }

      let created = buildChild(node)
      if let existing {
        existing.removeFromSuperview()
        stack.insertArrangedSubview(created, at: i + lead)
        standing[i] = node
      } else {
        stack.insertArrangedSubview(created, at: count + lead)
        standing.append(node)
      }
      takeWidthOffered(created, node, in: stack)
    }

    while count > newKids.count {
      stack.arrangedSubviews[count + lead - 1].removeFromSuperview()
    }
  }

  /// First index at or after [from] whose node carries [id].
  private func indexOfId(_ nodes: [[String: Any]], _ id: String, from: Int) -> Int? {
    for i in from..<nodes.count where (nodes[i]["id"] as? String) == id { return i }
    return nil
  }

  private func buildChild(_ node: [String: Any]) -> UIView {
    renderWidget(node) ?? UIView()
  }

  /**
   Reconciles a lazy list's windowed rows by their `<id>/<index>` keys, so a
   scroll (which shifts the window) or an edit reuses the rows the two windows
   share rather than rebuilding all of them. The rows are held in window order,
   so the old row at position i produced `list.rows[i]`; the list re-frames each
   by its new index. Bails to a rebuild if the view is not a lazy list.
   */
  private func reconcileLazyList(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) -> Bool {
    guard let list = view as? LazyListView else { return false }
    let oldRowNodes = childNodes(oldNode)
    let newRowNodes = childNodes(newNode)
    if list.rows.count != oldRowNodes.count { return false }

    let extent = max(1, number(newNode["itemExtent"]) ?? 48)
    let startIndex = max(0, Int(number(newNode["startIndex"]) ?? 0))
    let itemCount = max(0, Int(number(newNode["itemCount"]) ?? 0))

    var oldByKey: [String: Int] = [:]
    for (i, node) in oldRowNodes.enumerated() {
      if let key = node["id"] as? String { oldByKey[key] = i }
    }

    // The row view for each new row, in window order - reused from the old
    // window where the keys match, built fresh otherwise.
    var newRows: [UIView] = []
    var reused = Set<Int>()
    for newRow in newRowNodes {
      let oldIndex = (newRow["id"] as? String).flatMap { oldByKey[$0] }
      if let oldIndex, tryPatch(list.rows[oldIndex], oldRowNodes[oldIndex], newRow) {
        newRows.append(list.rows[oldIndex])
        reused.insert(oldIndex)
      } else {
        let built = renderWidget(newRow) ?? UIView()
        built.translatesAutoresizingMaskIntoConstraints = true
        list.addSubview(built)
        newRows.append(built)
      }
    }
    for (i, oldRow) in list.rows.enumerated() where !reused.contains(i) {
      oldRow.removeFromSuperview()
    }
    list.setWindow(
      rows: newRows,
      startIndex: startIndex,
      itemCount: itemCount,
      itemExtent: extent,
      rowExtents: rowExtents(newNode),
      startOffset: number(newNode["startOffset"]) ?? 0,
      totalExtent: number(newNode["totalExtent"]) ?? 0)
    // The list lays out before it scrolls, so the jump is clamped to the
    // height the new window gives it.
    if let target = lazyListJump(newNode, id: newNode["id"] as? String ?? "") {
      list.restoreOffset = target
      list.setNeedsLayout()
    }
    return true
  }

  /// The offset [node] asks its list to jump to, if it has not been obeyed.
  private func lazyListJump(_ node: [String: Any], id: String) -> CGFloat? {
    guard let target = number(node["scrollOffset"]) else { return nil }
    let version = (node["scrollVersion"] as? NSNumber)?.intValue ?? 0
    let key = "lazy:" + id
    if scrollVersions[key] == version { return nil }
    scrollVersions[key] = version
    return max(0, target)
  }

  /// The views that hold [node]'s children, one per child in order, or nil if
  /// this node's views cannot be walked 1:1 (the caller rebuilds instead).
  private func childViews(_ view: UIView, _ node: [String: Any]) -> [UIView]? {
    let kids = childNodes(node)
    // child-views:begin
    switch node["type"] as? String {
    case "Scaffold", "NavigationStack":
      return scaffoldChildViews(view, node)
    case "Card":
      // The card's children live in its content stack, after an optional title.
      guard let content = view.subviews.compactMap({ $0 as? UIStackView }).first
      else { return nil }
      let titleOffset = (node["title"] as? String) != nil ? 1 : 0
      guard content.arrangedSubviews.count - titleOffset == kids.count else { return nil }
      return Array(content.arrangedSubviews[titleOffset...])
    case "Column", "Row", "VStack", "HStack", "List", "ListView":
      guard let stack = view as? UIStackView else { return nil }
      let children = stack.arrangedSubviews.filter { !($0 is FlexibleSpacer) }
      return children.count == kids.count ? children : nil
    case "Center", "Padding", "Expanded", "Overlay", "AnimatedOpacity",
      "AnimatedContainer", "BottomBar":
      return view.subviews.count == kids.count ? view.subviews : nil
    case "AppBar", "NavigationBar":
      // The title subtree and the actions, which the bar remembers because
      // they sit among views of its own - the leading button, the spacer.
      guard let bar = view as? DnnAppBarView, bar.nodeViews.count == kids.count
      else { return nil }
      return bar.nodeViews
    case "Image":
      // The one child is the fallback, which stays in its host - hidden once
      // the picture is in - so that it can still be found here.
      guard let host = view.subviews.compactMap({ $0 as? ImageFallbackHost }).first,
        host.subviews.count == kids.count
      else { return nil }
      return host.subviews
    case "SwipeActions":
      // The row sits inside the foreground layer; the action bar is the view
      // behind it. Without this case the row's view could never be patched, so
      // a lazy list rebuilt every row it had matched by key - the whole point
      // of the keyed reconcile.
      guard let swipe = view as? SwipeActionsView,
        swipe.foreground.subviews.count == kids.count
      else { return nil }
      return swipe.foreground.subviews
    default:
      return kids.isEmpty ? [] : nil
    }
    // child-views:end
  }

  /// A Scaffold puts its children in different places - the app bar and body in
  /// a stack, the body wrapped in a scroll view, the FAB pinned over the top -
  /// so map each child node back to the view that holds it.
  private func scaffoldChildViews(_ view: UIView, _ node: [String: Any]) -> [UIView]? {
    guard let column = view.subviews.first(where: { $0 is UIStackView }) as? UIStackView
    else { return nil }
    let fab = view.subviews.first(where: { !($0 is UIStackView) })
    let bodyScrolls = node["bodyScrolls"] as? Bool ?? true
    var result: [UIView] = []
    var columnIndex = 0
    for child in childNodes(node) {
      switch child["type"] as? String {
      case "FloatingActionButton":
        guard let fab else { return nil }
        result.append(fab)
      case "BottomBar":
        // Always the last thing in the column, wherever it sits in the tree.
        guard let last = column.arrangedSubviews.last else { return nil }
        result.append(last)
      case "AppBar", "NavigationBar":
        guard columnIndex < column.arrangedSubviews.count else { return nil }
        result.append(column.arrangedSubviews[columnIndex])
        columnIndex += 1
      default:
        guard columnIndex < column.arrangedSubviews.count else { return nil }
        let holder = column.arrangedSubviews[columnIndex]
        columnIndex += 1
        if child["type"] as? String == "LazyList" || !bodyScrolls {
          result.append(holder)
        } else if let scroll = holder as? UIScrollView, let body = scroll.subviews.first {
          result.append(body)
        } else {
          result.append(holder)
        }
      }
    }
    return result
  }

  /// Applies [newNode]'s own props to [view] in place. Returns true when the
  /// props are unchanged, or changed only in ways this knows how to re-derive;
  /// false means the change needs a rebuild.
  private func patchSelf(_ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any])
    -> Bool
  {
    if propsEqual(oldNode, newNode) { return true }
    switch newNode["type"] as? String {
    case "Text": return patchText(view, newNode)
    case "Button", "MaterialButton": return patchButton(view, oldNode, newNode)
    case "AppBar", "NavigationBar": return patchAppBar(view, oldNode, newNode)
    case "Scaffold", "NavigationStack": return patchScaffold(view, oldNode, newNode)
    case "IconButton": return patchIconButton(view, oldNode, newNode)
    case "Box": return patchBox(view, newNode)
    case "Canvas": return patchCanvas(view, oldNode, newNode)
    case "Positioned": return patchPositioned(view, newNode)
    case "Scroll": return patchScroll(view, newNode)
    case "Icon": return patchIcon(view, newNode)
    case "Dropdown": return patchDropdown(view, newNode)
    case "BottomNavigation": return patchBottomNavigation(view, oldNode, newNode)
    case "FlutterSlot": return patchFlutterSlot(view, newNode)
    case "TextField": return patchTextField(view, oldNode, newNode)
    case "Checkbox":
      return patchIconControl(view, newNode, key: "checked", on: "checkmark.square.fill", off: "square")
    case "Radio":
      return patchIconControl(view, newNode, key: "selected", on: "largecircle.fill.circle", off: "circle")
    case "Toggle": return patchToggle(view, oldNode, newNode)
    case "Slider": return patchSlider(view, newNode)
    case "Tabs": return patchTabs(view, newNode)
    case "AnimatedOpacity": return patchAnimatedOpacity(view, newNode)
    case "AnimatedContainer": return patchAnimatedContainer(view, newNode)
    case "MapView": return patchMap(view, newNode)
    case "CameraPreview": return patchCamera(view, newNode)
    case "Card": return patchCard(view, oldNode, newNode)
    default: return false
    }
  }

  /// Re-derives a checkbox/radio (a button whose image carries the state).
  private func patchIconControl(
    _ view: UIView, _ node: [String: Any], key: String, on: String, off: String
  ) -> Bool {
    guard let button = view as? UIButton else { return false }
    let isOn = node[key] as? Bool ?? false
    button.setImage(controlImage(isOn ? on : off, on: isOn, node), for: .normal)
    styleControlLabel(button, node)
    announceChecked(button, isOn)
    // Setting the image does not fire the tap, so no suppression is needed.
    bindings[button.hash] = node
    return true
  }

  private func patchToggle(_ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any])
    -> Bool
  {
    // A label is present as a switch+label stack, absent as a bare switch, so a
    // change in whether it is present reshapes the view - leave that to rebuild.
    if ((oldNode["label"] as? String) == nil) != ((newNode["label"] as? String) == nil) {
      return false
    }
    let toggle: UISwitch
    if let sw = view as? UISwitch {
      toggle = sw
    } else if let sw = (view as? UIStackView)?.arrangedSubviews
      .compactMap({ $0 as? UISwitch }).first {
      toggle = sw
    } else {
      return false
    }
    // Setting isOn programmatically does not fire valueChanged, so it is safe.
    toggle.setOn(newNode["enabled"] as? Bool ?? false, animated: false)
    tintToggle(toggle, newNode)
    toggle.isEnabled = !(newNode["disabled"] as? Bool ?? false)
    toggle.accessibilityLabel =
      newNode["label"] as? String ?? newNode["semanticLabel"] as? String
    bindings[toggle.hash] = newNode
    if let label = (view as? UIStackView)?.arrangedSubviews.compactMap({ $0 as? UILabel }).first {
      label.text = newNode["label"] as? String
    }
    return true
  }

  /// Re-derives a card's own look; the title is patched too, but a change in
  /// whether it is present reshapes the content, so that is left to a rebuild.
  private func patchCard(_ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any])
    -> Bool
  {
    if ((oldNode["title"] as? String) == nil) != ((newNode["title"] as? String) == nil) {
      return false
    }
    guard let content = view.subviews.compactMap({ $0 as? UIStackView }).first else {
      return false
    }
    view.layer.borderWidth = 0
    view.layer.shadowOpacity = 0
    view.backgroundColor = (newNode["backgroundColor"] as? String).map {
      color($0, fallback: $0)
    } ?? surfaceVariantColor()
    switch newNode["variant"] as? String {
    case "outlined":
      view.layer.borderWidth = 1
      view.layer.borderColor = color(themeDivider, fallback: themeDivider).cgColor
    case "filled":
      break
    default:
      view.layer.shadowColor = UIColor.black.cgColor
      view.layer.shadowOpacity = 0.15
      view.layer.shadowRadius = number(newNode["elevation"]) ?? 2
      view.layer.shadowOffset = CGSize(width: 0, height: 1)
    }
    let inset = number(newNode["padding"]) ?? 16
    content.layoutMargins = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    if let title = newNode["title"] as? String {
      let label = content.arrangedSubviews.first as? UILabel
      label?.text = title
      // Repainted with whatever is in force, as it was drawn.
      label?.textColor = textInForce ?? color(nil, fallback: themeText)
    }
    return true
  }

  private func patchText(_ view: UIView, _ node: [String: Any]) -> Bool {
    // Selectable text is a text view and the rest a label, so a change of mind
    // about that is a different view.
    let selectable = node["selectable"] as? Bool ?? false
    if let textView = view as? UITextView {
      guard selectable else { return false }
      applySelectableText(textView, node)
      return true
    }
    guard !selectable, let label = view as? UILabel else { return false }
    applyText(label, node)
    return true
  }

  private func patchButton(
    _ view: UIView, _ oldNode: [String: Any], _ node: [String: Any]
  ) -> Bool {
    guard let button = view as? UIButton else { return false }
    // The tap is wired when the button is built, and so are the constraints
    // behind its minimum size.
    if (oldNode["eventId"] is String) != (node["eventId"] is String) { return false }
    for key in ["size", "minHeight", "minWidth"]
    where !valueEqual(oldNode[key], node[key]) {
      return false
    }
    styleButton(button, node)
    bindings[button.hash] = node
    return true
  }

  private func patchAppBar(
    _ view: UIView, _ oldNode: [String: Any], _ node: [String: Any]
  ) -> Bool {
    // What the bar is made of - a leading button, a title subtree, a centred
    // title - is decided when it is built.
    for key in ["leading", "centerTitle", "hasTitleNode"]
    where !valueEqual(oldNode[key], node[key]) {
      return false
    }
    guard let bar = view as? DnnAppBarView else { return false }
    let tint = color(node["backgroundColor"], fallback: themePrimary)
    if #available(iOS 26.0, *),
      let effect = view.subviews.compactMap({ $0 as? UIVisualEffectView }).first
    {
      // Retint the glass only when the colour actually changed - reassigning the
      // effect otherwise would flicker.
      if let glass = effect.effect as? UIGlassEffect, glass.tintColor != tint {
        let updated = UIGlassEffect()
        updated.tintColor = tint
        effect.effect = updated
      }
    } else {
      view.backgroundColor = tint
    }
    let foreground = appBarForeground(node)
    if let button = bar.leadingButton {
      button.tintColor = foreground
      if let eventId = node["leadingEventId"] as? String {
        bindings[button.hash] = ["eventId": eventId]
      }
    }
    if let title = bar.titleLabel {
      title.text = node["title"] as? String ?? ""
      title.textColor = foreground
    }
    return true
  }

  /// The colour an app bar's title, leading button and actions are drawn in:
  /// the one the app stated, or the one that reads against the bar.
  private func appBarForeground(_ node: [String: Any]) -> UIColor {
    if let stated = statedColor(node["foregroundColor"]) { return stated }
    // Over the theme's own primary it is the palette's onPrimary; over a
    // colour the app stated it is whichever of black and white contrasts.
    if node["backgroundColor"] == nil {
      return color(themeOnPrimary, fallback: themeOnPrimary)
    }
    return textOn(color(node["backgroundColor"], fallback: themePrimary))
  }

  /// A scaffold's colour is its own to repaint; where its children go is not.
  private func patchScaffold(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) -> Bool {
    for key in ["bodyScrolls", "safeArea"] where !valueEqual(oldNode[key], newNode[key]) {
      return false
    }
    view.backgroundColor = statedColor(newNode["backgroundColor"])
    return true
  }

  private func patchIconButton(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) -> Bool {
    guard let button = view as? UIButton else { return false }
    if (oldNode["eventId"] is String) != (newNode["eventId"] is String) { return false }
    styleIconButton(button, newNode)
    bindings[button.hash] = newNode
    return true
  }

  /// Patches the one child of a view that can swap it: in place when the old
  /// child can become the new one, and by rebuilding just that child when not.
  private func patchHostedChild(
    _ host: DnnSingleChildHost, _ oldKids: [[String: Any]], _ newKids: [[String: Any]],
    in node: [String: Any]
  ) -> Bool {
    guard let next = newKids.first else {
      host.replaceChild(nil)
      return true
    }
    if let before = oldKids.first, let existing = host.hostedChild,
      tryPatch(existing, before, next)
    {
      return true
    }
    host.replaceChild(buildChild(next))
    return true
  }

  /// Reconciles a `Stack`'s layers by position, rebuilding only the layers
  /// that cannot be patched and adding or dropping the ones at the end.
  private func reconcileLayers(
    _ stack: DnnStackView, _ oldKids: [[String: Any]], _ newKids: [[String: Any]]
  ) -> Bool {
    if stack.subviews.count != oldKids.count { return false }
    for i in newKids.indices {
      if i < oldKids.count {
        let existing = stack.subviews[i]
        if tryPatch(existing, oldKids[i], newKids[i]) { continue }
        existing.removeFromSuperview()
        stack.addLayer(buildChild(newKids[i]), at: i)
      } else {
        stack.addLayer(buildChild(newKids[i]), at: nil)
      }
    }
    while stack.subviews.count > newKids.count {
      guard let last = stack.subviews.last else { break }
      last.removeFromSuperview()
    }
    return true
  }

  /// The first UILabel at or below [view] - the app-bar title, whether it sits
  /// directly on the bar (flat) or inside a glass effect's content view.
  private func firstDescendantLabel(_ view: UIView) -> UILabel? {
    if let label = view as? UILabel { return label }
    for sub in view.subviews {
      if let found = firstDescendantLabel(sub) { return found }
    }
    return nil
  }

  private func patchTextField(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) -> Bool {
    // The label is drawn as a sibling, so a change in whether there is one
    // changes this field's own view tree - leave that to a rebuild. The error
    // is not: its label is always there, hidden when there is nothing to say,
    // so a validator answering mid-keystroke costs a text change and the field
    // keeps its first responder, caret and keyboard. (Android has always had
    // this, through TextInputLayout; iOS used to rebuild, and a form that
    // re-checked a field as it was typed lost the rest of the word.)
    if (oldNode["label"] as? String) != (newNode["label"] as? String) { return false }
    if (oldNode["obscureText"] as? Bool ?? false) != (newNode["obscureText"] as? Bool ?? false) {
      return false
    }
    guard let field = findTextField(view) else { return false }
    if let error = findErrorLabel(view) {
      applyFieldError(error, field, newNode["error"] as? String)
    } else if (oldNode["error"] as? String) != (newNode["error"] as? String) {
      return false
    }
    field.isEnabled = !(newNode["enabled"] as? Bool == false)
    // Only when one of them changed: the glyphs at the ends are views, and
    // there is no call to remake them on every keystroke.
    let fieldKeys = [
      "keyboardType", "textCapitalization", "textAlign", "prefixIcon", "suffixIcon",
      "suffixTappable",
    ]
    if fieldKeys.contains(where: { !valueEqual(oldNode[$0], newNode[$0]) }) {
      configureField(field, newNode)
    } else if let suffix = (isRTL ? field.leftView : field.rightView) as? UIButton {
      // Only the suffix is a button; the prefix is a picture and sends nothing.
      bindings[suffix.hash] = newNode
    }
    applyFieldHelper(view, newNode)
    // Sync the text when the user is not the one editing it, or when the app
    // itself changed the value - a controller.clear() after submitting bumps the
    // field's version, which the user's own typing never does. A re-render that
    // merely echoes the value the field already holds is left alone, so typing
    // is never interrupted and the caret never jumps.
    let value = newNode["initialValue"] as? String ?? ""
    // Only a *deliberate* change by the app - a bumped controller version -
    // overwrites what someone is typing. The value in the tree follows the
    // user's own keystrokes a beat behind (the controller records them without
    // bumping the version), so treating a different value as an app change
    // wrote that stale echo back into the field and ate whatever had been
    // typed in the meantime.
    let appChanged =
      (oldNode["valueVersion"] as? Int ?? -1) != (newNode["valueVersion"] as? Int ?? -1)
    if field.text != value, !field.isFirstResponder || appChanged {
      field.text = value
    }
    // A focus ask usually arrives on a live field - a failed submit sending the
    // caret back to the first thing to fix - so it has to be answered here as
    // well as at build time, or the second failed submit (nothing else about
    // the field changed) would be ignored.
    if let eventId = newNode["eventId"] as? String {
      applyFocusRequest(field, eventId: eventId, node: newNode)
    }
    bindings[field.hash] = newNode
    return true
  }

  private func findTextField(_ view: UIView) -> UITextField? {
    if let field = view as? UITextField { return field }
    for sub in view.subviews {
      if let found = findTextField(sub) { return found }
    }
    return nil
  }

  /// Deep equality over two nodes' own props (ignoring `id`, and children).
  private func propsEqual(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    mapEqual(a["props"] as? [String: Any] ?? [:], b["props"] as? [String: Any] ?? [:])
  }

  private func mapEqual(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    let keysA = a.keys.filter { $0 != "id" }
    let keysB = b.keys.filter { $0 != "id" }
    if keysA.count != keysB.count { return false }
    for key in keysA {
      guard b[key] != nil else { return false }
      if !valueEqual(a[key], b[key]) { return false }
    }
    return true
  }

  private func valueEqual(_ a: Any?, _ b: Any?) -> Bool {
    if let a = a as? [String: Any] {
      guard let b = b as? [String: Any] else { return false }
      return mapEqual(a, b)
    }
    if let a = a as? [Any] {
      guard let b = b as? [Any], a.count == b.count else { return false }
      for i in a.indices where !valueEqual(a[i], b[i]) { return false }
      return true
    }
    if let a = a as? NSObject, let b = b as? NSObject { return a.isEqual(b) }
    return a == nil && b == nil
  }

  // MARK: - Dispatch

  /// Builds the view for [node], and tells accessibility which node it is.
  private func renderWidget(_ node: [String: Any]) -> UIView? {
    guard let view = drawWidget(node) else { return nil }
    identify(view, node)
    return view
  }

  /**
   Exposes the node's `id` - a widget's `Key` - as the view's
   `accessibilityIdentifier`: what XCUITest matches, and what a device test's
   `id` selector reads. It is the id as written, as on Android.

   Called on every build and every patch, so an id that arrives or changes on
   a view that is kept is followed; `releaseIdentity` takes off one that went.
   A text field's id goes on the field itself rather than the stack around it,
   and a dropdown's on its button, since those are what a test fills and
   presses.

   Nothing is made an accessibility element for having an id. An element hides
   everything under it, and a view that only lays others out is still found by
   its identifier without being one.

   Only ever adds: a node with no id or role leaves the view as its own
   render function made it.
   */
  private func identify(_ view: UIView, _ node: [String: Any]) {
    let target = identityTarget(view, node)
    var id = node["id"] as? String
    if id?.isEmpty == true { id = nil }
    // A field nobody keyed keeps the name `renderTree` restores its focus by.
    // A keyed one is found by its key instead, which a rebuild does not change.
    if id == nil, target is UITextField { id = node["eventId"] as? String }
    if let id = id, target.accessibilityIdentifier != id {
      target.accessibilityIdentifier = id
    }

    // What the node says it is, where the view's class would not: a text
    // that is a heading, a box that is an image, a drawing with a name.
    let role = roleTrait(node)
    if !role.isEmpty {
      if let box = target as? DnnBoxView {
        if !box.roleTraits.contains(role) { box.roleTraits.insert(role) }
      } else if !target.accessibilityTraits.contains(role) {
        target.accessibilityTraits.insert(role)
      }
    }

    // "Loading", said by name: a bare ring is announced as nothing.
    if node["type"] as? String == "Loading", let name = node["semanticLabel"] as? String {
      view.isAccessibilityElement = true
      view.accessibilityLabel = name
    }
  }

  /// Takes off [view] the id and the role [oldNode] gave it, where [newNode]
  /// no longer gives the same - before the patch, so that a trait the patch
  /// sets for itself is not the one removed.
  private func releaseIdentity(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) {
    let target = identityTarget(view, oldNode)
    if let stale = oldNode["id"] as? String, !stale.isEmpty,
      (newNode["id"] as? String) != stale, target.accessibilityIdentifier == stale
    {
      target.accessibilityIdentifier = nil
    }
    let stale = roleTrait(oldNode)
    if stale.isEmpty || stale == roleTrait(newNode) { return }
    if let box = target as? DnnBoxView {
      box.roleTraits.remove(stale)
      return
    }
    // A trait the view has by its nature is not this function's to remove.
    if stale == .button, target is UIControl { return }
    if stale == .image, target is UIImageView { return }
    target.accessibilityTraits.remove(stale)
  }

  /// The view a node's id and role belong on: the control somebody uses,
  /// where the node's own view is only the layout around it.
  private func identityTarget(_ view: UIView, _ node: [String: Any]) -> UIView {
    let type = node["type"] as? String
    if type == "TextField" { return findTextField(view) ?? view }
    if type == "Dropdown" { return (view as? DnnDropdownView)?.control ?? view }
    return view
  }

  /// The trait `semanticRole` asks for. A drawing with a name is an image.
  private func roleTrait(_ node: [String: Any]) -> UIAccessibilityTraits {
    var role = node["semanticRole"] as? String
    if role == nil, node["type"] as? String == "Canvas", node["semanticLabel"] != nil {
      role = "image"
    }
    if role == "heading" { return .header }
    if role == "button" { return .button }
    if role == "image" { return .image }
    if role == "progress" { return .updatesFrequently }
    return []
  }

  // node-types:begin
  private func drawWidget(_ node: [String: Any]) -> UIView? {
    switch node["type"] as? String {
    // Structure
    case "Scaffold", "NavigationStack": return renderScaffold(node)
    case "AppBar", "NavigationBar": return renderAppBar(node)

    // Layout
    case "Column": return renderColumn(node)
    case "VStack": return renderStack(node, axis: .vertical)
    case "Row": return renderRow(node)
    case "HStack": return renderStack(node, axis: .horizontal)
    case "Wrap": return renderWrap(node)
    case "Expanded": return renderExpanded(node)
    case "Center": return renderCenter(node)
    case "SwipeActions": return renderSwipeActions(node)
    case "Padding": return renderPadding(node)
    case "SizedBox": return renderSizedBox(node)
    case "Spacer": return renderSpacer(node)
    case "Divider": return renderDivider(node)

    // Content
    case "Text": return renderText(node)
    case "Image": return renderImage(node)
    case "Loading": return renderLoading(node)
    case "Badge": return renderBadge(node)
    case "Alert": return renderAlert(node)
    case "Card": return renderCard(node)

    // Controls
    case "Button", "MaterialButton": return renderButton(node)
    case "IconButton": return renderIconButton(node)
    case "FloatingActionButton": return renderFab(node)
    case "TextField": return renderTextField(node)
    case "Checkbox": return renderCheckbox(node)
    case "Radio": return renderRadio(node)
    case "Toggle": return renderToggle(node)
    case "Slider": return renderSlider(node)
    case "Tabs": return renderTabs(node)
    case "AnimatedOpacity": return renderAnimatedOpacity(node)
    case "AnimatedContainer": return renderAnimatedContainer(node)
    case "MapView": return renderMap(node)
    case "CameraPreview": return renderCamera(node)
    case "GridView": return renderGrid(node)

    case "WebView": return renderWebView(node)

    // Lists
    case "List", "ListView": return renderList(node)
    case "ListItem", "ListRow": return renderListItem(node)
    case "LazyList": return renderLazyList(node)

    // Overlays
    case "Overlay": return renderOverlay(node)
    case "Dialog": return renderDialog(node)
    case "BottomSheet": return renderBottomSheet(node)
    case "Snackbar": return renderSnackbar(node)
    case "DatePicker": return renderPicker(node, time: false)
    case "TimePicker": return renderPicker(node, time: true)

    // Free-form composition
    case "Box": return renderBox(node)
    case "Stack": return renderLayers(node)
    case "Positioned": return renderPositioned(node)
    case "Scroll": return renderScroll(node)
    case "Icon": return renderIcon(node)
    case "Canvas": return renderCanvas(node)

    // Choosing
    case "Dropdown": return renderDropdown(node)

    // App chrome along the bottom edge
    case "BottomBar": return renderBottomBar(node)
    case "BottomNavigation": return renderBottomNavigation(node)

    // A region the Flutter view underneath paints
    case "FlutterSlot": return renderFlutterSlot(node)

    default:
      unknownTypes.insert(node["type"] as? String ?? "?")
      let label = UILabel()
      label.text = "Unknown widget: \(node["type"] ?? "?")"
      label.textAlignment = .center
      return label
    }
  }
  // node-types:end

  // MARK: - Structure

  /**
   A Scaffold's children are, in order, an optional app bar, the body and an
   optional floating action button - the shape `UIBuilder.scaffold` builds.
   */
  /// Whether [node] lays its children out in the space it is given, rather
  /// than sizing itself to them.
  private func fillsViewport(_ node: [String: Any]) -> Bool {
    switch node["type"] as? String {
    case "Center": return true
    case "Column", "VStack":
      // 'min' hugs the children whatever else was asked; 'max' fills without
      // distributing anything.
      let size = node["mainAxisSize"] as? String
      if size == "min" { return false }
      return node["mainAxisAlignment"] != nil || size == "max"
    case "Stack":
      return true
    case "Box", "Canvas":
      let expand = node["expand"] as? String
      return expand == "height" || expand == "both"
    default: return false
    }
  }

  private func renderScaffold(_ node: [String: Any]) -> UIView {
    let container = UIView()
    let column = UIStackView()
    column.axis = .vertical
    column.alignment = .fill
    column.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(column)

    // A scaffold that states its colour paints it, and what is drawn over it
    // with no colour of its own reads against it.
    let savedText = textInForce
    defer { textInForce = savedText }
    if let stated = statedColor(node["backgroundColor"]) {
      container.backgroundColor = stated
      textInForce = textOn(stated)
    }

    // A bar at the top of the screen fills the status bar's strip with its own
    // colour, the way a UINavigationBar does - so the column starts at the very
    // top when there is one to fill it, and at the safe area when there is not,
    // because a body on its own must not run under the clock. The bar insets
    // its own title, so nothing lands behind the icons either way.
    //
    // The children are told apart by type: the bars, the button, and whatever
    // is left is the body.
    let children = childNodes(node)
    let hasBar = children.contains { child in
      let type = child["type"] as? String
      return type == "AppBar" || type == "NavigationBar"
    }
    let hasBottomBar = children.contains { child in
      child["type"] as? String == "BottomBar"
    }
    // `safeArea: false` lets the body run under the system insets, and
    // `bodyScrolls: false` hands it the height between the bars instead of a
    // scroll view - which is what an Expanded, a Scroll or a Stack inside it
    // needs to have something to divide.
    let safeArea = node["safeArea"] as? Bool ?? true
    let bodyScrolls = node["bodyScrolls"] as? Bool ?? true

    let top = column.topAnchor.constraint(
      equalTo: hasBar ? container.topAnchor
        : (safeArea ? container.safeAreaLayoutGuide.topAnchor : container.topAnchor))

    // The bottom stops at the safe area, so a body ends above the home
    // indicator rather than running under it - which is what the Android
    // side does against the navigation bar, and the point is that the two
    // agree. iOS on its own would let a scroll view run under the indicator;
    // this renderer draws one screen for four platforms, so the screen wins
    // over the platform here.
    //
    // The keyboard still works out right: `keyboardChanged` shortens the
    // container, which lifts it clear of the indicator, so the inset
    // collapses to nothing exactly when the keyboard has taken that space.
    //
    // A bottom bar is the exception, as a top bar is: it runs to the very
    // edge, fills the indicator's strip with its own colour and keeps its
    // child above it.
    let bottom: NSLayoutConstraint
    if hasBottomBar || !safeArea {
      bottom = column.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    } else {
      bottom = column.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
    }

    NSLayoutConstraint.activate([
      top,
      column.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      column.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      bottom,
    ])

    var fab: UIView?
    var fabExtended = false
    var bottomBar: UIView?
    for child in children {
      switch child["type"] as? String {
      case "FloatingActionButton":
        fab = renderWidget(child)
        fabExtended = child["label"] is String
      case "AppBar", "NavigationBar":
        if let bar = renderWidget(child) { column.addArrangedSubview(bar) }
      case "BottomBar":
        bottomBar = renderWidget(child)
      default:
        guard let body = renderWidget(child) else { continue }
        // A long list scrolls itself, and needs the bounded height a scroll
        // view around it would take away. So does a body that asked not to
        // be scrolled: it is pinned between the bars and takes what is left.
        if child["type"] as? String == "LazyList" || !bodyScrolls {
          body.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
          column.addArrangedSubview(body)
          continue
        }
        // The body scrolls, so a screen taller than the window is reachable
        // rather than clipped.
        let scroll = UIScrollView()
        if !safeArea { scroll.contentInsetAdjustmentBehavior = .never }
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)
        NSLayoutConstraint.activate([
          body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
          body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
          body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
          body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
          body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        // A body that places its children in the space it is given - a Center,
        // or a Column distributing down its main axis - needs that space to
        // exist: inside a scroll view it would otherwise be exactly as tall as
        // its content, with nothing to centre within. At least the viewport,
        // never less, so a taller screen still scrolls.
        if fillsViewport(child) {
          body.heightAnchor.constraint(
            greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor
          ).isActive = true
        }
        column.addArrangedSubview(scroll)
      }
    }
    // Under the body, wherever the tree listed it.
    if let bottomBar { column.addArrangedSubview(bottomBar) }
    // What a snackbar has to stay above - see SnackbarHost.
    scaffoldBottomBar = bottomBar
    scaffoldFab = fab

    if let fab {
      fab.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(fab)
      // Above the bottom bar when there is one, and the home indicator when
      // there is not. An extended button is a pill as wide as its label.
      let fabFloor = bottomBar?.topAnchor ?? container.safeAreaLayoutGuide.bottomAnchor
      NSLayoutConstraint.activate([
        fab.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        fab.bottomAnchor.constraint(equalTo: fabFloor, constant: -16),
        fabExtended
          ? fab.widthAnchor.constraint(greaterThanOrEqualToConstant: 56)
          : fab.widthAnchor.constraint(equalToConstant: 56),
        fab.heightAnchor.constraint(equalToConstant: 56),
      ])
    }
    return container
  }

  private func renderAppBar(_ node: [String: Any]) -> UIView {
    let bar = DnnAppBarView()
    let tint = color(node["backgroundColor"], fallback: themePrimary)
    // The title, the leading button and the actions share one colour: the one
    // the app stated, or the one that reads against the bar.
    let foreground = appBarForeground(node)

    // iOS 26 Liquid Glass: a translucent bar, tinted with the brand colour, that
    // the content behind it shows through - the native look. Older systems keep
    // the opaque fill.
    let host: UIView
    if #available(iOS 26.0, *), themeGlassChrome {
      let glass = UIGlassEffect()
      glass.tintColor = tint
      let effect = UIVisualEffectView(effect: glass)
      effect.translatesAutoresizingMaskIntoConstraints = false
      bar.addSubview(effect)
      NSLayoutConstraint.activate([
        effect.topAnchor.constraint(equalTo: bar.topAnchor),
        effect.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        effect.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
        effect.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
      ])
      host = effect.contentView
    } else {
      bar.backgroundColor = tint
      host = bar
    }

    // One row: the leading button, the title, room, then the actions.
    let row = UIStackView()
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(row)

    let leading = node["leading"] as? String
    if let leading {
      // Drawn the platform's way, as SF Symbols.
      let symbol: String
      let spoken: String
      switch leading {
      case "close": (symbol, spoken) = ("xmark", "Close")
      case "menu": (symbol, spoken) = ("line.3.horizontal", "Menu")
      // Back points to where the screen came from: the start of the line,
      // which is the right when it reads right to left. Named outright rather
      // than left to `chevron.backward`, which turns with the app's language
      // and not with the tree's.
      default: (symbol, spoken) = (isRTL ? "chevron.right" : "chevron.left", "Back")
      }
      let button = UIButton(type: .system)
      button.setImage(
        UIImage(systemName: symbol) ?? UIImage(systemName: "chevron.left"), for: .normal)
      button.tintColor = foreground
      button.accessibilityLabel = spoken
      button.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 40),
        button.heightAnchor.constraint(equalToConstant: 36),
      ])
      if let eventId = node["leadingEventId"] as? String {
        bindings[button.hash] = ["eventId": eventId]
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
      }
      row.addArrangedSubview(button)
      bar.leadingButton = button
    }

    // The title subtree, when there is one, is the first child; the rest are
    // the actions. Both are drawn in the bar's foreground unless they say
    // otherwise.
    let savedText = textInForce
    textInForce = foreground
    defer { textInForce = savedText }

    let kids = childNodes(node)
    var actions = kids
    let titleView: UIView
    if node["hasTitleNode"] as? Bool == true, let first = kids.first {
      titleView = buildChild(first)
      // The title is the screen's heading, whichever way it was given: what
      // "next heading" lands on, and what tells a reader which screen this is.
      firstDescendantLabel(titleView)?.accessibilityTraits.insert(.header)
      bar.nodeViews.append(titleView)
      actions = Array(kids.dropFirst())
    } else {
      let title = DnnAppBarTitleLabel()
      title.text = node["title"] as? String ?? ""
      title.textColor = foreground
      title.font = .systemFont(ofSize: 20, weight: .medium)
      title.accessibilityTraits = .header
      bar.titleLabel = title
      titleView = title
    }
    // A long title gives way to the buttons beside it.
    titleView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let centered = node["centerTitle"] as? Bool ?? false
    if centered {
      titleView.translatesAutoresizingMaskIntoConstraints = false
      host.addSubview(titleView)
    } else {
      row.addArrangedSubview(titleView)
    }

    let gap = UIView()
    gap.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    gap.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
    row.addArrangedSubview(gap)

    for action in actions {
      let view = buildChild(action)
      view.setContentHuggingPriority(.required, for: .horizontal)
      view.setContentCompressionResistancePriority(.required, for: .horizontal)
      row.addArrangedSubview(view)
      bar.nodeViews.append(view)
    }

    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(
        equalTo: host.leadingAnchor, constant: leading == nil ? 16 : 4),
      row.trailingAnchor.constraint(
        equalTo: host.trailingAnchor, constant: actions.isEmpty ? -16 : -12),
      // Against the bar's *safe area* rather than its top edge: a bar sitting
      // at the top of the screen is that much taller and puts its title below
      // the clock, and one anywhere else has no inset and is unchanged. The
      // same trick as the Android bar's padding, spelt the way iOS spells it.
      row.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor, constant: 6),
      row.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6),
      // The row's height is what sets the bar's: a title's line and its room.
      row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
    ])
    // And no more than that unless what is in it needs it. "At least" alone
    // left the bar free to take whatever the body did not: over a scroller
    // with little in it the bar came out a third of the screen tall, and a
    // different height on every page of one app.
    let snug = row.heightAnchor.constraint(equalToConstant: 36)
    snug.priority = UILayoutPriority(740)
    snug.isActive = true
    if centered {
      NSLayoutConstraint.activate([
        titleView.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        titleView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        titleView.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -112),
      ])
    }
    return bar
  }

  // MARK: - Layout

  private func renderColumn(_ node: [String: Any]) -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = number(node["spacing"]) ?? 0
    // How the children are distributed down the column is a spacer's job -
    // see `distribute(_:_:axis:)`, called once the children are in. A stack
    // has nothing to distribute unless something gave it height.
    stack.distribution = .fill
    switch node["crossAxisAlignment"] as? String {
    case "start": stack.alignment = .leading
    case "end": stack.alignment = .trailing
    case "stretch": stack.alignment = .fill
    default: stack.alignment = .center
    }
    addArranged(stack, node)
    applyFlex(stack, node, axis: .vertical)
    distribute(stack, node, axis: .vertical)
    return stack
  }

  /// A view that takes whatever room is left over along [axis], so the
  /// children beside it are pushed where the app asked for them.
  ///
  /// It is a `FlexibleSpacer` rather than a plain view because the reconciler
  /// walks a stack's arranged subviews against the tree's children one to one:
  /// a spacer is not one of those children, and everything that indexes into
  /// the stack steps over it.
  private func flexibleSpacer(axis: NSLayoutConstraint.Axis = .vertical) -> UIView {
    let spacer = FlexibleSpacer()
    spacer.setContentHuggingPriority(.defaultLow, for: axis)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: axis)
    return spacer
  }

  private func renderRow(_ node: [String: Any]) -> UIView {
    let stack = RowStack()
    stack.axis = .horizontal
    switch node["crossAxisAlignment"] as? String {
    case "start": stack.alignment = .top
    case "end": stack.alignment = .bottom
    case "stretch": stack.alignment = .fill
    default: stack.alignment = .center
    }
    stack.spacing = number(node["spacing"]) ?? 0
    stack.distribution = .fill
    addArranged(stack, node)
    applyFlex(stack, node, axis: .horizontal)
    distribute(stack, node, axis: .horizontal)
    return stack
  }

  /**
   Puts the spacers a stated `mainAxisAlignment` needs around or between the
   children, and stops the stack hugging them.

   Every alignment but the default one is a spacer's job here: `.equalSpacing`
   distributes only what is left over, and when nothing gave the stack room it
   *squeezes* the children instead - which is how a row of a label and a button
   ended up with the label printed under the button. Spacers that collapse to
   nothing degrade to children side by side, and open up the moment something
   does give the stack room.
   */
  private func distribute(
    _ stack: UIStackView, _ node: [String: Any], axis: NSLayoutConstraint.Axis
  ) {
    // 'min' hugs the children even when an alignment was asked for, and with
    // no room to spare there is nothing to distribute.
    let size = node["mainAxisSize"] as? String
    if size == "min" { return }
    let count = stack.arrangedSubviews.count

    func extent(_ view: UIView) -> NSLayoutDimension {
      axis == .vertical ? view.heightAnchor : view.widthAnchor
    }
    /// A spacer between each pair of children, all of one size.
    func spaceBetween() -> [UIView] {
      var between: [UIView] = []
      for i in stride(from: count - 1, to: 0, by: -1) {
        let spacer = flexibleSpacer(axis: axis)
        stack.insertArrangedSubview(spacer, at: i)
        between.append(spacer)
      }
      if let first = between.first {
        for other in between.dropFirst() {
          extent(other).constraint(equalTo: extent(first)).isActive = true
        }
      }
      return between
    }

    switch node["mainAxisAlignment"] as? String {
    case "center":
      // Two spacers of one size, or the stack is free to give all the room
      // to either and the children end up at an edge.
      let before = flexibleSpacer(axis: axis)
      let after = flexibleSpacer(axis: axis)
      stack.insertArrangedSubview(before, at: 0)
      stack.addArrangedSubview(after)
      extent(after).constraint(equalTo: extent(before)).isActive = true
    case "end":
      stack.insertArrangedSubview(flexibleSpacer(axis: axis), at: 0)
    case "spaceBetween":
      _ = spaceBetween()
    case "spaceAround", "spaceEvenly":
      guard count > 0 else { return }
      // The gaps at the two ends are half a gap for 'around' and a whole one
      // for 'evenly'.
      let between = spaceBetween()
      let before = flexibleSpacer(axis: axis)
      let after = flexibleSpacer(axis: axis)
      stack.insertArrangedSubview(before, at: 0)
      stack.addArrangedSubview(after)
      extent(after).constraint(equalTo: extent(before)).isActive = true
      if let gap = between.first {
        let share: CGFloat = node["mainAxisAlignment"] as? String == "spaceAround" ? 0.5 : 1
        extent(before).constraint(equalTo: extent(gap), multiplier: share).isActive = true
      }
    default:
      // No alignment, but asked to fill: the room left over goes after the
      // children rather than into one of them - unless a child is there to
      // take it.
      let flexible = childNodes(node).contains { child in
        let type = child["type"] as? String
        return type == "Expanded" || type == "Spacer"
      }
      guard size == "max", count > 0, !flexible else { return }
      stack.addArrangedSubview(flexibleSpacer(axis: axis))
    }
    // A stack that is distributing its children wants all the room it can get,
    // so anything able to stretch it should.
    stack.setContentHuggingPriority(UILayoutPriority(1), for: axis)
  }

  private func renderWrap(_ node: [String: Any]) -> UIView {
    let flow = FlowView(
      hSpacing: CGFloat(number(node["spacing"]) ?? 0),
      vSpacing: CGFloat(number(node["runSpacing"]) ?? 0)
    )
    flow.alignment = node["alignment"] as? String ?? "start"
    flow.crossAlignment = node["crossAxisAlignment"] as? String ?? "start"
    for child in childNodes(node) {
      guard let view = renderWidget(child) else { continue }
      // The flow positions its children by frame, so they must not manage their
      // own on the outside; their inner Auto Layout still gives them a size.
      view.translatesAutoresizingMaskIntoConstraints = true
      flow.addSubview(view)
    }
    return flow
  }

  /// Gives Expanded children equal, flex-weighted sizes along [axis] - the way
  /// Flutter's Expanded divides the free space in a Row or Column. A plain
  /// `.fill` stack of low-hugging containers sizes them unequally; tying their
  /// widths (or heights) together by their flex fixes that. Non-Expanded
  /// children keep their intrinsic size.
  private func applyFlex(
    _ stack: UIStackView, _ node: [String: Any], axis: NSLayoutConstraint.Axis
  ) {
    let crossAxis: NSLayoutConstraint.Axis = axis == .horizontal ? .vertical : .horizontal
    let kids = childNodes(node)
    var anchor: UIView?
    var anchorFlex = 1
    let flexible = kids.contains { $0["type"] as? String == "Expanded" }
    for (index, kid) in kids.enumerated() {
      guard index < stack.arrangedSubviews.count else { continue }
      guard kid["type"] as? String == "Expanded" else {
        // The room left over is the Expanded's, so what sits beside one
        // keeps to its own size. An Expanded's container has no size to hug,
        // which leaves the stack weighing the label inside it against the
        // button beside it - and a button hugs a notch less than a label, so
        // the button got the room: a card's star came out in the middle of
        // the card, in a button as wide as the title should have been.
        if flexible {
          stack.arrangedSubviews[index].setContentHuggingPriority(.defaultHigh, for: axis)
        }
        continue
      }
      let view = stack.arrangedSubviews[index]
      let flex = kid["flex"] as? Int ?? 1
      // An Expanded grows on the main axis only; on the cross axis it should hug
      // its child, so a row of them stays the height of one button.
      view.setContentHuggingPriority(.defaultHigh, for: crossAxis)
      if let anchor = anchor {
        let multiplier = CGFloat(flex) / CGFloat(anchorFlex)
        let constraint =
          axis == .horizontal
          ? view.widthAnchor.constraint(equalTo: anchor.widthAnchor, multiplier: multiplier)
          : view.heightAnchor.constraint(equalTo: anchor.heightAnchor, multiplier: multiplier)
        constraint.isActive = true
      } else {
        anchor = view
        anchorFlex = flex
      }
    }
  }

  /// VStack and HStack: the iOS flavour of Column and Row.
  private func renderStack(_ node: [String: Any], axis: NSLayoutConstraint.Axis) -> UIView {
    let stack = UIStackView()
    stack.axis = axis
    stack.spacing = number(node["spacing"]) ?? 0
    if axis == .vertical {
      switch node["alignment"] as? String {
      case "center": stack.alignment = .center
      case "trailing": stack.alignment = .trailing
      default: stack.alignment = .leading
      }
    } else {
      switch node["alignment"] as? String {
      case "top": stack.alignment = .top
      case "bottom": stack.alignment = .bottom
      default: stack.alignment = .center
      }
    }
    addArranged(stack, node)
    return stack
  }

  /// Takes the remaining space of the stack it sits in.
  private func renderExpanded(_ node: [String: Any]) -> UIView {
    let container = UIView()
    container.setContentHuggingPriority(.defaultLow, for: .horizontal)
    container.setContentHuggingPriority(.defaultLow, for: .vertical)

    guard let child = firstChild(node), let view = renderWidget(child) else {
      return container
    }
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    if node["fit"] as? String == "loose" {
      // Flutter's Flexible: the child may be smaller than its share, and sits
      // at the start of it. The weak equalities let a share with nothing else
      // sizing it across the axis hug the child.
      let hugTrailing = view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
      hugTrailing.priority = UILayoutPriority(249)
      let hugBottom = view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
      hugBottom.priority = UILayoutPriority(249)
      NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: container.topAnchor),
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        hugTrailing,
        hugBottom,
      ])
      return container
    }
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    return container
  }

  private func renderCenter(_ node: [String: Any]) -> UIView {
    let container = UIView()
    guard let child = firstChild(node), let view = renderWidget(child) else {
      return container
    }
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      view.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
      view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
    ])
    return container
  }

  private func renderSwipeActions(_ node: [String: Any]) -> UIView {
    let child = firstChild(node).flatMap { renderWidget($0) } ?? UIView()
    func actions(_ key: String) -> [SwipeActionsView.Action] {
      ((node[key] as? [Any]) ?? []).compactMap { raw in
        guard let a = raw as? [String: Any], let eventId = a["eventId"] as? String
        else { return nil }
        return SwipeActionsView.Action(
          label: a["label"] as? String ?? "",
          color: color(a["color"], fallback: "#d32f2f"),
          eventId: eventId)
      }
    }
    return SwipeActionsView(
      child: child,
      actions: actions("actions"),
      leadingActions: actions("leadingActions"),
      surface: surfaceColor()
    ) { [weak self] eventId in
      self?.send(eventId: eventId, data: [:])
    }
  }

  private func renderPadding(_ node: [String: Any]) -> UIView {
    // One number for every edge, or four - see UIBuilder.padding.
    let uniform = number(node["padding"])
    func edge(_ name: String) -> CGFloat {
      CGFloat(uniform ?? number(node[name]) ?? 0)
    }
    let container = UIView()
    guard let child = firstChild(node), let view = renderWidget(child) else {
      return container
    }
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(
        equalTo: container.topAnchor, constant: edge("paddingTop")),
      view.bottomAnchor.constraint(
        equalTo: container.bottomAnchor, constant: -edge("paddingBottom")),
      view.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: edge("paddingLeft")),
      view.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -edge("paddingRight")),
    ])
    return container
  }

  private func renderSizedBox(_ node: [String: Any]) -> UIView {
    let box = UIView()
    box.translatesAutoresizingMaskIntoConstraints = false
    if let height = number(node["height"]) {
      box.heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    if let width = number(node["width"]) {
      box.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
    return box
  }

  private func renderSpacer(_ node: [String: Any]) -> UIView {
    let spacer = UIView()
    if let minLength = number(node["minLength"]), minLength > 0 {
      spacer.translatesAutoresizingMaskIntoConstraints = false
      spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: minLength).isActive = true
    }
    // Hugging last means the stack gives it whatever is left.
    spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return spacer
  }

  private func renderDivider(_ node: [String: Any]) -> UIView {
    let line = UIView()
    line.backgroundColor = color(node["color"], fallback: themeDivider)
    line.translatesAutoresizingMaskIntoConstraints = false
    let thickness = number(node["thickness"]) ?? 1

    if node["orientation"] as? String == "vertical" {
      line.widthAnchor.constraint(equalToConstant: thickness).isActive = true
      line.heightAnchor.constraint(
        equalToConstant: number(node["height"]) ?? 24).isActive = true
      return line
    }

    // The margin is expressed as padding around the rule.
    let container = UIView()
    let margin = number(node["margin"]) ?? 16
    container.addSubview(line)
    NSLayoutConstraint.activate([
      line.heightAnchor.constraint(equalToConstant: thickness),
      line.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      line.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
      line.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
    ])
    return container
  }

  // MARK: - Content

  /// Runs [body] with text over [background] made legible against it.
  private func over<T>(_ background: Any?, _ body: () -> T) -> T {
    guard let stated = background as? String else { return body() }
    let saved = textInForce
    textInForce = textOn(color(stated, fallback: stated))
    defer { textInForce = saved }
    return body()
  }

  /// The background this node stated, if it stated one - see `over(_:_:)`.
  private func statedBackground(_ node: [String: Any]) -> Any? {
    switch node["type"] as? String {
    case "Card": return node["backgroundColor"]
    case "AnimatedContainer": return node["color"]
    case "Scaffold", "NavigationStack": return node["backgroundColor"]
    case "Box": return boxBackground(node)
    default: return nil
    }
  }

  private func renderText(_ node: [String: Any]) -> UIView {
    // A label cannot be selected, so selectable text is a text view that
    // neither edits nor scrolls - which sizes to its text as a label does.
    if node["selectable"] as? Bool == true {
      let textView = UITextView()
      textView.isEditable = false
      textView.isScrollEnabled = false
      textView.backgroundColor = .clear
      textView.textContainerInset = .zero
      textView.textContainer.lineFragmentPadding = 0
      applySelectableText(textView, node)
      return textView
    }
    let label = UILabel()
    applyText(label, node)
    return label
  }

  /// The colour a run of text takes: the one it states, the one in force over
  /// a stated background, or the theme's.
  private func textColor(_ node: [String: Any]) -> UIColor {
    node["color"] == nil
      ? (textInForce ?? color(nil, fallback: themeText))
      : color(node["color"], fallback: themeText)
  }

  /// 'left', 'center', 'right' or 'justify'; anything else follows the
  /// reading direction - the tree's, which `.natural` would not: that follows
  /// the language the app is running in. 'left' and 'right' are the sides they
  /// name whichever way the screen reads.
  private func textAlignment(_ value: Any?) -> NSTextAlignment {
    switch value as? String {
    case "left": return .left
    case "center": return .center
    case "right": return .right
    case "justify": return .justified
    default: return isRTL ? .right : .natural
    }
  }

  /// Whether [node] says anything a plain label cannot: runs of their own,
  /// letter spacing, a line height, a decoration.
  private func isRichText(_ node: [String: Any]) -> Bool {
    node["spans"] != nil || node["letterSpacing"] != nil || node["lineHeight"] != nil
      || node["decoration"] != nil
  }

  /// [node]'s text with every style it states, each span inheriting from the
  /// node whatever it does not state itself.
  private func richText(_ node: [String: Any]) -> NSAttributedString {
    let size = number(node["fontSize"]) ?? 14
    let weight = number(node["fontWeight"]) ?? 400
    let family = node["fontFamily"] as? String
    let italic = node["italic"] as? Bool ?? false
    let inherited = textColor(node)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = textAlignment(node["textAlign"])
    // A multiple of the font size, as CSS and Flutter both spell it.
    if let multiple = number(node["lineHeight"]), multiple > 0 {
      paragraph.minimumLineHeight = size * multiple
      paragraph.maximumLineHeight = size * multiple
    }
    var base: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]
    if let spacing = number(node["letterSpacing"]) {
      base[.kern] = NSNumber(value: Double(spacing))
    }

    let result = NSMutableAttributedString()
    var runs: [[String: Any]] = []
    if let spans = node["spans"] as? [Any] {
      runs = spans.compactMap { $0 as? [String: Any] }
    }
    if runs.isEmpty {
      runs = [["text": node["content"] as? String ?? ""]]
    }
    for span in runs {
      var attributes = base
      attributes[.font] = dnnFont(
        size: number(span["fontSize"]) ?? size,
        weight: number(span["fontWeight"]) ?? weight,
        family: family,
        italic: span["italic"] as? Bool ?? italic)
      attributes[.foregroundColor] =
        span["color"] == nil ? inherited : color(span["color"], fallback: themeText)
      let decoration = span["decoration"] as? String ?? node["decoration"] as? String
      if decoration == "lineThrough" {
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
      } else if decoration == "underline" {
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
      }
      result.append(
        NSAttributedString(string: span["text"] as? String ?? "", attributes: attributes))
    }
    return result
  }

  /// Everything a Text node says, on a label - at build time and on a patch.
  private func applyText(_ label: UILabel, _ node: [String: Any]) {
    if isRichText(node) {
      label.attributedText = richText(node)
    } else {
      label.attributedText = nil
      label.textColor = textColor(node)
      label.font = dnnFont(
        size: number(node["fontSize"]) ?? 14,
        weight: number(node["fontWeight"]) ?? 400,
        family: node["fontFamily"] as? String,
        italic: node["italic"] as? Bool ?? false)
      label.text = node["content"] as? String ?? ""
      label.textAlignment = textAlignment(node["textAlign"])
    }
    // After the text: a label applies its line breaking to an attributed
    // string as it is set.
    clampLines(label, node)
  }

  private func applySelectableText(_ textView: UITextView, _ node: [String: Any]) {
    textView.attributedText = richText(node)
    let maxLines = Int(number(node["maxLines"]) ?? 0)
    textView.textContainer.maximumNumberOfLines = maxLines > 0 ? maxLines : 0
    textView.textContainer.lineBreakMode =
      maxLines > 0 && (node["overflow"] as? String) != "clip"
      ? .byTruncatingTail
      : .byWordWrapping
  }

  /// Caps a label at `maxLines`, ending it with an ellipsis when asked.
  ///
  /// `numberOfLines = 0` is UIKit's "as many as it takes", which is what makes
  /// an unknown-length line push a fixed-height row out of shape.
  private func clampLines(_ label: UILabel, _ node: [String: Any]) {
    let maxLines = Int(number(node["maxLines"]) ?? 0)
    label.numberOfLines = maxLines > 0 ? maxLines : 0
    label.lineBreakMode =
      maxLines > 0 && (node["overflow"] as? String) != "clip"
      ? .byTruncatingTail
      : .byWordWrapping
  }

  /**
   An image.

   A URL is fetched off the main thread and applied when it arrives; any other
   source is looked up in the app's asset catalogue. A source that cannot be
   loaded leaves the alt text in place, which is also the view's accessibility
   label - so a broken image is still announced and still visible.

   The node may carry one child: a fallback the app would rather show than the
   alt text, while the image is on its way and for good if it never comes. It
   takes the image's place - the same edges - and is hidden, not removed, once
   the picture is in, so the reconciler still finds the view its child node
   belongs to.
   */
  private func renderImage(_ node: [String: Any]) -> UIView {
    let alt = node["alt"] as? String ?? ""
    let container = UIView()

    let fallback: UIView
    var constraints: [NSLayoutConstraint] = []
    if let child = firstChild(node) {
      let host = ImageFallbackHost()
      let view = buildChild(child)
      view.translatesAutoresizingMaskIntoConstraints = false
      host.addSubview(view)
      host.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(host)
      // Held to the image's edges only while it stands in for it: an image
      // with no stated size is as big as its picture once that arrives, not
      // as big as whatever was shown in the meantime.
      host.holds = [
        host.topAnchor.constraint(equalTo: container.topAnchor),
        host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      ]
      constraints += host.holds
      constraints += [
        view.topAnchor.constraint(equalTo: host.topAnchor),
        view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      ]
      fallback = host
    } else {
      let label = UILabel()
      label.text = alt
      label.textColor = .secondaryLabel
      label.textAlignment = .center
      label.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(label)
      constraints += [
        label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      ]
      fallback = label
    }

    let imageView = UIImageView()
    // An image nobody described is decoration: there is nothing to say about
    // it, and "image" on its own is noise.
    imageView.isAccessibilityElement = !alt.isEmpty
    imageView.accessibilityLabel = alt.isEmpty ? nil : alt
    imageView.accessibilityTraits = .image
    imageView.clipsToBounds = true
    imageView.contentMode = {
      switch node["fit"] as? String {
      case "contain": return .scaleAspectFit
      case "fill": return .scaleToFill
      case "none": return .center
      case "scaleDown": return .scaleAspectFit
      default: return .scaleAspectFill
      }
    }()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(imageView)

    constraints += [
      imageView.topAnchor.constraint(equalTo: container.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ]
    if let width = number(node["width"]) {
      constraints.append(container.widthAnchor.constraint(equalToConstant: width))
    }
    if let height = number(node["height"]) {
      constraints.append(container.heightAnchor.constraint(equalToConstant: height))
    }
    NSLayoutConstraint.activate(constraints)

    load(node["src"] as? String, into: imageView, hiding: fallback)
    return container
  }

  /// Puts [image] in [view] and takes what stood in for it out of the way.
  private func show(_ image: UIImage, in view: UIImageView, hiding fallback: UIView) {
    view.image = image
    fallback.isHidden = true
    if let host = fallback as? ImageFallbackHost {
      NSLayoutConstraint.deactivate(host.holds)
    }
  }

  /**
   Fills `view` from `src`, hiding `fallback` once it arrives.

   A remote image already in `imageCache` is shown here and now, before this
   returns - so a rebuild of a screen full of pictures never shows the alt
   text or the fallback in between. One that is not is fetched once however
   many views are waiting for it, decoded where it was fetched rather than on
   the thread that draws, and remembered. The bytes themselves are the
   session's to keep: `URLSession.shared` stores them in `URLCache.shared`, on
   disk, for as long as the response's cache headers allow.
   */
  private func load(_ src: String?, into view: UIImageView, hiding fallback: UIView) {
    guard let src, !src.isEmpty else { return }

    guard src.hasPrefix("http://") || src.hasPrefix("https://") else {
      if let bundled = localImage(src) {
        show(bundled, in: view, hiding: fallback)
      }
      return
    }

    if let cached = NativeUIRenderer.imageCache.object(forKey: src as NSString) {
      show(cached, in: view, hiding: fallback)
      return
    }

    guard let url = URL(string: src) else { return }
    // Weakly: a row scrolled away before its picture arrived owes it nothing.
    let waiter: (UIImage?) -> Void = { [weak self, weak view, weak fallback] image in
      guard let self, let image, let view, let fallback else { return }
      self.show(image, in: view, hiding: fallback)
    }
    if NativeUIRenderer.imageWaiters[src] != nil {
      NativeUIRenderer.imageWaiters[src]?.append(waiter)
      return
    }
    NativeUIRenderer.imageWaiters[src] = [waiter]

    URLSession.shared.dataTask(with: url) { data, _, _ in
      var decoded: UIImage?
      if let data, let image = UIImage(data: data) {
        decoded = image
        // `UIImage(data:)` only reads the header; the pixels are decoded the
        // first time the image is drawn, on the main thread. Do it here.
        if #available(iOS 15.0, *), let prepared = image.preparingForDisplay() {
          decoded = prepared
        }
      }
      let result = decoded
      DispatchQueue.main.async {
        if let result {
          let pixels = result.size.width * result.scale * result.size.height * result.scale
          NativeUIRenderer.imageCache.setObject(
            result, forKey: src as NSString, cost: Int(pixels * 4))
        }
        // A failure is told to the waiters too - they do nothing with it, and
        // what stood in for the image stays - so the next render may try again.
        let waiting = NativeUIRenderer.imageWaiters.removeValue(forKey: src) ?? []
        for waiter in waiting { waiter(result) }
      }
    }.resume()
  }

  /**
   An image that is not fetched: one that ships with the app, or one that
   travels in the tree itself.

   A path such as `assets/photo.jpg` is a *Flutter* asset: the build copies it
   into the app's Flutter assets directory, not into the asset catalogue, so
   `UIImage(named:)` alone never finds it. `lookupKey(forAsset:)` says where it
   went - the same lookup the icon font uses. The asset catalogue and a plain
   file path are tried after it, for an image the host app added natively.
   */
  private func localImage(_ src: String) -> UIImage? {
    if src.hasPrefix("data:") {
      guard let comma = src.firstIndex(of: ","),
        src[src.startIndex..<comma].contains("base64"),
        let data = Data(
          base64Encoded: String(src[src.index(after: comma)...]),
          options: .ignoreUnknownCharacters)
      else { return nil }
      return UIImage(data: data)
    }
    let key = FlutterDartProject.lookupKey(forAsset: src)
    if let path = Bundle.main.path(forResource: key, ofType: nil),
      let image = UIImage(contentsOfFile: path)
    {
      return image
    }
    if let named = UIImage(named: src) { return named }
    if src.hasPrefix("file://"), let url = URL(string: src) {
      return UIImage(contentsOfFile: url.path)
    }
    return src.hasPrefix("/") ? UIImage(contentsOfFile: src) : nil
  }

  private func renderLoading(_ node: [String: Any]) -> UIView {
    let tint = color(node["color"], fallback: themePrimary)
    let indeterminate = node["indeterminate"] as? Bool ?? false
    let value = Float(number(node["value"]) ?? 0)

    switch prop(node, "type") as? String {
    case "progress-linear":
      let bar = UIProgressView(progressViewStyle: .default)
      bar.progressTintColor = tint
      bar.progress = indeterminate ? 0.3 : value
      return bar
    case "skeleton":
      let block = UIView()
      block.backgroundColor = color(themeDivider, fallback: themeDivider)
      block.layer.cornerRadius = 4
      block.translatesAutoresizingMaskIntoConstraints = false
      block.heightAnchor.constraint(
        equalToConstant: number(node["height"]) ?? 16).isActive = true
      // A finite width is fixed; an infinite one (the default) fills the row,
      // so it just must not hug itself down to nothing.
      if let width = number(node["width"]).map({ CGFloat($0) }), width.isFinite {
        block.widthAnchor.constraint(equalToConstant: width).isActive = true
      } else {
        block.setContentHuggingPriority(.defaultLow, for: .horizontal)
      }
      return block
    case "pulse":
      let container = UIView()
      if let child = firstChild(node), let view = renderWidget(child) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
          view.topAnchor.constraint(equalTo: container.topAnchor),
          view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
          view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
          view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
      }
      return container
    case "progress-circular" where !indeterminate:
      // UIKit has no stock determinate ring, so draw one: a grey track and a
      // tinted arc that sweeps clockwise from twelve o'clock to `value`.
      let diameter = CGFloat(number(node["size"]) ?? 36)
      let lineWidth: CGFloat = 3
      let ring = UIView()
      ring.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        ring.widthAnchor.constraint(equalToConstant: diameter),
        ring.heightAnchor.constraint(equalToConstant: diameter),
      ])
      let center = CGPoint(x: diameter / 2, y: diameter / 2)
      let radius = (diameter - lineWidth) / 2
      // The path lives in the layer's own coordinate space (0...diameter), so it
      // draws correctly before the ring view is laid out - no layoutSubviews.
      let path = UIBezierPath(
        arcCenter: center, radius: radius,
        startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true
      ).cgPath
      let track = CAShapeLayer()
      track.path = path
      track.strokeColor = color(themeDivider, fallback: themeDivider).cgColor
      track.fillColor = UIColor.clear.cgColor
      track.lineWidth = lineWidth
      ring.layer.addSublayer(track)
      let arc = CAShapeLayer()
      arc.path = path
      arc.strokeColor = tint.cgColor
      arc.fillColor = UIColor.clear.cgColor
      arc.lineWidth = lineWidth
      arc.lineCap = .round
      arc.strokeEnd = CGFloat(max(0, min(1, value)))
      ring.layer.addSublayer(arc)
      return ring
    default:
      let spinner = UIActivityIndicatorView(style: .medium)
      spinner.color = tint
      spinner.startAnimating()
      return spinner
    }
  }

  private func renderBadge(_ node: [String: Any]) -> UIView {
    let tint = color(node["color"], fallback: themePrimary)
    let outlined = node["variant"] as? String == "outlined"

    guard node["variant"] as? String != "dot", let text = node["label"] as? String else {
      let dot = UIView()
      dot.backgroundColor = tint
      dot.layer.cornerRadius = 4
      dot.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        dot.widthAnchor.constraint(equalToConstant: 8),
        dot.heightAnchor.constraint(equalToConstant: 8),
      ])
      return dot
    }

    let label = PaddedLabel(insets: UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8))
    label.text = text
    label.font = .systemFont(ofSize: 12)
    label.textColor = outlined ? tint : textOn(tint)
    label.layer.cornerRadius = 12
    label.layer.masksToBounds = true
    if outlined {
      label.layer.borderWidth = 1
      label.layer.borderColor = tint.cgColor
    } else {
      label.backgroundColor = tint
    }
    return label
  }

  /**
   A web page, in the platform's own browser view.

   Sized by its `height` prop rather than by its content: a `WKWebView` has no
   intrinsic height, and a scaffold's body scrolls, so one left to itself would
   be zero points tall.
   */
  private func renderWebView(_ node: [String: Any]) -> UIView {
    let configuration = WKWebViewConfiguration()
    // Off unless the app asks, matching the other renderers: a page that is
    // only being read does not need to run code.
    configuration.defaultWebpagePreferences.allowsContentJavaScript =
      node["javaScriptEnabled"] as? Bool ?? false

    let web = WKWebView(frame: .zero, configuration: configuration)
    web.translatesAutoresizingMaskIntoConstraints = false

    let frame = WebViewFrame()
    frame.translatesAutoresizingMaskIntoConstraints = false
    frame.addSubview(web)
    let height = number(node["height"]) ?? 300
    NSLayoutConstraint.activate([
      frame.heightAnchor.constraint(equalToConstant: height),
      web.topAnchor.constraint(equalTo: frame.topAnchor),
      web.bottomAnchor.constraint(equalTo: frame.bottomAnchor),
      web.leadingAnchor.constraint(equalTo: frame.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: frame.trailingAnchor),
    ])

    if let url = (node["url"] as? String).flatMap(URL.init(string:)) {
      web.load(URLRequest(url: url))
    } else {
      unknownTypes.insert("WebView(url)")
    }
    return frame
  }

  private func renderAlert(_ node: [String: Any]) -> UIView {
    let tint: UIColor
    switch prop(node, "type") as? String {
    case "success": tint = color(themeSuccess, fallback: themeSuccess)
    case "error": tint = color(themeError, fallback: themeError)
    case "warning": tint = color(themeWarning, fallback: themeWarning)
    default: tint = color(themeInfo, fallback: themeInfo)
    }

    let body = UIStackView()
    body.axis = .vertical
    body.spacing = 4

    if let title = node["title"] as? String {
      let label = UILabel()
      label.text = title
      label.textColor = tint
      label.font = .systemFont(ofSize: 15, weight: .semibold)
      body.addArrangedSubview(label)
    }

    let message = UILabel()
    message.text = node["message"] as? String ?? ""
    message.textColor = color(themeText, fallback: themeText)
    message.numberOfLines = 0
    body.addArrangedSubview(message)

    // A row rather than a column, so a dismissible alert can put its close
    // button at the trailing edge - where the web and Flutter renderers put
    // theirs.
    let row = UIStackView()
    row.axis = .horizontal
    row.alignment = .top
    row.spacing = 8
    row.isLayoutMarginsRelativeArrangement = true
    row.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    row.backgroundColor = tint.withAlphaComponent(0.1)
    row.layer.borderColor = tint.cgColor
    row.layer.borderWidth = 1
    row.addArrangedSubview(body)

    // Absent means not dismissible, which is what the other three renderers
    // read too. The builders always write the prop (defaulting it to true), so
    // this only decides for a hand-built node.
    if node["dismissible"] as? Bool == true {
      let close = UIButton(type: .system)
      close.setImage(
        UIImage(systemName: "xmark")?
          .withTintColor(tint, renderingMode: .alwaysOriginal),
        for: .normal)
      close.accessibilityLabel = "Dismiss"
      close.setContentHuggingPriority(.required, for: .horizontal)
      close.setContentCompressionResistancePriority(.required, for: .horizontal)
      // Removed here rather than reported to Dart, which is what the other
      // renderers do: the alert is a leaf the app did not ask to hear about.
      // A later render that still carries the alert brings it back, on every
      // renderer alike.
      close.addAction(
        UIAction { [weak row] _ in row?.removeFromSuperview() }, for: .touchUpInside)
      row.addArrangedSubview(close)
    }
    return row
  }

  private func renderCard(_ node: [String: Any]) -> UIView {
    let card = UIView()
    card.layer.cornerRadius = 8

    // Every variant draws the colour the app stated; only what it does
    // *besides* the fill - a border, a shadow - is the variant's.
    card.backgroundColor = (node["backgroundColor"] as? String).map {
      color($0, fallback: $0)
    } ?? surfaceVariantColor()
    switch node["variant"] as? String {
    case "outlined":
      card.layer.borderWidth = 1
      card.layer.borderColor = color(themeDivider, fallback: themeDivider).cgColor
    case "filled":
      break
    default:
      card.layer.shadowColor = UIColor.black.cgColor
      card.layer.shadowOpacity = 0.15
      card.layer.shadowRadius = number(node["elevation"]) ?? 2
      card.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    let content = UIStackView()
    content.axis = .vertical
    content.spacing = 8
    content.isLayoutMarginsRelativeArrangement = true
    let inset = number(node["padding"]) ?? 16
    content.layoutMargins = UIEdgeInsets(
      top: inset, left: inset, bottom: inset, right: inset)
    content.translatesAutoresizingMaskIntoConstraints = false

    over(node["backgroundColor"]) {
      if let title = node["title"] as? String {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        if let inForce = textInForce { label.textColor = inForce }
        content.addArrangedSubview(label)
      }
      for child in childNodes(node) {
        if let view = renderWidget(child) { content.addArrangedSubview(view) }
      }
    }

    card.addSubview(content)
    // Pinned at the top, not stretched to the bottom. A card given more room
    // than its content - a grid cell, a row of cards of different heights -
    // would otherwise stretch the content stack, and a stretched label centres
    // its text, which is not what the other renderers draw or what Flutter
    // does. The bottom equality is strong enough to make a free-standing card
    // hug its content and weak enough to give way when something taller wins.
    let bottom = content.bottomAnchor.constraint(equalTo: card.bottomAnchor)
    // Weaker than a label's hold on its own height (251), so a card that is
    // being stretched leaves its content alone; strong enough to size a card
    // that nothing else is sizing, since nothing competes there.
    bottom.priority = UILayoutPriority(249)
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: card.topAnchor),
      content.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor),
      bottom,
      content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
    ])
    return card
  }

  // MARK: - Controls

  private func renderButton(_ node: [String: Any]) -> UIView {
    let button = DnnButton(type: .system)
    // The one button scale, shared by every renderer - see UIBuilder.button.
    let height: CGFloat
    switch node["size"] as? String {
    case "sm": height = 28
    case "lg": height = 44
    default: height = 36
    }
    // The scale, then whatever the app stated instead of it.
    let minHeight = number(node["minHeight"]) ?? height
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)
      .isActive = true
    if let minWidth = number(node["minWidth"]) {
      button.widthAnchor.constraint(
        greaterThanOrEqualToConstant: minWidth
      ).isActive = true
    }
    button.layer.cornerRadius = 4
    styleButton(button, node)
    bindTap(button, node)
    return button
  }

  /// A button's label, glyph, colours and padding - everything about it that a
  /// patch can change without rebuilding it.
  private func styleButton(_ button: UIButton, _ node: [String: Any]) {
    let fontSize: CGFloat
    let padding: CGFloat
    switch node["size"] as? String {
    case "sm": (fontSize, padding) = (12, 12)
    case "lg": (fontSize, padding) = (16, 24)
    default: (fontSize, padding) = (14, 16)
    }
    let font = number(node["fontSize"]) ?? fontSize
    let padH = number(node["paddingHorizontal"]) ?? padding
    let padV = number(node["paddingVertical"]) ?? 0

    button.setTitle(node["label"] as? String ?? "Button", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: font, weight: .medium)
    button.isEnabled = !(node["disabled"] as? Bool ?? false)

    let variant = node["variant"] as? String ?? "primary"
    let tint = color(
      node["color"] ?? variantColor(variant), fallback: themePrimary)
    var foreground = tint
    button.layer.borderWidth = 0
    switch variant {
    case "secondary", "tertiary":
      button.backgroundColor = .clear
    case "outlined":
      // A border and no fill.
      button.backgroundColor = .clear
      button.layer.borderWidth = 1
      button.layer.borderColor = tint.cgColor
    case "tonal":
      // A quiet fill of the same colour the label is drawn in.
      button.backgroundColor = tint.withAlphaComponent(0.16)
    default:
      button.backgroundColor = tint
      foreground =
        node["color"] == nil
        ? color(themeOnPrimary, fallback: themeOnPrimary)
        : textOn(tint)
    }
    if let stated = statedColor(node["foregroundColor"]) { foreground = stated }
    if !button.isEnabled {
      // Material's disabled button: what it is drawn on at 12%, its label at
      // 38%. Left in its own colours it looked exactly like one that works.
      let on = color(themeText, fallback: themeText)
      if button.backgroundColor != .clear {
        button.backgroundColor = on.withAlphaComponent(0.12)
      }
      if button.layer.borderWidth > 0 {
        button.layer.borderColor = on.withAlphaComponent(0.12).cgColor
      }
      foreground = on.withAlphaComponent(0.38)
      button.setTitleColor(foreground, for: .disabled)
    }
    button.setTitleColor(foreground, for: .normal)
    // The glyph is a template image, which a system button paints in its tint.
    button.tintColor = foreground

    var trailing = padH
    if let glyph = iconImage(node["iconCodepoint"], size: font + 4) {
      button.setImage(glyph, for: .normal)
      // The gap between the glyph and the label, paid for at the far edge so
      // the label is not clipped.
      // These insets name sides, and the glyph is on the other one when the
      // screen reads right to left.
      button.titleEdgeInsets =
        isRTL
        ? UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
        : UIEdgeInsets(top: 0, left: 6, bottom: 0, right: -6)
      trailing += 6
    } else {
      button.setImage(nil, for: .normal)
      button.titleEdgeInsets = .zero
    }
    button.contentEdgeInsets = UIEdgeInsets(
      top: padV, left: isRTL ? trailing : padH, bottom: padV, right: isRTL ? padH : trailing)
    // Fills the width it is offered instead of hugging its label.
    (button as? DnnButton)?.expands = node["expand"] as? Bool ?? false
  }

  private func renderIconButton(_ node: [String: Any]) -> UIView {
    let button = UIButton(type: .system)
    styleIconButton(button, node)
    bindTap(button, node)
    return button
  }

  /// An icon button's glyph, colour, size and whether it can be pressed.
  private func styleIconButton(_ button: UIButton, _ node: [String: Any]) {
    // The colour it states; failing that the one in force around it - an app
    // bar's foreground, the text over a coloured card - and failing that a
    // quiet one, since an icon button usually sits on the surface.
    let tint =
      node["color"] == nil
      ? (textInForce ?? color(themeTextSecondary, fallback: themeTextSecondary))
      : color(node["color"], fallback: themeTextSecondary)
    applyIcon(button, node, color: tint)
    if let size = number(node["size"]), let font = iconFont {
      button.titleLabel?.font = font.withSize(size)
    }
    button.setTitleColor(tint.withAlphaComponent(0.38), for: .disabled)
    button.isEnabled = !(node["disabled"] as? Bool ?? false)
    button.accessibilityLabel = node["tooltip"] as? String
  }

  private func renderFab(_ node: [String: Any]) -> UIView {
    let button = UIButton(type: .system)
    // White for contrast against the FAB's tint, unless the app said what
    // goes on it.
    applyIcon(button, node, color: color(node["foregroundColor"], fallback: themeOnPrimary))
    button.accessibilityLabel = node["tooltip"] as? String
    bindTap(button, node)

    // An extended button: the glyph and a label side by side, in a pill as
    // wide as they need. The two are one attributed title, since they are set
    // in different fonts.
    if let label = node["label"] as? String {
      let ink = color(node["foregroundColor"], fallback: themeOnPrimary)
      let title = NSMutableAttributedString()
      if let glyph = button.title(for: .normal), let font = iconFont {
        title.append(
          NSAttributedString(
            string: glyph,
            attributes: [
              .font: font, .foregroundColor: ink,
              // The glyph is taller than the label's line; this sits the two
              // on one centre line.
              .baselineOffset: NSNumber(value: -5),
            ]))
        title.append(NSAttributedString(string: "  "))
      }
      title.append(
        NSAttributedString(
          string: label,
          attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: ink,
          ]))
      button.setTitle(nil, for: .normal)
      button.setAttributedTitle(title, for: .normal)
      button.contentEdgeInsets =
        isRTL
        ? UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 16)
        : UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 20)
    }

    // iOS 26 Liquid Glass: an interactive glass pill that lenses under the touch,
    // tinted with the brand colour. Older systems, or an app that opted its
    // chrome out of glass, keep the flat filled circle.
    if #available(iOS 26.0, *), themeGlassChrome {
      let glass = UIGlassEffect()
      glass.isInteractive = true
      glass.tintColor = color(node["backgroundColor"], fallback: themePrimary)
      let effect = UIVisualEffectView(effect: glass)
      effect.cornerConfiguration = .capsule()
      button.translatesAutoresizingMaskIntoConstraints = false
      effect.contentView.addSubview(button)
      NSLayoutConstraint.activate([
        button.topAnchor.constraint(equalTo: effect.contentView.topAnchor),
        button.bottomAnchor.constraint(equalTo: effect.contentView.bottomAnchor),
        button.leadingAnchor.constraint(equalTo: effect.contentView.leadingAnchor),
        button.trailingAnchor.constraint(equalTo: effect.contentView.trailingAnchor),
      ])
      return effect
    }

    button.backgroundColor = color(node["backgroundColor"], fallback: themePrimary)
    button.layer.cornerRadius = 28
    return button
  }

  /**
   Draws [node]'s icon as a Material Icons glyph from its codepoint, in [color] -
   the same full icon set Flutter and the web renderers use. Without a codepoint,
   or if the bundled Material Icons font is somehow missing, the button is left
   glyphless: a partial SF Symbol map would only cover a couple of dozen names
   (the rest a placeholder dot) and would look unlike the icons everywhere else.
   */
  private func applyIcon(_ button: UIButton, _ node: [String: Any], color: UIColor) {
    guard let codepoint = number(node["iconCodepoint"]),
      let scalar = UnicodeScalar(UInt32(codepoint)), let font = iconFont
    else {
      button.setImage(nil, for: .normal)
      button.setTitle(nil, for: .normal)
      return
    }
    button.setImage(nil, for: .normal)
    button.setTitle(String(scalar), for: .normal)
    button.titleLabel?.font = font
    button.setTitleColor(color, for: .normal)
  }

  /**
   A text field that reports what the user does.

   The events match every other renderer: `<eventId>_change` on each keystroke,
   `_focus` and `_blur`, and `_submit` on the keyboard's return key.
   */
  private func renderTextField(_ node: [String: Any]) -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 4
    stack.alignment = .fill

    // A label sits above the field, whatever `floatingLabel` says. UIKit has no
    // floating label - the animated label in the outline is a Material pattern -
    // and iOS forms label a field either above it or with the placeholder
    // alone, so drawing Material's here would look imported. Web, Android and
    // the Flutter host do float it; this is the one renderer that does not, and
    // the protocol says so.
    if let labelText = node["label"] as? String {
      let label = UILabel()
      label.text = labelText
      label.font = .systemFont(ofSize: 13)
      label.textColor = .secondaryLabel
      stack.addArrangedSubview(label)
    }

    let field = UITextField()
    field.placeholder = node["hint"] as? String ?? node["placeholder"] as? String
    field.text = node["initialValue"] as? String ?? ""
    field.isEnabled = !(node["enabled"] as? Bool == false)
    field.isSecureTextEntry = node["obscureText"] as? Bool ?? false
    field.borderStyle = .roundedRect
    // What the return key says. UIKit has no traversal of its own, so what it
    // then does is `focusFieldAfter`.
    if node["textInputAction"] as? String == "next" { field.returnKeyType = .next }
    configureField(field, node)
    // A field's own name. UIKit falls back to the placeholder, which is the
    // right answer only when there is no label drawn above it.
    field.accessibilityLabel =
      node["label"] as? String ?? node["hint"] as? String
        ?? node["placeholder"] as? String
    // Why it is refusing, for a reader that cannot see the red text below.
    field.accessibilityHint = node["error"] as? String
    stack.addArrangedSubview(field)

    if let eventId = node["eventId"] as? String {
      // Names the field so its focus and caret can be restored to the view the
      // next render rebuilds in its place (see renderTree).
      field.accessibilityIdentifier = eventId
      bindings[field.hash] = node
      applyFocusRequest(field, eventId: eventId, node: node)
      field.delegate = textFieldDelegate
      field.addTarget(self, action: #selector(textChanged(_:)), for: .editingChanged)
      field.addTarget(self, action: #selector(editingBegan(_:)), for: .editingDidBegin)
      field.addTarget(self, action: #selector(editingEnded(_:)), for: .editingDidEnd)
      field.addTarget(
        self, action: #selector(editingSubmitted(_:)), for: .editingDidEndOnExit)
    }

    // The error label is always built, and hidden when there is nothing to
    // say. A validator that answers while someone is typing would otherwise
    // *add* a view to this field's own tree, which the patch path cannot do -
    // and rebuilding the field takes the keyboard and the caret with it.
    let error = TextFieldErrorLabel()
    error.font = .systemFont(ofSize: 12)
    error.textColor = color(themeError, fallback: themeError)
    error.numberOfLines = 0
    applyFieldError(error, field, node["error"] as? String)

    // The helper is always built too, for the same reason, and gives way to
    // the error when there is one.
    let helper = TextFieldHelperLabel()
    helper.font = .systemFont(ofSize: 12)
    helper.textColor = color(themeTextSecondary, fallback: themeTextSecondary)
    helper.numberOfLines = 0
    stack.addArrangedSubview(helper)
    stack.addArrangedSubview(error)
    applyFieldHelper(stack, node)
    return stack
  }

  /// The parts of a field a patch can change as readily as a build can set
  /// them: its keyboard, its capitalisation, its alignment and the glyphs at
  /// its two ends.
  private func configureField(_ field: UITextField, _ node: [String: Any]) {
    switch node["keyboardType"] as? String {
    case "number": field.keyboardType = .numberPad
    case "decimal": field.keyboardType = .decimalPad
    case "email": field.keyboardType = .emailAddress
    case "phone": field.keyboardType = .phonePad
    case "url": field.keyboardType = .URL
    default: field.keyboardType = .default
    }
    switch node["textCapitalization"] as? String {
    case "none": field.autocapitalizationType = .none
    case "words": field.autocapitalizationType = .words
    case "sentences": field.autocapitalizationType = .sentences
    case "characters": field.autocapitalizationType = .allCharacters
    default:
      // Nobody wants an address capitalised for them.
      let kind = node["keyboardType"] as? String
      field.autocapitalizationType = kind == "email" || kind == "url" ? .none : .sentences
    }
    field.textAlignment = textAlignment(node["textAlign"])

    let quiet = color(themeTextSecondary, fallback: themeTextSecondary)
    // The prefix sits where the text starts and the suffix where it ends. A
    // field's `leftView` and `rightView` are the sides they are named for, so
    // which glyph goes in which depends on the way the screen reads.
    var prefix: UIView?
    var suffix: UIView?
    if let glyph = iconImage(node["prefixIcon"], size: 20) {
      let holder = UIImageView(image: glyph)
      holder.tintColor = quiet
      holder.contentMode = .center
      holder.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
      prefix = holder
    }
    if let glyph = iconImage(node["suffixIcon"], size: 20) {
      // A button, so a tap on it is the suffix's and not the field's.
      let button = UIButton(type: .system)
      button.setImage(glyph, for: .normal)
      button.tintColor = quiet
      button.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
      button.isUserInteractionEnabled = node["suffixTappable"] as? Bool ?? false
      button.addTarget(self, action: #selector(fieldSuffixTapped(_:)), for: .touchUpInside)
      bindings[button.hash] = node
      suffix = button
    }
    let left = isRTL ? suffix : prefix
    let right = isRTL ? prefix : suffix
    field.leftView = left
    field.leftViewMode = left == nil ? .never : .always
    field.rightView = right
    field.rightViewMode = right == nil ? .never : .always
  }

  /// Shows the helper under a field, unless an error is being shown instead.
  private func applyFieldHelper(_ view: UIView, _ node: [String: Any]) {
    guard let helper = findHelperLabel(view) else { return }
    let text = node["helper"] as? String
    helper.text = text
    helper.isHidden = text == nil || (node["error"] as? String) != nil
  }

  private func findHelperLabel(_ view: UIView) -> TextFieldHelperLabel? {
    if let label = view as? TextFieldHelperLabel { return label }
    for sub in view.subviews {
      if let found = findHelperLabel(sub) { return found }
    }
    return nil
  }

  /// Takes or gives up the keyboard when the app asks: once for `autofocus`,
  /// and again whenever `focusVersion` changes.
  ///
  /// Deferred to the next turn of the run loop, because a field that is not in
  /// the window yet cannot become first responder - the view is built here and
  /// added by its parent afterwards.
  private func applyFocusRequest(
    _ field: UITextField, eventId: String, node: [String: Any]
  ) {
    let version = (node["focusVersion"] as? NSNumber)?.intValue
    let wanted = (node["focusRequested"] as? Bool) != false
    let auto = (node["autofocus"] as? Bool) == true
    guard let ask = version ?? (auto ? Self.autofocusVersion : nil) else { return }
    if focusVersions[eventId] == ask { return }
    focusVersions[eventId] = ask
    DispatchQueue.main.async { [weak field] in
      guard let field else { return }
      if wanted {
        field.becomeFirstResponder()
      } else {
        field.resignFirstResponder()
      }
    }
  }

  /// Shows [message] under a field, or takes the space back when there is
  /// none; the field carries it for a reader that cannot see the red text.
  private func applyFieldError(
    _ label: TextFieldErrorLabel, _ field: UITextField, _ message: String?
  ) {
    label.text = message
    label.isHidden = message == nil
    field.accessibilityHint = message
  }

  private func findErrorLabel(_ view: UIView) -> TextFieldErrorLabel? {
    if let label = view as? TextFieldErrorLabel { return label }
    for sub in view.subviews {
      if let found = findErrorLabel(sub) { return found }
    }
    return nil
  }

  /**
   The glyph for a checkable control, in the palette's colours.

   The brand primary when it is on and the quiet text colour when it is off -
   UIKit's own blue belongs to neither the app nor its theme, and an unchecked
   box drawn in the brand colour reads as if it were already checked. The colour
   is baked into the image (`.alwaysOriginal`) rather than left to the button's
   `tintColor`, so the two states can differ.
   */
  /// A check box's or radio button's glyph, in the colours [node] states -
  /// `activeColor` for one that is on, and `checkColor` for the tick in it -
  /// or the brand's.
  private func controlImage(_ name: String, on: Bool, _ node: [String: Any]) -> UIImage? {
    let tint = on
      ? color(node["activeColor"], fallback: themePrimary)
      : color(themeTextSecondary, fallback: themeTextSecondary)
    let image = UIImage(systemName: name)
    // The tick is cut out of the filled square, so it shows whatever is
    // behind the control. An app that names its colour gets the symbol drawn
    // in two: the tick, then the square.
    if on, let check = statedColor(node["checkColor"]) {
      return image?.applyingSymbolConfiguration(
        UIImage.SymbolConfiguration(paletteColors: [check, tint]))
    }
    return image?.withTintColor(tint, renderingMode: .alwaysOriginal)
  }

  /// A switch's colours, the app's where the node states them. On the build
  /// and on every patch: the thumb is one colour on and another off, and
  /// UIKit has one property for both.
  private func tintToggle(_ toggle: UISwitch, _ node: [String: Any]) {
    toggle.onTintColor = color(node["activeColor"], fallback: themePrimary)
    toggle.thumbTintColor = statedColor(
      node[toggle.isOn ? "thumbColor" : "inactiveThumbColor"])
    // UIKit has no colour for the track of a switch that is off; the view's
    // own background, rounded to the track's shape, is what shows there.
    if let track = statedColor(node["inactiveTrackColor"]) {
      toggle.backgroundColor = track
      toggle.layer.cornerRadius = toggle.intrinsicContentSize.height / 2
      toggle.clipsToBounds = true
    } else {
      toggle.backgroundColor = nil
    }
  }

  /// A slider's colours, the app's where the node states them.
  private func tintSlider(_ slider: UISlider, _ node: [String: Any]) {
    slider.minimumTrackTintColor = color(node["activeColor"], fallback: themePrimary)
    slider.maximumTrackTintColor = statedColor(node["inactiveColor"])
    slider.thumbTintColor = statedColor(node["thumbColor"])
  }

  /// Tells VoiceOver whether a checkable control is on.
  ///
  /// The state lives in the button's *image*, which a screen reader cannot
  /// read: without this it announces the label and nothing about whether the
  /// box is ticked. `.selected` is the trait UIKit uses for exactly this.
  private func announceChecked(_ button: UIButton, _ checked: Bool) {
    if checked {
      button.accessibilityTraits.insert(.selected)
    } else {
      button.accessibilityTraits.remove(.selected)
    }
  }

  /// A checkable control's label is body text, not a link, so it takes the
  /// text colour rather than the button's tint.
  private func styleControlLabel(_ button: UIButton, _ node: [String: Any]) {
    button.setTitle(node["label"] as? String, for: .normal)
    button.setTitleColor(color(themeText, fallback: themeText), for: .normal)
    // A control with no text of its own is named by the node - a list tile's
    // title, usually - or it is announced as "button" and no more. One with a
    // title is left to say it, which is what nil means here.
    button.accessibilityLabel =
      node["label"] is String ? nil : node["semanticLabel"] as? String
    // A disabled control takes no tap and says so to a screen reader, which
    // `isEnabled` does on its own. It does not look it, though: the glyph's
    // colour is baked into the image and the title's is set outright, so
    // neither dims the way a system button's would. Faded as a whole instead,
    // to the 38% Material draws a disabled control at. Set both ways, because
    // this runs on a patch too and the control may have just come back.
    let disabled = node["disabled"] as? Bool ?? false
    button.isEnabled = !disabled
    button.alpha = disabled ? 0.38 : 1
  }

  private func renderCheckbox(_ node: [String: Any]) -> UIView {
    // UIKit has no checkbox, so it is a button whose image carries the state.
    let button = UIButton(type: .system)
    let checked = node["checked"] as? Bool ?? false
    button.setImage(
      controlImage(checked ? "checkmark.square.fill" : "square", on: checked, node),
      for: .normal)
    styleControlLabel(button, node)
    announceChecked(button, checked)
    bindings[button.hash] = node
    button.addTarget(self, action: #selector(checkboxTapped(_:)), for: .touchUpInside)
    return button
  }

  private func renderRadio(_ node: [String: Any]) -> UIView {
    let button = UIButton(type: .system)
    let selected = node["selected"] as? Bool ?? false
    button.setImage(
      controlImage(selected ? "largecircle.fill.circle" : "circle", on: selected, node),
      for: .normal)
    styleControlLabel(button, node)
    announceChecked(button, selected)
    bindings[button.hash] = node
    button.addTarget(self, action: #selector(radioTapped(_:)), for: .touchUpInside)
    return button
  }

  /// A live camera preview.
  ///
  /// The frames go from the capture session straight to a preview layer - they
  /// never enter app memory, let alone Dart. The view owns the session and
  /// stops it when it leaves the window, because a preview nobody is looking
  /// at still costs battery and heat.
  private func renderCamera(_ node: [String: Any]) -> UIView {
    let preview = CameraPreviewView()
    preview.translatesAutoresizingMaskIntoConstraints = false
    preview.heightAnchor.constraint(
      equalToConstant: CGFloat(number(node["height"]) ?? 300)
    ).isActive = true
    preview.onStatus = { [weak self] status, message in
      guard let self, let eventId = node["eventId"] as? String else { return }
      var data: [String: Any] = ["status": status]
      if let message { data["message"] = message }
      self.send(eventId: "\(eventId)_status", data: data)
    }
    preview.apply(
      facing: node["facing"] as? String ?? "back",
      active: node["active"] as? Bool ?? true
    )
    return preview
  }

  private func patchCamera(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let preview = view as? CameraPreviewView else { return false }
    preview.apply(
      facing: node["facing"] as? String ?? "back",
      active: node["active"] as? Bool ?? true
    )
    return true
  }

  /// A map, drawn by MapKit.
  ///
  /// The view is never rebuilt while it is on screen - see [patchMap] - because
  /// a replaced map throws away its tiles and starts the download again.
  private func renderMap(_ node: [String: Any]) -> UIView {
    let map = MKMapView()
    map.translatesAutoresizingMaskIntoConstraints = false
    map.heightAnchor.constraint(
      equalToConstant: CGFloat(number(node["height"]) ?? 300)
    ).isActive = true
    map.delegate = mapDelegate
    applyMap(map, node)
    return map
  }

  /// Centre, zoom, markers and whether it moves under a finger.
  private func applyMap(_ map: MKMapView, _ node: [String: Any]) {
    let interactive = node["interactive"] as? Bool ?? true
    map.isScrollEnabled = interactive
    map.isZoomEnabled = interactive
    map.isRotateEnabled = interactive
    map.isPitchEnabled = interactive

    bindings[map.hash] = node
    mapDelegate.nodes[ObjectIdentifier(map)] = node

    let latitude = number(node["latitude"]) ?? 0
    let longitude = number(node["longitude"]) ?? 0
    let zoom = number(node["zoom"]) ?? 13
    let centre = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

    // Slippy zoom to a map rect, which is exact where a region is not: a
    // region is a span in degrees that MapKit then fits to the view's shape,
    // so a square span on an oblong map zooms out and the map reports back a
    // zoom the app never asked for. Map points do not have that problem - the
    // world is MKMapSize.world.width points across and 256*2^zoom pixels, so
    // the two scales convert exactly, both ways.
    let size = map.bounds.size.width > 0
      ? map.bounds.size
      : CGSize(width: UIScreen.main.bounds.width, height: 300)
    let pointsPerPixel = MKMapSize.world.width / (256 * pow(2, zoom))
    let rectWidth = Double(size.width) * pointsPerPixel
    let rectHeight = Double(size.height) * pointsPerPixel
    let centrePoint = MKMapPoint(centre)
    let rect = MKMapRect(
      x: centrePoint.x - rectWidth / 2,
      y: centrePoint.y - rectHeight / 2,
      width: rectWidth,
      height: rectHeight
    )
    // Setting what the map is already showing would fight a pan in flight.
    let showing = map.visibleMapRect
    if abs(showing.midX - rect.midX) > rectWidth * 0.01
      || abs(showing.midY - rect.midY) > rectHeight * 0.01
      || abs(showing.size.width - rectWidth) > rectWidth * 0.01
    {
      mapDelegate.applying = true
      map.setVisibleMapRect(rect, animated: false)
      mapDelegate.applying = false
    }

    let markers = node["markers"] as? [[String: Any]] ?? []
    map.removeAnnotations(map.annotations)
    for marker in markers {
      let point = MKPointAnnotation()
      point.coordinate = CLLocationCoordinate2D(
        latitude: number(marker["latitude"]) ?? 0,
        longitude: number(marker["longitude"]) ?? 0
      )
      point.title = marker["label"] as? String
      map.addAnnotation(point)
    }
  }

  private func patchMap(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let map = view as? MKMapView else { return false }
    applyMap(map, node)
    return true
  }

  /// Fades its child to the opacity the tree asks for.
  ///
  /// The first render sets the alpha; a later one that changes it animates
  /// from where the view already is - which is why this node is patched rather
  /// than rebuilt.
  private func renderAnimatedOpacity(_ node: [String: Any]) -> UIView {
    let container = UIView()
    container.alpha = CGFloat(fadeOpacity(node))
    guard let child = firstChild(node), let view = renderWidget(child) else {
      return container
    }
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    return container
  }

  private func fadeOpacity(_ node: [String: Any]) -> Double {
    Swift.min(Swift.max(number(node["opacity"]) ?? 1, 0), 1)
  }

  private func patchAnimatedOpacity(_ view: UIView, _ node: [String: Any]) -> Bool {
    let target = CGFloat(fadeOpacity(node))
    if abs(view.alpha - target) < 0.001 { return true }
    let duration = (number(node["durationMs"]) ?? 200) / 1000
    // Only the fade's own animation, not every animation on the layer: a box
    // growing further up the tree animates this view's position through the
    // same layer, and removing that would snap it to where it is going.
    view.layer.removeAnimation(forKey: "opacity")
    UIView.animate(withDuration: duration, delay: 0, options: curve(node)) {
      view.alpha = target
    }
    return true
  }

  /// A box that moves to the size and colour the tree asks for.
  ///
  /// The same bargain as the fade: the first render sets it, a later one
  /// animates the difference, and the node is patched rather than rebuilt -
  /// which is why it appears in `childViews` too. The child is centred, as it
  /// is on the other three renderers.
  private func renderAnimatedContainer(_ node: [String: Any]) -> UIView {
    let box = AnimatedBoxView()
    box.clipsToBounds = true
    box.backgroundColor = (node["color"] as? String).map { color($0, fallback: $0) }
    box.setSize(width: number(node["width"]), height: number(node["height"]))
    guard let child = firstChild(node),
      let view = over(node["color"], { renderWidget(child) })
    else { return box }
    view.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(view)
    // Centred, and inside the edges rather than pinned to them: a box with no
    // stated size still shrinks to fit the child, because the smallest box
    // these leave room for is the child's own size - and one with a stated
    // size stretches without dragging the child out with it.
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(greaterThanOrEqualTo: box.topAnchor),
      view.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor),
      view.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor),
      view.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor),
      view.centerXAnchor.constraint(equalTo: box.centerXAnchor),
      view.centerYAnchor.constraint(equalTo: box.centerYAnchor),
    ])
    return box
  }

  private func patchAnimatedContainer(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let box = view as? AnimatedBoxView else { return false }
    let duration = (number(node["durationMs"]) ?? 200) / 1000
    let target = (node["color"] as? String).map { color($0, fallback: $0) }
    box.setSize(width: number(node["width"]), height: number(node["height"]))
    // Laid out from the top of the tree: a box that grows moves whatever is
    // below it, and that has to move at the same time or it jumps.
    var root: UIView = box
    while let parent = root.superview { root = parent }
    UIView.animate(withDuration: duration, delay: 0, options: curve(node)) {
      box.backgroundColor = target
      root.layoutIfNeeded()
    }
    return true
  }

  /// A protocol curve name as a UIKit animation option.
  private func curve(_ node: [String: Any]) -> UIView.AnimationOptions {
    switch node["curve"] as? String {
    case "linear": return .curveLinear
    case "easeIn": return .curveEaseIn
    case "easeOut": return .curveEaseOut
    default: return .curveEaseInOut
    }
  }

  /// A strip of labels, one selected.
  ///
  /// A segmented control, because that is how iOS asks someone to choose one
  /// of a few things - Material's underlined tabs would look imported. The
  /// selection is the app's: a tap reports the index and the next tree says
  /// which segment is selected.
  private func renderTabs(_ node: [String: Any]) -> UIView {
    let labels = (node["tabs"] as? [Any])?.map { "\($0)" } ?? []
    let control = UISegmentedControl(items: labels)
    control.selectedSegmentIndex = tabIndex(node, count: labels.count)
    control.selectedSegmentTintColor = color(themePrimary, fallback: themePrimary)
    control.setTitleTextAttributes(
      [.foregroundColor: color(themeOnPrimary, fallback: themeOnPrimary)],
      for: .selected)
    bindings[control.hash] = node
    control.addTarget(self, action: #selector(tabChanged(_:)), for: .valueChanged)
    return control
  }

  /// The selected index [node] names, kept inside the control's range.
  private func tabIndex(_ node: [String: Any], count: Int) -> Int {
    let index = Int(number(node["selectedIndex"]) ?? 0)
    guard count > 0 else { return UISegmentedControl.noSegment }
    return Swift.min(Swift.max(index, 0), count - 1)
  }

  private func patchTabs(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let control = view as? UISegmentedControl else { return false }
    let labels = (node["tabs"] as? [Any])?.map { "\($0)" } ?? []
    // A different set of labels is a different control; only the selection
    // moves in place, which is what a tap changes.
    guard labels.count == control.numberOfSegments else { return false }
    for (index, label) in labels.enumerated() {
      guard control.titleForSegment(at: index) == label else { return false }
    }
    bindings[control.hash] = node
    let index = tabIndex(node, count: labels.count)
    if control.selectedSegmentIndex != index {
      control.selectedSegmentIndex = index
    }
    return true
  }

  /// Equal cells in a fixed number of columns.
  ///
  /// Frame-positioned like the Wrap's flow, because every cell has to be one
  /// size - which a stack cannot do without a row of equal-width constraints
  /// per line.
  private func renderGrid(_ node: [String: Any]) -> UIView {
    let grid = GridView(
      columns: Int(number(node["crossAxisCount"]) ?? 2),
      hSpacing: CGFloat(number(node["spacing"]) ?? 0),
      vSpacing: CGFloat(number(node["runSpacing"]) ?? 0),
      aspectRatio: CGFloat(number(node["childAspectRatio"]) ?? 1)
    )
    for child in childNodes(node) {
      guard let view = renderWidget(child) else { continue }
      // The grid frames its cells, so they must not manage their own.
      view.translatesAutoresizingMaskIntoConstraints = true
      grid.addSubview(view)
    }
    return grid
  }

  /// A value dragged along a track.
  ///
  /// UIKit's own slider, so the gesture, the accessibility and the feel are the
  /// platform's. `divisions` is not something UISlider has, so the value is
  /// snapped to the nearest step as it moves - which is what the other
  /// renderers get from their step attribute.
  private func renderSlider(_ node: [String: Any]) -> UIView {
    let slider = UISlider()
    slider.minimumValue = Float(number(node["min"]) ?? 0)
    slider.maximumValue = Float(number(node["max"]) ?? 1)
    slider.value = sliderValue(node)
    slider.isEnabled = !(node["disabled"] as? Bool ?? false)
    tintSlider(slider, node)
    bindings[slider.hash] = node
    slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
    for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
      slider.addTarget(self, action: #selector(sliderReleased(_:)), for: event)
    }
    return slider
  }

  /// [node]'s value, snapped to its divisions and clamped to its range.
  private func sliderValue(_ node: [String: Any]) -> Float {
    let min = Float(number(node["min"]) ?? 0)
    let max = Float(number(node["max"]) ?? 1)
    let value = Float(number(node["value"]) ?? Double(min))
    return Swift.min(Swift.max(value, min), max)
  }

  /// Snaps [value] to one of [node]'s divisions, if it has any.
  private func sliderSnap(_ node: [String: Any], _ value: Float) -> Float {
    guard let divisions = number(node["divisions"]), divisions > 0 else {
      return value
    }
    let min = Float(number(node["min"]) ?? 0)
    let max = Float(number(node["max"]) ?? 1)
    let step = (max - min) / Float(divisions)
    return min + (((value - min) / step).rounded() * step)
  }

  private func patchSlider(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let slider = view as? UISlider else { return false }
    slider.minimumValue = Float(number(node["min"]) ?? 0)
    slider.maximumValue = Float(number(node["max"]) ?? 1)
    slider.isEnabled = !(node["disabled"] as? Bool ?? false)
    tintSlider(slider, node)
    bindings[slider.hash] = node
    // Not while a finger is on it: the app is echoing back the value the drag
    // is already setting, and writing it would fight the gesture.
    let value = sliderValue(node)
    if slider.value != value && !slider.isTracking { slider.value = value }
    return true
  }

  private func renderToggle(_ node: [String: Any]) -> UIView {
    let toggle = UISwitch()
    toggle.isOn = node["enabled"] as? Bool ?? false
    tintToggle(toggle, node)
    toggle.isEnabled = !(node["disabled"] as? Bool ?? false)
    // A switch has no text of its own: it is named by the label drawn beside
    // it, or by the node - a list tile's title - when there is none.
    toggle.accessibilityLabel = node["label"] as? String ?? node["semanticLabel"] as? String
    bindings[toggle.hash] = node
    toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)

    guard let labelText = node["label"] as? String else { return toggle }

    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 8
    stack.alignment = .center
    let label = UILabel()
    label.text = labelText
    label.textColor = color(themeText, fallback: themeText)
    stack.addArrangedSubview(toggle)
    stack.addArrangedSubview(label)
    return stack
  }

  // MARK: - Lists

  private func renderList(_ node: [String: Any]) -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .fill
    addArranged(stack, node)
    return stack
  }

  private func renderListItem(_ node: [String: Any]) -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 2
    stack.alignment = .leading
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

    let title = UILabel()
    title.text = node["text"] as? String ?? ""
    title.font = .systemFont(ofSize: 16)
    stack.addArrangedSubview(title)

    if let subtitle = node["subtitle"] as? String {
      let label = UILabel()
      label.text = subtitle
      label.font = .systemFont(ofSize: 13)
      label.textColor = .secondaryLabel
      stack.addArrangedSubview(label)
    }
    return stack
  }

  // MARK: - Long lists

  /**
   A list of `itemCount` rows of `itemExtent` points, of which the node carries
   only the rows from `startIndex` on.

   The scrollable area is sized for every row, and each row the node carries is
   framed where it sits in the whole list. The visible range goes back to Dart,
   which sends a different window of rows when that range nears its edge.
   */
  private func renderLazyList(_ node: [String: Any]) -> UIView {
    let id = node["id"] as? String ?? ""
    let list = LazyListView()
    list.itemCount = max(0, Int(number(node["itemCount"]) ?? 0))
    list.itemExtent = max(1, number(node["itemExtent"]) ?? 48)
    list.startIndex = max(0, Int(number(node["startIndex"]) ?? 0))
    // Rows of their own heights arrive with the window's own heights, where
    // the window starts and how tall the list is; uniform rows are arithmetic.
    list.rowExtents = rowExtents(node)
    list.startOffset = number(node["startOffset"]) ?? 0
    list.totalExtent = number(node["totalExtent"]) ?? 0
    // The views are new on every render, so the offset the user scrolled to
    // is put back once the list has a size.
    list.restoreOffset = listOffsets[id] ?? 0
    // "Scroll there" is a moment, carried by a version like a field's focus:
    // obeyed the first time it is seen and whenever it changes.
    if let target = lazyListJump(node, id: id) {
      list.restoreOffset = target
      listOffsets[id] = target
    }
    // Takes whatever height the stack it sits in has left.
    list.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)

    for child in childNodes(node) {
      let row = renderWidget(child) ?? UIView()
      row.translatesAutoresizingMaskIntoConstraints = true
      list.addSubview(row)
      list.rows.append(row)
    }

    let eventId = node["rangeEventId"] as? String
    list.onViewportChange = { [weak self, weak list] in
      guard let self, let list else { return }
      self.reportRange(list, id: id, eventId: eventId)
    }
    return list
  }

  /// Remembers where `list` is scrolled, and sends the rows it shows when they
  /// differ from the ones last sent for this list.
  private func reportRange(_ list: LazyListView, id: String, eventId: String?) {
    let viewport = list.bounds.height
    guard list.restoreOffset == nil, viewport > 0 else { return }

    // A bounce past either end is not a position.
    let maxOffset = max(0, list.contentSize.height - viewport)
    let offset = min(max(0, list.contentOffset.y), maxOffset)
    listOffsets[id] = offset

    guard let eventId else { return }
    // Rows of different heights are reported as pixels: only the Dart side
    // knows how tall the rows outside the window are, so only it can say
    // which row an offset lands on.
    if !list.rowExtents.isEmpty {
      if let previous = listOffsetReports[id],
        previous.offset == offset, previous.viewport == viewport
      {
        return
      }
      listOffsetReports[id] = (offset: offset, viewport: viewport)
      send(eventId: eventId, data: ["offset": offset, "viewport": viewport])
      return
    }
    let first = Int(floor(offset / list.itemExtent))
    let last = min(list.itemCount - 1, Int(ceil((offset + viewport) / list.itemExtent)) - 1)
    if let previous = listRanges[id], previous.first == first, previous.last == last {
      return
    }
    listRanges[id] = (first: first, last: last)
    send(eventId: eventId, data: ["first": first, "last": last])
  }

  /// The heights of the rows a node's window carries, in points.
  private func rowExtents(_ node: [String: Any]) -> [CGFloat] {
    guard let extents = node["extents"] as? [Any] else { return [] }
    return extents.map { number($0) ?? 0 }
  }

  // MARK: - Overlays

  /**
   The screen, with overlays drawn above it.

   The first child is the screen; each later one is pinned over the whole
   container, later ones on top. Overlays are views like any other rather than
   presented view controllers, so they come and go exactly as the tree does -
   this renderer never closes one, it only sends the overlay's events.
   */
  private func renderOverlay(_ node: [String: Any]) -> UIView {
    let container = UIView()
    for child in childNodes(node) {
      guard let view = renderWidget(child) else { continue }
      pin(view, to: container)
    }
    return container
  }

  /**
   Backs a modal surface - a dialog or a bottom sheet - with iOS 26 Liquid
   Glass, or the opaque surface fill on older systems. The glass fills [surface]
   and sits behind whatever content is added next; the surface's own rounded clip
   shapes it.

   Left untinted on purpose: a white tint (the surface colour) renders the glass
   as a solid white panel indistinguishable from the old fill, so it reads as a
   plain sheet. Untinted, it frosts the dimmed scrim behind it into a real glass
   panel, and the root's light appearance keeps the fixed dark content legible.
   */
  private func applyModalSurface(_ surface: UIView) {
    if #available(iOS 26.0, *) {
      let effect = UIVisualEffectView(effect: UIGlassEffect())
      // Fade the frost as the app asks for more transparency, so the backdrop
      // shows through more sharply. The content is a sibling on top, so it stays
      // crisp; a floor keeps some glass presence at full transparency.
      effect.alpha = max(0.2, 1 - themeGlassTransparency)
      pin(effect, to: surface)
    } else {
      surface.backgroundColor = surfaceVariantColor()
    }
  }

  /**
   A modal dialog: a scrim over everything, and a surface centred on it.

   A tap on the scrim sends the dismiss event with `reason: scrim` when the
   dialog is dismissible. The surface sits beside the scrim rather than inside
   it, so a touch on the surface never reaches the scrim's recognizer.
   */
  private func renderDialog(_ node: [String: Any]) -> UIView {
    let container = modalContainer(node)

    let surface = UIView()
    surface.layer.cornerRadius = 16
    surface.clipsToBounds = true
    surface.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(surface)
    applyModalSurface(surface)

    let content = surfaceContent(node, inset: 24)
    pin(content, to: surface)

    let safe = container.safeAreaLayoutGuide
    let preferredWidth = surface.widthAnchor.constraint(
      equalTo: container.widthAnchor, constant: -48)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      surface.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      surface.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
      surface.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
      surface.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -48),
      preferredWidth,
      surface.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 24),
      surface.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -24),
    ])
    return container
  }

  /**
   A modal sheet along the bottom edge.

   Dismissed like a dialog, and also by dragging it down past a threshold,
   which sends `reason: swipe` and springs the sheet back - the app removes it
   by rendering a tree without it.
   */
  private func renderBottomSheet(_ node: [String: Any]) -> UIView {
    let container = modalContainer(node)

    let surface = SheetSurface()
    surface.layer.cornerRadius = 16
    surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    surface.clipsToBounds = true
    surface.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(surface)
    applyModalSurface(surface)

    let content = surfaceContent(node, inset: 16)
    // Dragging down at the top moves the sheet, not the content.
    content.bounces = false
    content.translatesAutoresizingMaskIntoConstraints = false
    surface.addSubview(content)

    let preferredWidth = surface.widthAnchor.constraint(equalTo: container.widthAnchor)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: surface.topAnchor),
      content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      // The surface runs to the screen's edge; its content stops above the
      // home indicator.
      content.bottomAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.bottomAnchor),
      surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      surface.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      surface.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
      surface.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
      preferredWidth,
      surface.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: 0.9),
      surface.topAnchor.constraint(
        greaterThanOrEqualTo: container.safeAreaLayoutGuide.topAnchor),
    ])

    if isDismissible(node) {
      let drag = UIPanGestureRecognizer(target: self, action: #selector(sheetDragged(_:)))
      let dragDelegate = SheetDragDelegate()
      dragDelegate.content = content
      drag.delegate = dragDelegate
      // The recognizer holds its delegate weakly.
      surface.dragDelegate = dragDelegate
      surface.addGestureRecognizer(drag)
      bindings[drag.hash] = node
    }
    return container
  }

  /**
   A message along the bottom edge that blocks nothing.

   Its host covers the container but lets through every touch that does not
   land on the bar. After `durationMs` it sends the dismiss event with
   `reason: timeout`, once per snackbar however often it is rendered.
   */
  private func renderSnackbar(_ node: [String: Any]) -> UIView {
    // Above the scaffold's bottom bar and floating button, not over them.
    let host = SnackbarHost()
    host.below = { [weak self] in
      [self?.scaffoldBottomBar, self?.scaffoldFab].compactMap { $0 }
    }
    snackbarHost = host

    let bar = UIView()
    bar.backgroundColor = color(inversePalette.surface, fallback: inversePalette.surface)
    bar.layer.cornerRadius = 4
    bar.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(bar)

    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    stack.isLayoutMarginsRelativeArrangement = true
    // More room before the message than after the action, whichever side each
    // is on.
    stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 6, leading: 16, bottom: 6, trailing: 8)

    let message = UILabel()
    message.text = node["message"] as? String ?? ""
    message.textColor = color(inversePalette.text, fallback: inversePalette.text)
    message.font = .systemFont(ofSize: 14)
    message.numberOfLines = 0
    stack.addArrangedSubview(message)

    if let actionLabel = node["actionLabel"] as? String, node["actionEventId"] is String {
      let action = UIButton(type: .system)
      action.setTitle(actionLabel, for: .normal)
      action.setTitleColor(
        color(inversePalette.primary, fallback: inversePalette.primary), for: .normal)
      action.setContentHuggingPriority(.required, for: .horizontal)
      action.setContentCompressionResistancePriority(.required, for: .horizontal)
      bindings[action.hash] = node
      action.addTarget(self, action: #selector(snackbarActionTapped(_:)), for: .touchUpInside)
      stack.addArrangedSubview(action)
    }

    pin(stack, to: bar)
    let preferredWidth = bar.widthAnchor.constraint(equalTo: host.widthAnchor, constant: -32)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      bar.centerXAnchor.constraint(equalTo: host.centerXAnchor),
      bar.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
      bar.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -32),
      preferredWidth,
      bar.bottomAnchor.constraint(
        equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -16),
    ])

    trackSnackbar(node)
    return host
  }

  /// Starts the timeout of a snackbar the tree did not hold before.
  private func trackSnackbar(_ node: [String: Any]) {
    let identity =
      node["id"] as? String ?? node["dismissEventId"] as? String
      ?? node["message"] as? String ?? ""
    renderedSnackbars.insert(identity)
    guard !shownSnackbars.contains(identity) else { return }
    shownSnackbars.insert(identity)

    if let message = node["message"] as? String {
      UIAccessibility.post(notification: .announcement, argument: message)
    }

    guard
      let eventId = node["dismissEventId"] as? String,
      let duration = number(node["durationMs"]), duration > 0
    else { return }
    let timeout = DispatchWorkItem { [weak self] in
      self?.send(eventId: eventId, data: ["reason": "timeout"])
    }
    snackbarTimers[identity] = timeout
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Double(duration) / 1000, execute: timeout)
  }

  /// Cancels the timeouts of snackbars the last render left out, so one that
  /// comes back later is a new snackbar.
  private func forgetRemovedSnackbars() {
    for (identity, timeout) in snackbarTimers where !renderedSnackbars.contains(identity) {
      timeout.cancel()
      snackbarTimers[identity] = nil
    }
    shownSnackbars.formIntersection(renderedSnackbars)
  }

  /// A full-size container for a modal overlay, with its scrim.
  private func modalContainer(_ node: [String: Any]) -> UIView {
    let container = UIView()
    // VoiceOver stays inside the overlay while it is open.
    container.accessibilityViewIsModal = true
    container.accessibilityLabel = node["title"] as? String

    let scrim = UIView()
    // A glass surface reads as glass only when the content behind it shows
    // through; the 0.4 scrim dims it to a flat grey. iOS 26 glass sheets use
    // lighter dimming for exactly this reason, so drop the scrim there and let
    // the frost carry the separation. Older systems keep the solid dimming.
    let scrimAlpha: CGFloat
    if #available(iOS 26.0, *) {
      // Lighten the dimming as the app asks for more glass transparency, so the
      // frosted surface has more of the backdrop to show through.
      scrimAlpha = 0.15 * (1 - themeGlassTransparency)
    } else {
      scrimAlpha = 0.4
    }
    scrim.backgroundColor = UIColor.black.withAlphaComponent(scrimAlpha)
    pin(scrim, to: container)

    if isDismissible(node) {
      let tap = UITapGestureRecognizer(target: self, action: #selector(scrimTapped(_:)))
      scrim.addGestureRecognizer(tap)
      bindings[tap.hash] = node
    }
    return container
  }

  /**
   The scrolling content of a dialog or sheet: its title, then its children
   top to bottom.

   The scroll view is as tall as its content until the surface's own limits
   make it shorter, and then scrolls.
   */
  private func surfaceContent(_ node: [String: Any], inset: CGFloat) -> UIScrollView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 16
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)

    if let title = node["title"] as? String {
      let label = UILabel()
      label.text = title
      label.font = .systemFont(ofSize: 20, weight: .semibold)
      label.numberOfLines = 0
      label.accessibilityTraits = .header
      stack.addArrangedSubview(label)
    }
    for child in childNodes(node) {
      guard let view = renderWidget(child) else { continue }
      // The dialog's actions row asks to sit at the end, which a filling
      // stack would otherwise stretch across.
      if child["type"] as? String == "Row", child["mainAxisAlignment"] as? String == "end" {
        stack.addArrangedSubview(trailing(view))
      } else {
        stack.addArrangedSubview(view)
      }
    }

    let scroll = UIScrollView()
    scroll.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let fitContent = scroll.heightAnchor.constraint(equalTo: stack.heightAnchor)
    fitContent.priority = .defaultHigh
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      fitContent,
    ])
    return scroll
  }

  /// Wraps `view` so it keeps its own width at the trailing edge.
  private func trailing(_ view: UIView) -> UIView {
    let box = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: box.topAnchor),
      view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
      view.trailingAnchor.constraint(equalTo: box.trailingAnchor),
      view.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor),
    ])
    return box
  }

  private func isDismissible(_ node: [String: Any]) -> Bool {
    (node["dismissible"] as? Bool ?? true) && node["dismissEventId"] is String
  }

  /// Sends a dismissible overlay's dismiss event; the app decides whether it
  /// goes.
  private func dismiss(_ node: [String: Any]?, reason: String) {
    guard let node, isDismissible(node), let eventId = node["dismissEventId"] as? String
    else { return }
    send(eventId: eventId, data: ["reason": reason])
  }

  @objc private func scrimTapped(_ sender: UITapGestureRecognizer) {
    dismiss(bindings[sender.hash], reason: "scrim")
  }

  @objc private func snackbarActionTapped(_ sender: UIButton) {
    guard let eventId = bindings[sender.hash]?["actionEventId"] as? String else { return }
    send(eventId: eventId, data: [:])
  }

  /// Follows a downward drag, and on release past the threshold - or a fast
  /// flick - asks for the sheet to be dismissed. Either way it springs back.
  @objc private func sheetDragged(_ sender: UIPanGestureRecognizer) {
    guard let sheet = sender.view else { return }
    let distance = max(0, sender.translation(in: sheet.superview).y)

    switch sender.state {
    case .changed:
      sheet.transform = CGAffineTransform(translationX: 0, y: distance)
    case .ended, .cancelled, .failed:
      let flicked = sender.velocity(in: sheet.superview).y > 1000
      let threshold = min(120, sheet.bounds.height / 3)
      if sender.state == .ended, distance > threshold || flicked {
        dismiss(bindings[sender.hash], reason: "swipe")
      }
      UIView.animate(
        withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8,
        initialSpringVelocity: 0, options: [],
        animations: { sheet.transform = .identity }, completion: nil)
    default:
      break
    }
  }

  // MARK: - Free-form composition

  /// A colour the tree states, or nil when it states none (or one that does
  /// not parse). `#rrggbb` and `#aarrggbb` both.
  private func statedColor(_ value: Any?) -> UIColor? {
    (value as? String).flatMap { UIColor(hex: $0) }
  }

  /// `[left, top, right, bottom]` as insets; one number is all four edges.
  private func insets(_ value: Any?) -> UIEdgeInsets {
    if let all = number(value) {
      return UIEdgeInsets(top: all, left: all, bottom: all, right: all)
    }
    guard let list = value as? [Any], list.count >= 4 else { return .zero }
    return UIEdgeInsets(
      top: number(list[1]) ?? 0, left: number(list[0]) ?? 0,
      bottom: number(list[3]) ?? 0, right: number(list[2]) ?? 0)
  }

  /// An `[x, y]` pair.
  private func point(_ value: Any?) -> CGPoint? {
    guard let list = value as? [Any], list.count >= 2 else { return nil }
    return CGPoint(x: number(list[0]) ?? 0, y: number(list[1]) ?? 0)
  }

  /// A length that can be a constraint's constant: infinity cannot.
  private func finite(_ value: Any?) -> CGFloat? {
    guard let parsed = number(value), parsed.isFinite else { return nil }
    return parsed
  }

  /// The background a Box states, when it is solid enough to read text
  /// against - a faint tint over something else says nothing about what the
  /// text is over.
  private func boxBackground(_ node: [String: Any]) -> Any? {
    guard node["gradient"] == nil, let stated = statedColor(node["color"]),
      stated.cgColor.alpha >= 0.5
    else { return nil }
    return node["color"]
  }

  /// Everything a Box (or a Canvas, which is sized and touched like one) says
  /// about itself.
  private func boxStyle(_ node: [String: Any]) -> DnnBoxStyle {
    var style = DnnBoxStyle()

    let expand = node["expand"] as? String
    style.expandWidth = expand == "width" || expand == "both"
    style.expandHeight = expand == "height" || expand == "both"
    // An infinite width is Flutter's way of saying "all of it".
    if let width = number(node["width"]) {
      if width.isFinite { style.width = width } else { style.expandWidth = true }
    }
    if let height = number(node["height"]) {
      if height.isFinite { style.height = height } else { style.expandHeight = true }
    }
    style.minWidth = finite(node["minWidth"])
    style.maxWidth = finite(node["maxWidth"])
    style.minHeight = finite(node["minHeight"])
    style.maxHeight = finite(node["maxHeight"])
    style.aspectRatio = finite(node["aspectRatio"])
    style.padding = insets(node["padding"])
    style.margin = insets(node["margin"])
    style.alignment = point(node["alignment"])

    style.color = statedColor(node["color"])
    if let gradient = node["gradient"] as? [String: Any] {
      style.gradientColors = (gradient["colors"] as? [Any] ?? []).compactMap {
        statedColor($0)
      }
      style.gradientStops = (gradient["stops"] as? [Any] ?? []).compactMap { number($0) }
      style.gradientRadial = gradient["type"] as? String == "radial"
      // Alignments run from -1 to 1; a layer's unit space from 0 to 1.
      func unit(_ alignment: CGPoint) -> CGPoint {
        CGPoint(x: (alignment.x + 1) / 2, y: (alignment.y + 1) / 2)
      }
      let begin = point(gradient["begin"])
      let end = point(gradient["end"])
      if style.gradientRadial {
        // `begin` is the centre and `end` a point the last colour is reached
        // at. A radial layer wants the corner of the ellipse's box instead.
        let centre = unit(begin ?? CGPoint(x: 0, y: 0))
        var reach = CGSize(width: 0.5, height: 0.5)
        if let end = end {
          let edge = unit(end)
          let dx = abs(edge.x - centre.x)
          let dy = abs(edge.y - centre.y)
          let radius = max(dx, dy)
          if radius > 0.0001 {
            reach = CGSize(width: dx > 0.0001 ? dx : radius, height: dy > 0.0001 ? dy : radius)
          }
        }
        style.gradientStart = centre
        style.gradientEnd = CGPoint(x: centre.x + reach.width, y: centre.y + reach.height)
      } else {
        style.gradientStart = unit(begin ?? CGPoint(x: -1, y: 0))
        style.gradientEnd = unit(end ?? CGPoint(x: 1, y: 0))
      }
    }

    style.borderWidth = max(0, finite(node["borderWidth"]) ?? 0)
    style.borderColor = statedColor(node["borderColor"])
    if style.borderWidth == 0, style.borderColor != nil { style.borderWidth = 1 }
    if let radii = node["borderRadii"] as? [Any], radii.count >= 4 {
      style.radii = radii.prefix(4).map { finite($0) ?? 0 }
    } else if let radius = finite(node["borderRadius"]) {
      style.radii = [radius, radius, radius, radius]
    }
    style.circle = node["shape"] as? String == "circle"
    if let shadow = node["shadow"] as? [String: Any] {
      style.shadowColor =
        statedColor(shadow["color"]) ?? UIColor.black.withAlphaComponent(0.25)
      style.shadowBlur = max(0, finite(shadow["blur"]) ?? 0)
      style.shadowOffset = CGSize(
        width: finite(shadow["dx"]) ?? 0, height: finite(shadow["dy"]) ?? 0)
    }
    style.clip = node["clip"] as? Bool ?? false
    style.opacity = finite(node["opacity"]) ?? 1
    if let transform = node["transform"] as? [String: Any] {
      // About the centre, which is where a view's transform already pivots:
      // scaled, then turned, then moved.
      let scale = finite(transform["scale"]) ?? 1
      style.transform = CGAffineTransform(
        translationX: finite(transform["dx"]) ?? 0, y: finite(transform["dy"]) ?? 0
      )
      .rotated(by: finite(transform["rotate"]) ?? 0)
      .scaledBy(x: scale, y: scale)
    }

    style.tapEventId = node["tapEventId"] as? String
    style.doubleTapEventId = node["doubleTapEventId"] as? String
    style.longPressEventId = node["longPressEventId"] as? String
    style.panEventId = node["panEventId"] as? String
    style.ripple = node["ripple"] as? Bool ?? false
    style.dragData = node["dragData"] as? String
    style.dropEventId = node["dropEventId"] as? String
    style.sizeEventId = node["sizeEventId"] as? String
    style.semanticLabel = node["semanticLabel"] as? String
    style.semanticValue = node["semanticValue"] as? String
    style.tooltip = node["tooltip"] as? String
    style.liveRegion = node["liveRegion"] as? Bool ?? false
    style.excludeSemantics = node["excludeSemantics"] as? Bool ?? false
    style.disabled = node["disabled"] as? Bool ?? false
    style.selected = node["selected"] as? Bool
    style.ignorePointer = node["ignorePointer"] as? Bool ?? false
    return style
  }

  private func configureBox(_ box: DnnBoxView, _ node: [String: Any]) {
    box.onEvent = { [weak self] eventId, data in
      self?.send(eventId: eventId, data: data)
    }
    box.apply(boxStyle(node))
  }

  /// A decorated box around at most one child - see `DnnBoxView`.
  private func renderBox(_ node: [String: Any]) -> UIView {
    let box = DnnBoxView()
    configureBox(box, node)
    if let child = firstChild(node) {
      box.replaceChild(over(boxBackground(node)) { buildChild(child) })
    }
    // Only notes what a live region says to begin with; see `announceChanges`.
    box.announceChanges()
    return box
  }

  /// Restyles a box in place - moving there over `animateMs` when the tree
  /// asks for motion, and landing at once when it does not.
  private func patchBox(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let box = view as? DnnBoxView else { return false }
    let duration = Double(number(node["animateMs"]) ?? 0) / 1000
    guard duration > 0, box.window != nil else {
      configureBox(box, node)
      return true
    }
    // Laid out from the top of the tree: a box that grows moves whatever is
    // around it, and that has to move at the same time or it jumps. Settled
    // first, so nothing but this change is carried along.
    var root: UIView = box
    while let parent = root.superview { root = parent }
    root.layoutIfNeeded()
    UIView.animate(
      withDuration: duration, delay: 0,
      options: [curve(node), .allowUserInteraction, .beginFromCurrentState],
      animations: {
        self.configureBox(box, node)
        root.layoutIfNeeded()
      }, completion: nil)
    return true
  }

  /// A surface drawn by a list of commands - see `DnnCanvasDrawingView`.
  private func renderCanvas(_ node: [String: Any]) -> UIView {
    let canvas = DnnCanvasView()
    configureBox(canvas, node)
    canvas.drawing.set(
      commands: node["commands"] as? [Any] ?? [], paints: node["paints"] as? [Any] ?? [])
    if let child = firstChild(node) {
      canvas.replaceChild(buildChild(child))
    }
    canvas.announceChanges()
    return canvas
  }

  /// Repaints a canvas in place. A render that changes only the picture - a
  /// game's frame - touches nothing but the picture.
  private func patchCanvas(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) -> Bool {
    guard let canvas = view as? DnnCanvasView else { return false }
    var before = oldNode["props"] as? [String: Any] ?? [:]
    var after = newNode["props"] as? [String: Any] ?? [:]
    for key in ["commands", "paints"] {
      before[key] = nil
      after[key] = nil
    }
    if !mapEqual(before, after) { configureBox(canvas, newNode) }
    canvas.drawing.set(
      commands: newNode["commands"] as? [Any] ?? [],
      paints: newNode["paints"] as? [Any] ?? [])
    return true
  }

  /// Children drawn over one another - see `DnnStackView`. (`renderStack` is
  /// the VStack/HStack one.)
  private func renderLayers(_ node: [String: Any]) -> UIView {
    let stack = DnnStackView()
    stack.configure(
      // An alignment the tree states names a side. With none stated the
      // layers gather at the top *start*, which is the right-hand corner when
      // the screen reads right to left.
      alignment: point(node["alignment"]) ?? CGPoint(x: isRTL ? 1 : -1, y: -1),
      expand: node["fit"] as? String == "expand",
      clip: node["clip"] as? Bool ?? true)
    for child in childNodes(node) {
      stack.addLayer(buildChild(child), at: nil)
    }
    return stack
  }

  /// A child pinned inside a Stack; outside one it is just its child.
  private func renderPositioned(_ node: [String: Any]) -> UIView {
    let wrapper = DnnPositionedView()
    if let child = firstChild(node) {
      wrapper.replaceChild(buildChild(child))
    }
    applyPosition(wrapper, node)
    return wrapper
  }

  private func applyPosition(_ view: DnnPositionedView, _ node: [String: Any]) {
    view.setPosition(
      left: finite(node["left"]), top: finite(node["top"]), right: finite(node["right"]),
      bottom: finite(node["bottom"]), width: finite(node["width"]),
      height: finite(node["height"]))
  }

  private func patchPositioned(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let wrapper = view as? DnnPositionedView else { return false }
    applyPosition(wrapper, node)
    return true
  }

  /// One child, scrolled along one axis - see `DnnScrollView`.
  private func renderScroll(_ node: [String: Any]) -> UIView {
    let scroll = DnnScrollView()
    configureScroll(scroll, node)
    if let child = firstChild(node) {
      scroll.replaceChild(buildChild(child))
    }
    // The views are new on a rebuild, so the offset the user scrolled to is
    // put back once the scroller has content - for a scroller with an id to
    // remember it by.
    let id = node["id"] as? String
    if let id, let saved = scrollOffsets[id] {
      scroll.restoreOffset = saved
    }
    scroll.onScrolled = { [weak self] offset in
      guard let id else { return }
      self?.scrollOffsets[id] = offset
    }
    applyScrollJump(scroll, node)
    return scroll
  }

  private func configureScroll(_ scroll: DnnScrollView, _ node: [String: Any]) {
    let horizontal = node["axis"] as? String == "horizontal"
    scroll.configure(
      horizontal: horizontal,
      padding: insets(node["padding"]),
      shrinkWrap: node["shrinkWrap"] as? Bool ?? false,
      reverse: node["reverse"] as? Bool ?? false)
    // Pull-to-refresh is a vertical gesture.
    let refreshId = node["refreshEventId"] as? String
    scroll.setRefresh(
      enabled: refreshId != nil && !horizontal,
      tint: color(themePrimary, fallback: themePrimary))
    scroll.onRefresh = { [weak self] in
      guard let refreshId else { return }
      self?.send(eventId: refreshId, data: [:])
    }
    scroll.setRefreshing(node["refreshing"] as? Bool ?? false)
    // Set on every patch: the id is a prop like any other, and names a
    // different callback from one build to the next.
    if let scrolledId = node["scrollEventId"] as? String {
      scroll.onReport = { [weak self] offset, maxExtent, viewport in
        self?.send(
          eventId: scrolledId,
          data: [
            "offset": Double(offset), "maxExtent": Double(maxExtent),
            "viewport": Double(viewport),
          ])
      }
    } else {
      scroll.onReport = nil
    }
  }

  /// Jumps to `scrollOffset` the first time its `scrollVersion` is seen, and
  /// again whenever the version changes - a moment carried as a state, like a
  /// field's `focusVersion`.
  private func applyScrollJump(_ scroll: DnnScrollView, _ node: [String: Any]) {
    guard let offset = finite(node["scrollOffset"]) else { return }
    let version = (node["scrollVersion"] as? NSNumber)?.intValue ?? 0
    if let id = node["id"] as? String {
      // Remembered past a rebuild, so a new view for the same scroller does
      // not obey the same ask twice.
      if scrollVersions[id] == version { return }
      scrollVersions[id] = version
    } else if scroll.appliedScrollVersion == version {
      return
    }
    scroll.appliedScrollVersion = version
    scroll.jump(to: offset)
  }

  private func patchScroll(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let scroll = view as? DnnScrollView else { return false }
    configureScroll(scroll, node)
    applyScrollJump(scroll, node)
    return true
  }

  /// One glyph of an icon font: Material Icons, which the app already
  /// bundles, unless the node names another family UIKit knows.
  private func renderIcon(_ node: [String: Any]) -> UIView {
    let label = UILabel()
    label.textAlignment = .center
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentHuggingPriority(.required, for: .vertical)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    applyGlyph(label, node)
    return label
  }

  private func applyGlyph(_ label: UILabel, _ node: [String: Any]) {
    let size = number(node["size"]) ?? 24
    var font = iconFont?.withSize(size)
    if let family = node["fontFamily"] as? String, family != "MaterialIcons",
      let named = UIFont(name: family, size: size)
    {
      font = named
    }
    if let font, let codepoint = number(node["codepoint"]), codepoint >= 0,
      let scalar = UnicodeScalar(UInt32(codepoint))
    {
      label.font = font
      label.text = String(scalar)
    } else {
      label.text = nil
    }
    // The colour it states, or the one in force around it - an app bar's
    // foreground, the text over a coloured box - or the theme's text colour.
    label.textColor = textColor(node)
    if let spoken = node["semanticLabel"] as? String {
      label.isAccessibilityElement = true
      label.accessibilityLabel = spoken
      label.accessibilityTraits = .image
    } else {
      // A glyph is a private-use character; read aloud it is noise.
      label.isAccessibilityElement = false
    }
  }

  private func patchIcon(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let label = view as? UILabel else { return false }
    applyGlyph(label, node)
    return true
  }

  /// A Material Icons glyph as a template image, for the places UIKit wants an
  /// image rather than text: a tab bar item, a button's icon, a field's ends.
  private func iconImage(_ codepoint: Any?, size: CGFloat) -> UIImage? {
    guard let value = number(codepoint), value >= 0,
      let scalar = UnicodeScalar(UInt32(value)), let font = iconFont?.withSize(size)
    else { return nil }
    let glyph = String(scalar) as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: UIColor.black,
    ]
    let measured = glyph.size(withAttributes: attributes)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    let image = renderer.image { _ in
      glyph.draw(
        at: CGPoint(x: (size - measured.width) / 2, y: (size - measured.height) / 2),
        withAttributes: attributes)
    }
    return image.withRenderingMode(.alwaysTemplate)
  }

  // MARK: - Choosing

  /// One of a list, chosen from a pull-down menu - see `DnnDropdownView`.
  private func renderDropdown(_ node: [String: Any]) -> UIView {
    let dropdown = DnnDropdownView()
    configureDropdown(dropdown, node)
    return dropdown
  }

  private func configureDropdown(_ dropdown: DnnDropdownView, _ node: [String: Any]) {
    let eventId = node["eventId"] as? String
    let payload = node["data"] as? [String: Any] ?? [:]
    dropdown.onPick = { [weak self] index in
      guard let eventId else { return }
      var data = payload
      data["index"] = index
      self?.send(eventId: eventId, data: data)
    }
    dropdown.configure(
      items: (node["items"] as? [Any])?.map { "\($0)" } ?? [],
      selected: (node["selectedIndex"] as? NSNumber)?.intValue,
      label: node["label"] as? String,
      hint: node["hint"] as? String,
      error: node["error"] as? String,
      enabled: (node["enabled"] as? Bool ?? true) && eventId != nil,
      outlined: node["outlined"] as? Bool ?? true,
      text: color(themeText, fallback: themeText),
      quiet: color(themeTextSecondary, fallback: themeTextSecondary),
      border: color(themeDivider, fallback: themeDivider),
      danger: color(themeError, fallback: themeError))
  }

  private func patchDropdown(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let dropdown = view as? DnnDropdownView else { return false }
    configureDropdown(dropdown, node)
    return true
  }

  /**
   The platform's date or time picker, as an overlay.

   Presented the way a Dialog is: a scrim over everything and a surface on it,
   in the tree for as long as it is open. Done sends the value, Cancel and a tap
   on the scrim send the dismiss event, and the app closes it by rendering a
   tree without it.
   */
  private func renderPicker(_ node: [String: Any], time: Bool) -> UIView {
    let container = modalContainer(node)

    let surface = UIView()
    surface.layer.cornerRadius = 16
    surface.clipsToBounds = true
    surface.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(surface)
    applyModalSurface(surface)

    let panel = DnnPickerPanel(
      title: node["title"] as? String,
      confirm: node["confirmLabel"] as? String ?? "Done",
      cancel: node["cancelLabel"] as? String ?? "Cancel",
      tint: color(themePrimary, fallback: themePrimary))
    pin(panel, to: surface)

    let picker = panel.picker
    if time {
      picker.datePickerMode = .time
      if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .wheels }
      // A picker takes its clock from its locale; the tree can say which.
      if let use24Hour = node["use24Hour"] as? Bool {
        picker.locale = Locale(identifier: use24Hour ? "en_GB" : "en_US")
      }
      let hour = (node["hour"] as? NSNumber)?.intValue ?? 0
      let minute = (node["minute"] as? NSNumber)?.intValue ?? 0
      if let date = Calendar.current.date(
        bySettingHour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0,
        of: Date())
      {
        picker.date = date
      }
    } else {
      picker.datePickerMode = .date
      if #available(iOS 14.0, *) {
        picker.preferredDatePickerStyle = .inline
      } else if #available(iOS 13.4, *) {
        picker.preferredDatePickerStyle = .wheels
      }
      let first = day(node["first"] as? String)
      let last = day(node["last"] as? String)
      if let first, let last, first <= last {
        picker.minimumDate = first
        picker.maximumDate = last
      }
      if let initial = day(node["initial"] as? String) { picker.date = initial }
    }

    let eventId = node["eventId"] as? String
    let dismissId = node["dismissEventId"] as? String
    panel.onCancel = { [weak self] in
      guard let dismissId else { return }
      self?.send(eventId: dismissId, data: ["reason": "cancel"])
    }
    panel.onDone = { [weak self] date in
      guard let self, let eventId else { return }
      if time {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.send(
          eventId: eventId, data: ["hour": parts.hour ?? 0, "minute": parts.minute ?? 0])
      } else {
        self.send(eventId: eventId, data: ["value": self.dayFormatter.string(from: date)])
      }
    }

    let safe = container.safeAreaLayoutGuide
    let preferredWidth = surface.widthAnchor.constraint(
      equalTo: container.widthAnchor, constant: -32)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      surface.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      surface.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
      surface.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
      surface.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -32),
      preferredWidth,
      surface.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 16),
      surface.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -16),
    ])
    return container
  }

  /// `yyyy-mm-dd`, in the device's own time zone: a day, not an instant.
  private lazy var dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private func day(_ value: String?) -> Date? {
    guard let value else { return nil }
    return dayFormatter.date(from: value)
  }

  // MARK: - App chrome along the bottom edge

  /**
   Holds its child along the bottom edge of a scaffold.

   The bar itself runs to the very edge of the screen and paints the home
   indicator's strip; its child stops at the safe area. Anywhere but the bottom
   of the screen there is no inset and it is simply its child on a surface.
   */
  private func renderBottomBar(_ node: [String: Any]) -> UIView {
    let bar = UIView()
    bar.backgroundColor = surfaceColor()
    guard let child = firstChild(node) else { return bar }
    let view = buildChild(child)
    view.translatesAutoresizingMaskIntoConstraints = false
    bar.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: bar.topAnchor),
      view.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
      view.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor),
    ])
    return bar
  }

  /// A BottomNavigation's destinations, their glyphs drawn from the icon font.
  private func navItems(_ node: [String: Any]) -> [DnnNavItem] {
    var items: [DnnNavItem] = []
    for raw in node["items"] as? [Any] ?? [] {
      guard let item = raw as? [String: Any] else { continue }
      items.append(
        DnnNavItem(
          label: item["label"] as? String ?? "",
          icon: iconImage(item["icon"], size: 24),
          selectedIcon: iconImage(item["selectedIcon"], size: 24)))
    }
    return items
  }

  /// What a tap on a destination sends.
  private func navHandler(_ node: [String: Any]) -> (Int) -> Void {
    let eventId = node["eventId"] as? String
    let payload = node["data"] as? [String: Any] ?? [:]
    return { [weak self] index in
      guard let eventId else { return }
      var data = payload
      data["index"] = index
      self?.send(eventId: eventId, data: data)
    }
  }

  /**
   The destinations of an app, one selected: a tab bar, which is how iOS draws
   them, or the same destinations down the leading edge when the tree asks for
   a rail.

   The selection is the app's: a tap reports the index and the next tree says
   which destination is selected.
   */
  private func renderBottomNavigation(_ node: [String: Any]) -> UIView {
    let items = navItems(node)
    let selected = Int(number(node["selectedIndex"]) ?? 0)
    let tint = color(themePrimary, fallback: themePrimary)
    let idle = color(themeTextSecondary, fallback: themeTextSecondary)

    if node["rail"] as? Bool == true {
      let rail = DnnRailView()
      rail.configure(items: items, tint: tint, idle: idle, background: surfaceColor())
      rail.selectIndex(selected)
      rail.onSelect = navHandler(node)
      return rail
    }

    let bar = DnnTabBar()
    var tabs: [UITabBarItem] = []
    for (index, item) in items.enumerated() {
      let tab = UITabBarItem(
        title: item.label, image: item.icon, selectedImage: item.selectedIcon ?? item.icon)
      tab.tag = index
      tabs.append(tab)
    }
    bar.items = tabs
    bar.tintColor = tint
    bar.unselectedItemTintColor = idle
    bar.barTintColor = surfaceColor()
    bar.isTranslucent = false
    bar.selectIndex(selected)
    bar.onSelect = navHandler(node)
    return bar
  }

  private func patchBottomNavigation(
    _ view: UIView, _ oldNode: [String: Any], _ newNode: [String: Any]
  ) -> Bool {
    // Different destinations are a different bar; only the selection moves in
    // place, which is what a tap changes.
    for key in ["items", "rail"] where !valueEqual(oldNode[key], newNode[key]) {
      return false
    }
    let selected = Int(number(newNode["selectedIndex"]) ?? 0)
    if let rail = view as? DnnRailView {
      rail.selectIndex(selected)
      rail.onSelect = navHandler(newNode)
      return true
    }
    if let bar = view as? DnnTabBar {
      bar.selectIndex(selected)
      bar.onSelect = navHandler(newNode)
      return true
    }
    return false
  }

  // MARK: - FlutterSlot

  /**
   A region the Flutter view underneath paints.

   The renderer's container sits *over* the Flutter view, so the slot draws
   nothing: it only takes up the room the tree gives it. `updateSlotRects` cuts
   a hole in the container where it is, and tells Dart where that is, so the
   Flutter side can paint the widget registered under `slotId` into the same
   rectangle. The node's child is the fallback for renderers with no Flutter
   engine, and is not drawn here.
   */
  private func renderFlutterSlot(_ node: [String: Any]) -> UIView {
    let slot = DnnFlutterSlotView()
    slot.slotId = node["slotId"] as? String ?? ""
    slot.setSize(width: finite(node["width"]), height: finite(node["height"]) ?? 0)
    slot.onMoved = { [weak self] in self?.updateSlotRects() }
    return slot
  }

  private func patchFlutterSlot(_ view: UIView, _ node: [String: Any]) -> Bool {
    guard let slot = view as? DnnFlutterSlotView,
      slot.slotId == node["slotId"] as? String ?? ""
    else { return false }
    slot.setSize(width: finite(node["width"]), height: finite(node["height"]) ?? 0)
    return true
  }

  /// What every render ends with: the slots found again, and the viewport
  /// re-read in case the appearance changed under it.
  private func finishRender(_ tree: [String: Any]) {
    // The bar under a snackbar may have changed without the snackbar's own
    // layer being laid out again.
    snackbarHost?.setNeedsLayout()
    refreshSlots(tree)
    sendViewport()
  }

  private func collectSlots(_ view: UIView, into slots: inout [DnnFlutterSlotView]) {
    for subview in view.subviews {
      if let slot = subview as? DnnFlutterSlotView {
        slots.append(slot)
      } else {
        collectSlots(subview, into: &slots)
      }
    }
  }

  /// Whether [node]'s tree holds an overlay that covers the screen.
  private func hasModal(_ node: [String: Any]) -> Bool {
    let type = node["type"] as? String ?? ""
    if ["Dialog", "BottomSheet", "DatePicker", "TimePicker"].contains(type) { return true }
    for child in childNodes(node) where hasModal(child) { return true }
    return false
  }

  /// Finds the slots the render left on screen. A tree with none costs one
  /// walk of the views and nothing else.
  private func refreshSlots(_ tree: [String: Any]) {
    guard let container = rootContainer else { return }
    var found: [DnnFlutterSlotView] = []
    collectSlots(container, into: &found)
    if found.isEmpty && slotViews.isEmpty && slotReports.isEmpty { return }
    slotViews = found
    // A dialog or a sheet is drawn above the slot, so there is nothing to
    // show through it while one is up.
    slotsCovered = !found.isEmpty && hasModal(tree)
    // The render changed constraints; the frames follow at the next layout
    // pass, and the rectangles are read from the frames.
    container.layoutIfNeeded()
    updateSlotRects()
  }

  /// Re-reads the slots after a layout the renderer did not cause - a
  /// rotation, the keyboard - once that layout has reached them.
  private func scheduleSlotUpdate() {
    guard !slotViews.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in
      self?.updateSlotRects()
    }
  }

  /// The part of [slot] that is actually visible, in [container]'s own
  /// coordinates: cut by every clipping view above it, so a slot scrolled half
  /// under an app bar opens a hole only where it shows.
  private func visibleRect(of slot: UIView, in container: UIView) -> CGRect {
    var rect = slot.bounds
    var current: UIView = slot
    while current !== container, let parent = current.superview {
      rect = parent.convert(rect, from: current)
      if parent.clipsToBounds || parent === container {
        rect = rect.intersection(parent.bounds)
      }
      if rect.isNull { return rect }
      current = parent
    }
    return rect
  }

  /**
   Opens a hole in the container over each visible slot, and sends
   `dnn:slotRect` for each slot whose rectangle changed since it was last sent.

   The rectangle is in points from the Flutter view's top-left corner - the
   whole slot, even where it is scrolled out of sight, because that is where
   Flutter has to paint; the hole is only the part that shows. `visible` is
   false for a slot with no window, no size, or nothing showing.
   */
  private func updateSlotRects() {
    guard let container = rootContainer, let host = controller.view else { return }
    var holes: [CGRect] = []
    var seen = Set<String>()
    for slot in slotViews {
      seen.insert(slot.slotId)
      var rect = CGRect.zero
      var visible = false
      if slot.window != nil, slot.isDescendant(of: container) {
        rect = slot.convert(slot.bounds, to: host)
        let showing = visibleRect(of: slot, in: container)
        if !showing.isNull, showing.width > 0, showing.height > 0 {
          visible = true
          holes.append(showing)
        }
      }
      reportSlot(slot.slotId, rect, visible: visible)
    }
    // A slot the tree no longer holds is told so once.
    for slotId in slotReports.keys.filter({ !seen.contains($0) }) {
      slotReports[slotId] = nil
      send(
        eventId: "dnn:slotRect",
        data: [
          "slotId": slotId, "x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0,
          "visible": false,
        ])
    }
    container.setHoles(slotsCovered ? [] : holes)
  }

  private func reportSlot(_ slotId: String, _ rect: CGRect, visible: Bool) {
    // Half a point is below anything a layout means, and above the noise a
    // scroll's deceleration makes.
    func snap(_ value: CGFloat) -> Double { Double((value * 2).rounded() / 2) }
    let x = snap(rect.minX)
    let y = snap(rect.minY)
    let width = snap(rect.width)
    let height = snap(rect.height)
    let signature = "\(x),\(y),\(width),\(height),\(visible)"
    if slotReports[slotId] == signature { return }
    slotReports[slotId] = signature
    send(
      eventId: "dnn:slotRect",
      data: [
        "slotId": slotId, "x": x, "y": y, "width": width, "height": height,
        "visible": visible,
      ])
  }

  // MARK: - Events

  /// Hears when a map settles, so the app is told where it ended up rather
  /// than where it passed through.
  private lazy var mapDelegate: MapDelegate = {
    let delegate = MapDelegate()
    delegate.onIdle = { [weak self] map, node in
      guard let self, let eventId = node["eventId"] as? String else { return }
      // The same arithmetic backwards: how many map points one pixel covers
      // says which slippy zoom the map is at.
      let width = max(Double(map.bounds.size.width), 1)
      let pointsPerPixel = map.visibleMapRect.size.width / width
      self.send(
        eventId: "\(eventId)_idle",
        data: [
          "latitude": map.region.center.latitude,
          "longitude": map.region.center.longitude,
          "zoom": pointsPerPixel > 0
            ? log2(MKMapSize.world.width / (256 * pointsPerPixel))
            : 13,
        ]
            )
    }
    return delegate
  }()

  private lazy var textFieldDelegate: TextFieldDelegate = {
    let delegate = TextFieldDelegate()
    delegate.onNext = { [weak self] field in self?.focusFieldAfter(field) ?? false }
    delegate.nodeFor = { [weak self] field in self?.bindings[field.hash] }
    delegate.onTap = { [weak self] field in
      // The renderer putting the focus back after a rebuild is not a tap.
      guard let self, !self.restoringFocus,
        let eventId = self.bindings[field.hash]?["eventId"] as? String
      else { return }
      self.send(eventId: "\(eventId)_tap", data: [:])
    }
    return delegate
  }()

  private func bindTap(_ button: UIButton, _ node: [String: Any]) {
    guard node["eventId"] is String else { return }
    bindings[button.hash] = node
    button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
  }

  @objc private func buttonTapped(_ sender: UIButton) {
    send(bindings[sender.hash], extra: [:])
  }

  @objc private func checkboxTapped(_ sender: UIButton) {
    guard let node = bindings[sender.hash] else { return }
    let checked = !(node["checked"] as? Bool ?? false)
    send(node, extra: ["checked": checked])
  }

  @objc private func radioTapped(_ sender: UIButton) {
    guard let node = bindings[sender.hash] else { return }
    send(node, extra: ["value": node["value"] ?? ""])
  }

  @objc private func toggleChanged(_ sender: UISwitch) {
    send(bindings[sender.hash], extra: ["enabled": sender.isOn])
  }

  @objc private func tabChanged(_ sender: UISegmentedControl) {
    send(bindings[sender.hash], extra: ["index": sender.selectedSegmentIndex])
  }

  @objc private func sliderChanged(_ sender: UISlider) {
    guard let node = bindings[sender.hash] else { return }
    let snapped = sliderSnap(node, sender.value)
    if snapped != sender.value { sender.value = snapped }
    sendSuffixed(node, suffix: "change", value: snapped)
  }

  @objc private func sliderReleased(_ sender: UISlider) {
    guard let node = bindings[sender.hash] else { return }
    sendSuffixed(node, suffix: "end", value: sliderSnap(node, sender.value))
  }

  /// Sends `<eventId>_<suffix>` with the node's payload and a value.
  private func sendSuffixed(_ node: [String: Any], suffix: String, value: Float) {
    guard let eventId = node["eventId"] as? String else { return }
    var data = node["data"] as? [String: Any] ?? [:]
    data["value"] = Double(value)
    send(eventId: "\(eventId)_\(suffix)", data: data)
  }

  @objc private func textChanged(_ sender: UITextField) {
    sendFieldEvent(sender, suffix: "change")
  }

  @objc private func fieldSuffixTapped(_ sender: UIButton) {
    guard let eventId = bindings[sender.hash]?["eventId"] as? String else { return }
    send(eventId: "\(eventId)_suffix", data: [:])
  }

  @objc private func editingBegan(_ sender: UITextField) {
    sendFieldEvent(sender, suffix: "focus")
  }

  @objc private func editingEnded(_ sender: UITextField) {
    sendFieldEvent(sender, suffix: "blur")
  }

  @objc private func editingSubmitted(_ sender: UITextField) {
    sendFieldEvent(sender, suffix: "submit")
  }

  /**
   Moves the keyboard to the text field after [field] in the rendered tree.

   UIKit has no focus traversal to lean on - `nextFocusedView` is for hardware
   keyboards and focus engines, not for a return key - so the order comes from
   the view hierarchy itself, walked depth first. That is the order the fields
   were declared in, which is what an app means by "next" without having to
   name the field. A disabled field is stepped over, and the last field has
   nowhere to go, where the keyboard closing is the right thing anyway.
   */
  @discardableResult
  private func focusFieldAfter(_ field: UITextField) -> Bool {
    guard let container = rootContainer else { return false }
    var fields: [UITextField] = []
    collectTextFields(container, into: &fields)
    guard let index = fields.firstIndex(of: field) else { return false }
    for candidate in fields[(index + 1)...] where candidate.isEnabled {
      // The app still hears the submit; it just does not hear a blur, because
      // the keyboard never left.
      sendFieldEvent(field, suffix: "submit")
      return candidate.becomeFirstResponder()
    }
    return false
  }

  private func collectTextFields(_ view: UIView, into fields: inout [UITextField]) {
    for subview in view.subviews {
      if let field = subview as? UITextField { fields.append(field) }
      collectTextFields(subview, into: &fields)
    }
  }

  private func sendFieldEvent(_ field: UITextField, suffix: String) {
    // A focus or blur the renderer itself caused while rebuilding is not a user
    // action; the value keeps flowing, only the churn is hidden.
    if restoringFocus, suffix == "focus" || suffix == "blur" { return }
    guard
      let node = bindings[field.hash],
      let eventId = node["eventId"] as? String
    else { return }
    send(eventId: "\(eventId)_\(suffix)", data: ["value": field.text ?? ""])
  }

  /// Sends the node's own event, its payload merged with [extra].
  private func send(_ node: [String: Any]?, extra: [String: Any]) {
    guard let node, let eventId = node["eventId"] as? String else { return }
    var data = node["data"] as? [String: Any] ?? [:]
    data.merge(extra) { _, new in new }
    send(eventId: eventId, data: data)
  }

  /**
   Hands one event to Dart.

   Dart owns every handler - the native side only reports what happened - so
   this is the whole of the return path.
   */
  private func send(eventId: String, data: [String: Any]) {
    // `build` names the tree the views are showing. An id allocated by order
    // means something else after a rebuild that allocated a different number
    // before it, and Dart may have built several times since this tree was
    // sent. Left out when Dart gave none, which Dart reads as "the latest".
    var arguments: [String: Any] = ["eventId": eventId, "data": data]
    if let treeBuild { arguments["build"] = treeBuild }
    methodChannel?.invokeMethod(NativeUIRenderer.eventMethod, arguments: arguments)
  }

  /// The number Dart gave the tree being shown; nil if it gave none.
  private var treeBuild: Int?

  /// The bottom bar and floating button of the scaffold last drawn, and the
  /// snackbar layer that keeps clear of them.
  private weak var scaffoldBottomBar: UIView?
  private weak var scaffoldFab: UIView?
  private weak var snackbarHost: SnackbarHost?

  // MARK: - Helpers

  /**
   The tree as this file reads it: each node's props lifted onto the node.

   Dart sends `{type, props: {...}, children}`, and everything here reads a prop
   straight off the node (`node["title"]`), so the whole tree is flattened once
   per render. The node's own `type` and `children` win over any prop of the
   same name, and the props stay under `props` too: Loading and Alert have a
   prop called `type`, read through `prop(_:_:)`.
   */
  private func normalized(_ node: [String: Any]) -> [String: Any] {
    let props = node["props"] as? [String: Any] ?? [:]
    var flat = props
    flat["type"] = node["type"]
    flat["props"] = props
    flat["children"] = childNodes(node).map { normalized($0) }
    return flat
  }

  /// A prop as the app set it, for names the node itself also uses.
  private func prop(_ node: [String: Any], _ name: String) -> Any? {
    (node["props"] as? [String: Any])?[name]
  }

  private func childNodes(_ node: [String: Any]) -> [[String: Any]] {
    (node["children"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
  }

  private func firstChild(_ node: [String: Any]) -> [String: Any]? {
    childNodes(node).first
  }

  /// Adds `view` to `container`, filling it.
  private func pin(_ view: UIView, to container: UIView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
  }

  private func addArranged(_ stack: UIStackView, _ node: [String: Any]) {
    for child in childNodes(node) {
      guard let view = renderWidget(child) else { continue }
      stack.addArrangedSubview(view)
      takeWidthOffered(view, child, in: stack)
    }
  }

  /// Lets [view], just arranged in [stack] as [child], be as wide as the
  /// stack when it is something that takes the width it is offered.
  ///
  /// A column that aligns its children at one edge hands each of them only
  /// what it asks for, and several things ask for nothing: a slider and a
  /// progress bar have no width of their own, a box that expands has none
  /// until something gives it one, and a row's `mainAxisSize` is max. In
  /// Flutter all of those take the column's width. Here they came out a
  /// thumb with no track, a bar a few points long, and a `Stack` of layers
  /// with no size at all - nothing on screen where the layers should be.
  private func takeWidthOffered(_ view: UIView, _ child: [String: Any], in stack: UIStackView) {
    guard stack.axis == .vertical, stack.alignment != .fill, fillsWidth(child) else { return }
    // A row is as wide as its children until told otherwise, so it is the
    // one that has to ask; that was how a card's row of an email and a
    // button came out email-wide, with the space between them nowhere to go.
    (view as? RowStack)?.takeTheWidthOffered()
    // Below required, so a width the child states for itself still wins.
    let fill = view.widthAnchor.constraint(equalTo: stack.widthAnchor)
    fill.priority = UILayoutPriority(999)
    fill.isActive = true
  }

  /// Whether [node] takes all the width it is offered rather than the width
  /// of what is in it - Flutter's rule for each, and the Kotlin renderer's
  /// `fillsWidth`.
  private func fillsWidth(_ node: [String: Any]) -> Bool {
    switch node["type"] as? String {
    case "Row", "HStack":
      // Unless it said `mainAxisSize: 'min'`: a row as wide as its children.
      return node["mainAxisSize"] as? String != "min"
    case "TextField", "Slider", "Wrap", "Divider":
      return true
    case "Loading":
      return prop(node, "type") as? String == "progress-linear"
    case "Box", "Canvas":
      if let width = number(node["width"]) { return !width.isFinite }
      let expand = node["expand"] as? String
      if expand == "width" || expand == "both" { return true }
      return firstChild(node).map(fillsWidth) ?? false
    case "Padding", "Expanded":
      return firstChild(node).map(fillsWidth) ?? false
    case "Column", "VStack", "Card":
      return childNodes(node).contains(where: fillsWidth)
    case "Stack":
      // A layer that is not pinned is what sizes the stack.
      return childNodes(node).contains {
        $0["type"] as? String != "Positioned" && fillsWidth($0)
      }
    default:
      return false
    }
  }

  private func number(_ value: Any?) -> CGFloat? {
    (value as? NSNumber).map { CGFloat($0.doubleValue) }
  }

  /// The colour text takes over a background the app stated, rather than over
  /// the surface the theme's text colour was chosen against.
  ///
  /// The rule is WCAG's relative luminance, the same one the Dart renderers
  /// apply from `src/contrast.dart` - white over a dark colour, the default
  /// theme's near-black over a light one - so a card the app coloured reads
  /// the same on all four renderers.
  private func textOn(_ background: UIColor) -> UIColor {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    background.getRed(&r, green: &g, blue: &b, alpha: &a)
    let luminance =
      0.2126 * linearChannel(r) + 0.7152 * linearChannel(g) + 0.0722 * linearChannel(b)
    return luminance > 0.179
      ? color(Self.onLight, fallback: Self.onLight)
      : color(Self.onDark, fallback: Self.onDark)
  }

  private func linearChannel(_ value: CGFloat) -> CGFloat {
    value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  /// Parses `#rgb`, `#rrggbb` and `#aarrggbb`.
  private func color(_ value: Any?, fallback: String) -> UIColor {
    UIColor(hex: value as? String ?? "") ?? UIColor(hex: fallback) ?? .systemBlue
  }
}

/// A label with room around its text, for badges.
private class PaddedLabel: UILabel {
  private let insets: UIEdgeInsets

  init(insets: UIEdgeInsets) {
    self.insets = insets
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    insets = .zero
    super.init(coder: coder)
  }

  override func drawText(in rect: CGRect) {
    super.drawText(in: rect.inset(by: insets))
  }

  override var intrinsicContentSize: CGSize {
    let size = super.intrinsicContentSize
    return CGSize(
      width: size.width + insets.left + insets.right,
      height: size.height + insets.top + insets.bottom
    )
  }
}

/// Handles the return key: dismiss, or move to the next field.
///
/// Dismissing is the default, and resigning here is what fires
/// `editingDidEndOnExit` and so the field's submit event. A field asking to
/// advance is handled by [onNext] instead - which sends the submit itself,
/// since it never resigns and so never triggers that event.
private class TextFieldDelegate: NSObject, UITextFieldDelegate {
  /// Moves to the next field, answering whether there was one.
  var onNext: ((UITextField) -> Bool)?

  /// The node a field was built from, for what it says about typing.
  var nodeFor: ((UITextField) -> [String: Any]?)?

  /// A field that asked to hear about it was tapped.
  var onTap: ((UITextField) -> Void)?

  /// A tap on a field is the field about to take the keyboard. A `tappable`
  /// one reports it, and a `readOnly` one stops there: it shows its value and
  /// opens whatever the app opens, without a keyboard coming up over it.
  func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
    guard let node = nodeFor?(textField) else { return true }
    if node["tappable"] as? Bool == true { onTap?(textField) }
    return !(node["readOnly"] as? Bool ?? false)
  }

  /// Refuses typing into a read-only field, and past a field's `maxLength`.
  func textField(
    _ textField: UITextField, shouldChangeCharactersIn range: NSRange,
    replacementString string: String
  ) -> Bool {
    guard let node = nodeFor?(textField) else { return true }
    if node["readOnly"] as? Bool == true { return false }
    guard let limit = (node["maxLength"] as? NSNumber)?.intValue, limit > 0 else {
      return true
    }
    let current = (textField.text ?? "") as NSString
    guard range.location + range.length <= current.length else { return true }
    let next = current.replacingCharacters(in: range, with: string)
    // Deleting is always allowed, so a value already too long can be fixed.
    return next.count <= limit || next.count <= (textField.text ?? "").count
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField.returnKeyType == .next, onNext?(textField) == true {
      // Handled: the caret is in the next field and the keyboard stayed up.
      return false
    }
    textField.resignFirstResponder()
    return true
  }
}

/// Holds a web view at the width of whatever holds *it*.
///
/// A `WKWebView` has no intrinsic width, and a Column centres its children
/// unless told otherwise - which gives an arranged subview its intrinsic size.
/// The result is a view that loads the page perfectly and is zero points wide,
/// so nothing appears and nothing reports an error. Taking the superview's
/// width is what makes an embedded page visible by default.
private class WebViewFrame: UIView {
  private var pinned: NSLayoutConstraint?

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    pinned?.isActive = false
    guard let superview else { return }
    pinned = widthAnchor.constraint(equalTo: superview.widthAnchor)
    pinned?.isActive = true
  }
}

/// A view that takes no touches itself, only those landing on its subviews -
/// so a snackbar blocks nothing but its own bar.
private class PassthroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

/**
 The layer a snackbar sits in, which keeps it clear of what the scaffold under
 it has at the bottom: Material shows a snackbar above the bottom bar and the
 floating button, never over them.

 The snackbar is drawn beside the scaffold, not inside it, so it cannot be
 constrained to those views; it is moved up by however far it would reach into
 them instead. `below` answers the views to stay above.
 */
private class SnackbarHost: PassthroughView {
  var below: (() -> [UIView])?

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let bar = subviews.first else { return }
    var ceiling = CGFloat.greatestFiniteMagnitude
    for view in below?() ?? [] where view.window != nil && !view.isHidden
      && view.bounds.height > 0
    {
      ceiling = min(ceiling, view.convert(view.bounds, to: self).minY)
    }
    // From the centre and the bounds, which a transform leaves alone.
    let bottom = bar.center.y + bar.bounds.height / 2
    let lift = ceiling == CGFloat.greatestFiniteMagnitude ? 0 : max(0, bottom + 8 - ceiling)
    bar.transform = lift > 0 ? CGAffineTransform(translationX: 0, y: -lift) : .identity
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // Once more when everything beside it has been laid out too.
    DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() }
  }
}

/// A bottom sheet's surface, which keeps its drag recognizer's delegate alive.
private class SheetSurface: UIView {
  var dragDelegate: SheetDragDelegate?
}

/// Lets a sheet's drag begin only downwards, and only while its content is
/// scrolled to the top.
private class SheetDragDelegate: NSObject, UIGestureRecognizerDelegate {
  weak var content: UIScrollView?

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: pan.view)
    return velocity.y > abs(velocity.x) && (content?.contentOffset.y ?? 0) <= 0
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    otherGestureRecognizer.view === content
  }
}

/**
 The scroll view of a `LazyList`.

 Sized for every row, with the rows it has framed at their place in the whole
 list. It calls `onViewportChange` when its size changes and when it scrolls,
 after putting back the offset of the list it replaced.
 */
/// A list row that slides its child left to reveal trailing action buttons: a
/// partial swipe snaps open so a button can be tapped, a full swipe fires the
/// first action. The child is opaque so the actions stay hidden until swiped;
/// the pan begins only on a mostly-horizontal drag so the list still scrolls.
private class SwipeActionsView: UIView, UIGestureRecognizerDelegate {
  struct Action { let label: String; let color: UIColor; let eventId: String }

  /// The layer the row itself lives in; the action bar sits behind it.
  /// Reachable so `childViews` can walk into a swipe row rather than rebuild it.
  let foreground = UIView()
  private let actionWidth: CGFloat = 88
  private let actions: [Action]
  private let leadingActions: [Action]
  private let onFire: (String) -> Void
  /// The resting offset the current drag adds to: 0 closed, negative for the
  /// trailing actions, positive for the leading ones.
  private var offset: CGFloat = 0

  private var openOffset: CGFloat { -actionWidth * CGFloat(actions.count) }
  private var openLeadingOffset: CGFloat {
    actionWidth * CGFloat(leadingActions.count)
  }

  init(
    child: UIView,
    actions: [Action],
    leadingActions: [Action] = [],
    surface: UIColor,
    onFire: @escaping (String) -> Void
  ) {
    self.actions = actions
    self.leadingActions = leadingActions
    self.onFire = onFire
    super.init(frame: .zero)
    clipsToBounds = true

    /// One bar of buttons, pinned to an edge; `tagOffset` keeps the two bars'
    /// button tags apart, since a tap looks the action up by tag.
    func addBar(_ actions: [Action], leading: Bool, tagOffset: Int) {
      guard !actions.isEmpty else { return }
      let bar = UIStackView()
      bar.axis = .horizontal
      bar.distribution = .fillEqually
      bar.translatesAutoresizingMaskIntoConstraints = false
      addSubview(bar)
      NSLayoutConstraint.activate([
        bar.topAnchor.constraint(equalTo: topAnchor),
        bar.bottomAnchor.constraint(equalTo: bottomAnchor),
        leading
          ? bar.leadingAnchor.constraint(equalTo: leadingAnchor)
          : bar.trailingAnchor.constraint(equalTo: trailingAnchor),
        bar.widthAnchor.constraint(
          equalToConstant: actionWidth * CGFloat(actions.count)),
      ])
      for (index, action) in actions.enumerated() {
        let button = UIButton(type: .system)
        button.setTitle(action.label, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = action.color
        button.tag = tagOffset + index
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        bar.addArrangedSubview(button)
      }
    }

    addBar(leadingActions, leading: true, tagOffset: 1000)
    addBar(actions, leading: false, tagOffset: 0)

    foreground.backgroundColor = surface
    foreground.translatesAutoresizingMaskIntoConstraints = false
    addSubview(foreground)
    child.translatesAutoresizingMaskIntoConstraints = false
    foreground.addSubview(child)
    NSLayoutConstraint.activate([
      foreground.topAnchor.constraint(equalTo: topAnchor),
      foreground.bottomAnchor.constraint(equalTo: bottomAnchor),
      foreground.leadingAnchor.constraint(equalTo: leadingAnchor),
      foreground.trailingAnchor.constraint(equalTo: trailingAnchor),
      child.topAnchor.constraint(equalTo: foreground.topAnchor),
      child.bottomAnchor.constraint(equalTo: foreground.bottomAnchor),
      child.leadingAnchor.constraint(equalTo: foreground.leadingAnchor),
      child.trailingAnchor.constraint(equalTo: foreground.trailingAnchor),
    ])

    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    pan.delegate = self
    foreground.addGestureRecognizer(pan)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// 1, or -1 when the row reads right to left.
  ///
  /// The offsets here are counted towards the *end* of the row: negative
  /// uncovers the trailing actions. The bars are pinned by leading and
  /// trailing anchors and so change sides with the reading direction; the
  /// finger and the transform are in screen coordinates and have to be turned
  /// to match, or a swipe would slide the row over the bar it meant to show.
  private var directionSign: CGFloat {
    effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: self).x * directionSign
    let next = min(
      max(offset + translation, openOffset * 1.8),
      openLeadingOffset * 1.8)
    switch gesture.state {
    case .changed:
      foreground.transform = CGAffineTransform(translationX: next * directionSign, y: 0)
    case .ended, .cancelled:
      if next <= openOffset * 1.6, let first = actions.first {
        onFire(first.eventId)
        settle(to: 0)
      } else if next >= openLeadingOffset * 1.6, let first = leadingActions.first {
        onFire(first.eventId)
        settle(to: 0)
      } else if next <= openOffset / 2 {
        settle(to: openOffset)
      } else if openLeadingOffset > 0, next >= openLeadingOffset / 2 {
        settle(to: openLeadingOffset)
      } else {
        settle(to: 0)
      }
    default:
      break
    }
  }

  private func settle(to value: CGFloat) {
    offset = value
    let sign = directionSign
    UIView.animate(withDuration: 0.2) {
      self.foreground.transform = CGAffineTransform(translationX: value * sign, y: 0)
    }
  }

  @objc private func actionTapped(_ sender: UIButton) {
    let leading = sender.tag >= 1000
    let list = leading ? leadingActions : actions
    let index = leading ? sender.tag - 1000 : sender.tag
    guard index < list.count else { return }
    onFire(list[index].eventId)
    settle(to: 0)
  }

  // Begin only when the drag is mostly horizontal, so a vertical drag still
  // scrolls the list. Overrides UIView's own gestureRecognizerShouldBegin.
  override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    guard let pan = gesture as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: self)
    return abs(velocity.x) > abs(velocity.y)
  }

  func gestureRecognizer(
    _ gesture: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

private class LazyListView: UIScrollView {
  var itemCount = 0
  var itemExtent: CGFloat = 48
  var startIndex = 0
  var rows: [UIView] = []

  /// The heights of the rows in the window, when they differ from each other,
  /// with where the window starts and how tall the whole list is. Empty for a
  /// list whose rows are all `itemExtent` tall, which is arithmetic instead.
  var rowExtents: [CGFloat] = []
  var startOffset: CGFloat = 0
  var totalExtent: CGFloat = 0

  /// The offset to scroll to once laid out; nil after that.
  var restoreOffset: CGFloat?
  var onViewportChange: (() -> Void)?

  /// The scroll view holds its delegate weakly, so the list keeps it.
  private let scrollDelegate = LazyListScrollDelegate()
  private var framedWidth: CGFloat = -1
  private var reportedSize: CGSize = .zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    // The range arithmetic assumes no inset.
    contentInsetAdjustmentBehavior = .never
    alwaysBounceVertical = true
    delegate = scrollDelegate
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    contentInsetAdjustmentBehavior = .never
    delegate = scrollDelegate
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let width = bounds.width
    let height = rowExtents.isEmpty ? CGFloat(itemCount) * itemExtent : totalExtent
    if contentSize.width != width || contentSize.height != height {
      contentSize = CGSize(width: width, height: height)
    }
    if width != framedWidth {
      framedWidth = width
      frameRows(width: width)
    }

    guard bounds.height > 0 else { return }
    if let restore = restoreOffset {
      restoreOffset = nil
      contentOffset = CGPoint(x: 0, y: min(restore, max(0, height - bounds.height)))
    }
    if bounds.size != reportedSize {
      reportedSize = bounds.size
      onViewportChange?()
    }
  }

  /// Puts every row the list is holding where it belongs in the whole list.
  private func frameRows(width: CGFloat) {
    var top = startOffset
    for (offset, row) in rows.enumerated() {
      let height = rowExtents.isEmpty
        ? itemExtent
        : (offset < rowExtents.count ? rowExtents[offset] : 0)
      let y = rowExtents.isEmpty
        ? CGFloat(startIndex + offset) * itemExtent
        : top
      row.frame = CGRect(x: 0, y: y, width: width, height: height)
      top += height
    }
  }

  /// Replaces the window a reconcile produced and forces a re-frame, since the
  /// rows and their start index changed while the width did not.
  func setWindow(
    rows newRows: [UIView],
    startIndex: Int,
    itemCount: Int,
    itemExtent: CGFloat,
    rowExtents: [CGFloat] = [],
    startOffset: CGFloat = 0,
    totalExtent: CGFloat = 0
  ) {
    self.rows = newRows
    self.startIndex = startIndex
    self.itemCount = itemCount
    self.itemExtent = itemExtent
    self.rowExtents = rowExtents
    self.startOffset = startOffset
    self.totalExtent = totalExtent
    framedWidth = -1
    setNeedsLayout()
  }
}

private class LazyListScrollDelegate: NSObject, UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    (scrollView as? LazyListView)?.onViewportChange?()
  }
}

private extension UIView {
  /// The text field editing within this subtree, if any.
  func firstResponderTextField() -> UITextField? {
    if let field = self as? UITextField, field.isFirstResponder { return field }
    for sub in subviews {
      if let found = sub.firstResponderTextField() { return found }
    }
    return nil
  }

  /// The text field carrying [identifier] in this subtree, if any.
  func textField(withIdentifier identifier: String) -> UITextField? {
    if let field = self as? UITextField, field.accessibilityIdentifier == identifier {
      return field
    }
    for sub in subviews {
      if let found = sub.textField(withIdentifier: identifier) { return found }
    }
    return nil
  }
}

private extension UIColor {
  /// Parses `#rgb`, `#rrggbb` and `#aarrggbb`.
  convenience init?(hex: String) {
    guard hex.hasPrefix("#") else { return nil }
    var digits = String(hex.dropFirst())
    if digits.count == 3 {
      digits = digits.map { "\($0)\($0)" }.joined()
    }
    if digits.count == 6 {
      digits = "ff" + digits
    }
    guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }

    self.init(
      red: CGFloat((value >> 16) & 0xff) / 255,
      green: CGFloat((value >> 8) & 0xff) / 255,
      blue: CGFloat(value & 0xff) / 255,
      alpha: CGFloat((value >> 24) & 0xff) / 255
    )
  }
}

/// Lays its subviews out from the start of the line to its end - left to
/// right, or right to left when the view has been told the screen reads that
/// way - wrapping onto the next line when the
/// current one runs out of width, and sizes itself to the height that takes.
/// UIKit has no wrapping stack, so a Wrap node is drawn with one of these.
/// Equal cells in `columns` columns, each `aspectRatio` wide over tall.
///
/// A grid is not a flow: every cell is one size, and that size comes from the
/// width available rather than from what is inside it.
/// The view behind an `AnimatedContainer`: a plain box that remembers the
/// constraints holding its stated size, so a patch can move them.
/// A stack's flexible spacer: the view that takes up the slack when a row or
/// column aligns its children at the center or the end. It is a type of its
/// own so the reconciler can tell it apart from a child - see
/// `flexibleSpacer(axis:)`.
private final class FlexibleSpacer: UIView {}

/// What an `Image` node's fallback child is drawn in. A type of its own so the
/// reconciler can find the child's view, and so the loader knows which
/// constraints to let go of when the picture arrives - see `renderImage`.
private final class ImageFallbackHost: UIView {
  var holds: [NSLayoutConstraint] = []
}

/// A row, which can be asked to take all the width it is offered.
///
/// Two constraints say that: a width it cannot have, at a priority anything
/// can beat, so it grows until something stops it - and, once it is on screen,
/// a cap at the window's width, because a `Center` hands its child whatever it
/// asks for and would otherwise let the row put its children thousands of
/// points off screen. The cap waits for the window because a constraint
/// between two views needs them both in the same hierarchy, and a row is built
/// before it is added to one.
private final class RowStack: UIStackView {
  private var wantsFullWidth = false
  private var cap: NSLayoutConstraint?

  func takeTheWidthOffered() {
    guard !wantsFullWidth else { return }
    wantsFullWidth = true
    let wide = widthAnchor.constraint(equalToConstant: 10_000)
    wide.priority = UILayoutPriority(200)
    wide.isActive = true
    applyCap()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    applyCap()
  }

  private func applyCap() {
    guard wantsFullWidth, cap == nil, let window = window else { return }
    let capped = widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor)
    capped.isActive = true
    cap = capped
  }
}

/// The label under a text field that shows why it is refusing. It is a type of
/// its own so a patch can find it without counting subviews - see
/// `applyFieldError`.
private final class TextFieldErrorLabel: UILabel {}

/// The label under a text field that says what it is for, found by its type
/// for the same reason - see `applyFieldHelper`.
private final class TextFieldHelperLabel: UILabel {}

private final class AnimatedBoxView: UIView {
  private var widthConstraint: NSLayoutConstraint?
  private var heightConstraint: NSLayoutConstraint?

  /// Sets or clears the stated width and height. Changing a constant animates
  /// with whatever block the caller is inside; adding or removing a constraint
  /// changes what the box is measured from, and lands at once.
  func setSize(width: CGFloat?, height: CGFloat?) {
    widthConstraint = apply(width, to: widthConstraint, anchor: widthAnchor)
    heightConstraint = apply(height, to: heightConstraint, anchor: heightAnchor)
  }

  private func apply(
    _ value: CGFloat?,
    to constraint: NSLayoutConstraint?,
    anchor: NSLayoutDimension
  ) -> NSLayoutConstraint? {
    guard let value = value else {
      constraint?.isActive = false
      return nil
    }
    if let constraint = constraint {
      constraint.constant = value
      return constraint
    }
    let created = anchor.constraint(equalToConstant: value)
    created.isActive = true
    return created
  }
}

private final class GridView: UIView {
  private let columns: Int
  private let hSpacing: CGFloat
  private let vSpacing: CGFloat
  private let aspectRatio: CGFloat
  private var heightConstraint: NSLayoutConstraint?

  init(columns: Int, hSpacing: CGFloat, vSpacing: CGFloat, aspectRatio: CGFloat) {
    self.columns = max(columns, 1)
    self.hSpacing = hSpacing
    self.vSpacing = vSpacing
    self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    // Fill the parent's width; the height follows from the rows below.
    guard let superview = superview else { return }
    translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalTo: superview.widthAnchor).isActive = true
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let width = bounds.width
    guard width > 0 else { return }
    let cellWidth =
      (width - hSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    let cellHeight = cellWidth / aspectRatio
    let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
    for (index, sub) in subviews.enumerated() {
      let column = index % columns
      let row = index / columns
      // The first cell of a row is at the start of it, which is the right
      // when the screen reads right to left.
      let fromStart = CGFloat(column) * (cellWidth + hSpacing)
      sub.frame = CGRect(
        x: rtl ? width - fromStart - cellWidth : fromStart,
        y: CGFloat(row) * (cellHeight + vSpacing),
        width: cellWidth,
        height: cellHeight
      )
    }
    let rows = (subviews.count + columns - 1) / columns
    let total =
      rows == 0 ? 0 : CGFloat(rows) * cellHeight + CGFloat(rows - 1) * vSpacing
    if let constraint = heightConstraint {
      if abs(constraint.constant - total) > 0.5 { constraint.constant = total }
    } else {
      let constraint = heightAnchor.constraint(equalToConstant: total)
      constraint.isActive = true
      heightConstraint = constraint
    }
  }
}

/// A view that shows what the camera sees.
///
/// Owns its capture session: started when there is a window to show it in and
/// stopped when there is not, so a screen that is no longer on top is not
/// quietly holding the camera open.
private final class CameraPreviewView: UIView {
  var onStatus: ((String, String?) -> Void)?

  private let session = AVCaptureSession()
  private var layerAdded = false
  private var facing = "back"
  private var active = true
  private var configured = false

  /// Configuring and running a session blocks; neither belongs on the thread
  /// that is drawing.
  private let queue = DispatchQueue(label: "dnn.camera")

  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

  private var previewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }

  func apply(facing: String, active: Bool) {
    let facingChanged = facing != self.facing
    self.facing = facing
    self.active = active
    if facingChanged { configured = false }
    updateRunning()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateRunning()
  }

  deinit {
    let session = self.session
    DispatchQueue.global(qos: .utility).async { session.stopRunning() }
  }

  private func updateRunning() {
    guard window != nil, active else {
      queue.async { [session] in
        if session.isRunning { session.stopRunning() }
      }
      return
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      start()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.start()
          } else {
            self.onStatus?("denied", "The camera permission was refused.")
          }
        }
      }
    default:
      onStatus?("denied", "The camera permission was refused.")
    }
  }

  private func start() {
    if !layerAdded {
      previewLayer.videoGravity = .resizeAspectFill
      previewLayer.session = session
      layerAdded = true
    }
    queue.async { [weak self] in
      guard let self else { return }
      if !self.configured {
        guard self.configure() else { return }
        self.configured = true
      }
      if !self.session.isRunning { self.session.startRunning() }
      DispatchQueue.main.async { self.onStatus?("ready", nil) }
    }
  }

  /// Picks the camera and wires it to the session. False when the device has
  /// none - a simulator, or a Mac without one - which is a thing to report
  /// rather than a blank rectangle.
  private func configure() -> Bool {
    session.beginConfiguration()
    for input in session.inputs { session.removeInput(input) }
    let position: AVCaptureDevice.Position = facing == "front" ? .front : .back
    let device =
      AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: position)
      ?? AVCaptureDevice.default(for: .video)
    guard let device, let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      session.commitConfiguration()
      DispatchQueue.main.async { [weak self] in
        self?.onStatus?("unavailable", "This device has no camera.")
      }
      return false
    }
    session.addInput(input)
    // The preview only needs what fits the view; a full-resolution stream is
    // heat and battery for pixels nobody sees.
    session.sessionPreset = .high
    session.commitConfiguration()
    return true
  }
}

/// Reports where a map came to rest.
///
/// Only when it settles: a position per frame would re-render the whole tree
/// per frame, which is the thing a map must not do.
private final class MapDelegate: NSObject, MKMapViewDelegate {
  var onIdle: ((MKMapView, [String: Any]) -> Void)?
  var nodes: [ObjectIdentifier: [String: Any]] = [:]

  /// True while the renderer itself is moving the map, so applying the tree's
  /// own centre is not reported back as if a finger had done it.
  var applying = false

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    guard !applying, let node = nodes[ObjectIdentifier(mapView)] else { return }
    onIdle?(mapView, node)
  }
}

private final class FlowView: UIView {
  private let hSpacing: CGFloat
  private let vSpacing: CGFloat
  private var heightConstraint: NSLayoutConstraint?

  /// Where the children sit along each line: 'start', 'center', 'end' or
  /// 'spaceBetween'.
  var alignment = "start"
  /// Where a child shorter than its line sits across it: 'start', 'center' or
  /// 'end'.
  var crossAlignment = "start"

  init(hSpacing: CGFloat, vSpacing: CGFloat) {
    self.hSpacing = hSpacing
    self.vSpacing = vSpacing
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    // Fill the parent's width so there is a line to wrap within; the height is
    // driven by layoutSubviews below.
    guard let superview = superview else { return }
    translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalTo: superview.widthAnchor).isActive = true
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let maxWidth = bounds.width
    guard maxWidth > 0 else { return }
    let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft

    // Which children share a line comes first; where each sits on its line
    // needs the whole line.
    var lines: [[UIView]] = [[]]
    var sizes: [[CGSize]] = [[]]
    var x: CGFloat = 0
    for sub in subviews {
      let size = sub.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
      if x > 0, x + size.width > maxWidth {
        lines.append([])
        sizes.append([])
        x = 0
      }
      lines[lines.count - 1].append(sub)
      sizes[sizes.count - 1].append(size)
      x += size.width + hSpacing
    }

    var y: CGFloat = 0
    var total: CGFloat = 0
    for (index, line) in lines.enumerated() where !line.isEmpty {
      let lineSizes = sizes[index]
      var lineWidth = hSpacing * CGFloat(line.count - 1)
      var lineHeight: CGFloat = 0
      for size in lineSizes {
        lineWidth += size.width
        lineHeight = max(lineHeight, size.height)
      }
      let free = max(0, maxWidth - lineWidth)
      var cursor: CGFloat = 0
      var gap = hSpacing
      switch alignment {
      case "center":
        cursor = free / 2
      case "end":
        cursor = free
      case "spaceBetween":
        if line.count > 1 { gap = hSpacing + free / CGFloat(line.count - 1) }
      default:
        break
      }
      for (position, sub) in line.enumerated() {
        let size = lineSizes[position]
        var top = y
        switch crossAlignment {
        case "center":
          top = y + (lineHeight - size.height) / 2
        case "end":
          top = y + lineHeight - size.height
        default:
          break
        }
        // `cursor` counts from the start of the line; the frame wants the
        // distance from the left.
        sub.frame = CGRect(
          x: rtl ? maxWidth - cursor - size.width : cursor,
          y: top, width: size.width, height: size.height)
        cursor += size.width + gap
      }
      total = y + lineHeight
      y += lineHeight + vSpacing
    }

    if let constraint = heightConstraint {
      if abs(constraint.constant - total) > 0.5 { constraint.constant = total }
    } else {
      let constraint = heightAnchor.constraint(equalToConstant: total)
      constraint.isActive = true
      heightConstraint = constraint
    }
  }
}
