import UIKit

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

  var tapEventId: String?
  var doubleTapEventId: String?
  var longPressEventId: String?
  var panEventId: String?
  var ripple = false
  var dragData: String?
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
  UIDropInteractionDelegate
{
  let surface = UIView()
  let content = UIView()

  /// Sends `(eventId, data)` to the app.
  var onEvent: ((String, [String: Any]) -> Void)?

  private(set) var style = DnnBoxStyle()

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
  private var doubleTapRecognizer: UITapGestureRecognizer?
  private var longPressRecognizer: UILongPressGestureRecognizer?
  private var panRecognizer: UIPanGestureRecognizer?
  private var dragger: UIDragInteraction?
  private var dropper: UIDropInteraction?
  private var lastPan = CGPoint.zero
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

  /// Restyles the box in place. Inside a `UIView.animate` block the size,
  /// colour, opacity and transform move there instead of landing at once.
  func apply(_ next: DnnBoxStyle) {
    if next.sizeEventId != style.sizeEventId {
      reportedSize = CGSize(width: -1, height: -1)
    }
    style = next

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
    transform = next.transform
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

    // The child never leaves the padded area, whatever else is asked.
    next.append(
      child.leftAnchor.constraint(greaterThanOrEqualTo: content.leftAnchor, constant: inset.left))
    next.append(
      child.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: inset.top))
    next.append(
      content.rightAnchor.constraint(
        greaterThanOrEqualTo: child.rightAnchor, constant: inset.right))
    next.append(
      content.bottomAnchor.constraint(
        greaterThanOrEqualTo: child.bottomAnchor, constant: inset.bottom))

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
        surface.addGestureRecognizer(recognizer)
        panRecognizer = recognizer
      }
    } else if let recognizer = panRecognizer {
      surface.removeGestureRecognizer(recognizer)
      panRecognizer = nil
    }
  }

  private func pointData(_ point: CGPoint) -> [String: Any] {
    ["x": Double(point.x), "y": Double(point.y)]
  }

  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard let eventId = style.tapEventId else { return }
    onEvent?(eventId, pointData(recognizer.location(in: surface)))
  }

  @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
    guard let eventId = style.doubleTapEventId else { return }
    onEvent?(eventId, pointData(recognizer.location(in: surface)))
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let eventId = style.longPressEventId else { return }
    onEvent?(eventId, pointData(recognizer.location(in: surface)))
  }

  @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
    guard let eventId = style.panEventId else { return }
    let point = recognizer.location(in: surface)
    let velocity = recognizer.velocity(in: surface)
    let suffix: String
    switch recognizer.state {
    case .began:
      suffix = "_start"
      lastPan = point
    case .changed:
      suffix = "_update"
    case .ended, .cancelled, .failed:
      suffix = "_end"
    default:
      return
    }
    let data: [String: Any] = [
      "x": Double(point.x),
      "y": Double(point.y),
      "dx": Double(point.x - lastPan.x),
      "dy": Double(point.y - lastPan.y),
      "vx": Double(velocity.x),
      "vy": Double(velocity.y),
    ]
    lastPan = point
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
    return [item]
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
    if let local = session.localDragSession?.items.first?.localObject as? String {
      onEvent?(eventId, ["data": local])
      return
    }
    _ = session.loadObjects(ofClass: NSString.self) { [weak self] items in
      let text = (items.first as? NSString).map { $0 as String } ?? ""
      self?.onEvent?(eventId, ["data": text])
    }
  }
}

// MARK: - Canvas

/// One entry of a canvas's `paints`.
struct DnnPaint {
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
    _ context: CGContext, _ path: CGPath, _ paint: DnnPaint, strokeOnly: Bool = false
  ) {
    context.addPath(path)
    if paint.stroke || strokeOnly {
      context.setStrokeColor(paint.color.cgColor)
      // A width of zero is a hairline, as it is in Flutter.
      let hairline = 1 / max(contentScaleFactor, 1)
      context.setLineWidth(paint.width > 0 ? paint.width : hairline)
      context.setLineCap(paint.cap)
      context.setLineJoin(paint.join)
      context.strokePath()
    } else {
      context.setFillColor(paint.color.cgColor)
      context.fillPath()
    }
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
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: dnnColor(options["color"]) ?? UIColor.black,
      .paragraphStyle: paragraph,
    ]
    let text = NSAttributedString(string: string, attributes: attributes)
    if let maxWidth = dnnNumber(options["maxWidth"]), maxWidth > 0, maxWidth.isFinite {
      // Aligned within the width it was given.
      text.draw(
        with: CGRect(x: x, y: y, width: maxWidth, height: 100_000),
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
        fillOrStroke(context, segmentPath(segments), paint(command, 2))
      case "text":
        drawText(command)
      case "save":
        context.saveGState()
        saves += 1
      case "restore":
        // An unmatched restore would pop UIKit's own state.
        if saves > 0 {
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
      default:
        break
      }
    }
    while saves > 0 {
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
  private var settled = false
  private var wasAtEnd = true
  private var lastExtent: CGFloat = -1

  var hostedChild: UIView? { child }

  override init(frame: CGRect) {
    super.init(frame: frame)
    // The scaffold has already kept the content clear of the system insets.
    contentInsetAdjustmentBehavior = .never
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
    // Along the axis the scroller is as long as its content when that is all
    // it was asked to be (`shrinkWrap`), and otherwise only when nothing else
    // gives it a length at all.
    let along: NSLayoutConstraint
    if horizontal {
      next.append(
        view.heightAnchor.constraint(
          equalTo: frameGuide.heightAnchor, constant: -(padding.top + padding.bottom)))
      along = frameGuide.widthAnchor.constraint(equalTo: contentGuide.widthAnchor)
    } else {
      next.append(
        view.widthAnchor.constraint(
          equalTo: frameGuide.widthAnchor, constant: -(padding.left + padding.right)))
      along = frameGuide.heightAnchor.constraint(equalTo: contentGuide.heightAnchor)
    }
    // Weaker than a box hugging its child (100): a scroller that *was* given
    // a length longer than its content otherwise met this by stretching the
    // content to match - one list tile on a short page came out half as tall
    // again as the ones beside it.
    along.priority = UILayoutPriority(shrinkWrap ? 999 : 50)
    next.append(along)
    childConstraints = next
    NSLayoutConstraint.activate(next)
  }

  private func setOffset(_ value: CGFloat) {
    let target = horizontal ? CGPoint(x: value, y: 0) : CGPoint(x: 0, y: value)
    if contentOffset != target { contentOffset = target }
  }

  /// Scrolls to [offset] now, or as soon as there is content to scroll.
  func jump(to offset: CGFloat) {
    if settled {
      let viewport = horizontal ? bounds.width : bounds.height
      let extent = horizontal ? contentSize.width : contentSize.height
      let maxOffset = max(0, extent - viewport)
      // Reversed, an offset counts from the far end - as it does on the
      // other renderers, and as `onReport` says it.
      let held = min(max(0, offset), maxOffset)
      setOffset(reverse ? maxOffset - held : held)
    } else {
      pendingJump = offset
    }
  }

  /// An offset the app asked for before there was content to scroll, counted
  /// the way `jump(to:)` counts it; `restoreOffset` is the view's own.
  private var pendingJump: CGFloat?

  override func layoutSubviews() {
    super.layoutSubviews()
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
  private var tint = UIColor.systemBlue
  private var idle = UIColor.gray

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
      widthAnchor.constraint(equalToConstant: 80),
    ])
  }

  func configure(items: [DnnNavItem], tint: UIColor, idle: UIColor, background: UIColor) {
    self.items = items
    self.tint = tint
    self.idle = idle
    backgroundColor = background
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    buttons = []
    icons = []
    labels = []

    for (index, item) in items.enumerated() {
      let button = UIButton(type: .custom)
      button.tag = index
      button.accessibilityLabel = item.label
      button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)

      let icon = UIImageView(image: item.icon)
      icon.contentMode = .center
      let label = UILabel()
      label.text = item.label
      label.font = .systemFont(ofSize: 12, weight: .medium)
      label.textAlignment = .center

      // The button takes the touch; what is drawn inside it does not.
      let inner = UIStackView(arrangedSubviews: [icon, label])
      inner.axis = .vertical
      inner.alignment = .center
      inner.spacing = 4
      inner.isUserInteractionEnabled = false
      inner.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(inner)
      NSLayoutConstraint.activate([
        inner.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
        inner.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -8),
        inner.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
        inner.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
        icon.heightAnchor.constraint(equalToConstant: 24),
      ])

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
