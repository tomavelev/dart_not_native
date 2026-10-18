import CoreImage
import UIKit
import UIKit.UIGestureRecognizerSubclass

// The views behind the free-form nodes - Box, Stack, Positioned, Scroll,
// Canvas, Dropdown, the pickers, the bottom navigation, FlutterSlot - and the
// renderer's root container. They live here rather than in
// NativeUIRenderer.swift because none of them needs the renderer: each takes
// plain values and reports through a closure, and the renderer does the
// reading of the tree.

// MARK: - Shared helpers

/// Parses `#rgb`, `#rrggbb` and `#aarrggbb`.
func dnnColor(_ value: Any?) -> UIColor? {
  guard let hex = value as? String, hex.hasPrefix("#") else { return nil }
  var digits = String(hex.dropFirst())
  if digits.count == 3 {
    digits = digits.map { "\($0)\($0)" }.joined()
  }
  if digits.count == 6 {
    digits = "ff" + digits
  }
  guard digits.count == 8, let parsed = UInt32(digits, radix: 16) else { return nil }
  return UIColor(
    red: CGFloat((parsed >> 16) & 0xff) / 255,
    green: CGFloat((parsed >> 8) & 0xff) / 255,
    blue: CGFloat(parsed & 0xff) / 255,
    alpha: CGFloat((parsed >> 24) & 0xff) / 255
  )
}

func dnnNumber(_ value: Any?) -> CGFloat? {
  guard let boxed = value as? NSNumber else { return nil }
  return CGFloat(boxed.doubleValue)
}

/// A CSS weight (100...900) as a UIKit one.
func dnnFontWeight(_ value: CGFloat) -> UIFont.Weight {
  if value >= 850 { return .black }
  if value >= 750 { return .heavy }
  if value >= 650 { return .bold }
  if value >= 550 { return .semibold }
  if value >= 450 { return .medium }
  if value >= 350 { return .regular }
  if value >= 250 { return .light }
  if value >= 150 { return .thin }
  return .ultraLight
}

/// The font for a size, a CSS weight, a family name (or the generic
/// 'monospace' / 'serif') and whether it slants. A family UIKit does not know
/// falls back to the system font.
func dnnFont(size: CGFloat, weight: CGFloat, family: String?, italic: Bool) -> UIFont {
  let resolved = dnnFontWeight(weight)
  var font = UIFont.systemFont(ofSize: size, weight: resolved)
  if let family = family, !family.isEmpty {
    switch family {
    case "monospace":
      if #available(iOS 13.0, *) {
        font = UIFont.monospacedSystemFont(ofSize: size, weight: resolved)
      } else if let mono = UIFont(name: "Menlo-Regular", size: size) {
        font = mono
      }
    case "serif":
      if #available(iOS 13.0, *) {
        if let descriptor = font.fontDescriptor.withDesign(.serif) {
          font = UIFont(descriptor: descriptor, size: size)
        }
      } else if let serif = UIFont(name: "TimesNewRomanPSMT", size: size) {
        font = serif
      }
    default:
      if let named = UIFont(name: family, size: size) {
        font = named
      } else if let first = UIFont.fontNames(forFamilyName: family).first,
        let named = UIFont(name: first, size: size)
      {
        font = named
      }
    }
  }
  if italic {
    let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
      font = UIFont(descriptor: descriptor, size: size)
    }
  }
  return font
}

/// "As wide (or tall) as what holds me", as a wish rather than a demand: it
/// wins over a view's own hugging and loses to anything that is required, so
/// a view asked to expand takes the room there is and never breaks a layout
/// that has none to give.
func dnnFill(_ view: UIView, _ superview: UIView, horizontal: Bool) -> NSLayoutConstraint {
  let constraint =
    horizontal
    ? view.widthAnchor.constraint(equalTo: superview.widthAnchor)
    : view.heightAnchor.constraint(equalTo: superview.heightAnchor)
  constraint.priority = UILayoutPriority(740)
  return constraint
}

/// A rectangle with a radius per corner: top left, top right, bottom right,
/// bottom left.
func dnnRoundedPath(_ rect: CGRect, _ radii: [CGFloat]) -> UIBezierPath {
  let limit = max(0, min(rect.width, rect.height) / 2)
  func radius(_ index: Int) -> CGFloat {
    guard index < radii.count else { return 0 }
    return min(max(radii[index], 0), limit)
  }
  let tl = radius(0)
  let tr = radius(1)
  let br = radius(2)
  let bl = radius(3)
  let quarter = CGFloat.pi / 2
  let path = UIBezierPath()
  path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
  path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
  if tr > 0 {
    path.addArc(
      withCenter: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
      startAngle: -quarter, endAngle: 0, clockwise: true)
  }
  path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
  if br > 0 {
    path.addArc(
      withCenter: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
      startAngle: 0, endAngle: quarter, clockwise: true)
  }
  path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
  if bl > 0 {
    path.addArc(
      withCenter: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
      startAngle: quarter, endAngle: quarter * 2, clockwise: true)
  }
  path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
  if tl > 0 {
    path.addArc(
      withCenter: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
      startAngle: quarter * 2, endAngle: quarter * 3, clockwise: true)
  }
  path.close()
  return path
}

/// A view that holds at most one child of the tree, and can swap it - which is
/// what lets the reconciler rebuild one subtree in place instead of the screen.
protocol DnnSingleChildHost: AnyObject {
  var hostedChild: UIView? { get }
  func replaceChild(_ view: UIView?)
}

// MARK: - Box

/// Everything a `Box` node says about itself, read out of the tree by the
/// renderer.
struct DnnBoxStyle {
  var width: CGFloat?
  var height: CGFloat?
  var minWidth: CGFloat?
  var maxWidth: CGFloat?
  var minHeight: CGFloat?
  var maxHeight: CGFloat?
  var expandWidth = false
  var expandHeight = false
  var aspectRatio: CGFloat?
  var padding = UIEdgeInsets.zero
  var margin = UIEdgeInsets.zero
  /// `[x, y]` from -1 to 1, or nil for a child that fills the box.
  var alignment: CGPoint?

  var color: UIColor?
  var gradientColors: [UIColor] = []
  var gradientStops: [CGFloat] = []
  var gradientRadial = false
  var gradientStart = CGPoint(x: 0, y: 0.5)
  var gradientEnd = CGPoint(x: 1, y: 0.5)
  var borderWidth: CGFloat = 0
  var borderColor: UIColor?
  /// Top left, top right, bottom right, bottom left.
  var radii: [CGFloat] = [0, 0, 0, 0]
  var circle = false
  var shadowColor: UIColor?
  var shadowBlur: CGFloat = 0
  var shadowOffset = CGSize.zero
  var clip = false
  var opacity: CGFloat = 1
  var transform = CGAffineTransform.identity
  /// The turn in [transform], in radians: kept apart because a whole turn is
  /// no change to a matrix, and a box that spins has to be told the way
  /// round.
  var rotation: CGFloat = 0
  /// A whole matrix (`transform.matrix`), in place of `transform`, worked
  /// about `pivot`: an alignment in the box and a shift from it.
  var matrix: CATransform3D?
  var pivot: (CGFloat, CGFloat, CGFloat, CGFloat) = (-1, -1, 0, 0)

  var tapEventId: String?
  /// Told as a finger goes down, and `_cancel` when it does not make a tap.
  var tapDownEventId: String?
  var doubleTapEventId: String?
  var longPressEventId: String?
  var panEventId: String?
  /// 'horizontal' or 'vertical' for a pan along that axis alone.
  var panAxis: String?
  /// Whether the pan hears a second finger, and reports the pinch.
  var panScale = false
  var ripple = false
  var dragData: String?
  /// Told `_start` when the box is picked up and `_end` when it is let go.
  var dragEventId: String?
  var dropEventId: String?
  var sizeEventId: String?
  var semanticLabel: String?
  /// The state said after the name: "Upload, 40%".
  var semanticValue: String?
  /// Names a box that has no label and no text inside it.
  var tooltip: String?
  /// Changes inside are announced without the reader moving to the box.
  var liveRegion = false
  /// What is inside is not there for a screen reader; the box's label is.
  var excludeSemantics = false
  /// A button the app drew and switched off: announced, and said to be dimmed.
  var disabled = false
  /// On or off, for a box that is a toggle (a filter chip); nil for any other.
  var selected: Bool?
  var ignorePointer = false
}

/**
 The view behind a `Box`.

 Two layers: this view carries the margin, the shadow, the opacity and the
 transform; `surface` inside it carries the paint and the clip; and `content`
 inside that holds the child. The shadow sits on the outer layer, with a path
 of its own, so the surface is free to clip without cutting its own shadow off.
 */
class DnnBoxView: UIView, DnnSingleChildHost, UIDragInteractionDelegate,
  UIDropInteractionDelegate, UIGestureRecognizerDelegate
{
  /// A pan along one axis begins only with a movement along it; one that
  /// sets off the other way is the scroller's the box is in or holds.
  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    guard recognizer === panRecognizer, let axis = style.panAxis,
      let pan = recognizer as? UIPanGestureRecognizer
    else { return super.gestureRecognizerShouldBegin(recognizer) }
    let velocity = pan.velocity(in: surface)
    return axis == "horizontal"
      ? abs(velocity.x) >= abs(velocity.y)
      : abs(velocity.y) > abs(velocity.x)
  }

  /// A scroller waits for a pan along one axis to say whether the movement
  /// is its own. Left to race, the scroller around a row took a sideways
  /// swipe before the row could; this way the pan answers first, and when it
  /// declines - the movement set off the other way - the scroller has it.
  func gestureRecognizer(
    _ recognizer: UIGestureRecognizer,
    shouldBeRequiredToFailBy other: UIGestureRecognizer
  ) -> Bool {
    recognizer === panRecognizer && style.panAxis != nil
      && other is UIPanGestureRecognizer && other.view is UIScrollView
  }

  let surface = UIView()
  let content = UIView()

  /// Sends `(eventId, data)` to the app.
  var onEvent: ((String, [String: Any]) -> Void)?

  private(set) var style = DnnBoxStyle()

  /// Whether the box moves to the size its child comes to (`animateSize`),
  /// over how long and along what. While it moves, the child may stand past
  /// its edges - clipped there, when the box clips.
  var animatesSize = false {
    didSet { if oldValue != animatesSize { applyChildLayout(force: true) } }
  }
  var sizeSeconds: TimeInterval = 0
  /// The protocol's name for the curve the size moves along.
  var sizeCurve: String?
  /// Told when a move to the child's size has got there.
  var sizeEndEventId: String?

  /// Set while the renderer draws a tree: it moves a box to its size itself
  /// then (`moveSizes`).
  static var rendering = false

  /// The size the box last settled at, for one that moves to its size: a
  /// change outside a render - a picture arriving in it - is moved to here.
  private var settledSize: CGSize?

  /// Moves the box from a size to the one its child has come to by itself,
  /// held at the first: given by the renderer, which knows the root to lay
  /// out as it goes.
  var followSize: ((DnnBoxView, CGSize, CGSize) -> Void)?

  /// Whether the box stays at the top of the scroller it is in once the
  /// content has scrolled past it (`sticky`).
  var sticky = false {
    didSet {
      if sticky { DnnBoxView.stickies.add(self) } else { DnnBoxView.stickies.remove(self) }
      if oldValue != sticky { watchScroller() }
    }
  }
  /// The boxes that are sticky, to stack each under those before it.
  private static let stickies = NSHashTable<DnnBoxView>.weakObjects()
  private var stickObservation: NSKeyValueObservation?
  private var stuckBy: CGFloat = 0

  override func didMoveToWindow() {
    super.didMoveToWindow()
    watchScroller()
  }

  /// Follows the scroller round the box, while it is sticky and on screen.
  private func watchScroller() {
    stickObservation = nil
    guard sticky, window != nil else {
      stick(0)
      return
    }
    var up = superview
    while let view = up, !(view is UIScrollView) { up = view.superview }
    guard let scroll = up as? UIScrollView else { return }
    stickObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
      self?.follow(scroll)
    }
    follow(scroll)
  }

  /// The scroller round the box, and where in it the box's place is -
  /// where it would be, unmoved.
  private func place() -> (UIScrollView, CGFloat)? {
    var up = superview
    while let view = up, !(view is UIScrollView) { up = view.superview }
    guard let scroll = up as? UIScrollView else { return nil }
    return (scroll, convert(CGPoint.zero, to: scroll).y - stuckBy)
  }

  /// Moves the box down by as far as its place has gone above the top of
  /// what [scroll] shows - or above the bottom of the sticky boxes before it
  /// in the scroller, which it stacks under, as Flutter's pinned headers do.
  private func follow(_ scroll: UIScrollView) {
    guard let (_, place) = place() else { return }
    var above: CGFloat = 0
    for other in DnnBoxView.stickies.allObjects where other !== self && other.window != nil {
      guard let (theirs, at) = other.place(), theirs === scroll, at < place else { continue }
      above += other.bounds.height
    }
    let top = scroll.contentOffset.y + scroll.adjustedContentInset.top + above
    stick(max(0, top - place))
  }

  private func stick(_ down: CGFloat) {
    guard abs(down - stuckBy) >= 0.5 || (down == 0 && stuckBy != 0) else { return }
    stuckBy = down
    applyTransform()
    // Over the rows that scroll beneath it: they come after it.
    layer.zPosition = down > 0 ? 1 : 0
  }
  private var sizePins: [NSLayoutConstraint] = []

  private var childPins: [NSLayoutConstraint] = []

  /// Holds the box at [size] - the one it is moving from, then the one it is
  /// moving to - against what its child would make it. The child is held at
  /// the size it has come to, so that it is laid out once and the box moves
  /// over it: text squeezed to the old width would wrap again, and keep the
  /// narrow width as its own once let go.
  func pinSize(_ size: CGSize) {
    NSLayoutConstraint.deactivate(sizePins)
    sizePins = [
      surface.widthAnchor.constraint(equalToConstant: size.width),
      surface.heightAnchor.constraint(equalToConstant: size.height),
    ]
    for pin in sizePins { pin.priority = UILayoutPriority(999) }
    NSLayoutConstraint.activate(sizePins)
    if childPins.isEmpty, let child = content.subviews.first {
      let natural = child.bounds.size
      childPins = [
        child.widthAnchor.constraint(equalToConstant: natural.width),
        child.heightAnchor.constraint(equalToConstant: natural.height),
      ]
      for pin in childPins { pin.priority = UILayoutPriority(998) }
      NSLayoutConstraint.activate(childPins)
    }
  }

  /// Leaves the box to its child again.
  func unpinSize() {
    NSLayoutConstraint.deactivate(sizePins + childPins)
    sizePins = []
    childPins = []
  }

  private var marginConstraints: [NSLayoutConstraint] = []
  private var sizeConstraints: [NSLayoutConstraint] = []
  private var childConstraints: [NSLayoutConstraint] = []
  private var fillConstraints: [NSLayoutConstraint] = []
  private var sizingApplied: [CGFloat?]?
  private var childLayoutApplied: (padding: UIEdgeInsets, alignment: CGPoint?)?

  private var gradientLayer: CAGradientLayer?
  private var shapeMask: CAShapeLayer?
  private var borderShape: CAShapeLayer?
  private var highlight: UIView?

  private var tapRecognizer: UITapGestureRecognizer?
  private var pressWatcher: DnnPressWatcher?
  private var doubleTapRecognizer: UITapGestureRecognizer?
  private var longPressRecognizer: UILongPressGestureRecognizer?
  private var panRecognizer: UIPanGestureRecognizer?
  private var dragger: UIDragInteraction?
  private var dropper: UIDropInteraction?
  /// Builds what a drag of this box carries (`dragFeedback`), when the tree
  /// names something: built when the drag begins, never laid out in the box.
  var makeFeedback: (() -> UIView?)?
  private var lastPan = CGPoint.zero

  /// The pinch a pan that hears one (`panScale`) is watching for, whether it
  /// is going, whether the app has been told a pan began - by the pan or by
  /// the pinch, whichever came first - and where the point between the
  /// fingers was last reported, on the screen.
  private var pinchRecognizer: UIPinchGestureRecognizer?
  private var pinching = false
  private var panTold = false
  private var lastFocal = CGPoint.zero
  private var angleFrom: CGFloat = 0

  /// The angle of the line from the pinch's first finger to its second.
  private func fingerAngle(_ recognizer: UIPinchGestureRecognizer) -> CGFloat? {
    guard recognizer.numberOfTouches >= 2 else { return nil }
    let a = recognizer.location(ofTouch: 0, in: nil)
    let b = recognizer.location(ofTouch: 1, in: nil)
    return atan2(b.y - a.y, b.x - a.x)
  }

  /// [radians] brought within half a turn either way.
  private func turn(_ radians: CGFloat) -> CGFloat {
    var turn = radians
    while turn > .pi { turn -= 2 * .pi }
    while turn < -.pi { turn += 2 * .pi }
    return turn
  }

  /// The pan and the pinch are one gesture to the app, and are heard together.
  func gestureRecognizer(
    _ recognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    let mine: [UIGestureRecognizer?] = [panRecognizer, pinchRecognizer]
    return mine.contains { $0 === recognizer } && mine.contains { $0 === other }
  }

  @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
    guard let eventId = style.panEventId else { return }
    let point = recognizer.location(in: surface)
    let onScreen = recognizer.location(in: nil)
    switch recognizer.state {
    case .began:
      pinching = true
      lastFocal = onScreen
      angleFrom = fingerAngle(recognizer) ?? 0
      if !panTold {
        panTold = true
        onEvent?(
          eventId + "_start",
          ["x": Double(point.x), "y": Double(point.y), "dx": 0.0, "dy": 0.0,
           "vx": 0.0, "vy": 0.0, "pointers": 2])
      }
    case .changed:
      guard recognizer.numberOfTouches >= 2 else { return }
      onEvent?(
        eventId + "_update",
        [
          "x": Double(point.x), "y": Double(point.y),
          "dx": Double(onScreen.x - lastFocal.x), "dy": Double(onScreen.y - lastFocal.y),
          "vx": 0.0, "vy": 0.0,
          "scale": Double(recognizer.scale),
          "rotation": Double(turn((fingerAngle(recognizer) ?? angleFrom) - angleFrom)),
          "pointers": recognizer.numberOfTouches,
        ])
      lastFocal = onScreen
    case .ended, .cancelled, .failed:
      pinching = false
      // The pan goes on with the finger left, from where it is - or, when
      // there is no pan going, the gesture is over.
      if let pan = panRecognizer, pan.state == .began || pan.state == .changed {
        lastPan = pan.location(in: nil)
      } else if panTold {
        panTold = false
        onEvent?(
          eventId + "_end",
          ["x": Double(point.x), "y": Double(point.y), "dx": 0.0, "dy": 0.0,
           "vx": 0.0, "vy": 0.0])
      }
    default:
      return
    }
  }
  private var hovering = false
  private var reportedSize = CGSize(width: -1, height: -1)

  var hostedChild: UIView? { content.subviews.first }

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  private func setUp() {
    surface.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(surface)
    surface.addSubview(content)
    marginConstraints = [
      surface.leftAnchor.constraint(equalTo: leftAnchor),
      surface.topAnchor.constraint(equalTo: topAnchor),
      rightAnchor.constraint(equalTo: surface.rightAnchor),
      bottomAnchor.constraint(equalTo: surface.bottomAnchor),
    ]
    NSLayoutConstraint.activate(marginConstraints)
    NSLayoutConstraint.activate([
      content.leftAnchor.constraint(equalTo: surface.leftAnchor),
      content.topAnchor.constraint(equalTo: surface.topAnchor),
      content.rightAnchor.constraint(equalTo: surface.rightAnchor),
      content.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
    ])
  }

  // MARK: Applying a style

  /// The style's transform - its parts, or its whole matrix about its
  /// pivot - and the move down a sticky box has made.
  private func applyTransform() {
    let down = CGAffineTransform(translationX: 0, y: stuckBy)
    guard let matrix = style.matrix else {
      transform = stuckBy == 0 ? style.transform : style.transform.concatenating(down)
      return
    }
    // From the view's middle, which is where a layer's transform works, to
    // the point in the painted box the matrix works about.
    let box = surface.frame
    let (ax, ay, ox, oy) = style.pivot
    let dx = box.minX + (ax + 1) / 2 * box.width + ox - bounds.midX
    let dy = box.minY + (ay + 1) / 2 * box.height + oy - bounds.midY
    var whole = CATransform3DConcat(
      CATransform3DConcat(CATransform3DMakeTranslation(-dx, -dy, 0), matrix),
      CATransform3DMakeTranslation(dx, dy, 0))
    if stuckBy != 0 { whole = CATransform3DConcat(whole, CATransform3DMakeAffineTransform(down)) }
    layer.transform = whole
  }

  /// Restyles the box in place. Inside a `UIView.animate` block the size,
  /// colour, opacity and transform move there instead of landing at once.
  func apply(_ next: DnnBoxStyle) {
    if next.sizeEventId != style.sizeEventId {
      reportedSize = CGSize(width: -1, height: -1)
    }
    let turnedFrom = style.rotation
    style = next
    // A turn of half a circle or more, animated: UIKit moves between the two
    // matrices, which for a whole turn are the same one and for more than a
    // half go the short way round. So the angle itself is moved.
    let time = UIView.inheritedAnimationDuration
    if time > 0, next.matrix == nil, abs(next.rotation - turnedFrom) >= .pi {
      let spin = CABasicAnimation(keyPath: "transform.rotation.z")
      spin.fromValue = turnedFrom
      spin.toValue = next.rotation
      spin.duration = time
      layer.add(spin, forKey: "dnn.spin")
    }

    if marginConstraints.count == 4 {
      marginConstraints[0].constant = next.margin.left
      marginConstraints[1].constant = next.margin.top
      marginConstraints[2].constant = next.margin.right
      marginConstraints[3].constant = next.margin.bottom
    }
    applySizing()
    applyChildLayout(force: false)
    applyFill()

    surface.backgroundColor = next.color
    applyGradient()
    alpha = min(max(next.opacity, 0), 1)
    applyTransform()
    isUserInteractionEnabled = !next.ignorePointer
    // What the box says of itself to a screen reader - whether it is an
    // element, its name, its traits - is worked out when it is asked for (see
    // "Accessibility" below), because it depends on what is inside the box and
    // on the boxes around it, and both change without this box being restyled.
    // Only what can be stated outright is set here.
    content.accessibilityElementsHidden = next.excludeSemantics
    if next.longPressEventId != nil {
      accessibilityCustomActions = [
        UIAccessibilityCustomAction(
          name: "Long press", target: self,
          selector: #selector(handleAccessibilityLongPress(_:)))
      ]
    } else {
      accessibilityCustomActions = nil
    }

    applyRecognizers()
    applyDragAndDrop()
    applyShape()
    setNeedsLayout()
  }

  private func applySizing() {
    let key: [CGFloat?] = [
      style.width, style.height, style.minWidth, style.maxWidth, style.minHeight,
      style.maxHeight, style.aspectRatio,
    ]
    if let applied = sizingApplied, applied == key { return }
    sizingApplied = key

    NSLayoutConstraint.deactivate(sizeConstraints)
    var next: [NSLayoutConstraint] = []
    if let width = style.width {
      next.append(surface.widthAnchor.constraint(equalToConstant: max(0, width)))
    }
    if let height = style.height {
      next.append(surface.heightAnchor.constraint(equalToConstant: max(0, height)))
    }
    if let minWidth = style.minWidth {
      next.append(surface.widthAnchor.constraint(greaterThanOrEqualToConstant: max(0, minWidth)))
    }
    if let maxWidth = style.maxWidth {
      next.append(surface.widthAnchor.constraint(lessThanOrEqualToConstant: max(0, maxWidth)))
    }
    if let minHeight = style.minHeight {
      next.append(
        surface.heightAnchor.constraint(greaterThanOrEqualToConstant: max(0, minHeight)))
    }
    if let maxHeight = style.maxHeight {
      next.append(surface.heightAnchor.constraint(lessThanOrEqualToConstant: max(0, maxHeight)))
    }
    // Just under required: a box asked to be wider than the screen gives way
    // rather than breaking the layout around it.
    for constraint in next { constraint.priority = UILayoutPriority(999) }
    if let ratio = style.aspectRatio, ratio > 0 {
      let aspect = surface.widthAnchor.constraint(
        equalTo: surface.heightAnchor, multiplier: ratio)
      aspect.priority = UILayoutPriority(998)
      next.append(aspect)
    }
    sizeConstraints = next
    NSLayoutConstraint.activate(next)
  }

  private func applyChildLayout(force: Bool) {
    if !force, let applied = childLayoutApplied, applied.padding == style.padding,
      applied.alignment == style.alignment
    {
      return
    }
    childLayoutApplied = (padding: style.padding, alignment: style.alignment)

    NSLayoutConstraint.deactivate(childConstraints)
    childConstraints = []
    guard let child = content.subviews.first else { return }
    let inset = style.padding
    var next: [NSLayoutConstraint] = []

    // The child never leaves the padded area, whatever else is asked - but
    // for a box on its way to its child's size, which is held at the size it
    // is passing through and lets the child stand past it.
    let within = [
      child.leftAnchor.constraint(greaterThanOrEqualTo: content.leftAnchor, constant: inset.left),
      child.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: inset.top),
      content.rightAnchor.constraint(
        greaterThanOrEqualTo: child.rightAnchor, constant: inset.right),
      content.bottomAnchor.constraint(
        greaterThanOrEqualTo: child.bottomAnchor, constant: inset.bottom),
    ]
    if animatesSize {
      for constraint in within { constraint.priority = UILayoutPriority(996) }
    }
    next += within

    if let alignment = style.alignment {
      if alignment.x < -0.33 {
        next.append(
          child.leftAnchor.constraint(equalTo: content.leftAnchor, constant: inset.left))
      } else if alignment.x > 0.33 {
        next.append(
          content.rightAnchor.constraint(equalTo: child.rightAnchor, constant: inset.right))
      } else {
        next.append(
          child.centerXAnchor.constraint(
            equalTo: content.centerXAnchor, constant: (inset.left - inset.right) / 2))
      }
      if alignment.y < -0.33 {
        next.append(child.topAnchor.constraint(equalTo: content.topAnchor, constant: inset.top))
      } else if alignment.y > 0.33 {
        next.append(
          content.bottomAnchor.constraint(equalTo: child.bottomAnchor, constant: inset.bottom))
      } else {
        next.append(
          child.centerYAnchor.constraint(
            equalTo: content.centerYAnchor, constant: (inset.top - inset.bottom) / 2))
      }
      // With nothing else sizing it, the box hugs its child.
      let hugWidth = content.widthAnchor.constraint(
        equalTo: child.widthAnchor, constant: inset.left + inset.right)
      hugWidth.priority = UILayoutPriority(100)
      let hugHeight = content.heightAnchor.constraint(
        equalTo: child.heightAnchor, constant: inset.top + inset.bottom)
      hugHeight.priority = UILayoutPriority(100)
      next.append(hugWidth)
      next.append(hugHeight)
    } else {
      // The child fills the content area. The far edges are a notch weaker
      // than the box's own stated size, so a child with a fixed size of its
      // own stays that size at the top left instead of shrinking the box.
      next.append(child.leftAnchor.constraint(equalTo: content.leftAnchor, constant: inset.left))
      next.append(child.topAnchor.constraint(equalTo: content.topAnchor, constant: inset.top))
      let right = content.rightAnchor.constraint(
        equalTo: child.rightAnchor, constant: inset.right)
      right.priority = UILayoutPriority(997)
      let bottom = content.bottomAnchor.constraint(
        equalTo: child.bottomAnchor, constant: inset.bottom)
      bottom.priority = UILayoutPriority(997)
      next.append(right)
      next.append(bottom)
    }
    childConstraints = next
    NSLayoutConstraint.activate(next)
  }

  private func applyFill() {
    NSLayoutConstraint.deactivate(fillConstraints)
    fillConstraints = []
    guard let parent = superview else { return }
    if style.expandWidth {
      fillConstraints.append(dnnFill(self, parent, horizontal: true))
    }
    if style.expandHeight {
      fillConstraints.append(dnnFill(self, parent, horizontal: false))
    }
    NSLayoutConstraint.activate(fillConstraints)
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    applyFill()
  }

  func replaceChild(_ view: UIView?) {
    content.subviews.forEach { $0.removeFromSuperview() }
    if let view = view {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    applyChildLayout(force: true)
  }

  // MARK: Paint

  private func applyGradient() {
    guard style.gradientColors.count >= 2 else {
      gradientLayer?.removeFromSuperlayer()
      gradientLayer = nil
      return
    }
    let gradient: CAGradientLayer
    if let existing = gradientLayer {
      gradient = existing
    } else {
      gradient = CAGradientLayer()
      surface.layer.insertSublayer(gradient, at: 0)
      gradientLayer = gradient
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradient.colors = style.gradientColors.map { $0.cgColor }
    if style.gradientStops.count == style.gradientColors.count {
      gradient.locations = style.gradientStops.map { NSNumber(value: Double($0)) }
    } else {
      gradient.locations = nil
    }
    gradient.type = style.gradientRadial ? .radial : .axial
    gradient.startPoint = style.gradientStart
    gradient.endPoint = style.gradientEnd
    gradient.frame = surface.bounds
    CATransaction.commit()
  }

  /// The corner radii in force for [bounds]: a circle's follow its size.
  private func radiiInForce(_ bounds: CGRect) -> [CGFloat] {
    if style.circle {
      let radius = min(bounds.width, bounds.height) / 2
      return [radius, radius, radius, radius]
    }
    return style.radii
  }

  /// Corners, border, clip and shadow, which all follow the surface's size.
  private func applyShape() {
    let bounds = surface.bounds
    let radii = radiiInForce(bounds)
    let rounded = radii.filter { $0 > 0 }
    let largest = rounded.max() ?? 0
    // One radius on some of the corners is something a layer does by itself;
    // four different ones need a path.
    let uniform = !rounded.contains { abs($0 - largest) > 0.01 }
    let borderColor = (style.borderColor ?? UIColor.black).cgColor

    if uniform {
      var corners: CACornerMask = []
      if radii.count == 4 {
        if radii[0] > 0 { corners.insert(.layerMinXMinYCorner) }
        if radii[1] > 0 { corners.insert(.layerMaxXMinYCorner) }
        if radii[2] > 0 { corners.insert(.layerMaxXMaxYCorner) }
        if radii[3] > 0 { corners.insert(.layerMinXMaxYCorner) }
      }
      let limit = max(0, min(bounds.width, bounds.height) / 2)
      let radius = bounds.isEmpty ? largest : min(largest, limit)
      surface.layer.mask = nil
      shapeMask = nil
      borderShape?.removeFromSuperlayer()
      borderShape = nil
      surface.layer.cornerRadius = radius
      surface.layer.maskedCorners = corners
      surface.layer.borderWidth = style.borderWidth
      surface.layer.borderColor = borderColor
      surface.clipsToBounds = style.clip
      highlight?.layer.cornerRadius = radius
      highlight?.layer.maskedCorners = corners
      if let gradient = gradientLayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.cornerRadius = radius
        gradient.maskedCorners = corners
        CATransaction.commit()
      }
    } else {
      let path = dnnRoundedPath(bounds, radii).cgPath
      surface.layer.cornerRadius = 0
      surface.layer.borderWidth = 0
      surface.clipsToBounds = false
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      let mask = shapeMask ?? CAShapeLayer()
      mask.frame = bounds
      mask.path = path
      if shapeMask == nil {
        surface.layer.mask = mask
        shapeMask = mask
      }
      if style.borderWidth > 0 {
        let border = borderShape ?? CAShapeLayer()
        border.frame = bounds
        border.path = path
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = borderColor
        // Half of the stroke falls outside the path and is cut by the mask.
        border.lineWidth = style.borderWidth * 2
        border.zPosition = 1
        if borderShape == nil {
          surface.layer.addSublayer(border)
          borderShape = border
        }
      } else {
        borderShape?.removeFromSuperlayer()
        borderShape = nil
      }
      if let gradient = gradientLayer {
        gradient.frame = bounds
        gradient.cornerRadius = 0
      }
      CATransaction.commit()
    }

    if let shadow = style.shadowColor {
      layer.shadowColor = shadow.cgColor
      layer.shadowOpacity = 1
      layer.shadowRadius = style.shadowBlur / 2
      layer.shadowOffset = style.shadowOffset
      layer.shadowPath = dnnRoundedPath(surface.frame, radii).cgPath
    } else {
      layer.shadowOpacity = 0
      layer.shadowPath = nil
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    applyShape()
    // A matrix works about a point in the box, which moves with its size.
    if style.matrix != nil { applyTransform() }
    if animatesSize, sizePins.isEmpty {
      let size = surface.bounds.size
      let was = settledSize
      settledSize = size
      // Its child changed size between renders: held where it was, and
      // moved from there.
      if !DnnBoxView.rendering, window != nil, let was, let follow = followSize,
        abs(size.width - was.width) > 0.5 || abs(size.height - was.height) > 0.5
      {
        pinSize(was)
        follow(self, was, size)
      }
    }

    guard let eventId = style.sizeEventId else { return }
    let size = surface.bounds.size
    if abs(size.width - reportedSize.width) > 0.5 || abs(size.height - reportedSize.height) > 0.5 {
      reportedSize = size
      let handler = onEvent
      // Out of the layout pass: the answer is usually another render.
      DispatchQueue.main.async {
        handler?(eventId, ["width": Double(size.width), "height": Double(size.height)])
      }
    }
  }

  // MARK: Touch feedback

  private func setHighlighted(_ on: Bool) {
    guard style.ripple else { return }
    let overlay: UIView
    if let existing = highlight {
      overlay = existing
    } else {
      overlay = UIView(frame: surface.bounds)
      overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      overlay.isUserInteractionEnabled = false
      overlay.backgroundColor = UIColor.gray.withAlphaComponent(0.25)
      overlay.alpha = 0
      overlay.layer.cornerRadius = surface.layer.cornerRadius
      overlay.layer.maskedCorners = surface.layer.maskedCorners
      surface.addSubview(overlay)
      highlight = overlay
    }
    UIView.animate(
      withDuration: on ? 0.05 : 0.25, delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction],
      animations: { overlay.alpha = on ? 1 : 0 }, completion: nil)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    setHighlighted(true)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    setHighlighted(false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesCancelled(touches, with: event)
    setHighlighted(false)
  }

  // MARK: Gestures

  private func applyRecognizers() {
    let hadDoubleTap = doubleTapRecognizer != nil
    if style.doubleTapEventId != nil {
      if doubleTapRecognizer == nil {
        let recognizer = UITapGestureRecognizer(
          target: self, action: #selector(handleDoubleTap(_:)))
        recognizer.numberOfTapsRequired = 2
        surface.addGestureRecognizer(recognizer)
        doubleTapRecognizer = recognizer
      }
    } else if let recognizer = doubleTapRecognizer {
      surface.removeGestureRecognizer(recognizer)
      doubleTapRecognizer = nil
    }
    // A single tap waits for the double tap to fail, and that is set up when
    // the recognizer is made - so it is remade when the double tap comes or
    // goes.
    if hadDoubleTap != (doubleTapRecognizer != nil), let recognizer = tapRecognizer {
      surface.removeGestureRecognizer(recognizer)
      tapRecognizer = nil
    }

    if style.tapEventId != nil {
      if tapRecognizer == nil {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        if let double = doubleTapRecognizer { recognizer.require(toFail: double) }
        surface.addGestureRecognizer(recognizer)
        tapRecognizer = recognizer
      }
    } else if let recognizer = tapRecognizer {
      surface.removeGestureRecognizer(recognizer)
      tapRecognizer = nil
    }

    if style.tapDownEventId != nil {
      if pressWatcher == nil {
        let watcher = DnnPressWatcher()
        watcher.onDown = { [weak self] point in
          guard let self, let eventId = self.style.tapDownEventId else { return }
          self.onEvent?(eventId, self.pointData(point))
        }
        watcher.onLost = { [weak self] in
          guard let self, let eventId = self.style.tapDownEventId else { return }
          self.onEvent?(eventId + "_cancel", [:])
        }
        surface.addGestureRecognizer(watcher)
        pressWatcher = watcher
      }
      // A tap that waits for a second one is still to come when the finger lifts.
      pressWatcher?.tapWait = style.doubleTapEventId != nil ? 0.4 : 0
    } else if let watcher = pressWatcher {
      surface.removeGestureRecognizer(watcher)
      pressWatcher = nil
    }

    if style.longPressEventId != nil {
      if longPressRecognizer == nil {
        let recognizer = UILongPressGestureRecognizer(
          target: self, action: #selector(handleLongPress(_:)))
        surface.addGestureRecognizer(recognizer)
        longPressRecognizer = recognizer
      }
    } else if let recognizer = longPressRecognizer {
      surface.removeGestureRecognizer(recognizer)
      longPressRecognizer = nil
    }

    if style.panEventId != nil {
      if panRecognizer == nil {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.delegate = self
        surface.addGestureRecognizer(recognizer)
        panRecognizer = recognizer
      }
    } else if let recognizer = panRecognizer {
      surface.removeGestureRecognizer(recognizer)
      panRecognizer = nil
    }

    if style.panEventId != nil && style.panScale {
      if pinchRecognizer == nil {
        let recognizer = UIPinchGestureRecognizer(
          target: self, action: #selector(handlePinch(_:)))
        recognizer.delegate = self
        surface.addGestureRecognizer(recognizer)
        pinchRecognizer = recognizer
      }
    } else if let recognizer = pinchRecognizer {
      surface.removeGestureRecognizer(recognizer)
      pinchRecognizer = nil
    }
  }

  private func pointData(_ point: CGPoint) -> [String: Any] {
    ["x": Double(point.x), "y": Double(point.y)]
  }

  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    pressWatcher?.tapped()
    guard let eventId = style.tapEventId else { return }
    onEvent?(eventId, pointData(recognizer.location(in: surface)))
  }

  @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
    pressWatcher?.lose()
    guard let eventId = style.doubleTapEventId else { return }
    onEvent?(eventId, pointData(recognizer.location(in: surface)))
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    pressWatcher?.lose()
    guard let eventId = style.longPressEventId else { return }
    onEvent?(eventId, pointData(recognizer.location(in: surface)))
  }

  @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
    guard let eventId = style.panEventId else { return }
    let point = recognizer.location(in: surface)
    // How far the finger moved is measured on the screen, not in the box: a
    // box that follows the finger - a row being swiped away - has the finger
    // at the same place in it all the while, and would be told it never moved.
    let onScreen = recognizer.location(in: nil)
    let velocity = recognizer.velocity(in: nil)
    let suffix: String
    switch recognizer.state {
    case .began:
      lastPan = onScreen
      // A pinch that came first has told the app already.
      if panTold { return }
      panTold = true
      suffix = "_start"
    case .changed:
      // Two fingers are the pinch's to report; the pan's centroid moving is
      // the same movement.
      if pinching {
        lastPan = onScreen
        return
      }
      suffix = "_update"
    case .ended, .cancelled, .failed:
      if pinching { return }
      panTold = false
      suffix = "_end"
    default:
      return
    }
    let data: [String: Any] = [
      "x": Double(point.x),
      "y": Double(point.y),
      "dx": Double(onScreen.x - lastPan.x),
      "dy": Double(onScreen.y - lastPan.y),
      "vx": Double(velocity.x),
      "vy": Double(velocity.y),
    ]
    lastPan = onScreen
    onEvent?(eventId + suffix, data)
  }

  // MARK: Accessibility

  /// What `semanticRole` adds - a heading, an image - set by the renderer's
  /// `identify`. Kept apart from the stored traits so that it can be replaced
  /// without disturbing them.
  var roleTraits: UIAccessibilityTraits = []

  /// The name the tree gave, then the state said after it ("Upload, 40%").
  private var statedLabel: String? {
    let parts = [style.semanticLabel, style.semanticValue].compactMap { part -> String? in
      guard let part = part, !part.isEmpty else { return nil }
      return part
    }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  /// Whether a tap or a long press on the box means something.
  private var isActivatable: Bool {
    style.tapEventId != nil || style.longPressEventId != nil
  }

  /// Whether the box sits in one that lets no touch through (`IgnorePointer`),
  /// or is one itself. A finger would not reach it, so "activate" must not.
  private var pointerIgnored: Bool {
    var view: UIView? = self
    while let current = view {
      if let box = current as? DnnBoxView, box.style.ignorePointer { return true }
      view = current.superview
    }
    return false
  }

  /// Whether something under [view] can be activated in its own right: a
  /// control, or another box that takes a tap or a long press.
  private func holdsActionable(_ view: UIView) -> Bool {
    for sub in view.subviews where !sub.isHidden {
      if sub is UIControl { return true }
      if let box = sub as? DnnBoxView, box.isActivatable { return true }
      if holdsActionable(sub) { return true }
    }
    return false
  }

  /// The text a reader would merge into this box: what is said by the views
  /// under [view] that are not themselves something to activate.
  private func collectText(_ view: UIView, into parts: inout [String], skipActionable: Bool) {
    for sub in view.subviews {
      if sub.isHidden || sub.accessibilityElementsHidden { continue }
      if skipActionable {
        if sub is UIControl { continue }
        if let box = sub as? DnnBoxView, box.isActivatable { continue }
      }
      if sub.isAccessibilityElement {
        // A label answers with its text, an image with its `alt`, a box with
        // the name it was given. A label kept out of the tree is an icon
        // nobody named, and never gets here.
        var said = sub.accessibilityLabel
        if said == nil, let text = sub as? UITextView { said = text.text }
        let words = (said ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        if !words.isEmpty { parts.append(words.joined(separator: " ")) }
      } else {
        collectText(sub, into: &parts, skipActionable: skipActionable)
      }
    }
  }

  /// What the box is called: the label the tree stated, else the text inside
  /// it, else its tooltip - the only name an icon in a box was given.
  private func spokenName(skipActionable: Bool) -> String? {
    if let stated = statedLabel { return stated }
    if !style.excludeSemantics {
      var parts: [String] = []
      collectText(content, into: &parts, skipActionable: skipActionable)
      if !parts.isEmpty { return parts.joined(separator: ", ") }
    }
    if let tooltip = style.tooltip,
      !tooltip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return tooltip
    }
    return nil
  }

  /**
   A box that takes a tap is one thing to a screen reader - "Tic Tac Toe,
   button" - so that VoiceOver and Switch Control can activate it and a UI test
   can find it. So is a box the tree named, and one whose only name is its
   tooltip.

   Unless it holds something else that can be activated. An element hides
   everything under it, so a card that opens on a tap and carries a delete
   button stays a container: the delete button and the texts are reached one
   by one. The card's own tap is then reachable by touch but not as a single
   VoiceOver element, which is the price of keeping what is nested inside it
   addressable.
   */
  override var isAccessibilityElement: Bool {
    get {
      if !style.excludeSemantics, holdsActionable(content) { return false }
      if statedLabel != nil || isActivatable { return true }
      // A tooltip names the box only when nothing inside already says what
      // it is; text inside is read where it stands.
      guard let tooltip = style.tooltip,
        !tooltip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return false }
      if style.excludeSemantics { return true }
      var parts: [String] = []
      collectText(content, into: &parts, skipActionable: false)
      return parts.isEmpty
    }
    set { super.isAccessibilityElement = newValue }
  }

  /// Worked out when it is asked for rather than stored, so that the name
  /// follows the text inside as it is patched.
  override var accessibilityLabel: String? {
    get { spokenName(skipActionable: true) ?? super.accessibilityLabel }
    set { super.accessibilityLabel = newValue }
  }

  override var accessibilityTraits: UIAccessibilityTraits {
    get {
      var traits = super.accessibilityTraits.union(roleTraits)
      if style.tapEventId != nil { traits.insert(.button) }
      if style.liveRegion { traits.insert(.updatesFrequently) }
      // Still there to be read, and said to be unavailable.
      if isActivatable, pointerIgnored { traits.insert(.notEnabled) }
      if style.disabled { traits.insert(.notEnabled) }
      if style.selected == true { traits.insert(.selected) }
      return traits
    }
    set { super.accessibilityTraits = newValue }
  }

  /// What a screen reader's "activate" does: the tap, at the middle, with the
  /// payload a finger there would send.
  override func accessibilityActivate() -> Bool {
    guard let eventId = style.tapEventId, !pointerIgnored else { return false }
    onEvent?(eventId, pointData(CGPoint(x: surface.bounds.midX, y: surface.bounds.midY)))
    return true
  }

  /// The "Long press" action: the long press, at the middle.
  @objc private func handleAccessibilityLongPress(_ action: UIAccessibilityCustomAction) -> Bool {
    guard let eventId = style.longPressEventId, !pointerIgnored else { return false }
    onEvent?(eventId, pointData(CGPoint(x: surface.bounds.midX, y: surface.bounds.midY)))
    return true
  }

  private var lastAnnounced: String?

  /**
   `liveRegion`: says what the box now reads as, if that changed since it was
   last asked. Called by the renderer once the box is built - which only
   records what it says - and again after each patch of what is inside it.

   UIKit has no live region. `.updatesFrequently` makes VoiceOver re-read a
   box it is already on; the announcement is what reaches a reader who is
   somewhere else on the screen.
   */
  func announceChanges() {
    guard style.liveRegion else {
      lastAnnounced = nil
      return
    }
    let now = spokenName(skipActionable: false) ?? ""
    let before = lastAnnounced
    lastAnnounced = now
    guard let before = before, before != now, !now.isEmpty, window != nil else { return }
    UIAccessibility.post(notification: .announcement, argument: now)
  }

  // MARK: Drag and drop

  private func applyDragAndDrop() {
    if style.dragData != nil {
      if dragger == nil {
        let interaction = UIDragInteraction(delegate: self)
        // Off by default on an iPhone.
        interaction.isEnabled = true
        surface.addInteraction(interaction)
        dragger = interaction
      }
    } else if let interaction = dragger {
      surface.removeInteraction(interaction)
      dragger = nil
    }

    if style.dropEventId != nil {
      if dropper == nil {
        let interaction = UIDropInteraction(delegate: self)
        surface.addInteraction(interaction)
        dropper = interaction
      }
    } else if let interaction = dropper {
      surface.removeInteraction(interaction)
      dropper = nil
    }
  }

  func dragInteraction(
    _ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession
  ) -> [UIDragItem] {
    guard let data = style.dragData else { return [] }
    let item = UIDragItem(itemProvider: NSItemProvider(object: data as NSString))
    // What a drop inside this app reads, without the provider's round trip.
    item.localObject = data
    DnnDragTrail.begin(
      at: session.location(in: window ?? surface),
      grab: session.location(in: surface))
    return [item]
  }

  /// What is lifted: what the tree said to carry, its corner where the box's
  /// is - so the finger holds it by the point it took the box by, as
  /// Flutter's default anchor does - or else the box itself.
  func dragInteraction(
    _ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
    session: UIDragSession
  ) -> UITargetedDragPreview? {
    guard let feedback = makeFeedback?() else { return nil }
    let size = feedback.systemLayoutSizeFitting(
      UIScreen.main.bounds.size,
      withHorizontalFittingPriority: .fittingSizeLevel,
      verticalFittingPriority: .fittingSizeLevel)
    feedback.frame = CGRect(origin: .zero, size: size)
    feedback.layoutIfNeeded()
    let parameters = UIDragPreviewParameters()
    parameters.backgroundColor = .clear
    let target = UIDragPreviewTarget(
      container: surface, center: CGPoint(x: size.width / 2, y: size.height / 2))
    return UITargetedDragPreview(view: feedback, parameters: parameters, target: target)
  }

  func dragInteraction(_ interaction: UIDragInteraction, sessionDidMove session: UIDragSession) {
    DnnDragTrail.moved(to: session.location(in: window ?? surface))
  }

  /// The box whose drag is in the air, and what its end sends. Held here for
  /// as long as the drag lasts: the app may draw something else where the box
  /// was while it is away, and a view that was taken out of the screen - and
  /// let go of - would never hear its drag end.
  private static var carried: (box: DnnBoxView, end: () -> Void)?

  func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession)
  {
    guard let eventId = style.dragEventId, let onEvent else { return }
    DnnBoxView.carried = (self, { onEvent(eventId + "_end", DnnDragTrail.ended()) })
    onEvent(eventId + "_start", [:])
  }

  /// The finger has lifted; what becomes of the drag is still to come.
  func dragInteraction(
    _ interaction: UIDragInteraction, session: UIDragSession,
    willEndWith operation: UIDropOperation
  ) {
    DnnDragTrail.release()
  }

  /// However it ended - on a target or on nothing - and after any drop.
  func dragInteraction(
    _ interaction: UIDragInteraction, session: UIDragSession,
    didEndWith operation: UIDropOperation
  ) {
    guard let carried = DnnBoxView.carried, carried.box === self else { return }
    DnnBoxView.carried = nil
    carried.end()
  }

  private func setHovering(_ over: Bool) {
    guard hovering != over else { return }
    hovering = over
    guard let eventId = style.dropEventId else { return }
    onEvent?(eventId + "_hover", ["over": over])
  }

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession)
    -> Bool
  {
    style.dropEventId != nil
  }

  func dropInteraction(
    _ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession
  ) -> UIDropProposal {
    UIDropProposal(operation: .copy)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession)
  {
    setHovering(true)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession)
  {
    setHovering(false)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession)
  {
    setHovering(false)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    setHovering(false)
    guard let eventId = style.dropEventId else { return }
    let at = window.map { session.location(in: $0) } ?? .zero
    if let local = session.localDragSession?.items.first?.localObject as? String {
      DnnDragTrail.moved(to: at)
      onEvent?(eventId, DnnDragTrail.corner().merging(["data": local]) { $1 })
      return
    }
    // From outside the app: no grab to take off.
    let corner: [String: Any] = ["x": Double(at.x), "y": Double(at.y)]
    _ = session.loadObjects(ofClass: NSString.self) { [weak self] items in
      let text = (items.first as? NSString).map { $0 as String } ?? ""
      self?.onEvent?(eventId, corner.merging(["data": text]) { $1 })
    }
  }
}

/// Hears a finger go down at once (`tapDownEventId`), and whether it went on
/// to make a tap - recognising nothing itself, so it takes nothing from the
/// recognisers beside it or the scroller around it.
final class DnnPressWatcher: UIGestureRecognizer {
  var onDown: ((CGPoint) -> Void)?
  var onLost: (() -> Void)?
  /// How long after the finger lifts the tap may still come: a tap that
  /// waits for a second one comes late.
  var tapWait: TimeInterval = 0
  private var start = CGPoint.zero
  private var pressing = false
  private var ended = false

  init() {
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
  }

  /// The tap came: the press is over, and was one.
  func tapped() { pressing = false }

  /// The press will not be a tap: moved off, taken, held.
  func lose() {
    guard pressing else { return }
    pressing = false
    onLost?()
  }

  override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
  override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
    false
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    guard !pressing, let touch = touches.first, let view else { return }
    pressing = true
    ended = false
    start = touch.location(in: view)
    onDown?(start)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard pressing, let touch = touches.first, let view else { return }
    let at = touch.location(in: view)
    // Gone too far to be a tap: Flutter's slop.
    if hypot(at.x - start.x, at.y - start.y) > 18 { lose() }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    ended = true
    // The tap's own handler runs about now; whatever has not heard one by
    // the time it could have did not make one.
    DispatchQueue.main.asyncAfter(deadline: .now() + tapWait) { [weak self] in
      self?.lose()
    }
    state = .failed
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    lose()
    state = .failed
  }

  override func reset() {
    super.reset()
    // Ended by something other than the finger lifting: taken.
    if !ended { lose() }
  }
}

/// Where the drag in the air is, in the window, and how fast it is going:
/// what a drop and the end of a drag report. What is reported is the corner
/// of what is carried - the finger less the point it took the box by.
enum DnnDragTrail {
  private static var at = CGPoint.zero
  private static var grab = CGPoint.zero
  private static var velocity = CGPoint.zero
  private static var time = CACurrentMediaTime()

  /// The speed it had when the finger lifted, once it has.
  private static var letGo: CGPoint?

  static func begin(at point: CGPoint, grab offset: CGPoint) {
    at = point
    grab = offset
    velocity = .zero
    letGo = nil
    time = CACurrentMediaTime()
  }

  /// The finger lifted: the speed is what it was then. The end of the drag
  /// is told after the platform has animated the drop.
  static func release() {
    guard letGo == nil else { return }
    // A finger that stood still before it lifted was not moving.
    letGo = CACurrentMediaTime() - time > 0.1 ? .zero : velocity
  }

  static func moved(to point: CGPoint) {
    // The same place again - the drop, after the last move - is no move.
    if point == at { return }
    let now = CACurrentMediaTime()
    let elapsed = now - time
    if elapsed > 0 {
      // Smoothed as a pan's is: the last two moves alone say little.
      velocity = CGPoint(
        x: 0.6 * (point.x - at.x) / elapsed + 0.4 * velocity.x,
        y: 0.6 * (point.y - at.y) / elapsed + 0.4 * velocity.y)
    }
    at = point
    time = now
  }

  static func corner() -> [String: Any] {
    ["x": Double(at.x - grab.x), "y": Double(at.y - grab.y)]
  }

  static func ended() -> [String: Any] {
    release()
    let speed = letGo ?? .zero
    return corner().merging(["vx": Double(speed.x), "vy": Double(speed.y)]) { $1 }
  }
}

// MARK: - Canvas

extension CGAffineTransform {
  /// The transform without its move: what it does to a distance.
  fileprivate var linear: CGAffineTransform {
    CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
  }
}

/// One entry of a canvas's `paints`.
/// A paint's gradient, placed in the canvas's own coordinates: two points
/// for a linear one, a centre and a radius for a radial one, a centre and
/// the angle it starts at for a sweep.
struct DnnPaintGradient {
  let gradient: CGGradient
  let radial: Bool
  let from: CGPoint
  let to: CGPoint
  let radius: CGFloat

  /// A sweep's colours and where each sits in a whole turn; nil for the
  /// other two kinds. Core Graphics draws no sweep, so it is drawn here.
  let sweep: (colors: [UIColor], stops: [CGFloat], angle: CGFloat)?

  init?(_ raw: Any?) {
    guard let spec = raw as? [String: Any],
      var colors = (spec["colors"] as? [Any])?.map({ dnnColor($0) ?? .clear }),
      !colors.isEmpty
    else { return nil }
    // One colour is a flat fill; Core Graphics wants two to draw between.
    if colors.count == 1 { colors.append(colors[0]) }
    func point(_ key: String) -> CGPoint {
      let xy = spec[key] as? [Any] ?? []
      return CGPoint(
        x: xy.count > 0 ? dnnNumber(xy[0]) ?? 0 : 0,
        y: xy.count > 1 ? dnnNumber(xy[1]) ?? 0 : 0)
    }
    var stops = (spec["stops"] as? [Any])?.map { dnnNumber($0) ?? 0 }
    if stops?.count != colors.count {
      // Evenly spaced when no stops are said, as in Flutter.
      stops = colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
    }
    guard
      let made = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors.map { $0.cgColor } as CFArray, locations: stops)
    else { return nil }
    gradient = made
    radial = spec["type"] as? String == "radial"
    sweep =
      spec["type"] as? String == "sweep"
      ? (colors, stops ?? [], dnnNumber(spec["angle"]) ?? 0) : nil
    if sweep != nil {
      radius = 0
      from = point("center")
      to = from
    } else if radial {
      radius = dnnNumber(spec["radius"]) ?? 0
      guard radius > 0 else { return nil }
      from = point("center")
      to = from
    } else {
      radius = 0
      from = point("from")
      to = point("to")
    }
  }

  /// Fills the context's clip with the gradient, held at its end colours
  /// beyond its ends.
  func draw(in context: CGContext) {
    let beyond: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    if let sweep = sweep {
      drawSweep(sweep.colors, sweep.stops, from: sweep.angle, in: context)
    } else if radial {
      context.drawRadialGradient(
        gradient, startCenter: from, startRadius: 0, endCenter: from, endRadius: radius,
        options: beyond)
    } else {
      context.drawLinearGradient(gradient, start: from, end: to, options: beyond)
    }
  }
}

extension DnnPaintGradient {
  /// A sweep as thin wedges about the centre, each the colour the turn has
  /// reached - half a degree wide, which is past what an eye picks out.
  fileprivate func drawSweep(
    _ colors: [UIColor], _ stops: [CGFloat], from angle: CGFloat, in context: CGContext
  ) {
    let clip = context.boundingBoxOfClipPath
    guard !clip.isEmpty, !clip.isInfinite else { return }
    // Far enough to pass every corner of what is being filled.
    let reach =
      [
        CGPoint(x: clip.minX, y: clip.minY), CGPoint(x: clip.maxX, y: clip.minY),
        CGPoint(x: clip.minX, y: clip.maxY), CGPoint(x: clip.maxX, y: clip.maxY),
      ].map { hypot($0.x - from.x, $0.y - from.y) }.max() ?? 0
    guard reach > 0 else { return }
    let parts = colors.map { color -> [CGFloat] in
      var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
      color.getRed(&r, green: &g, blue: &b, alpha: &a)
      return [r, g, b, a]
    }
    func colour(at turn: CGFloat) -> CGColor {
      var index = 0
      while index < stops.count - 1 && turn > stops[index + 1] { index += 1 }
      let next = min(index + 1, parts.count - 1)
      let span = stops[next] - stops[index]
      let t = span > 0 ? min(max((turn - stops[index]) / span, 0), 1) : (turn < stops[index] ? 0 : 1)
      let mixed = (0..<4).map { parts[index][$0] + (parts[next][$0] - parts[index][$0]) * t }
      return UIColor(red: mixed[0], green: mixed[1], blue: mixed[2], alpha: mixed[3]).cgColor
    }
    let wedges = 720
    let step = 2 * CGFloat.pi / CGFloat(wedges)
    context.saveGState()
    // Wedges that meet edge to edge show a hair of what is behind when they
    // are smoothed; each is drawn hard and a touch wider than its share.
    context.setShouldAntialias(false)
    for wedge in 0..<wedges {
      let start = angle + CGFloat(wedge) * step
      let end = start + step * 1.5
      context.move(to: from)
      context.addLine(to: CGPoint(x: from.x + reach * cos(start), y: from.y + reach * sin(start)))
      context.addLine(to: CGPoint(x: from.x + reach * cos(end), y: from.y + reach * sin(end)))
      context.closePath()
      context.setFillColor(colour(at: (CGFloat(wedge) + 0.5) / CGFloat(wedges)))
      context.fillPath()
    }
    context.restoreGState()
  }
}

struct DnnPaint {
  /// A blur's sigma; zero for none.
  var blur: CGFloat = 0
  var gradient: DnnPaintGradient?
  /// How what it draws is laid over what is there.
  var blend: CGBlendMode = .normal
  var color = UIColor.black
  var stroke = false
  var width: CGFloat = 0
  var cap = CGLineCap.butt
  var join = CGLineJoin.miter
}

/**
 Replays a canvas's command list into Core Graphics.

 Coordinates are points from the top left with y down, which is what a UIKit
 drawing context already is. Angles are radians clockwise from three o'clock:
 in a y-down space that is simply the angle increasing, which Core Graphics
 calls `clockwise: false` (its names assume y up).
 */
final class DnnCanvasDrawingView: UIView {
  private var commands: [Any] = []
  private var paints: [DnnPaint] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  private func setUp() {
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
    // A new size is a new picture, not the old one stretched.
    contentMode = .redraw
  }

  func set(commands: [Any], paints: [Any]) {
    self.commands = commands
    self.paints = paints.map { (raw: Any) -> DnnPaint in
      var paint = DnnPaint()
      guard let map = raw as? [String: Any] else { return paint }
      paint.color = dnnColor(map["color"]) ?? .black
      paint.gradient = DnnPaintGradient(map["gradient"])
      paint.blur = max(0, dnnNumber(map["blur"]) ?? 0)
      paint.blend = dnnBlendMode(map["blend"] as? String)
      paint.stroke = (map["style"] as? String) == "stroke"
      paint.width = dnnNumber(map["strokeWidth"]) ?? 0
      switch map["cap"] as? String {
      case "round": paint.cap = .round
      case "square": paint.cap = .square
      default: paint.cap = .butt
      }
      switch map["join"] as? String {
      case "round": paint.join = .round
      case "bevel": paint.join = .bevel
      default: paint.join = .miter
      }
      return paint
    }
    setNeedsDisplay()
  }

  private func item(_ list: [Any], _ index: Int) -> Any? {
    index >= 0 && index < list.count ? list[index] : nil
  }

  private func num(_ list: [Any], _ index: Int) -> CGFloat {
    let parsed = dnnNumber(item(list, index)) ?? 0
    return parsed.isFinite ? parsed : 0
  }

  private func rect(_ list: [Any], _ index: Int) -> CGRect {
    CGRect(
      x: num(list, index), y: num(list, index + 1), width: num(list, index + 2),
      height: num(list, index + 3)
    ).standardized
  }

  private func paint(_ list: [Any], _ index: Int) -> DnnPaint {
    guard let boxed = item(list, index) as? NSNumber else { return DnnPaint() }
    let position = boxed.intValue
    return position >= 0 && position < paints.count ? paints[position] : DnnPaint()
  }

  private func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // Core Graphics traps on a corner wider than half the rectangle.
    let corner = max(0, min(radius, min(rect.width, rect.height) / 2))
    if corner > 0 {
      path.addRoundedRect(in: rect, cornerWidth: corner, cornerHeight: corner)
    } else {
      path.addRect(rect)
    }
    return path
  }

  /// Adds the arc of the oval in [rect] from [start] over [sweep], joined to
  /// whatever the path already holds with a line.
  private func addArc(
    _ path: CGMutablePath, _ rect: CGRect, _ start: CGFloat, _ sweep: CGFloat
  ) {
    guard rect.width > 0, rect.height > 0 else { return }
    // A unit circle scaled to the oval, then moved to its centre.
    let toOval = CGAffineTransform(translationX: rect.midX, y: rect.midY)
      .scaledBy(x: rect.width / 2, y: rect.height / 2)
    path.addArc(
      center: .zero, radius: 1, startAngle: start, endAngle: start + sweep,
      clockwise: sweep < 0, transform: toOval)
  }

  private func fillOrStroke(
    _ context: CGContext, _ path: CGPath, _ paint: DnnPaint, strokeOnly: Bool = false,
    evenOdd: Bool = false
  ) {
    let rule: CGPathFillRule = evenOdd ? .evenOdd : .winding
    // In the paint's blend, and back to the plain one after.
    context.setBlendMode(paint.blend)
    defer { context.setBlendMode(.normal) }
    context.addPath(path)
    let stroked = paint.stroke || strokeOnly
    if stroked {
      context.setStrokeColor(paint.color.cgColor)
      // A width of zero is a hairline, as it is in Flutter.
      let hairline = 1 / max(contentScaleFactor, 1)
      context.setLineWidth(paint.width > 0 ? paint.width : hairline)
      context.setLineCap(paint.cap)
      context.setLineJoin(paint.join)
    }
    if let gradient = paint.gradient, paint.blur > 0 {
      // A shadow is one colour, so a blurred gradient is drawn into a
      // picture of its own, blurred there and laid back where it belongs.
      context.beginPath()
      blurredGradient(context, stroked ? strokedCopy(path, paint) : path, gradient,
        paint.blur, rule: stroked ? .winding : rule)
    } else if let gradient = paint.gradient {
      // Core Graphics paints a gradient over a region rather than with it:
      // the shape - or the outline of its stroke - becomes the clip, and the
      // gradient is drawn through that.
      context.saveGState()
      if stroked { context.replacePathWithStrokedPath() }
      context.clip(using: stroked ? .winding : rule)
      gradient.draw(in: context)
      context.restoreGState()
    } else if paint.blur > 0 {
      // Core Graphics blurs nothing but a shadow. So the shape is drawn far
      // off to one side, where it cannot be seen, and its shadow - in the
      // shape's own colour - is thrown back to where the shape belongs.
      let far: CGFloat = 20000
      let scale = max(contentScaleFactor, 1)
      // A shadow's offset is counted on the screen, whatever the commands
      // have turned or scaled; the shape is moved by what that comes to in
      // the space it is drawn in.
      let away = CGSize(width: -far * scale, height: 0).applying(
        context.userSpaceToDeviceSpaceTransform.inverted().linear)
      let outline = stroked ? strokedCopy(path, paint) : path
      context.beginPath()
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: far, height: 0), blur: paint.blur * 2,
        color: paint.color.cgColor)
      context.translateBy(x: away.width, y: away.height)
      context.addPath(outline)
      context.setFillColor(paint.color.cgColor)
      context.fillPath(using: stroked ? .winding : rule)
      context.restoreGState()
    } else if stroked {
      context.strokePath()
    } else {
      context.setFillColor(paint.color.cgColor)
      context.fillPath(using: rule)
    }
  }

  /// One Core Image context for every blurred gradient: making one is slow.
  private static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

  /// [gradient] drawn through [outline], blurred by [sigma]: drawn into a
  /// picture of the shape's bounds and the blur's reach, at the pixels the
  /// screen has there, blurred, and drawn back over the same place.
  private func blurredGradient(
    _ context: CGContext, _ outline: CGPath, _ gradient: DnnPaintGradient, _ sigma: CGFloat,
    rule: CGPathFillRule
  ) {
    let bounds = outline.boundingBoxOfPath.insetBy(dx: -sigma * 3, dy: -sigma * 3)
    guard bounds.width > 0, bounds.height > 0, bounds.width < 10000, bounds.height < 10000
    else { return }
    let device = context.userSpaceToDeviceSpaceTransform
    let scale = max(sqrt(abs(device.a * device.d - device.b * device.c)), 1)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    let sharp = UIGraphicsImageRenderer(size: bounds.size, format: format).image { drawn in
      let inner = drawn.cgContext
      inner.translateBy(x: -bounds.minX, y: -bounds.minY)
      inner.addPath(outline)
      inner.clip(using: rule)
      gradient.draw(in: inner)
    }
    guard let input = sharp.cgImage.map({ CIImage(cgImage: $0) }),
      let filter = CIFilter(name: "CIGaussianBlur")
    else { return }
    // Clamped first, so the blur does not fade in from the picture's edges.
    filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(sigma * scale, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage?.cropped(to: input.extent),
      let blurred = Self.blurContext.createCGImage(output, from: input.extent)
    else { return }
    UIGraphicsPushContext(context)
    UIImage(cgImage: blurred, scale: scale, orientation: .up).draw(in: bounds)
    UIGraphicsPopContext()
  }

  /// The outline of [path] stroked the way [paint] says, as a shape to fill.
  private func strokedCopy(_ path: CGPath, _ paint: DnnPaint) -> CGPath {
    let hairline = 1 / max(contentScaleFactor, 1)
    return path.copy(
      strokingWithWidth: paint.width > 0 ? paint.width : hairline, lineCap: paint.cap,
      lineJoin: paint.join, miterLimit: 10)
  }

  private func segmentPath(_ segments: [Any]) -> CGPath {
    let path = CGMutablePath()
    for raw in segments {
      guard let segment = raw as? [Any], let name = segment.first as? String else { continue }
      switch name {
      case "M":
        path.move(to: CGPoint(x: num(segment, 1), y: num(segment, 2)))
      case "L":
        let point = CGPoint(x: num(segment, 1), y: num(segment, 2))
        if path.isEmpty { path.move(to: point) } else { path.addLine(to: point) }
      case "Q":
        if path.isEmpty { path.move(to: CGPoint(x: num(segment, 1), y: num(segment, 2))) }
        path.addQuadCurve(
          to: CGPoint(x: num(segment, 3), y: num(segment, 4)),
          control: CGPoint(x: num(segment, 1), y: num(segment, 2)))
      case "C":
        if path.isEmpty { path.move(to: CGPoint(x: num(segment, 1), y: num(segment, 2))) }
        path.addCurve(
          to: CGPoint(x: num(segment, 5), y: num(segment, 6)),
          control1: CGPoint(x: num(segment, 1), y: num(segment, 2)),
          control2: CGPoint(x: num(segment, 3), y: num(segment, 4)))
      case "A":
        addArc(path, rect(segment, 1), num(segment, 5), num(segment, 6))
      case "R":
        path.addRect(rect(segment, 1))
      case "O":
        path.addEllipse(in: rect(segment, 1))
      case "Z":
        if !path.isEmpty { path.closeSubpath() }
      default:
        break
      }
    }
    return path
  }

  private func drawText(_ command: [Any]) {
    guard let string = item(command, 1) as? String else { return }
    let x = num(command, 2)
    let y = num(command, 3)
    let options = item(command, 4) as? [String: Any] ?? [:]
    let font = dnnFont(
      size: dnnNumber(options["size"]) ?? 14,
      weight: dnnNumber(options["weight"]) ?? 400,
      family: options["family"] as? String,
      italic: false)
    let align = options["align"] as? String ?? "left"
    let paragraph = NSMutableParagraphStyle()
    switch align {
    case "center": paragraph.alignment = .center
    case "right": paragraph.alignment = .right
    default: paragraph.alignment = .left
    }
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: dnnColor(options["color"]) ?? UIColor.black,
      .paragraphStyle: paragraph,
    ]
    // Room after each letter, where the paint said.
    if let spacing = dnnNumber(options["letterSpacing"]) {
      attributes[.kern] = NSNumber(value: Double(spacing))
    }
    let text = NSAttributedString(string: string, attributes: attributes)
    if let maxWidth = dnnNumber(options["maxWidth"]), maxWidth > 0, maxWidth.isFinite {
      // Aligned within the width it was given.
      // A text already broken into lines (`wrap: false`) is not broken
      // again: a box narrower than the glyphs is widened about its
      // alignment instead.
      var left = x
      var width = maxWidth
      if options["wrap"] as? Bool == false {
        let natural = ceil(
          text.boundingRect(
            with: CGSize(width: 100_000, height: 100_000),
            options: [.usesLineFragmentOrigin], context: nil
          ).width)
        if natural > maxWidth {
          let extra = natural - maxWidth
          left -= align == "center" ? extra / 2 : align == "right" ? extra : 0
          width = natural
        }
      }
      text.draw(
        with: CGRect(x: left, y: y, width: width, height: 100_000),
        options: [.usesLineFragmentOrigin], context: nil)
      return
    }
    // Aligned about x.
    let width = text.size().width
    var left = x
    if align == "center" {
      left = x - width / 2
    } else if align == "right" {
      left = x - width
    }
    text.draw(at: CGPoint(x: left, y: y))
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    var saves = 0
    // The depth each open layer was begun at, innermost last.
    var layers: [Int] = []
    for raw in commands {
      guard let command = raw as? [Any], let name = command.first as? String else { continue }
      switch name {
      case "rect":
        let path = CGMutablePath()
        path.addRect(self.rect(command, 1))
        fillOrStroke(context, path, paint(command, 5))
      case "rrect":
        fillOrStroke(
          context, roundedRect(self.rect(command, 1), num(command, 5)), paint(command, 6))
      case "circle":
        let radius = abs(num(command, 3))
        let path = CGMutablePath()
        path.addEllipse(
          in: CGRect(
            x: num(command, 1) - radius, y: num(command, 2) - radius, width: radius * 2,
            height: radius * 2))
        fillOrStroke(context, path, paint(command, 4))
      case "oval":
        let path = CGMutablePath()
        path.addEllipse(in: self.rect(command, 1))
        fillOrStroke(context, path, paint(command, 5))
      case "line":
        let path = CGMutablePath()
        path.move(to: CGPoint(x: num(command, 1), y: num(command, 2)))
        path.addLine(to: CGPoint(x: num(command, 3), y: num(command, 4)))
        // A line has no inside to fill.
        fillOrStroke(context, path, paint(command, 5), strokeOnly: true)
      case "arc":
        let oval = self.rect(command, 1)
        let start = num(command, 5)
        let sweep = num(command, 6)
        let useCenter = (item(command, 7) as? Bool) ?? false
        let path = CGMutablePath()
        if abs(sweep) >= CGFloat.pi * 2 - 0.0001 {
          path.addEllipse(in: oval)
        } else {
          if useCenter { path.move(to: CGPoint(x: oval.midX, y: oval.midY)) }
          addArc(path, oval, start, sweep)
          if useCenter, !path.isEmpty { path.closeSubpath() }
        }
        fillOrStroke(context, path, paint(command, 8))
      case "path":
        let segments = item(command, 1) as? [Any] ?? []
        fillOrStroke(
          context, segmentPath(segments), paint(command, 2),
          evenOdd: item(command, 3) as? String == "evenOdd")
      case "text":
        drawText(command)
      case "save":
        context.saveGState()
        saves += 1
      case "saveLayer":
        // Drawn on its own until the matching restore, then laid over the
        // canvas at the paint's opacity and in its blend.
        context.saveGState()
        saves += 1
        context.setAlpha(min(max(num(command, 1), 0), 1))
        context.setBlendMode(dnnBlendMode(item(command, 2) as? String))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        layers.append(saves)
      case "restore":
        // An unmatched restore would pop UIKit's own state.
        if saves > 0 {
          if layers.last == saves {
            layers.removeLast()
            context.endTransparencyLayer()
          }
          context.restoreGState()
          saves -= 1
        }
      case "translate":
        context.translateBy(x: num(command, 1), y: num(command, 2))
      case "rotate":
        context.rotate(by: num(command, 1))
      case "scale":
        let sx = num(command, 1)
        context.scaleBy(x: sx, y: command.count > 2 ? num(command, 2) : sx)
      case "clipRect":
        context.clip(to: self.rect(command, 1))
      case "clipRRect":
        context.addPath(roundedRect(self.rect(command, 1), num(command, 5)))
        context.clip()
      case "clipPath":
        let outline = segmentPath(item(command, 1) as? [Any] ?? [])
        // Clipping to no path at all is an error to Core Graphics; what it
        // means is that nothing is left to draw in.
        if outline.isEmpty {
          context.clip(to: .zero)
        } else {
          context.addPath(outline)
          context.clip(using: item(command, 2) as? String == "evenOdd" ? .evenOdd : .winding)
        }
      default:
        break
      }
    }
    while saves > 0 {
      if layers.last == saves {
        layers.removeLast()
        context.endTransparencyLayer()
      }
      context.restoreGState()
      saves -= 1
    }
  }
}

/// A `Canvas`: a box's sizing and touch, with the drawing behind its child.
final class DnnCanvasView: DnnBoxView {
  let drawing = DnnCanvasDrawingView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    installDrawing()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    installDrawing()
  }

  private func installDrawing() {
    drawing.frame = surface.bounds
    drawing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    surface.insertSubview(drawing, at: 0)
  }
}

// MARK: - Stack and Positioned

/// A `Positioned`: its child, pinned to the edges of the stack it sits in.
final class DnnPositionedView: UIView, DnnSingleChildHost {
  private var pinLeft: CGFloat?
  private var pinTop: CGFloat?
  private var pinRight: CGFloat?
  private var pinBottom: CGFloat?
  private var pinWidth: CGFloat?
  private var pinHeight: CGFloat?
  private var edgeConstraints: [NSLayoutConstraint] = []

  var hostedChild: UIView? { subviews.first }

  func replaceChild(_ view: UIView?) {
    subviews.forEach { $0.removeFromSuperview() }
    guard let view = view else { return }
    view.translatesAutoresizingMaskIntoConstraints = false
    addSubview(view)
    NSLayoutConstraint.activate([
      view.leftAnchor.constraint(equalTo: leftAnchor),
      view.topAnchor.constraint(equalTo: topAnchor),
      view.rightAnchor.constraint(equalTo: rightAnchor),
      view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  func setPosition(
    left: CGFloat?, top: CGFloat?, right: CGFloat?, bottom: CGFloat?, width: CGFloat?,
    height: CGFloat?
  ) {
    pinLeft = left
    pinTop = top
    pinRight = right
    pinBottom = bottom
    pinWidth = width
    pinHeight = height
    attach()
  }

  /// Pins this view inside the stack holding it; outside a stack it is just
  /// its child.
  private func attach() {
    NSLayoutConstraint.deactivate(edgeConstraints)
    edgeConstraints = []
    guard let stack = superview as? DnnStackView else { return }
    var next: [NSLayoutConstraint] = []
    if let left = pinLeft {
      next.append(leftAnchor.constraint(equalTo: stack.leftAnchor, constant: left))
    }
    if let right = pinRight {
      next.append(stack.rightAnchor.constraint(equalTo: rightAnchor, constant: right))
    }
    if pinLeft == nil && pinRight == nil {
      next.append(stack.horizontalAlignment(for: self))
    }
    if let top = pinTop {
      next.append(topAnchor.constraint(equalTo: stack.topAnchor, constant: top))
    }
    if let bottom = pinBottom {
      next.append(stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottom))
    }
    if pinTop == nil && pinBottom == nil {
      next.append(stack.verticalAlignment(for: self))
    }
    if let width = pinWidth {
      next.append(widthAnchor.constraint(equalToConstant: max(0, width)))
    }
    if let height = pinHeight {
      next.append(heightAnchor.constraint(equalToConstant: max(0, height)))
    }
    edgeConstraints = next
    NSLayoutConstraint.activate(next)
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    attach()
  }
}

/**
 A `Stack`: children over one another, first at the back.

 A `DnnPositionedView` child pins itself; every other child sits at the
 stack's alignment and is what the stack sizes itself to. A stack with nothing
 but positioned children has nothing to size itself to, so it asks for the room
 it is in - which is what Flutter's does.
 */
final class DnnStackView: UIView {
  private var alignment = CGPoint(x: -1, y: -1)
  private var fitExpand = false
  private var fillConstraints: [NSLayoutConstraint] = []

  func configure(alignment: CGPoint, expand: Bool, clip: Bool) {
    self.alignment = alignment
    fitExpand = expand
    clipsToBounds = clip
  }

  func horizontalAlignment(for view: UIView) -> NSLayoutConstraint {
    if alignment.x < -0.33 { return view.leftAnchor.constraint(equalTo: leftAnchor) }
    if alignment.x > 0.33 { return view.rightAnchor.constraint(equalTo: rightAnchor) }
    return view.centerXAnchor.constraint(equalTo: centerXAnchor)
  }

  func verticalAlignment(for view: UIView) -> NSLayoutConstraint {
    if alignment.y < -0.33 { return view.topAnchor.constraint(equalTo: topAnchor) }
    if alignment.y > 0.33 { return view.bottomAnchor.constraint(equalTo: bottomAnchor) }
    return view.centerYAnchor.constraint(equalTo: centerYAnchor)
  }

  /// Adds a child at [index] among the layers, or on top when it is nil.
  func addLayer(_ view: UIView, at index: Int?) {
    view.translatesAutoresizingMaskIntoConstraints = false
    if let index = index, index < subviews.count {
      insertSubview(view, at: index)
    } else {
      addSubview(view)
    }
    // A positioned child pins itself as it arrives - see `didMoveToSuperview`.
    if view is DnnPositionedView { return }

    if fitExpand {
      NSLayoutConstraint.activate([
        view.leftAnchor.constraint(equalTo: leftAnchor),
        view.topAnchor.constraint(equalTo: topAnchor),
        view.rightAnchor.constraint(equalTo: rightAnchor),
        view.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
      return
    }

    // Inside the stack, at its alignment, and - weakly - the size of it.
    let insideRight = rightAnchor.constraint(greaterThanOrEqualTo: view.rightAnchor)
    insideRight.priority = UILayoutPriority(999)
    let insideBottom = bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor)
    insideBottom.priority = UILayoutPriority(999)
    let insideLeft = view.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor)
    insideLeft.priority = UILayoutPriority(999)
    let insideTop = view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor)
    insideTop.priority = UILayoutPriority(999)
    let hugWidth = widthAnchor.constraint(equalTo: view.widthAnchor)
    hugWidth.priority = UILayoutPriority(100)
    let hugHeight = heightAnchor.constraint(equalTo: view.heightAnchor)
    hugHeight.priority = UILayoutPriority(100)
    NSLayoutConstraint.activate([
      insideLeft, insideTop, insideRight, insideBottom,
      horizontalAlignment(for: view), verticalAlignment(for: view),
      hugWidth, hugHeight,
    ])
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    NSLayoutConstraint.deactivate(fillConstraints)
    fillConstraints = []
    guard let parent = superview else { return }
    let sizedByChild = subviews.contains { !($0 is DnnPositionedView) }
    if sizedByChild { return }
    fillConstraints = [
      dnnFill(self, parent, horizontal: true),
      dnnFill(self, parent, horizontal: false),
    ]
    NSLayoutConstraint.activate(fillConstraints)
  }
}

// MARK: - Scroll

/**
 A `Scroll`: one child, scrolled along one axis.

 The child is pinned to the content guide with the padding as its insets, and
 to the frame guide across the axis, so it is exactly as wide as a vertical
 scroller (or as tall as a horizontal one) and as long as it likes.
 */
final class DnnScrollView: UIScrollView, DnnSingleChildHost {
  private var horizontal = false
  private var padding = UIEdgeInsets.zero
  private var shrinkWrap = false
  private var reverse = false

  /// The offset to scroll to once there is content to scroll; nil after that.
  var restoreOffset: CGFloat?
  /// The `scrollVersion` this view last obeyed.
  var appliedScrollVersion: Int?
  /// Where the view is scrolled to, along its axis, whenever that changes.
  var onScrolled: ((CGFloat) -> Void)?
  var onRefresh: (() -> Void)?

  /// For the app: the offset (from the far end when reversed), how far it can
  /// go and the view's own length along its axis - when the view comes to
  /// rest, and at most every 100 ms on the way. Scrolling lays the view out
  /// once a frame, and a message per frame across the channel (and a rebuild
  /// per frame, for an app that listens) is what this is here to avoid.
  var onReport: ((CGFloat, CGFloat, CGFloat) -> Void)?
  /// Told where the view is (from the far end when reversed) each frame it
  /// moves, for what moves in step with it.
  var onFollow: ((CGFloat) -> Void)?
  private var reportedOffset: CGFloat = -1
  private var reportedAt: CFTimeInterval = 0
  private var seenOffset: CGFloat = -1
  private var settleWork: DispatchWorkItem?

  private func report() {
    guard let onReport = onReport, window != nil else { return }
    let viewport = horizontal ? bounds.width : bounds.height
    let extent = horizontal ? contentSize.width : contentSize.height
    let maxOffset = max(0, extent - viewport)
    // A bounce past either end is not a position.
    let raw = min(max(0, horizontal ? contentOffset.x : contentOffset.y), maxOffset)
    let offset = reverse ? maxOffset - raw : raw
    if abs(offset - reportedOffset) < 0.5 { return }
    reportedOffset = offset
    reportedAt = CACurrentMediaTime()
    onReport(offset, maxOffset, viewport)
  }

  private func moved() {
    if let onFollow {
      let viewport = horizontal ? bounds.width : bounds.height
      let extent = horizontal ? contentSize.width : contentSize.height
      let maxOffset = max(0, extent - viewport)
      let raw = min(max(0, horizontal ? contentOffset.x : contentOffset.y), maxOffset)
      onFollow(reverse ? maxOffset - raw : raw)
    }
    guard onReport != nil else { return }
    settleWork?.cancel()
    if CACurrentMediaTime() - reportedAt >= 0.1 { report() }
    // Nothing for a little longer than that: it has stopped.
    let work = DispatchWorkItem { [weak self] in self?.report() }
    settleWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
  }

  private weak var child: UIView?
  private var childConstraints: [NSLayoutConstraint] = []

  /// How long the content was when it was last laid out: the length the
  /// scroller takes where nothing else gives it one.
  private var fitted = UIView.noIntrinsicMetric

  /// As long as its content, as a wish that is easily overruled - by any
  /// height it is given, and by content longer than the room there is,
  /// which is what scrolling is for. Unlike a constraint between the two it
  /// asks nothing of the content.
  override var intrinsicContentSize: CGSize {
    if shrinkWrap { return super.intrinsicContentSize }
    return horizontal
      ? CGSize(width: fitted, height: UIView.noIntrinsicMetric)
      : CGSize(width: UIView.noIntrinsicMetric, height: fitted)
  }

  private func noteFitted() {
    let length = horizontal ? contentSize.width : contentSize.height
    guard !shrinkWrap, length > 0, abs(length - fitted) > 0.5 else { return }
    fitted = length
    invalidateIntrinsicContentSize()
  }

  private var settled = false
  private var wasAtEnd = true
  private var lastExtent: CGFloat = -1

  var hostedChild: UIView? { child }

  override init(frame: CGRect) {
    super.init(frame: frame)
    // The scaffold has already kept the content clear of the system insets.
    contentInsetAdjustmentBehavior = .never
    setNaturalLength()
  }

  /// How firmly the scroller holds to its content's length: barely, either
  /// way. Shorter than its content is every scroller on a full page.
  private func setNaturalLength() {
    for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
      setContentHuggingPriority(UILayoutPriority(50), for: axis)
      setContentCompressionResistancePriority(UILayoutPriority(1), for: axis)
    }
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    contentInsetAdjustmentBehavior = .never
  }

  func configure(horizontal: Bool, padding: UIEdgeInsets, shrinkWrap: Bool, reverse: Bool) {
    let changed =
      horizontal != self.horizontal || padding != self.padding
      || shrinkWrap != self.shrinkWrap
    self.horizontal = horizontal
    self.padding = padding
    self.shrinkWrap = shrinkWrap
    self.reverse = reverse
    // A scroller as long as its child has nowhere to scroll to.
    isScrollEnabled = !shrinkWrap
    if changed { rebuildConstraints() }
  }

  func replaceChild(_ view: UIView?) {
    child?.removeFromSuperview()
    child = view
    if let view = view {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    rebuildConstraints()
  }

  private func rebuildConstraints() {
    NSLayoutConstraint.deactivate(childConstraints)
    childConstraints = []
    guard let view = child else { return }
    let contentGuide = contentLayoutGuide
    let frameGuide = frameLayoutGuide
    var next: [NSLayoutConstraint] = [
      view.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: padding.top),
      contentGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: padding.bottom),
      view.leftAnchor.constraint(equalTo: contentGuide.leftAnchor, constant: padding.left),
      contentGuide.rightAnchor.constraint(equalTo: view.rightAnchor, constant: padding.right),
    ]
    // Across the axis the content is as wide (or tall) as the scroller.
    if horizontal {
      next.append(
        view.heightAnchor.constraint(
          equalTo: frameGuide.heightAnchor, constant: -(padding.top + padding.bottom)))
    } else {
      next.append(
        view.widthAnchor.constraint(
          equalTo: frameGuide.widthAnchor, constant: -(padding.left + padding.right)))
    }
    // Along it, a scroller asked to be as long as its content (`shrinkWrap`)
    // is tied to it. One that was not is only *naturally* that long - see
    // `intrinsicContentSize` - because a constraint works both ways: on a
    // page taller than a short list it was met by stretching the list, and
    // however weak it was made, something in a row was weaker.
    if shrinkWrap {
      let along =
        horizontal
        ? frameGuide.widthAnchor.constraint(equalTo: contentGuide.widthAnchor)
        : frameGuide.heightAnchor.constraint(equalTo: contentGuide.heightAnchor)
      along.priority = UILayoutPriority(999)
      next.append(along)
    }
    fitted = UIView.noIntrinsicMetric
    invalidateIntrinsicContentSize()
    childConstraints = next
    NSLayoutConstraint.activate(next)
  }

  private func setOffset(
    _ value: CGFloat, animated: Bool = false, seconds: TimeInterval = 0,
    points: (CGPoint, CGPoint)? = nil
  ) {
    let target = horizontal ? CGPoint(x: value, y: 0) : CGPoint(x: 0, y: value)
    DnnScrollTravel.stop(self)
    guard contentOffset != target else { return }
    if animated && seconds > 0 {
      DnnScrollTravel.go(self, to: target, seconds: seconds, points: points)
    } else {
      setContentOffset(target, animated: animated)
    }
  }

  /// Scrolls to [offset] now, or as soon as there is content to scroll -
  /// travelling there when [animated], if there is somewhere to travel from.
  func jump(
    to offset: CGFloat, animated: Bool = false, seconds: TimeInterval = 0,
    points: (CGPoint, CGPoint)? = nil
  ) {
    if settled {
      let viewport = horizontal ? bounds.width : bounds.height
      let extent = horizontal ? contentSize.width : contentSize.height
      let maxOffset = max(0, extent - viewport)
      // Reversed, an offset counts from the far end - as it does on the
      // other renderers, and as `onReport` says it.
      let held = min(max(0, offset), maxOffset)
      setOffset(
        reverse ? maxOffset - held : held, animated: animated, seconds: seconds, points: points)
    } else {
      pendingJump = offset
    }
  }

  /// An offset the app asked for before there was content to scroll, counted
  /// the way `jump(to:)` counts it; `restoreOffset` is the view's own.
  private var pendingJump: CGFloat?

  override func layoutSubviews() {
    super.layoutSubviews()
    noteFitted()
    let viewport = horizontal ? bounds.width : bounds.height
    let extent = horizontal ? contentSize.width : contentSize.height
    guard viewport > 0, extent > 0 else { return }
    let maxOffset = max(0, extent - viewport)

    if let asked = pendingJump {
      pendingJump = nil
      restoreOffset = nil
      let held = min(max(0, asked), maxOffset)
      setOffset(reverse ? maxOffset - held : held)
    } else if let restore = restoreOffset {
      restoreOffset = nil
      setOffset(min(max(0, restore), maxOffset))
    } else if reverse, !settled || (abs(extent - lastExtent) > 0.5 && wasAtEnd) {
      // A reversed scroller starts at its end, and stays there as it grows.
      setOffset(maxOffset)
    }
    settled = true
    lastExtent = extent

    let offset = horizontal ? contentOffset.x : contentOffset.y
    wasAtEnd = offset >= maxOffset - 1
    // A bounce past either end is not a position.
    onScrolled?(min(max(0, offset), maxOffset))
    // Laid out for other reasons too; only a move is worth a report.
    if abs(offset - seenOffset) >= 0.5 {
      seenOffset = offset
      moved()
    }
  }

  // MARK: Pull to refresh

  func setRefresh(enabled: Bool, tint: UIColor?) {
    if enabled {
      if refreshControl == nil {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        refreshControl = control
        alwaysBounceVertical = true
      }
      refreshControl?.tintColor = tint
    } else if refreshControl != nil {
      refreshControl = nil
    }
  }

  @objc private func refreshPulled() {
    onRefresh?()
  }

  /// The tree is the one that says how long the spinner stays.
  func setRefreshing(_ refreshing: Bool) {
    guard let control = refreshControl else { return }
    if refreshing {
      if !control.isRefreshing { control.beginRefreshing() }
    } else if control.isRefreshing {
      control.endRefreshing()
    }
  }
}

// MARK: - FlutterSlot and the root container

/**
 A `FlutterSlot`: an empty region of a stated size.

 It draws nothing. The root container cuts a hole where it sits, so the Flutter
 view underneath shows through and takes the touches, and `onMoved` tells the
 renderer whenever the hole may have moved - when the slot is laid out, and
 when any scroll view above it scrolls.
 */
final class DnnFlutterSlotView: UIView {
  var slotId = ""
  var onMoved: (() -> Void)?

  private var observations: [NSKeyValueObservation] = []
  private var heightConstraint: NSLayoutConstraint?
  private var widthConstraint: NSLayoutConstraint?
  private var fillConstraint: NSLayoutConstraint?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  deinit {
    observations.forEach { $0.invalidate() }
  }

  func setSize(width: CGFloat?, height: CGFloat) {
    if let constraint = heightConstraint {
      constraint.constant = max(0, height)
    } else {
      let constraint = heightAnchor.constraint(equalToConstant: max(0, height))
      constraint.priority = UILayoutPriority(999)
      constraint.isActive = true
      heightConstraint = constraint
    }
    widthConstraint?.isActive = false
    widthConstraint = nil
    if let width = width {
      let constraint = widthAnchor.constraint(equalToConstant: max(0, width))
      constraint.priority = UILayoutPriority(999)
      constraint.isActive = true
      widthConstraint = constraint
    }
    applyFill()
  }

  /// Without a width of its own, a slot is as wide as what holds it.
  private func applyFill() {
    fillConstraint?.isActive = false
    fillConstraint = nil
    guard widthConstraint == nil, let parent = superview else { return }
    let constraint = dnnFill(self, parent, horizontal: true)
    constraint.isActive = true
    fillConstraint = constraint
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    applyFill()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    observeScrollers()
    onMoved?()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onMoved?()
  }

  /// Watches every scroll view above the slot, since scrolling moves the slot
  /// on screen without laying anything out.
  private func observeScrollers() {
    observations.forEach { $0.invalidate() }
    observations = []
    guard window != nil else { return }
    var current = superview
    while let view = current {
      if let scroll = view as? UIScrollView {
        let observation = scroll.observe(\.contentOffset, options: [.new]) {
          [weak self] _, _ in
          self?.onMoved?()
        }
        observations.append(observation)
      }
      current = view.superview
    }
  }
}

/**
 The view everything the renderer draws lives in.

 It sits over the Flutter view. Where a `FlutterSlot` is showing it has a hole:
 the layer is masked so nothing is drawn there, and a touch there is answered
 with nil so it falls through to the Flutter view underneath.
 */
final class DnnRootContainerView: UIView {
  /// The container was laid out, or its safe area moved.
  var onLayout: (() -> Void)?

  private var holes: [CGRect] = []
  private var holeMask: CAShapeLayer?
  private var maskedBounds = CGRect.null

  /// The rectangles to leave open, in this view's own coordinates.
  func setHoles(_ rects: [CGRect]) {
    if rects == holes && (rects.isEmpty || maskedBounds == bounds) { return }
    holes = rects
    applyMask()
  }

  private func applyMask() {
    guard !holes.isEmpty else {
      // No slots, no mask: a mask costs an offscreen pass on every frame.
      layer.mask = nil
      holeMask = nil
      maskedBounds = CGRect.null
      return
    }
    let mask = holeMask ?? CAShapeLayer()
    // Even-odd: the bounds are filled, and each hole inside them is not.
    let path = UIBezierPath(rect: bounds)
    for hole in holes { path.append(UIBezierPath(rect: hole)) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    mask.frame = bounds
    mask.fillRule = .evenOdd
    mask.path = path.cgPath
    CATransaction.commit()
    maskedBounds = bounds
    if holeMask == nil {
      layer.mask = mask
      holeMask = mask
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if !holes.isEmpty { applyMask() }
    onLayout?()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    onLayout?()
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    for hole in holes where hole.contains(point) { return nil }
    return super.hitTest(point, with: event)
  }

  // MARK: Hardware keys

  /// A hardware key went down (true) or came up, under the name a browser's
  /// `KeyboardEvent.key` gives it.
  var onKey: ((String, Bool) -> Void)?

  private var keyObservers: [NSObjectProtocol] = []

  // UIKit hands a key to the first responder and on up from there. With no
  // field being typed in there is none, and the key goes to the view
  // controller without passing this view - so the container asks to be the
  // one whenever nothing else is. It is not a text input, so no keyboard
  // comes up for it.
  override var canBecomeFirstResponder: Bool { true }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    for token in keyObservers { NotificationCenter.default.removeObserver(token) }
    keyObservers = []
    guard window != nil else { return }
    // A field that is done with the keyboard leaves it with nobody.
    let names: [NSNotification.Name] = [
      UITextField.textDidEndEditingNotification,
      UITextView.textDidEndEditingNotification,
      UIApplication.didBecomeActiveNotification,
    ]
    for name in names {
      let token = NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        // After the turn: a field handing over to the next has not yet.
        DispatchQueue.main.async { self?.takeKeys() }
      }
      keyObservers.append(token)
    }
    takeKeys()
  }

  deinit {
    for token in keyObservers { NotificationCenter.default.removeObserver(token) }
  }

  /// Becomes the first responder when the window has none.
  private func takeKeys() {
    guard let window, !isFirstResponder, Self.firstResponder(in: window) == nil else { return }
    becomeFirstResponder()
  }

  private static func firstResponder(in view: UIView) -> UIView? {
    if view.isFirstResponder { return view }
    for child in view.subviews {
      if let found = firstResponder(in: child) { return found }
    }
    return nil
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    report(presses, down: true)
    super.pressesBegan(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    report(presses, down: false)
    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    report(presses, down: false)
    super.pressesCancelled(presses, with: event)
  }

  private func report(_ presses: Set<UIPress>, down: Bool) {
    guard let onKey, #available(iOS 13.4, *) else { return }
    for press in presses {
      guard let key = press.key, let name = Self.keyName(key) else { continue }
      onKey(name, down)
    }
  }

  @available(iOS 13.4, *)
  private static func keyName(_ key: UIKey) -> String? {
    switch key.keyCode {
    case .keyboardUpArrow: return "ArrowUp"
    case .keyboardDownArrow: return "ArrowDown"
    case .keyboardLeftArrow: return "ArrowLeft"
    case .keyboardRightArrow: return "ArrowRight"
    case .keyboardReturnOrEnter, .keypadEnter: return "Enter"
    case .keyboardSpacebar: return " "
    case .keyboardDeleteOrBackspace: return "Backspace"
    case .keyboardDeleteForward: return "Delete"
    case .keyboardEscape: return "Escape"
    case .keyboardTab: return "Tab"
    case .keyboardLeftShift, .keyboardRightShift: return "Shift"
    case .keyboardLeftControl, .keyboardRightControl: return "Control"
    case .keyboardLeftAlt, .keyboardRightAlt: return "Alt"
    case .keyboardLeftGUI, .keyboardRightGUI: return "Meta"
    case .keyboardPageUp: return "PageUp"
    case .keyboardPageDown: return "PageDown"
    case .keyboardHome: return "Home"
    case .keyboardEnd: return "End"
    default: break
    }
    let code = key.keyCode.rawValue
    let f1 = UIKeyboardHIDUsage.keyboardF1.rawValue
    if code >= f1 && code <= UIKeyboardHIDUsage.keyboardF12.rawValue {
      return "F\(code - f1 + 1)"
    }
    // What the key types, shift and all; a key that types nothing has a
    // name of UIKit's own here, which is not one a browser would give.
    let typed = key.characters
    return typed.isEmpty || typed.hasPrefix("UIKeyInput") ? nil : typed
  }
}

// MARK: - App bar

/// The app bar's title, as a type of its own so a patch can find it among the
/// labels its buttons carry.
final class DnnAppBarTitleLabel: UILabel {}

/// The app bar, which remembers the views its child nodes became - the title
/// subtree and the actions - so the reconciler can walk into them.
final class DnnAppBarView: UIView {
  var nodeViews: [UIView] = []
  weak var titleLabel: UILabel?
  weak var leadingButton: UIButton?
}

// MARK: - Text field

/// A text field that can keep its text clear of its edges.
///
/// UIKit's field has room inside it only while it wears one of UIKit's own
/// borders. One the app has given a fill or an outline of its own wears none,
/// and its text would start at the very edge: [insets] is the room, for the
/// text, the placeholder and the caret alike.
final class DnnTextField: UITextField {
  var insets: UIEdgeInsets? {
    didSet {
      invalidateIntrinsicContentSize()
      setNeedsLayout()
    }
  }

  /// The line under a field that is underlined; kept so it is made once.
  private var underline: UIView?

  /// The outline the app gave the field - `none`, `outline` or `underline`,
  /// and how round - and its colour and width in each state it named
  /// (`rest`, `focused`, `error`, `disabled`). Nil keeps UIKit's box.
  var outline: (kind: String, radius: CGFloat)? { didSet { paintOutline() } }
  var lines: [String: (UIColor, CGFloat)] = [:] { didSet { paintOutline() } }

  /// Whether the field is showing an error, which its outline says too.
  var inError = false { didSet { if inError != oldValue { paintOutline() } } }

  override var isEnabled: Bool { didSet { paintOutline() } }

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    paintOutline()
    return became
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    paintOutline()
    return resigned
  }

  /// Draws the outline in the colour and width of the state the field is in.
  private func paintOutline() {
    guard let outline, let rest = lines["rest"] else { return }
    let state =
      !isEnabled ? "disabled" : inError ? "error" : isFirstResponder ? "focused" : "rest"
    let (color, width) = lines[state] ?? rest
    layer.borderWidth = 0
    layer.cornerRadius = 0
    setUnderline(color: nil, width: 0)
    switch outline.kind {
    case "none":
      break
    case "outline":
      layer.borderWidth = width
      layer.borderColor = color.cgColor
      layer.cornerRadius = outline.radius
      layer.masksToBounds = true
    default:
      // A line under the field - and under one that is only filled, which
      // is how Material draws a filled field.
      setUnderline(color: color, width: width)
    }
  }

  /// Draws, or takes away, a line along the bottom edge.
  func setUnderline(color: UIColor?, width: CGFloat) {
    underline?.removeFromSuperview()
    underline = nil
    guard let color else { return }
    let line = UIView(
      frame: CGRect(x: 0, y: bounds.height - width, width: bounds.width, height: width))
    line.backgroundColor = color
    line.isUserInteractionEnabled = false
    line.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
    addSubview(line)
    underline = line
  }

  // From the bounds themselves, each of the three: UIKit works the
  // placeholder's rectangle out from the text's, and insets taken off both
  // left a placeholder two points tall.
  override func textRect(forBounds bounds: CGRect) -> CGRect {
    guard let insets else { return super.textRect(forBounds: bounds) }
    return bounds.inset(by: insets)
  }

  override func editingRect(forBounds bounds: CGRect) -> CGRect {
    guard let insets else { return super.editingRect(forBounds: bounds) }
    return bounds.inset(by: insets)
  }

  override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
    guard let insets else { return super.placeholderRect(forBounds: bounds) }
    return bounds.inset(by: insets)
  }

  // No `intrinsicContentSize` of its own: UIKit sizes a field from the text
  // rectangle above, so the room is already in its height - added again
  // here, every field with a look came out half as tall again.
}

// MARK: - Button

/// A button that can be asked to take the width it is offered.
final class DnnButton: UIButton {
  private var fill: NSLayoutConstraint?

  var expands = false {
    didSet { applyFill() }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    applyFill()
  }

  private func applyFill() {
    fill?.isActive = false
    fill = nil
    guard expands, let parent = superview else { return }
    let constraint = dnnFill(self, parent, horizontal: true)
    constraint.isActive = true
    fill = constraint
  }
}

// MARK: - Dropdown

/// A `Dropdown`: a caption, a bordered button showing the selection that opens
/// the platform's menu, and an error underneath.
final class DnnDropdownView: UIView {
  private let caption = UILabel()
  private let button = UIButton(type: .system)
  private let errorLabel = UILabel()
  private let chevron = UIImageView()

  /// The index of the item chosen from the menu.
  var onPick: ((Int) -> Void)?

  /// The button that opens the menu: what a test presses and a reader lands
  /// on, and so where the node's id goes rather than on the view around it.
  var control: UIView { button }

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  /// The room kept clear for the arrow is at the end of the field, and the
  /// button's insets name sides - so they follow the direction the view is
  /// told the screen reads in.
  override var semanticContentAttribute: UISemanticContentAttribute {
    didSet {
      let rtl = semanticContentAttribute == .forceRightToLeft
      button.semanticContentAttribute = semanticContentAttribute
      button.contentEdgeInsets = UIEdgeInsets(
        top: 10, left: rtl ? 36 : 12, bottom: 10, right: rtl ? 12 : 36)
    }
  }

  private func setUp() {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 4
    stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    caption.font = .systemFont(ofSize: 13)
    errorLabel.font = .systemFont(ofSize: 12)
    errorLabel.numberOfLines = 0

    button.contentHorizontalAlignment = .leading
    button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 36)
    button.titleLabel?.font = .systemFont(ofSize: 16)
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.layer.cornerRadius = 6

    if #available(iOS 13.0, *) {
      chevron.image = UIImage(systemName: "chevron.down")
    }
    chevron.contentMode = .scaleAspectFit
    chevron.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(chevron)

    stack.addArrangedSubview(caption)
    stack.addArrangedSubview(button)
    stack.addArrangedSubview(errorLabel)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
      chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      chevron.widthAnchor.constraint(equalToConstant: 14),
      chevron.heightAnchor.constraint(equalToConstant: 14),
    ])
  }

  func configure(
    items: [String], selected: Int?, label: String?, hint: String?, error: String?,
    enabled: Bool, outlined: Bool, text: UIColor, quiet: UIColor, border: UIColor,
    danger: UIColor
  ) {
    caption.text = label
    caption.textColor = quiet
    caption.isHidden = label == nil

    errorLabel.text = error
    errorLabel.textColor = danger
    errorLabel.isHidden = error == nil

    var shown: String?
    if let selected = selected, selected >= 0, selected < items.count {
      shown = items[selected]
    }
    button.setTitle(shown ?? hint ?? "", for: .normal)
    button.setTitleColor(shown == nil ? quiet : text, for: .normal)
    button.isEnabled = enabled
    button.alpha = enabled ? 1 : 0.5
    button.layer.borderWidth = outlined ? 1 : 0
    button.layer.borderColor = (error == nil ? border : danger).cgColor
    button.accessibilityLabel = label ?? hint
    button.accessibilityValue = shown
    button.accessibilityHint = error
    chevron.tintColor = quiet

    if #available(iOS 14.0, *) {
      var actions: [UIAction] = []
      for (index, item) in items.enumerated() {
        let action = UIAction(title: item, state: index == selected ? .on : .off) {
          [weak self] _ in
          self?.onPick?(index)
        }
        actions.append(action)
      }
      button.menu = UIMenu(title: "", children: actions)
      button.showsMenuAsPrimaryAction = true
    }
  }
}

// MARK: - Date and time pickers

/// The inside of a picker overlay: a title, the platform's picker, and the
/// two buttons that close it.
final class DnnPickerPanel: UIView {
  let picker = UIDatePicker()
  var onDone: ((Date) -> Void)?
  var onCancel: (() -> Void)?

  init(title: String?, confirm: String, cancel: String, tint: UIColor) {
    super.init(frame: .zero)

    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 12
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    if let title = title {
      let label = UILabel()
      label.text = title
      label.font = .systemFont(ofSize: 20, weight: .semibold)
      label.numberOfLines = 0
      label.accessibilityTraits = .header
      stack.addArrangedSubview(label)
    }

    picker.tintColor = tint
    stack.addArrangedSubview(picker)

    let buttons = UIStackView()
    buttons.axis = .horizontal
    buttons.spacing = 16
    buttons.alignment = .center
    let gap = UIView()
    gap.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    buttons.addArrangedSubview(gap)

    let cancelButton = UIButton(type: .system)
    cancelButton.setTitle(cancel, for: .normal)
    cancelButton.setTitleColor(tint, for: .normal)
    cancelButton.titleLabel?.font = .systemFont(ofSize: 16)
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    buttons.addArrangedSubview(cancelButton)

    let doneButton = UIButton(type: .system)
    doneButton.setTitle(confirm, for: .normal)
    doneButton.setTitleColor(tint, for: .normal)
    doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
    buttons.addArrangedSubview(doneButton)

    buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    stack.addArrangedSubview(buttons)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func doneTapped() {
    onDone?(picker.date)
  }

  @objc private func cancelTapped() {
    onCancel?()
  }
}

// MARK: - Text with runs that can be tapped

/// What a touch on a run of text does: where the run is in the string, the
/// event its tap sends and the one its long press sends.
struct DnnRun {
  let range: NSRange
  let tap: String?
  let longPress: String?
}

/// The run of `runs` a touch at `point` landed on, in text laid out by
/// `layout` into `container` - only a touch on the run's own glyphs counts.
func dnnRun(
  at point: CGPoint, in runs: [DnnRun], layout: NSLayoutManager, container: NSTextContainer
) -> DnnRun? {
  guard !runs.isEmpty, layout.numberOfGlyphs > 0 else { return nil }
  let glyph = layout.glyphIndex(for: point, in: container)
  // The nearest glyph is found for a touch anywhere; only one on it counts.
  let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
  guard box.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
  let character = layout.characterIndexForGlyph(at: glyph)
  return runs.first { NSLocationInRange(character, $0.range) }
}

/// The label a `Text` node is drawn with.
///
/// It knows which of its runs a touch landed on: a UILabel has no links of
/// its own, so the text is laid out again the way the label lays it out and
/// the touch is looked up in that.
/// A widget's own view in a line of text: where in the string its room is,
/// and the room's bounds against the baseline, as its attachment has them.
struct DnnInlineView {
  let location: Int
  let view: UIView
  let bounds: CGRect
}

final class DnnLabel: UILabel {
  /// The widgets in the text, each laid over the room kept for it - live,
  /// rather than a picture of what they were.
  var inline: [DnnInlineView] = [] {
    didSet {
      for old in oldValue where !inline.contains(where: { $0.view === old.view }) {
        old.view.removeFromSuperview()
      }
      for item in inline where item.view.superview !== self {
        item.view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(item.view)
      }
      isUserInteractionEnabled = !links.isEmpty || !inline.isEmpty
      setNeedsLayout()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard !inline.isEmpty, let text = attributedText, text.length > 0 else { return }
    let storage = NSTextStorage(attributedString: text)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: bounds.size)
    container.lineFragmentPadding = 0
    container.maximumNumberOfLines = numberOfLines
    container.lineBreakMode = lineBreakMode
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    for item in inline where item.location < text.length {
      let glyph = layout.glyphIndexForCharacter(at: item.location)
      let line =
        layout.isValidGlyphIndex(glyph)
        ? layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil) : .zero
      // A room cut off by the line limit has no line, and is not on the screen.
      guard !line.isEmpty else {
        item.view.isHidden = true
        continue
      }
      let at = layout.location(forGlyphAt: glyph)
      let height = item.bounds.height
      // A widget the line was made tall for fills it; a smaller one sits as
      // its attachment does, risen from the baseline.
      let y =
        height >= line.height - 1
        ? line.midY - height / 2
        : line.minY + at.y - item.bounds.maxY
      item.view.isHidden = false
      item.view.frame = CGRect(
        x: line.minX + at.x, y: y, width: item.bounds.width, height: height)
    }
  }

  /// The runs that can be tapped or held.
  var links: [DnnRun] = [] {
    didSet {
      isUserInteractionEnabled = !links.isEmpty || !inline.isEmpty
      if links.isEmpty {
        accessibilityTraits.remove(.link)
      } else {
        accessibilityTraits.insert(.link)
      }
    }
  }
  var onLink: ((String) -> Void)?

  private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
  private lazy var hold = UILongPressGestureRecognizer(
    target: self, action: #selector(held(_:)))

  /// A label given more height than its lines need writes them from the top,
  /// as Flutter's text does, where UIKit would centre them: a page that is
  /// one line of text had it halfway down the screen.
  override func drawText(in rect: CGRect) {
    var lines = textRect(forBounds: rect, limitedToNumberOfLines: numberOfLines)
    lines.origin.y = rect.origin.y
    lines.origin.x = rect.origin.x
    lines.size.width = rect.width
    super.drawText(in: lines)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if tap.view == nil {
      addGestureRecognizer(tap)
      addGestureRecognizer(hold)
    }
  }

  /// A touch that is on no link is not the label's: whatever is behind it -
  /// a row that can be tapped - gets it, as it would from a plain label.
  /// A touch on a widget in the text is the widget's: the label's own tap
  /// and hold leave it alone.
  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    let point = recognizer.location(in: self)
    if inline.contains(where: { !$0.view.isHidden && $0.view.frame.contains(point) }) {
      return false
    }
    return super.gestureRecognizerShouldBegin(recognizer)
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    super.point(inside: point, with: event)
      && (link(at: point) != nil
        || inline.contains { !$0.view.isHidden && $0.view.frame.contains(point) })
  }

  @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
    guard let eventId = link(at: recognizer.location(in: self))?.tap else { return }
    onLink?(eventId)
  }

  @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began,
      let eventId = link(at: recognizer.location(in: self))?.longPress
    else { return }
    onLink?(eventId)
  }

  private func link(at point: CGPoint) -> DnnRun? {
    guard !links.isEmpty, let text = attributedText, text.length > 0 else { return nil }
    let storage = NSTextStorage(attributedString: text)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: bounds.size)
    container.lineFragmentPadding = 0
    container.maximumNumberOfLines = numberOfLines
    container.lineBreakMode = lineBreakMode
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    // The lines are written from the top - see `drawText(in:)`.
    return dnnRun(at: point, in: links, layout: layout, container: container)
  }
}

/// The text view selectable text is drawn with: one that neither edits nor
/// scrolls, and whose runs can be tapped and held as a label's are. A tap or
/// a hold on a run is the run's as well as the selection's.
final class DnnSelectableTextView: UITextView, UIGestureRecognizerDelegate {
  var links: [DnnRun] = [] {
    didSet {
      if links.isEmpty {
        accessibilityTraits.remove(.link)
      } else {
        accessibilityTraits.insert(.link)
      }
    }
  }
  var onLink: ((String) -> Void)?

  private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
  private lazy var hold = UILongPressGestureRecognizer(
    target: self, action: #selector(held(_:)))

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if tap.view == nil {
      tap.delegate = self
      hold.delegate = self
      addGestureRecognizer(tap)
      addGestureRecognizer(hold)
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool { true }

  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    if recognizer === tap || recognizer === hold {
      return link(at: recognizer.location(in: self)) != nil
    }
    return super.gestureRecognizerShouldBegin(recognizer)
  }

  @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
    guard let eventId = link(at: recognizer.location(in: self))?.tap else { return }
    onLink?(eventId)
  }

  @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began,
      let eventId = link(at: recognizer.location(in: self))?.longPress
    else { return }
    onLink?(eventId)
  }

  private func link(at point: CGPoint) -> DnnRun? {
    let inset = textContainerInset
    let inText = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
    return dnnRun(at: inText, in: links, layout: layoutManager, container: textContainer)
  }
}

// MARK: - Bottom navigation

/// One destination of a `BottomNavigation`, its icons already drawn.
struct DnnNavItem {
  let label: String
  let icon: UIImage?
  let selectedIcon: UIImage?
}

/// A tab bar that is its own delegate, since nothing else owns it: there is no
/// tab bar controller behind a tree of views.
final class DnnTabBar: UITabBar, UITabBarDelegate {
  /// The index of the tab that was tapped.
  var onSelect: ((Int) -> Void)?

  private var fill: NSLayoutConstraint?

  override init(frame: CGRect) {
    super.init(frame: frame)
    delegate = self
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    delegate = self
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    onSelect?(item.tag)
  }

  func selectIndex(_ index: Int) {
    guard let items = items, index >= 0, index < items.count else {
      selectedItem = nil
      return
    }
    if selectedItem !== items[index] { selectedItem = items[index] }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    fill?.isActive = false
    fill = nil
    guard let parent = superview else { return }
    let constraint = dnnFill(self, parent, horizontal: true)
    constraint.isActive = true
    fill = constraint
  }
}

/// The same destinations down the leading edge, for a wide window.
final class DnnRailView: UIView {
  /// The index of the destination that was tapped.
  var onSelect: ((Int) -> Void)?

  private let stack = UIStackView()
  /// Holds the destinations, so more of them than the window is tall - seven
  /// on a phone held sideways - can be scrolled to rather than cut off.
  private let scroller = UIScrollView()
  private var items: [DnnNavItem] = []
  private var buttons: [UIButton] = []
  private var icons: [UIImageView] = []
  private var labels: [UILabel] = []
  /// The pill behind each destination of an extended rail.
  private var pills: [UIView] = []
  private var tint = UIColor.systemBlue
  private var idle = UIColor.gray
  private var extended = false
  private var width: NSLayoutConstraint?
  private var fill: NSLayoutConstraint?
  /// The views of the rail's leading and trailing nodes, in that order, kept
  /// so their nodes can be patched: they sit among the destinations.
  private(set) var nodeViews: [UIView] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  private func setUp() {
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroller.translatesAutoresizingMaskIntoConstraints = false
    scroller.showsVerticalScrollIndicator = false
    scroller.contentInsetAdjustmentBehavior = .never
    addSubview(scroller)
    scroller.addSubview(stack)
    NSLayoutConstraint.activate([
      scroller.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      scroller.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroller.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroller.trailingAnchor.constraint(equalTo: trailingAnchor),
      // As long as its destinations, as wide as the rail: it scrolls only
      // when they do not fit.
      stack.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroller.frameLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroller.frameLayoutGuide.trailingAnchor),
      scroller.contentLayoutGuide.widthAnchor.constraint(
        equalTo: scroller.frameLayoutGuide.widthAnchor),
    ])
    width = widthAnchor.constraint(equalToConstant: 80)
    width?.isActive = true
    // Where nothing says how tall the rail is, it is as tall as what it
    // holds - the scroller has no height of its own to offer.
    let natural = heightAnchor.constraint(equalTo: stack.heightAnchor, constant: 8)
    natural.priority = .defaultLow
    natural.isActive = true
  }

  /// A rail is as tall as the row it stands in, as Flutter's is: a row
  /// centres its children at their own height, and this one's was nothing,
  /// so the rail was a blank strip.
  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    fill?.isActive = false
    fill = nil
    guard let parent = superview else { return }
    let constraint = dnnFill(self, parent, horizontal: false)
    constraint.isActive = true
    fill = constraint
  }

  /// Puts [view] above the destinations or below them: centred over a rail's
  /// icons, at the leading edge of an extended one. Called after `configure`.
  func addSlot(_ view: UIView, above: Bool) {
    let holder = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    holder.addSubview(view)
    let inset: CGFloat = extended ? 12 : 8
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: holder.topAnchor, constant: 8),
      view.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8),
      view.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor, constant: inset),
      view.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -inset),
      extended
        ? view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset)
        : view.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
    ])
    if above {
      stack.insertArrangedSubview(holder, at: 0)
    } else {
      stack.addArrangedSubview(holder)
    }
    nodeViews.append(view)
  }

  func configure(
    items: [DnnNavItem], tint: UIColor, idle: UIColor, background: UIColor,
    extended: Bool = false
  ) {
    self.items = items
    self.tint = tint
    self.idle = idle
    self.extended = extended
    width?.constant = extended ? 256 : 80
    backgroundColor = background
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    nodeViews = []
    buttons = []
    icons = []
    labels = []
    pills = []

    for (index, item) in items.enumerated() {
      let button = UIButton(type: .custom)
      button.tag = index
      button.accessibilityLabel = item.label
      button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)

      let icon = UIImageView(image: item.icon)
      icon.contentMode = .center
      let label = UILabel()
      label.text = item.label
      label.font = .systemFont(ofSize: extended ? 14 : 12, weight: .medium)
      label.textAlignment = extended ? .natural : .center

      // The button takes the touch; what is drawn inside it does not. An
      // extended rail writes the label beside the icon, and the row is the
      // pill the selected one stands on.
      let inner = UIStackView(arrangedSubviews: [icon, label])
      inner.axis = extended ? .horizontal : .vertical
      inner.alignment = .center
      inner.spacing = extended ? 12 : 4
      inner.isUserInteractionEnabled = false
      inner.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(inner)
      let side: CGFloat = extended ? 28 : 4
      NSLayoutConstraint.activate([
        inner.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
        inner.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -8),
        inner.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: side),
        extended
          ? inner.trailingAnchor.constraint(
            lessThanOrEqualTo: button.trailingAnchor, constant: -side)
          : inner.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -side),
        icon.heightAnchor.constraint(equalToConstant: 24),
      ])
      if extended {
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let pill = UIView()
        pill.isUserInteractionEnabled = false
        pill.layer.cornerRadius = 28
        pill.translatesAutoresizingMaskIntoConstraints = false
        button.insertSubview(pill, at: 0)
        pills.append(pill)
        NSLayoutConstraint.activate([
          pill.topAnchor.constraint(equalTo: button.topAnchor),
          pill.bottomAnchor.constraint(equalTo: button.bottomAnchor),
          pill.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
          pill.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
        ])
      }

      stack.addArrangedSubview(button)
      buttons.append(button)
      icons.append(icon)
      labels.append(label)
    }
  }

  func selectIndex(_ index: Int) {
    for position in buttons.indices {
      let chosen = position == index
      let item = items[position]
      icons[position].image = chosen ? (item.selectedIcon ?? item.icon) : item.icon
      icons[position].tintColor = chosen ? tint : idle
      labels[position].textColor = chosen ? tint : idle
      if position < pills.count {
        pills[position].backgroundColor = chosen ? tint.withAlphaComponent(0.16) : .clear
      }
      if chosen {
        buttons[position].accessibilityTraits.insert(.selected)
      } else {
        buttons[position].accessibilityTraits.remove(.selected)
      }
    }
  }

  @objc private func tapped(_ sender: UIButton) {
    onSelect?(sender.tag)
  }
}


/// Moves a scroller to an offset over a time the app said, along its curve,
/// a frame at a time - so that a windowed list hears every step, as it does
/// under a finger. UIKit's own animated scroll keeps a pace of its own.
final class DnnScrollTravel: NSObject {
  private static let travels = NSMapTable<UIScrollView, DnnScrollTravel>.weakToStrongObjects()

  private weak var view: UIScrollView?
  private let from: CGPoint
  private let to: CGPoint
  private let seconds: TimeInterval
  private let points: (CGPoint, CGPoint)?
  private var start: CFTimeInterval?
  private var link: CADisplayLink?

  private init(
    _ view: UIScrollView, to: CGPoint, seconds: TimeInterval, points: (CGPoint, CGPoint)?
  ) {
    self.view = view
    self.from = view.contentOffset
    self.to = to
    self.seconds = seconds
    self.points = points
  }

  /// Sends [view] to [target] over [seconds] along the cubic [points] -
  /// straight, when there are none - in place of any travel it was on.
  static func go(
    _ view: UIScrollView, to target: CGPoint, seconds: TimeInterval,
    points: (CGPoint, CGPoint)?
  ) {
    stop(view)
    let travel = DnnScrollTravel(view, to: target, seconds: seconds, points: points)
    travels.setObject(travel, forKey: view)
    let link = CADisplayLink(target: travel, selector: #selector(step(_:)))
    travel.link = link
    link.add(to: .main, forMode: .common)
  }

  /// Ends the travel [view] is on, where it has got to.
  static func stop(_ view: UIScrollView) {
    travels.object(forKey: view)?.link?.invalidate()
    travels.removeObject(forKey: view)
  }

  @objc private func step(_ link: CADisplayLink) {
    guard let view = view else {
      link.invalidate()
      return
    }
    // A finger on it takes it from here.
    if view.isTracking || view.isDragging {
      DnnScrollTravel.stop(view)
      return
    }
    let begun = start ?? link.timestamp
    start = begun
    let t = seconds <= 0 ? 1 : min(1, (link.timestamp - begun) / seconds)
    let eased = points.map { dnnBezier($0.0, $0.1, CGFloat(t)) } ?? CGFloat(t)
    view.contentOffset = CGPoint(
      x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
    if t >= 1 { DnnScrollTravel.stop(view) }
  }
}

/// y at x = [t] on the cubic Bézier through (0,0), [one], [two] and (1,1).
/// A point travelling along an arc of a circle: Flutter's
/// `MaterialPointArcTween`, as `lib/src/hero_arc.dart` has it.
struct DnnArcPoint {
  let begin: CGPoint
  let end: CGPoint
  private var radius: CGFloat = 0
  private var centre = CGPoint.zero
  private var beginAngle: CGFloat?
  private var endAngle: CGFloat = 0

  init(from begin: CGPoint, to end: CGPoint) {
    self.begin = begin
    self.end = end
    let dx = end.x - begin.x
    let dy = end.y - begin.y
    // Nearly along an axis: a straight line.
    guard abs(dx) > 2, abs(dy) > 2 else { return }
    let distance = hypot(dx, dy)
    func sweep(_ r: CGFloat) -> CGFloat { 2 * asin(distance / (2 * r)) }
    func sign(_ v: CGFloat) -> CGFloat { v > 0 ? 1 : (v < 0 ? -1 : 0) }
    if abs(dx) < abs(dy) {
      radius = distance * distance / abs(dx) / 2
      centre = CGPoint(x: end.x + radius * sign(begin.x - end.x), y: end.y)
      if begin.x < end.x {
        beginAngle = sweep(radius) * sign(begin.y - end.y)
        endAngle = 0
      } else {
        beginAngle = .pi + sweep(radius) * sign(end.y - begin.y)
        endAngle = .pi
      }
    } else {
      radius = distance * distance / abs(dy) / 2
      centre = CGPoint(x: begin.x, y: begin.y + sign(end.y - begin.y) * radius)
      if begin.y < end.y {
        beginAngle = -.pi / 2
        endAngle = -.pi / 2 + sweep(radius) * sign(end.x - begin.x)
      } else {
        beginAngle = .pi / 2
        endAngle = .pi / 2 + sweep(radius) * sign(begin.x - end.x)
      }
    }
  }

  func at(_ t: CGFloat) -> CGPoint {
    if t <= 0 { return begin }
    if t >= 1 { return end }
    guard let from = beginAngle else {
      return CGPoint(x: begin.x + (end.x - begin.x) * t, y: begin.y + (end.y - begin.y) * t)
    }
    let angle = from + (endAngle - from) * t
    return CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
  }
}

/// A rectangle travelling along a Material arc: Flutter's
/// `MaterialRectArcTween` - the two corners on the diagonal that points most
/// nearly the way it goes, each on a `DnnArcPoint`.
struct DnnArcRectPath {
  let begin: CGRect
  let end: CGRect
  private let first: DnnArcPoint
  private let second: DnnArcPoint

  // Corners: 0 top left, 1 top right, 2 bottom left, 3 bottom right.
  private static let diagonals = [(0, 3), (3, 0), (1, 2), (2, 1)]

  private static func corner(_ rect: CGRect, _ corner: Int) -> CGPoint {
    switch corner {
    case 0: return CGPoint(x: rect.minX, y: rect.minY)
    case 1: return CGPoint(x: rect.maxX, y: rect.minY)
    case 2: return CGPoint(x: rect.minX, y: rect.maxY)
    default: return CGPoint(x: rect.maxX, y: rect.maxY)
    }
  }

  init(from begin: CGRect, to end: CGRect) {
    self.begin = begin
    self.end = end
    let towards = CGPoint(x: end.midX - begin.midX, y: end.midY - begin.midY)
    var best = DnnArcRectPath.diagonals[0]
    var support = -CGFloat.infinity
    for diagonal in DnnArcRectPath.diagonals {
      let from = DnnArcRectPath.corner(begin, diagonal.0)
      let to = DnnArcRectPath.corner(begin, diagonal.1)
      let length = hypot(to.x - from.x, to.y - from.y)
      let along = length == 0 ? 0 : (towards.x * (to.x - from.x) + towards.y * (to.y - from.y)) / length
      if along > support {
        support = along
        best = diagonal
      }
    }
    first = DnnArcPoint(
      from: DnnArcRectPath.corner(begin, best.0), to: DnnArcRectPath.corner(end, best.0))
    second = DnnArcPoint(
      from: DnnArcRectPath.corner(begin, best.1), to: DnnArcRectPath.corner(end, best.1))
  }

  func at(_ t: CGFloat) -> CGRect {
    if t <= 0 { return begin }
    if t >= 1 { return end }
    let a = first.at(t)
    let b = second.at(t)
    return CGRect(
      x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }
}

func dnnBezier(_ one: CGPoint, _ two: CGPoint, _ t: CGFloat) -> CGFloat {
  func at(_ p1: CGFloat, _ p2: CGFloat, _ m: CGFloat) -> CGFloat {
    3 * p1 * (1 - m) * (1 - m) * m + 3 * p2 * (1 - m) * m * m + m * m * m
  }
  var low: CGFloat = 0
  var high: CGFloat = 1
  var middle = t
  for _ in 0..<30 {
    middle = (low + high) / 2
    let x = at(one.x, two.x, middle)
    if abs(x - t) < 0.0001 { break }
    if x < t { low = middle } else { high = middle }
  }
  return at(one.y, two.y, middle)
}


/// Core Graphics' blend for a Flutter `BlendMode` name: how what is drawn is
/// laid over what is there.
func dnnBlendMode(_ name: String?) -> CGBlendMode {
  switch name {
  case "clear": return .clear
  case "src": return .copy
  case "dstOver", "dst": return .destinationOver
  case "srcIn": return .sourceIn
  case "dstIn": return .destinationIn
  case "srcOut": return .sourceOut
  case "dstOut": return .destinationOut
  case "srcATop": return .sourceAtop
  case "dstATop": return .destinationAtop
  case "xor": return .xor
  case "plus": return .plusLighter
  case "modulate", "multiply": return .multiply
  case "screen": return .screen
  case "overlay": return .overlay
  case "darken": return .darken
  case "lighten": return .lighten
  case "colorDodge": return .colorDodge
  case "colorBurn": return .colorBurn
  case "hardLight": return .hardLight
  case "softLight": return .softLight
  case "difference": return .difference
  case "exclusion": return .exclusion
  case "hue": return .hue
  case "saturation": return .saturation
  case "color": return .color
  case "luminosity": return .luminosity
  default: return .normal
  }
}

/// The view an `Image` node draws its picture in. Given only a width
/// (`statedWidth`), it is as tall as that width makes the picture in its own
/// proportions - and not tall at all before the picture comes - rather than
/// as tall as the picture is in points.
///
/// Told it fills its width (`fillsWidth`), it is as wide as the room it is
/// given and as tall as the picture is at that width.
final class DnnImageView: UIImageView {
  var statedWidth: CGFloat?

  var fillsWidth = false {
    didSet { followPicture() }
  }

  override var image: UIImage? {
    didSet { followPicture() }
  }

  /// The height the picture's proportions give the width, for one that
  /// fills it.
  private var proportion: NSLayoutConstraint?

  private func followPicture() {
    proportion?.isActive = false
    proportion = nil
    guard fillsWidth else { return }
    let size = image?.size ?? .zero
    let made =
      size.width > 0
      ? heightAnchor.constraint(equalTo: widthAnchor, multiplier: size.height / size.width)
      : heightAnchor.constraint(equalToConstant: 0)
    made.priority = UILayoutPriority(999)
    made.isActive = true
    proportion = made
  }

  override var intrinsicContentSize: CGSize {
    if fillsWidth {
      return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
    guard let width = statedWidth else { return super.intrinsicContentSize }
    guard let size = image?.size, size.width > 0 else {
      return CGSize(width: UIView.noIntrinsicMetric, height: 0)
    }
    return CGSize(width: width, height: width * size.height / size.width)
  }
}
