package com.programtom.dart_not_native

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.ClipData
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Point
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Region
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.DragEvent
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.VelocityTracker
import android.os.SystemClock
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.ViewTreeObserver
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.Interpolator
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.android.material.navigationrail.NavigationRailView
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.accessibility.AccessibilityNodeProviderCompat
import androidx.core.widget.NestedScrollView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// The views behind the free-form nodes - Box, Stack, Scroll, Canvas, the
// Flutter slot - and the few marker views the renderer finds its own parts by.
//
// They live apart from NativeUIRenderer because none of them needs the tree:
// the renderer reads a node into plain values (pixels, colour ints, event ids)
// and hands those over, so everything here can be read, and reasoned about, as
// an ordinary custom View.

/** What a view needs of the renderer: the screen's density and the way back to Dart. */
internal interface ViewHost {
    val density: Float

    fun send(eventId: String, data: Map<String, Any?>)

    /** Sends a box's size, unless that event id last carried the same one. */
    fun reportSize(eventId: String, width: Float, height: Float)
}

/**
 * A colour as the protocol writes it: `#rrggbb` or `#aarrggbb`.
 *
 * `Color.parseColor` reads both, and throws on anything else - which a tree
 * built by an app must never be able to turn into a failed render - so this
 * answers null instead and every caller names its own fallback.
 */
internal fun parseColorOrNull(value: Any?): Int? {
    val text = value as? String ?: return null
    return try {
        Color.parseColor(text.trim())
    } catch (e: IllegalArgumentException) {
        null
    }
}

// -----------------------------------------------------------------------------
// Box
// -----------------------------------------------------------------------------

/** A box's fill when it is not one colour. Alignments run -1..1, as in the tree. */
internal data class BoxGradient(
    val radial: Boolean,
    val colors: List<Int>,
    val stops: List<Float>?,
    val beginX: Float,
    val beginY: Float,
    val endX: Float?,
    val endY: Float?,
)

/** A box's shadow, in pixels. */
internal data class BoxShadow(val color: Int, val blur: Float, val dx: Float, val dy: Float)

/**
 * Everything a box draws and how big it is, in pixels and colour ints.
 *
 * A data class so that "did anything change" is `==`, and so an animation can
 * be a run of copies between the style on screen and the one asked for.
 */
internal data class BoxStyle(
    val width: Float? = null,
    val height: Float? = null,
    val minWidth: Float? = null,
    val maxWidth: Float? = null,
    val minHeight: Float? = null,
    val maxHeight: Float? = null,
    val expandWidth: Boolean = false,
    val expandHeight: Boolean = false,
    val aspectRatio: Float? = null,
    /** Left, top, right, bottom. */
    val padding: List<Int> = NO_EDGES,
    val margin: List<Int> = NO_EDGES,
    /** Where the child sits, -1..1 on each axis; null fills the content area. */
    val alignX: Float? = null,
    val alignY: Float? = null,
    val color: Int? = null,
    val gradient: BoxGradient? = null,
    val borderWidth: Float = 0f,
    val borderColor: Int = Color.TRANSPARENT,
    /** Top-left, top-right, bottom-right, bottom-left. */
    val radii: List<Float> = NO_RADII,
    val circle: Boolean = false,
    val shadow: BoxShadow? = null,
    val clip: Boolean = false,
    val opacity: Float = 1f,
    /** Degrees, because that is what a View rotates by. */
    val rotation: Float = 0f,
    val scale: Float = 1f,
    val dx: Float = 0f,
    val dy: Float = 0f,
) {
    companion object {
        val NO_EDGES = listOf(0, 0, 0, 0)
        val NO_RADII = listOf(0f, 0f, 0f, 0f)
    }

    /** Whether going from [other] to this needs a new measure, not just a repaint. */
    fun measuresLike(other: BoxStyle): Boolean =
        width == other.width && height == other.height &&
            minWidth == other.minWidth && maxWidth == other.maxWidth &&
            minHeight == other.minHeight && maxHeight == other.maxHeight &&
            expandWidth == other.expandWidth && expandHeight == other.expandHeight &&
            aspectRatio == other.aspectRatio && padding == other.padding &&
            margin == other.margin && alignX == other.alignX && alignY == other.alignY &&
            borderWidth == other.borderWidth
}

/**
 * What every view built from a node tells an accessibility service on top of
 * what its own class says: the node's `id`, and that a touch which would not
 * reach it cannot be performed on it either.
 *
 * The id is reported as the view's resource name, because that is the one
 * field uiautomator, Maestro and agent-device all read as "this element's
 * identifier", and the views here are built in code with no resource id of
 * their own to report. It is the node's id as written - see `identify`.
 *
 * It wraps whatever delegate the view already had rather than replacing it: a
 * Material slider's is the helper that describes its thumb, a text field's
 * the one that says its hint and error.
 */
internal class NodeAccessibility(private val inner: AccessibilityDelegateCompat?) :
    AccessibilityDelegateCompat() {

    /** The node's id, or null for a node with none. */
    var resourceName: String? = null

    /** A node marked as a heading - a screen reader's "next heading" stops on it. */
    var heading: Boolean = false

    /** Whether a box that is a toggle is on; null for one that is not a toggle. */
    var selected: Boolean? = null

    /** A box that stands for a control which is switched off. */
    var disabled: Boolean = false

    /** The class a node is announced as when its view's own would mislead - `semanticRole`. */
    var className: CharSequence? = null

    /**
     * What stands in for the view's text. An icon is a text view holding one
     * private-use character, which means nothing read aloud or matched by a
     * test: its node says the icon's name, or nothing.
     */
    var text: CharSequence? = null

    override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfoCompat) {
        if (inner != null) inner.onInitializeAccessibilityNodeInfo(host, info)
        else super.onInitializeAccessibilityNodeInfo(host, info)
        resourceName?.let { info.viewIdResourceName = it }
        if (heading) info.isHeading = true
        className?.let { info.className = it }
        if (disabled) info.isEnabled = false
        // "Selected", as Flutter's own filter chip says it - and the state a
        // device test can ask for (`selected=true`).
        selected?.let { info.isSelected = it }
        text?.let { info.text = it }
        if (pointerIgnored(host)) {
            // Still there to be read, and said to be unavailable: a touch
            // would not reach it, so "activate" must not either.
            if (info.isClickable || info.isLongClickable) info.isEnabled = false
            info.isClickable = false
            info.isLongClickable = false
            info.removeAction(AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_CLICK)
            info.removeAction(
                AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_LONG_CLICK,
            )
        }
    }

    override fun performAccessibilityAction(host: View, action: Int, args: Bundle?): Boolean {
        val activates = action == AccessibilityNodeInfo.ACTION_CLICK ||
            action == AccessibilityNodeInfo.ACTION_LONG_CLICK
        if (activates && pointerIgnored(host)) return false
        return inner?.performAccessibilityAction(host, action, args)
            ?: super.performAccessibilityAction(host, action, args)
    }

    override fun getAccessibilityNodeProvider(host: View): AccessibilityNodeProviderCompat? =
        if (inner != null) inner.getAccessibilityNodeProvider(host)
        else super.getAccessibilityNodeProvider(host)

    override fun sendAccessibilityEvent(host: View, eventType: Int) {
        if (inner != null) inner.sendAccessibilityEvent(host, eventType)
        else super.sendAccessibilityEvent(host, eventType)
    }

    override fun sendAccessibilityEventUnchecked(host: View, event: AccessibilityEvent) {
        if (inner != null) inner.sendAccessibilityEventUnchecked(host, event)
        else super.sendAccessibilityEventUnchecked(host, event)
    }

    override fun dispatchPopulateAccessibilityEvent(host: View, event: AccessibilityEvent): Boolean =
        inner?.dispatchPopulateAccessibilityEvent(host, event)
            ?: super.dispatchPopulateAccessibilityEvent(host, event)

    override fun onPopulateAccessibilityEvent(host: View, event: AccessibilityEvent) {
        if (inner != null) inner.onPopulateAccessibilityEvent(host, event)
        else super.onPopulateAccessibilityEvent(host, event)
    }

    override fun onInitializeAccessibilityEvent(host: View, event: AccessibilityEvent) {
        if (inner != null) inner.onInitializeAccessibilityEvent(host, event)
        else super.onInitializeAccessibilityEvent(host, event)
    }

    override fun onRequestSendAccessibilityEvent(
        host: ViewGroup,
        child: View,
        event: AccessibilityEvent,
    ): Boolean = inner?.onRequestSendAccessibilityEvent(host, child, event)
        ?: super.onRequestSendAccessibilityEvent(host, child, event)

    companion object {
        /** The delegate on [view], installed around whatever it had if this is the first ask. */
        fun of(view: View): NodeAccessibility {
            val existing = ViewCompat.getAccessibilityDelegate(view)
            if (existing is NodeAccessibility) return existing
            // Installing a delegate promotes a view from "auto" to "important",
            // which is right for one a test or a reader will ask for by id and
            // wrong for a layout nobody named - the caller decides.
            val importance = view.importantForAccessibility
            val delegate = NodeAccessibility(existing)
            ViewCompat.setAccessibilityDelegate(view, delegate)
            view.importantForAccessibility = importance
            return delegate
        }

        /** Whether [view] sits in a box that lets no touch through (`IgnorePointer`). */
        fun pointerIgnored(view: View): Boolean {
            var at: Any? = view
            while (at is View) {
                if (at is BoxLayout && at.events.ignorePointer) return true
                at = at.parent
            }
            return false
        }
    }
}

/** What a box reports and how it answers a finger. */
internal data class BoxEvents(
    val tap: String? = null,
    val doubleTap: String? = null,
    val longPress: String? = null,
    val pan: String? = null,
    val drop: String? = null,
    val size: String? = null,
    val dragData: String? = null,
    val ignorePointer: Boolean = false,
) {
    val handlesTouch: Boolean
        get() = tap != null || doubleTap != null || longPress != null || pan != null ||
            dragData != null
}

/**
 * The view behind a `Box`: size, space, paint and touch around one child.
 *
 * It draws its own decoration rather than wearing a GradientDrawable, for two
 * reasons the drawable cannot meet: a gradient here runs between any two
 * points, where the drawable knows eight directions, and the margin is *inside*
 * the view. The second matters more. Half the containers in the renderer hand a
 * child the layout params they think it should have - `matchWidth()` under a
 * Padding, a weight under an Expanded - and a margin kept in the params would
 * be lost every time one did. So the view is measured margin included, paints
 * inset by it, and no parent can drop it.
 *
 * Size follows one rule on each axis, first match wins: the stated
 * width/height; `expand`, or a parent that gave an exact size, fills what was
 * offered; otherwise the box hugs its child. A stated size is never larger than
 * what the parent offers, and the min/max pair bounds whichever applied.
 */
@SuppressLint("ViewConstructor")
internal open class BoxLayout(context: Context, private val host: ViewHost) :
    FrameLayout(context) {

    /** The style on screen - mid-animation, somewhere between two the tree asked for. */
    var style = BoxStyle()
        private set

    var events = BoxEvents()
        set(value) {
            field = value
            // Clickable and long-clickable are what an accessibility service
            // reads to offer "activate" and "long press": the touches here go
            // through a gesture detector, which it cannot see.
            isClickable = value.tap != null && !value.ignorePointer
            isLongClickable = value.longPress != null && !value.ignorePointer
            isFocusable = isClickable
            detector.setIsLongpressEnabled(value.longPress != null || value.dragData != null)
            setOnDragListener(if (value.drop == null) null else dropListener)
            reportSize()
        }

    private var animator: ValueAnimator? = null

    /** The decorated rectangle - the view's bounds less the margin. */
    protected val box = RectF()
    private val shape = Path()
    private val borderShape = Path()
    private var shapeDirty = true
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var shadowBlur = -1f

    init {
        // A ViewGroup with no background skips draw() altogether, and draw() is
        // where the decoration is painted.
        setWillNotDraw(false)
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) = outlineOf(outline)
        }
    }

    // -- Style ---------------------------------------------------------------

    /**
     * Moves the box to [next]: at once, or over [animateMs] when the tree asked
     * for motion and there is something on screen to move from.
     */
    fun setStyle(next: BoxStyle, animateMs: Long = 0, curve: Interpolator? = null) {
        animator?.cancel()
        animator = null
        if (next == style) return
        if (animateMs <= 0 || !isLaidOut) {
            show(next)
            return
        }
        // A box that was hugging has no stated size to travel from, so it
        // starts from the one it was laid out at.
        val from = style.copy(
            width = style.width ?: if (next.width != null) box.width() else null,
            height = style.height ?: if (next.height != null) box.height() else null,
        )
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = animateMs
            if (curve != null) interpolator = curve
            addUpdateListener { show(between(from, next, it.animatedValue as Float)) }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    // Only if it ran to the end: a cancel is a newer style
                    // taking over, and that one is the truth now.
                    if (animator === animation) show(next)
                }
            })
            start()
        }
    }

    private fun show(next: BoxStyle) {
        val before = style
        style = next
        alpha = next.opacity.coerceIn(0f, 1f)
        rotation = next.rotation
        scaleX = next.scale
        scaleY = next.scale
        translationX = next.dx
        translationY = next.dy
        // The outline is what clips a plain rounded box, and antialiases the
        // edge while it does. It also clips the view's *own* drawing, so a box
        // with a shadow - which is drawn outside the shape - clips its child
        // with a path instead (see dispatchDraw).
        clipToOutline = next.clip && next.shadow == null && outlineClips(next)
        // Before API 28 a blur cannot be drawn on a hardware canvas; the
        // platform's own elevation shadow stands in, without the colour or
        // the offset.
        elevation = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P && next.shadow != null) {
            next.shadow.blur / 2f
        } else {
            0f
        }
        // A shadow or a move gained by a patch, on a box already in its parent.
        if (spills(next) && !spills(before) && isAttachedToWindow) {
            letDrawOutside(this)
        }
        shapeDirty = true
        invalidateOutline()
        if (!next.measuresLike(before)) requestLayout()
        invalidate()
    }

    /** The style a fraction [t] of the way from [a] to [b]. */
    private fun between(a: BoxStyle, b: BoxStyle, t: Float): BoxStyle {
        fun mix(from: Float, to: Float) = from + (to - from) * t
        fun mixOrJump(from: Float?, to: Float?) =
            if (from != null && to != null) mix(from, to) else to
        fun mixColor(from: Int, to: Int) = ArgbEvaluator().evaluate(t, from, to) as Int
        // A fill appearing or leaving fades through its own colour at no
        // alpha; through transparent black it would darken on the way.
        val color = when {
            a.color == null && b.color == null -> null
            else -> mixColor(
                a.color ?: (b.color!! and 0x00ffffff),
                b.color ?: (a.color!! and 0x00ffffff),
            )
        }
        return b.copy(
            width = mixOrJump(a.width, b.width),
            height = mixOrJump(a.height, b.height),
            color = color,
            borderWidth = mix(a.borderWidth, b.borderWidth),
            borderColor = mixColor(a.borderColor, b.borderColor),
            radii = List(4) { mix(a.radii[it], b.radii[it]) },
            opacity = mix(a.opacity, b.opacity),
            rotation = mix(a.rotation, b.rotation),
            scale = mix(a.scale, b.scale),
            dx = mix(a.dx, b.dx),
            dy = mix(a.dy, b.dy),
        )
    }

    /**
     * Touch feedback in [color], cut to the box's shape; null removes it.
     *
     * The platform's `selectableItemBackground` is this ripple with a
     * rectangular mask, which spills past a rounded box's corners.
     */
    // "NewApi": lint reads `foreground` as View's, which arrived in API 23. A
    // FrameLayout has had its own since API 1, and that is the one this
    // resolves to on the two older releases the plugin still supports.
    @SuppressLint("NewApi")
    fun setRipple(color: Int?) {
        if (color == rippleColor) return
        rippleColor = color
        foreground = if (color == null) null else RippleDrawable(
            ColorStateList.valueOf(color), null, ShapeMask(),
        )
    }

    private var rippleColor: Int? = null

    /** The box's own shape as a ripple mask - opaque where the ripple may show. */
    private inner class ShapeMask : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        override fun draw(canvas: Canvas) {
            rebuildShape()
            canvas.drawPath(shape, paint)
        }

        override fun setAlpha(alpha: Int) = Unit
        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    // -- Measure and layout --------------------------------------------------

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val s = style
        val marginH = s.margin[0] + s.margin[2]
        val marginV = s.margin[1] + s.margin[3]
        // The border takes room inside the box, as it does in CSS and Flutter.
        val border = s.borderWidth.roundToInt()
        val padH = s.padding[0] + s.padding[2] + border * 2
        val padV = s.padding[1] + s.padding[3] + border * 2

        val wMode = MeasureSpec.getMode(widthMeasureSpec)
        val hMode = MeasureSpec.getMode(heightMeasureSpec)
        val availW = if (wMode == MeasureSpec.UNSPECIFIED) UNBOUNDED
        else max(0, MeasureSpec.getSize(widthMeasureSpec) - marginH)
        val availH = if (hMode == MeasureSpec.UNSPECIFIED) UNBOUNDED
        else max(0, MeasureSpec.getSize(heightMeasureSpec) - marginV)

        fun boundW(value: Int) = bound(value, s.minWidth, s.maxWidth, availW)
        fun boundH(value: Int) = bound(value, s.minHeight, s.maxHeight, availH)

        var w = axis(s.width, s.expandWidth, wMode, availW)?.let(::boundW)
        var h = axis(s.height, s.expandHeight, hMode, availH)?.let(::boundH)

        // An aspect ratio derives the free axis from the settled one; with
        // neither settled it takes the width on offer, as Flutter's does.
        val ratio = s.aspectRatio?.takeIf { it > 0f }
        if (ratio != null) {
            if (w != null && h == null) {
                h = (w / ratio).roundToInt()
            } else if (h != null && w == null) {
                w = (h * ratio).roundToInt()
            } else if (w == null && h == null) {
                if (availW != UNBOUNDED) {
                    w = availW
                    h = (w / ratio).roundToInt()
                    if (availH != UNBOUNDED && h > availH) {
                        h = availH
                        w = (h * ratio).roundToInt()
                    }
                } else if (availH != UNBOUNDED) {
                    h = availH
                    w = (h * ratio).roundToInt()
                }
            }
        }

        // An aligned child keeps its own size inside the box; an unaligned one
        // fills the content area.
        val aligned = s.alignX != null
        fun childSpec(size: Int?, avail: Int, most: Float?, pad: Int): Int {
            if (size != null) {
                return MeasureSpec.makeMeasureSpec(
                    max(0, size - pad),
                    if (aligned) MeasureSpec.AT_MOST else MeasureSpec.EXACTLY,
                )
            }
            val room = min(avail, most?.roundToInt() ?: UNBOUNDED)
            return if (room == UNBOUNDED) {
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            } else {
                MeasureSpec.makeMeasureSpec(max(0, room - pad), MeasureSpec.AT_MOST)
            }
        }

        var childW = 0
        var childH = 0
        val wSpec = childSpec(w, availW, s.maxWidth, padH)
        val hSpec = childSpec(h, availH, s.maxHeight, padV)
        // A child that states a size in its params - an image, a sized box -
        // keeps it, within what the box has to offer. The box measures its
        // child itself, so nothing else would read those params.
        fun stated(spec: Int, size: Int): Int {
            // Zero is not a size: it is a weighted child waiting for a share.
            if (size <= 0) return spec
            val room = MeasureSpec.getSize(spec)
            return MeasureSpec.makeMeasureSpec(
                if (MeasureSpec.getMode(spec) == MeasureSpec.UNSPECIFIED) size else min(size, room),
                MeasureSpec.EXACTLY,
            )
        }
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            val params = child.layoutParams
            var childWSpec = stated(wSpec, params.width)
            // A row that was not asked to hug is as wide as the box even where
            // the box places its child: aligned, it was offered the width
            // rather than given it, took only what its children needed, and
            // left an Expanded inside it nothing to expand into - a list tile
            // with its trailing icon straight after the title.
            if (aligned && w != null && params.width == LayoutParams.MATCH_PARENT &&
                child is LinearLayout && child.orientation == LinearLayout.HORIZONTAL
            ) {
                childWSpec = MeasureSpec.makeMeasureSpec(max(0, w - padH), MeasureSpec.EXACTLY)
            }
            child.measure(childWSpec, stated(hSpec, params.height))
            childW = max(childW, child.measuredWidth)
            childH = max(childH, child.measuredHeight)
        }

        val finalW = w ?: boundW(childW + padH)
        val finalH = h ?: boundH(childH + padV)
        // A hugging box that a minimum stretched: the child was measured
        // against the smaller size, and fills the larger one.
        if (!aligned && (finalW != childW + padH || finalH != childH + padV)) {
            val exactW = MeasureSpec.makeMeasureSpec(max(0, finalW - padH), MeasureSpec.EXACTLY)
            val exactH = MeasureSpec.makeMeasureSpec(max(0, finalH - padV), MeasureSpec.EXACTLY)
            for (i in 0 until childCount) {
                val child = getChildAt(i)
                if (child.visibility != GONE) child.measure(exactW, exactH)
            }
        }
        setMeasuredDimension(finalW + marginH, finalH + marginV)
    }

    /** One axis's size where something settles it, or null to hug the child. */
    private fun axis(stated: Float?, expand: Boolean, mode: Int, avail: Int): Int? = when {
        stated != null -> stated.roundToInt()
        mode == MeasureSpec.UNSPECIFIED -> null
        expand || mode == MeasureSpec.EXACTLY -> avail
        else -> null
    }

    private fun bound(value: Int, least: Float?, most: Float?, avail: Int): Int {
        var result = value
        if (most != null) result = min(result, most.roundToInt())
        if (least != null) result = max(result, least.roundToInt())
        return min(result, avail).coerceAtLeast(0)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val s = style
        box.set(
            s.margin[0].toFloat(),
            s.margin[1].toFloat(),
            (r - l - s.margin[2]).toFloat(),
            (b - t - s.margin[3]).toFloat(),
        )
        shapeDirty = true
        // The outline is built from the rectangle just set, and the platform
        // rebuilt it before this ran - from the last one, which on a first
        // layout is empty, and an empty outline clips everything away.
        invalidateOutline()
        // Turn and scale about the middle of what is painted, which is not the
        // middle of the view when the margins differ.
        pivotX = box.centerX()
        pivotY = box.centerY()

        val border = s.borderWidth.roundToInt()
        val left = s.margin[0] + border + s.padding[0]
        val top = s.margin[1] + border + s.padding[1]
        val contentW = (r - l) - s.margin[2] - border - s.padding[2] - left
        val contentH = (b - t) - s.margin[3] - border - s.padding[3] - top
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            val w = child.measuredWidth
            val h = child.measuredHeight
            val x = left + ((contentW - w) * (((s.alignX ?: -1f) + 1f) / 2f)).roundToInt()
            val y = top + ((contentH - h) * (((s.alignY ?: -1f) + 1f) / 2f)).roundToInt()
            child.layout(x, y, x + w, y + h)
        }
        reportSize()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // A shadow is drawn outside the box, which a parent that clips its
        // children - or clips them to its padding, as a Padding node's frame
        // would - cuts off at the box's own edge.
        if (spills(style)) letDrawOutside(this)
    }

    /**
     * Whether [s] paints outside the box's own bounds: a shadow does, and so
     * does a box moved, turned or grown from where it was laid out - a piece
     * lifted to show it is picked up. Flutter clips none of that.
     */
    private fun spills(s: BoxStyle): Boolean =
        s.shadow != null || s.dx != 0f || s.dy != 0f || s.rotation != 0f || s.scale > 1f

    private fun reportSize() {
        val eventId = events.size ?: return
        if (!isLaidOut && width == 0) return
        host.reportSize(eventId, box.width() / host.density, box.height() / host.density)
    }

    // -- Paint ---------------------------------------------------------------

    private fun outlineClips(s: BoxStyle): Boolean =
        s.circle || s.radii.all { it == s.radii[0] }

    private fun outlineOf(outline: Outline) {
        val s = style
        val rect = Rect()
        shapeBounds().roundOut(rect)
        when {
            s.circle -> outline.setOval(rect)
            outlineClips(s) -> outline.setRoundRect(rect, s.radii[0])
            else -> outline.setRect(rect)
        }
        // The outline casts the platform's shadow only where that is the
        // fallback for a drawn one; everywhere else it is there to clip.
        outline.alpha = if (elevation > 0f) 1f else 0f
    }

    /** The rectangle the shape fills: the box, or the circle inscribed in it. */
    private fun shapeBounds(): RectF {
        if (!style.circle) return RectF(box)
        val d = min(box.width(), box.height())
        val left = box.centerX() - d / 2f
        val top = box.centerY() - d / 2f
        return RectF(left, top, left + d, top + d)
    }

    private fun rebuildShape() {
        if (!shapeDirty) return
        shapeDirty = false
        val s = style
        val bounds = shapeBounds()
        shape.rewind()
        borderShape.rewind()
        // The border's centre line runs half its width inside the edge.
        val inset = s.borderWidth / 2f
        val inner = RectF(bounds).apply { inset(inset, inset) }
        if (s.circle) {
            shape.addOval(bounds, Path.Direction.CW)
            borderShape.addOval(inner, Path.Direction.CW)
        } else {
            shape.addRoundRect(bounds, corners(s.radii, 0f), Path.Direction.CW)
            borderShape.addRoundRect(inner, corners(s.radii, inset), Path.Direction.CW)
        }
        fill.shader = s.gradient?.let { shaderFor(it, bounds) }
    }

    private fun corners(radii: List<Float>, inset: Float) = FloatArray(8) {
        (radii[it / 2] - inset).coerceAtLeast(0f)
    }

    private fun shaderFor(gradient: BoxGradient, bounds: RectF): Shader? {
        if (gradient.colors.size < 2 || bounds.isEmpty) return null
        fun x(alignment: Float) = bounds.left + (alignment + 1f) / 2f * bounds.width()
        fun y(alignment: Float) = bounds.top + (alignment + 1f) / 2f * bounds.height()
        val colors = gradient.colors.toIntArray()
        val stops = gradient.stops?.takeIf { it.size == colors.size }?.toFloatArray()
        return if (gradient.radial) {
            // Centred on `begin`; out to `end` where one is given, and to the
            // nearer edge where it is not - Flutter's default of half the
            // shortest side.
            val cx = x(gradient.beginX)
            val cy = y(gradient.beginY)
            val radius = if (gradient.endX != null && gradient.endY != null) {
                hypot(x(gradient.endX) - cx, y(gradient.endY) - cy)
            } else {
                min(bounds.width(), bounds.height()) / 2f
            }
            RadialGradient(cx, cy, max(radius, 0.01f), colors, stops, Shader.TileMode.CLAMP)
        } else {
            LinearGradient(
                x(gradient.beginX), y(gradient.beginY),
                x(gradient.endX ?: 1f), y(gradient.endY ?: 0f),
                colors, stops, Shader.TileMode.CLAMP,
            )
        }
    }

    override fun draw(canvas: Canvas) {
        rebuildShape()
        val s = style
        val shadow = s.shadow
        if (shadow != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (shadowBlur != shadow.blur) {
                shadowBlur = shadow.blur
                shadowPaint.maskFilter = if (shadow.blur > 0f) {
                    BlurMaskFilter(shadow.blur, BlurMaskFilter.Blur.NORMAL)
                } else {
                    null
                }
            }
            shadowPaint.color = shadow.color
            val save = canvas.save()
            canvas.translate(shadow.dx, shadow.dy)
            canvas.drawPath(shape, shadowPaint)
            canvas.restoreToCount(save)
        }
        if (fill.shader != null) {
            fill.color = Color.BLACK
            canvas.drawPath(shape, fill)
        } else if (s.color != null) {
            fill.color = s.color
            canvas.drawPath(shape, fill)
        }
        if (s.borderWidth > 0f) {
            stroke.strokeWidth = s.borderWidth
            stroke.color = s.borderColor
            canvas.drawPath(borderShape, stroke)
        }
        super.draw(canvas)
    }

    override fun dispatchDraw(canvas: Canvas) {
        // The outline does the clipping where it can; this is the rest - corners
        // of four different radii, or a box that also has a shadow to keep.
        if (!style.clip || clipToOutline) {
            super.dispatchDraw(canvas)
            return
        }
        rebuildShape()
        val save = canvas.save()
        canvas.clipPath(shape)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }

    // -- Touch ---------------------------------------------------------------

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var panning = false
    private var velocity: VelocityTracker? = null

    private val detector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true

            // A box that also listens for a double tap cannot know a tap was
            // single until the second one fails to arrive; one that does not
            // answers at once.
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                if (events.doubleTap == null) point(events.tap, e)
                return true
            }

            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (events.doubleTap != null) point(events.tap, e)
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                point(events.doubleTap, e)
                return true
            }

            override fun onLongPress(e: MotionEvent) {
                point(events.longPress, e)
            }
        },
    )

    /**
     * Watches for the long press that picks a draggable box up.
     *
     * A detector of its own, fed from [onInterceptTouchEvent] as well as
     * [onTouchEvent]: a draggable row usually holds something that takes the
     * touch itself - a list tile with a tap - and then this box is never the
     * one the touch is delivered to. It still sees every event on the way
     * down, which is all a long press needs; the drag it starts takes the
     * gesture away from the child, so the tap does not also fire.
     */
    private val dragDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onLongPress(e: MotionEvent) = startDrag()
        },
    )
    private var dragDownTime = -1L
    private var dragFromX = 0f
    private var dragFromY = 0f

    private fun watchForDrag(ev: MotionEvent) {
        if (events.dragData == null) return
        // The same down arrives twice when no child takes it: once on the way
        // in, once as this box's own.
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            if (ev.downTime == dragDownTime) return
            dragDownTime = ev.downTime
            dragFromX = ev.x
            dragFromY = ev.y
        }
        dragDetector.onTouchEvent(ev)
    }

    /** A point in the box's own logical pixels - from its painted corner, not the margin's. */
    private fun logicalX(x: Float) = ((x - box.left) / host.density).toDouble()
    private fun logicalY(y: Float) = ((y - box.top) / host.density).toDouble()

    private fun point(eventId: String?, e: MotionEvent) {
        if (eventId == null) return
        host.send(eventId, mapOf("x" to logicalX(e.x), "y" to logicalY(e.y)))
    }

    private fun pan(phase: String, e: MotionEvent, dx: Float, dy: Float, vx: Float, vy: Float) {
        val eventId = events.pan ?: return
        val d = host.density.toDouble()
        host.send(
            "${eventId}_$phase",
            mapOf(
                "x" to logicalX(e.x), "y" to logicalY(e.y),
                "dx" to dx / d, "dy" to dy / d,
                "vx" to vx / d, "vy" to vy / d,
            ),
        )
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        // Neither the box nor anything in it: the touch goes to whatever is
        // underneath, as Flutter's IgnorePointer has it.
        if (events.ignorePointer) return false
        return super.dispatchTouchEvent(ev)
    }

    /**
     * A pan takes the gesture from the child once the finger has travelled, so
     * a draggable card can hold buttons that still take a tap.
     */
    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        watchForDrag(ev)
        if (events.pan == null) return false
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> beginTouch(ev)
            MotionEvent.ACTION_MOVE -> {
                velocity?.addMovement(ev)
                if (!panning && movedPastSlop(ev)) {
                    beginPan(ev)
                    return true
                }
            }
        }
        return false
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (!events.handlesTouch) return super.onTouchEvent(ev)
        // The margin is inside the view but outside the box.
        if (ev.actionMasked == MotionEvent.ACTION_DOWN && !box.contains(ev.x, ev.y)) return false
        watchForDrag(ev)
        detector.onTouchEvent(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                beginTouch(ev)
                drawableHotspotChanged(ev.x, ev.y)
                isPressed = true
            }
            MotionEvent.ACTION_MOVE -> {
                velocity?.addMovement(ev)
                if (events.pan != null) {
                    if (!panning && movedPastSlop(ev)) beginPan(ev)
                    if (panning) {
                        pan("update", ev, ev.x - lastX, ev.y - lastY, 0f, 0f)
                        lastX = ev.x
                        lastY = ev.y
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (panning) {
                    val tracker = velocity
                    tracker?.computeCurrentVelocity(1000)
                    pan("end", ev, 0f, 0f, tracker?.xVelocity ?: 0f, tracker?.yVelocity ?: 0f)
                    panning = false
                    parent?.requestDisallowInterceptTouchEvent(false)
                }
                velocity?.recycle()
                velocity = null
                isPressed = false
            }
        }
        return true
    }

    private fun beginTouch(ev: MotionEvent) {
        downX = ev.x
        downY = ev.y
        lastX = ev.x
        lastY = ev.y
        panning = false
        velocity?.recycle()
        velocity = VelocityTracker.obtain().also { it.addMovement(ev) }
    }

    private fun movedPastSlop(ev: MotionEvent) =
        abs(ev.x - downX) > slop || abs(ev.y - downY) > slop

    /**
     * The finger has moved far enough to mean it. From here the gesture is this
     * box's: an enclosing scroller is told not to take it, or a board inside a
     * scrolling page would lose every drag to the page.
     */
    private fun beginPan(ev: MotionEvent) {
        panning = true
        parent?.requestDisallowInterceptTouchEvent(true)
        pan("start", ev, 0f, 0f, 0f, 0f)
    }

    /** What an accessibility service's "activate" does: the tap, at the middle. */
    override fun performClick(): Boolean {
        super.performClick()
        return activate(events.tap)
    }

    /** ACTION_LONG_CLICK: the long press, at the middle, as a held finger sends it. */
    override fun performLongClick(): Boolean = activate(events.longPress)

    private fun activate(eventId: String?): Boolean {
        if (eventId == null || NodeAccessibility.pointerIgnored(this)) return false
        host.send(
            eventId,
            mapOf(
                "x" to (box.width() / 2f / host.density).toDouble(),
                "y" to (box.height() / 2f / host.density).toDouble(),
            ),
        )
        return true
    }

    /**
     * A box that takes a tap is announced as a button - "Tic Tac Toe, button",
     * its name being the text inside it, which Android merges into a clickable
     * group that has no description of its own.
     *
     * Unless it holds something else that can be activated: a card that opens
     * on a tap and carries a delete button is a clickable group, and calling
     * the whole of it a button would put one button inside another.
     */
    override fun getAccessibilityClassName(): CharSequence =
        if (isClickable && !holdsActionable(this) && !NodeAccessibility.pointerIgnored(this)) {
            Button::class.java.name
        } else {
            super.getAccessibilityClassName()
        }

    /**
     * A box that can be activated and was given no `semanticLabel` is named by
     * the text inside it - what TalkBack would read for a clickable group
     * anyway, said on the node itself so that a tool reading the tree sees
     * "Tic Tac Toe" on the thing it can press rather than a nameless button
     * with a label somewhere below it.
     *
     * Worked out when the node is asked for, not stored: the view's own
     * `contentDescription` stays what the tree said, and the name follows the
     * text as it is patched.
     */
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        if (!contentDescription.isNullOrEmpty()) return
        val parts = ArrayList<CharSequence>()
        if (namesItself()) collectText(this, parts, skipActionable = true)
        if (parts.isEmpty()) {
            // A tooltip is the only name an icon in a box was given. It names
            // the box unless something inside already says what it is.
            val hint = tooltipLabel?.takeIf { it.isNotBlank() } ?: return
            collectText(this, parts, skipActionable = false)
            if (parts.isEmpty()) info.contentDescription = hint
            return
        }
        info.contentDescription = parts.joinToString(", ")
    }

    /** The node's `tooltip`, which names a box that has no label and no text. */
    var tooltipLabel: String? = null

    /** `excludeSemantics`: what is inside is not there for a screen reader. */
    var hidesChildren = false
        set(value) {
            field = value
            for (i in 0 until childCount) hide(getChildAt(i))
        }

    override fun onViewAdded(child: View) {
        super.onViewAdded(child)
        hide(child)
    }

    private fun hide(child: View) {
        if (hidesChildren) {
            child.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        } else if (child.importantForAccessibility ==
            IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        ) {
            child.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
        }
    }

    private fun namesItself() =
        (isClickable || isLongClickable) && contentDescription.isNullOrEmpty()

    /** The text a reader would merge into [group]: what is not itself something to activate. */
    private fun collectText(
        group: ViewGroup,
        into: MutableList<CharSequence>,
        skipActionable: Boolean,
    ) {
        for (i in 0 until group.childCount) {
            val child = group.getChildAt(i)
            if (child.visibility != VISIBLE) continue
            if (skipActionable && (child.isClickable || child.isLongClickable)) continue
            val hidden = child.importantForAccessibility
            if (hidden == IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS) continue
            // A text view kept out of the tree is an icon nobody named.
            val said = child.contentDescription?.takeIf { it.isNotBlank() }
                ?: (child as? TextView)?.text?.takeIf {
                    it.isNotBlank() && hidden != IMPORTANT_FOR_ACCESSIBILITY_NO
                }
            if (said != null) {
                into += said.trim().replace(Regex("\\s+"), " ")
            } else if (child is ViewGroup) {
                collectText(child, into, skipActionable)
            }
        }
    }

    private var renamePosted = false

    /**
     * Something inside changed. A service keeps the node it last read, and the
     * change it was told about names the child, so the box says that it has
     * changed too - or a cell that went from empty to "X" would keep its old
     * name until something else refreshed it.
     */
    override fun onRequestSendAccessibilityEvent(child: View, event: AccessibilityEvent): Boolean {
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            !renamePosted && namesItself()
        ) {
            renamePosted = true
            post {
                renamePosted = false
                sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
            }
        }
        return super.onRequestSendAccessibilityEvent(child, event)
    }

    private fun holdsActionable(group: ViewGroup): Boolean {
        for (i in 0 until group.childCount) {
            val child = group.getChildAt(i)
            if (child.visibility != VISIBLE) continue
            if (child.isClickable || child.isLongClickable) return true
            if (child is ViewGroup && holdsActionable(child)) return true
        }
        return false
    }

    // -- Drag and drop -------------------------------------------------------

    /** Picks the box up, carrying its `dragData`, with the box itself as the shadow. */
    private fun startDrag() {
        val data = events.dragData ?: return
        val clip = ClipData.newPlainText("dnn", data)
        // Held where the finger took it: the platform's default hangs the
        // shadow by its middle, which for a row as wide as the screen jumps
        // it half off the side the moment it is picked up.
        val shadow = object : DragShadowBuilder(this) {
            override fun onProvideShadowMetrics(size: Point, touch: Point) {
                super.onProvideShadowMetrics(size, touch)
                touch.set(
                    dragFromX.roundToInt().coerceIn(0, size.x),
                    dragFromY.roundToInt().coerceIn(0, size.y),
                )
            }
        }
        // The string rides along as local state too: a drop in the same window
        // reads it from there without going through the clipboard machinery.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            startDragAndDrop(clip, shadow, data, 0)
        } else {
            @Suppress("DEPRECATION")
            startDrag(clip, shadow, data, 0)
        }
    }

    private val dropListener = OnDragListener { _, event ->
        val eventId = events.drop ?: return@OnDragListener false
        when (event.action) {
            // Answering true is what subscribes this view to the rest.
            DragEvent.ACTION_DRAG_STARTED -> true
            DragEvent.ACTION_DRAG_ENTERED -> {
                host.send("${eventId}_hover", mapOf("over" to true))
                true
            }
            DragEvent.ACTION_DRAG_EXITED -> {
                host.send("${eventId}_hover", mapOf("over" to false))
                true
            }
            DragEvent.ACTION_DROP -> {
                val data = event.localState as? String
                    ?: event.clipData?.takeIf { it.itemCount > 0 }
                        ?.getItemAt(0)?.text?.toString()
                    ?: ""
                // A drop is not followed by an exit, and the app's "something
                // is over me" would otherwise stay lit.
                host.send("${eventId}_hover", mapOf("over" to false))
                host.send(eventId, mapOf("data" to data))
                true
            }
            else -> true
        }
    }

    companion object {
        /** No limit on an axis - a size no screen reaches. */
        const val UNBOUNDED = Int.MAX_VALUE / 4
    }
}

/**
 * Lets [view] draw past its own bounds: the views above it stop clipping their
 * children, to their bounds and to their padding.
 *
 * Every view above it, not just its parent. A parent that does not clip lets
 * the view out of *its* children's bounds, but what is drawn there may be
 * outside the parent's own - a box that hugs the view, a line of a wrap the
 * view was lifted out of - and that is cut by the next one up. It stops at
 * whatever clips by its nature or was asked to: a scroller, a clipped box or
 * stack, the scaffold.
 */
internal fun letDrawOutside(view: View) {
    var child = view
    while (true) {
        val parent = child.parent as? ViewGroup ?: return
        // A stack or a box that was asked to clip is the app's own decision.
        if (parent is StackLayout && parent.clips) return
        if (parent is BoxLayout && parent.style.clip) return
        if (parent is ScrollView || parent is NestedScrollView ||
            parent is HorizontalScrollView || parent is ScaffoldLayout
        ) {
            return
        }
        parent.clipChildren = false
        parent.clipToPadding = false
        child = parent
    }
}

// -----------------------------------------------------------------------------
// Canvas
// -----------------------------------------------------------------------------

/** One drawing command, read out of the tree and ready to replay. */
internal fun interface CanvasOp {
    fun draw(canvas: Canvas)
}

/**
 * The view behind a `Canvas`: a box that replays a list of commands.
 *
 * The commands are compiled when they arrive ([compileCanvas]) - paints built,
 * paths assembled, numbers unboxed - so drawing is a walk over closures. The
 * canvas is scaled by the density once, which leaves every coordinate, stroke
 * and text size in the logical pixels the tree wrote them in.
 *
 * It stays hardware accelerated: nothing here needs a software layer, and a
 * frame a tick is exactly the case where the difference shows.
 */
@SuppressLint("ViewConstructor")
internal class CanvasView(context: Context, private val host: ViewHost) :
    BoxLayout(context, host) {

    private var ops: List<CanvasOp> = emptyList()

    /** Swaps the picture and asks for a repaint; the view itself is untouched. */
    fun setOps(next: List<CanvasOp>) {
        ops = next
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (ops.isEmpty()) return
        val save = canvas.save()
        canvas.translate(box.left, box.top)
        canvas.scale(host.density, host.density)
        for (op in ops) op.draw(canvas)
        // Whatever the commands left saved or clipped ends with the picture.
        canvas.restoreToCount(save)
    }
}

/**
 * Compiles a `Canvas` node's commands against its paints.
 *
 * The table of commands is in the doc comment of `UIBuilder.canvas`; this is
 * that table and nothing else. A command that names a paint out of range, or
 * that is not a list, is skipped rather than thrown on - a frame with one bad
 * command should lose that command, not the frame.
 */
internal fun compileCanvas(
    commands: List<*>,
    paints: List<*>,
    defaultTextColor: Int,
    typefaceFor: (String?) -> Typeface?,
): List<CanvasOp> {
    val built = paints.map { canvasPaint(it as? Map<*, *>) }
    val fallback = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
    val textPaints = HashMap<List<Any?>, TextPaint>()
    val ops = ArrayList<CanvasOp>(commands.size)
    // Saves the commands themselves made, so a stray `restore` cannot pop the
    // state the view set up around them.
    var depth = 0

    for (raw in commands) {
        val c = raw as? List<*> ?: continue
        fun f(i: Int) = (c.getOrNull(i) as? Number)?.toFloat() ?: 0f
        fun paint(i: Int) = built.getOrNull((c.getOrNull(i) as? Number)?.toInt() ?: -1) ?: fallback
        fun rect(i: Int) = RectF(f(i), f(i + 1), f(i) + f(i + 2), f(i + 1) + f(i + 3))

        when (c.getOrNull(0)) {
            "rect" -> {
                val r = rect(1)
                val p = paint(5)
                ops += CanvasOp { it.drawRect(r, p) }
            }
            "rrect" -> {
                val r = rect(1)
                val radius = f(5)
                val p = paint(6)
                ops += CanvasOp { it.drawRoundRect(r, radius, radius, p) }
            }
            "circle" -> {
                val cx = f(1)
                val cy = f(2)
                val radius = f(3)
                val p = paint(4)
                ops += CanvasOp { it.drawCircle(cx, cy, radius, p) }
            }
            "oval" -> {
                val r = rect(1)
                val p = paint(5)
                ops += CanvasOp { it.drawOval(r, p) }
            }
            "line" -> {
                val x1 = f(1)
                val y1 = f(2)
                val x2 = f(3)
                val y2 = f(4)
                val p = paint(5)
                ops += CanvasOp { it.drawLine(x1, y1, x2, y2, p) }
            }
            "arc" -> {
                val r = rect(1)
                val start = degrees(f(5))
                val sweep = degrees(f(6))
                val useCenter = c.getOrNull(7) == true
                val p = paint(8)
                ops += CanvasOp { it.drawArc(r, start, sweep, useCenter, p) }
            }
            "path" -> {
                val path = canvasPath(c.getOrNull(1) as? List<*> ?: emptyList<Any?>())
                val p = paint(2)
                ops += CanvasOp { it.drawPath(path, p) }
            }
            "text" -> canvasText(c, defaultTextColor, typefaceFor, textPaints)?.let { ops += it }
            "save" -> {
                depth++
                ops += CanvasOp { it.save() }
            }
            "restore" -> if (depth > 0) {
                depth--
                ops += CanvasOp { it.restore() }
            }
            "translate" -> {
                val dx = f(1)
                val dy = f(2)
                ops += CanvasOp { it.translate(dx, dy) }
            }
            "rotate" -> {
                val angle = degrees(f(1))
                ops += CanvasOp { it.rotate(angle) }
            }
            "scale" -> {
                val sx = f(1)
                // One number scales both axes.
                val sy = if (c.size > 2) f(2) else sx
                ops += CanvasOp { it.scale(sx, sy) }
            }
            "clipRect" -> {
                val r = rect(1)
                ops += CanvasOp { it.clipRect(r) }
            }
            "clipRRect" -> {
                val radius = f(5)
                val path = Path().apply { addRoundRect(rect(1), radius, radius, Path.Direction.CW) }
                ops += CanvasOp { it.clipPath(path) }
            }
        }
    }
    return ops
}

private fun degrees(radians: Float): Float = Math.toDegrees(radians.toDouble()).toFloat()

private fun canvasPaint(spec: Map<*, *>?): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = parseColorOrNull(spec?.get("color")) ?: Color.BLACK
    style = if (spec?.get("style") == "stroke") Paint.Style.STROKE else Paint.Style.FILL
    strokeWidth = (spec?.get("strokeWidth") as? Number)?.toFloat() ?: 1f
    strokeCap = when (spec?.get("cap")) {
        "round" -> Paint.Cap.ROUND
        "square" -> Paint.Cap.SQUARE
        else -> Paint.Cap.BUTT
    }
    strokeJoin = when (spec?.get("join")) {
        "round" -> Paint.Join.ROUND
        "bevel" -> Paint.Join.BEVEL
        else -> Paint.Join.MITER
    }
}

private fun canvasPath(segments: List<*>): Path {
    val path = Path()
    for (raw in segments) {
        val s = raw as? List<*> ?: continue
        fun f(i: Int) = (s.getOrNull(i) as? Number)?.toFloat() ?: 0f
        fun rect() = RectF(f(1), f(2), f(1) + f(3), f(2) + f(4))
        when (s.getOrNull(0)) {
            "M" -> path.moveTo(f(1), f(2))
            "L" -> path.lineTo(f(1), f(2))
            "Q" -> path.quadTo(f(1), f(2), f(3), f(4))
            "C" -> path.cubicTo(f(1), f(2), f(3), f(4), f(5), f(6))
            "A" -> {
                val sweep = degrees(f(6))
                // arcTo reads its sweep modulo 360, so a whole turn would be
                // no arc at all; it is the oval.
                if (abs(sweep) >= 360f) path.addOval(rect(), Path.Direction.CW)
                else path.arcTo(rect(), degrees(f(5)), sweep, false)
            }
            "R" -> path.addRect(rect(), Path.Direction.CW)
            "O" -> path.addOval(rect(), Path.Direction.CW)
            "Z" -> path.close()
        }
    }
    return path
}

/**
 * `text`: a string from its top-left corner.
 *
 * With a `maxWidth` it is laid out in a column that wide, wrapping, and `align`
 * places each line inside the column; without one it is a single line and
 * `align` says which part of it sits at `x`.
 */
private fun canvasText(
    c: List<*>,
    defaultColor: Int,
    typefaceFor: (String?) -> Typeface?,
    cache: HashMap<List<Any?>, TextPaint>,
): CanvasOp? {
    val text = c.getOrNull(1)?.toString() ?: return null
    val x = (c.getOrNull(2) as? Number)?.toFloat() ?: 0f
    val y = (c.getOrNull(3) as? Number)?.toFloat() ?: 0f
    val style = c.getOrNull(4) as? Map<*, *>
    val size = (style?.get("size") as? Number)?.toFloat() ?: 14f
    val weight = (style?.get("weight") as? Number)?.toInt() ?: 400
    val family = style?.get("family") as? String
    val color = parseColorOrNull(style?.get("color")) ?: defaultColor
    val align = style?.get("align") as? String
    val maxWidth = (style?.get("maxWidth") as? Number)?.toFloat()

    // A scoreboard draws many strings in a handful of styles; one paint each.
    val paint = cache.getOrPut(listOf(size, weight, family, color)) {
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = weighted(typefaceFor(family), weight, italic = false)
            // The canvas is scaled up by the density, so glyphs are measured
            // small and drawn large; without these the advances are rounded to
            // whole pixels at the small size and the letters visibly drift.
            isLinearText = true
            isSubpixelText = true
        }
    }

    if (maxWidth != null && maxWidth > 0f) {
        val alignment = when (align) {
            "center" -> Layout.Alignment.ALIGN_CENTER
            "right" -> Layout.Alignment.ALIGN_OPPOSITE
            else -> Layout.Alignment.ALIGN_NORMAL
        }
        val width = ceil(maxWidth).toInt()
        val layout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                .setAlignment(alignment)
                .setIncludePad(false)
                .build()
        } else {
            @Suppress("DEPRECATION")
            StaticLayout(text, paint, width, alignment, 1f, 0f, false)
        }
        return CanvasOp {
            val save = it.save()
            it.translate(x, y)
            layout.draw(it)
            it.restoreToCount(save)
        }
    }

    val baseline = y - paint.fontMetrics.ascent
    val start = when (align) {
        "center" -> x - paint.measureText(text) / 2f
        "right" -> x - paint.measureText(text)
        else -> x
    }
    return CanvasOp { it.drawText(text, start, baseline, paint) }
}

/**
 * [base] at a CSS-style [weight], italic or not.
 *
 * From API 28 a typeface can be asked for at any weight; before it there are
 * only regular and bold, and 600 is where the renderer has always drawn the
 * line between them.
 */
internal fun weighted(base: Typeface?, weight: Int, italic: Boolean): Typeface {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        return Typeface.create(base ?: Typeface.DEFAULT, weight.coerceIn(1, 1000), italic)
    }
    val style = when {
        weight >= 600 && italic -> Typeface.BOLD_ITALIC
        weight >= 600 -> Typeface.BOLD
        italic -> Typeface.ITALIC
        else -> Typeface.NORMAL
    }
    return Typeface.create(base ?: Typeface.DEFAULT, style)
}

// -----------------------------------------------------------------------------
// Stack
// -----------------------------------------------------------------------------

/**
 * The view a `Positioned` node becomes: its child, and the edges to pin it to.
 *
 * Inside a [StackLayout] the stack reads the edges and places it. Anywhere
 * else it is a frame around its child and nothing more, which is what the
 * protocol says a Positioned outside a stack is.
 */
internal class PositionedFrame(context: Context) : FrameLayout(context) {
    var edgeLeft: Int? = null
    var edgeTop: Int? = null
    var edgeRight: Int? = null
    var edgeBottom: Int? = null
    var fixedWidth: Int? = null
    var fixedHeight: Int? = null
}

/**
 * The view behind a `Stack`: children over one another, first at the back.
 *
 * The children that are not positioned decide the stack's size (unless its
 * parent already has) and sit at the alignment; the positioned ones are then
 * measured against that size and pinned to the edges they name.
 */
internal class StackLayout(context: Context) : FrameLayout(context) {
    /** Null is the start edge: the left, or the right in a right-to-left screen. */
    var alignX: Float? = null
    var alignY = -1f

    /** `fit: 'expand'`: the unpositioned children fill the stack. */
    var expandFit = false

    /**
     * Whether what is drawn outside the stack is cut off - at the *stack's*
     * edge, which is what Flutter's `clipBehavior` means. The platform's own
     * `clipChildren` cuts each child at the child's edge instead, and with it
     * the shadow of a button pinned in a corner, so that is always off and
     * the stack clips for itself (see [dispatchDraw]).
     */
    var clips = true
        set(value) {
            field = value
            invalidate()
            if (!value && isAttachedToWindow) letDrawOutside(this)
        }

    init {
        clipChildren = false
        clipToPadding = false
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (!clips) {
            super.dispatchDraw(canvas)
            return
        }
        val save = canvas.save()
        canvas.clipRect(0, 0, width, height)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // A child drawn outside the stack is outside the stack's own bounds
        // too, and it is the stack's *parent* that clips to those.
        if (!clips) letDrawOutside(this)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val wMode = MeasureSpec.getMode(widthMeasureSpec)
        val hMode = MeasureSpec.getMode(heightMeasureSpec)
        val wSize = MeasureSpec.getSize(widthMeasureSpec)
        val hSize = MeasureSpec.getSize(heightMeasureSpec)
        val wBounded = wMode != MeasureSpec.UNSPECIFIED
        val hBounded = hMode != MeasureSpec.UNSPECIFIED

        fun loose(bounded: Boolean, size: Int) =
            if (bounded) MeasureSpec.makeMeasureSpec(size, MeasureSpec.AT_MOST)
            else MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)

        fun exact(size: Int) = MeasureSpec.makeMeasureSpec(max(0, size), MeasureSpec.EXACTLY)

        var widest = 0
        var tallest = 0
        var unpositioned = false
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE || isPinned(child)) continue
            unpositioned = true
            child.measure(
                if (expandFit && wBounded) exact(wSize) else loose(wBounded, wSize),
                if (expandFit && hBounded) exact(hSize) else loose(hBounded, hSize),
            )
            widest = max(widest, child.measuredWidth)
            tallest = max(tallest, child.measuredHeight)
        }

        // With nothing unpositioned to size it, a stack is as big as it is
        // allowed to be - a board made only of pinned pieces still has a size.
        fun settle(mode: Int, size: Int, content: Int) = when {
            mode == MeasureSpec.EXACTLY -> size
            mode == MeasureSpec.AT_MOST ->
                if (unpositioned && !expandFit) min(content, size) else size
            else -> content
        }
        val width = settle(wMode, wSize, widest)
        val height = settle(hMode, hSize, tallest)

        for (i in 0 until childCount) {
            val child = getChildAt(i) as? PositionedFrame ?: continue
            if (child.visibility == GONE || !isPinned(child)) continue
            val l = child.edgeLeft
            val r = child.edgeRight
            val t = child.edgeTop
            val b = child.edgeBottom
            val w = child.fixedWidth
            val h = child.fixedHeight
            child.measure(
                // Two opposite edges stretch the child between them.
                if (l != null && r != null) exact(width - l - r)
                else if (w != null) exact(w)
                else MeasureSpec.makeMeasureSpec(width, MeasureSpec.AT_MOST),
                if (t != null && b != null) exact(height - t - b)
                else if (h != null) exact(h)
                else MeasureSpec.makeMeasureSpec(height, MeasureSpec.AT_MOST),
            )
        }
        setMeasuredDimension(width, height)
    }

    private fun isPinned(child: View): Boolean = child is PositionedFrame

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val width = r - l
        val height = b - t
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            val w = child.measuredWidth
            val h = child.measuredHeight
            // An axis a positioned child names no edge on falls back to the
            // alignment, as an unpositioned child's both do.
            val alignX = alignX ?: if (layoutDirection == LAYOUT_DIRECTION_RTL) 1f else -1f
            var x = ((width - w) * ((alignX + 1f) / 2f)).roundToInt()
            var y = ((height - h) * ((alignY + 1f) / 2f)).roundToInt()
            if (child is PositionedFrame) {
                val left = child.edgeLeft
                val right = child.edgeRight
                val top = child.edgeTop
                val bottom = child.edgeBottom
                if (left != null) x = left else if (right != null) x = width - right - w
                if (top != null) y = top else if (bottom != null) y = height - bottom - h
            }
            child.layout(x, y, x + w, y + h)
        }
    }
}

// -----------------------------------------------------------------------------
// Scroll
// -----------------------------------------------------------------------------

/**
 * What both scrollers share: where they were, and where they were told to go.
 *
 * A scroll position can only be set once the content has been laid out, so a
 * position to restore - or one the app asked for - waits in [pending] for the
 * next layout. A reversed scroller measures from the far end: it opens there,
 * and stays the same distance from it when the content grows, which is what
 * keeps a chat at its newest message.
 */
internal class ScrollMemory(private val view: ViewGroup, private val horizontal: Boolean) {
    var reverse = false

    /** An offset from the start (or, reversed, from the end) to apply at the next layout. */
    var pending: Int? = null

    /** Called with the offset - measured the same way - as it changes. */
    var onOffset: ((Int) -> Unit)? = null

    /**
     * Called with the offset, how far it can go and the scroller's own length
     * on its axis, in pixels, for the app: when the scroller comes to rest and
     * at most every [REPORT_EVERY_MS] on the way. Scrolling fires once a
     * frame, and a message per frame across the channel - and a rebuild per
     * frame, for an app that listens - is what this is here to avoid.
     */
    var onReport: ((offset: Int, range: Int, viewport: Int) -> Unit)? = null

    private var reported = -1
    private var reportedAt = 0L
    private val settled = Runnable { report() }

    private fun report() {
        val send = onReport ?: return
        if (!view.isAttachedToWindow) return
        val range = range()
        val offset = if (reverse) range - position() else position()
        if (offset == reported) return
        reported = offset
        reportedAt = SystemClock.uptimeMillis()
        val viewport = if (horizontal) {
            view.width - view.paddingLeft - view.paddingRight
        } else {
            view.height - view.paddingTop - view.paddingBottom
        }
        send(offset, range, viewport)
    }

    private fun moved() {
        if (onReport == null) return
        view.removeCallbacks(settled)
        if (SystemClock.uptimeMillis() - reportedAt >= REPORT_EVERY_MS) report()
        // Nothing for a little longer than a frame or two: it has stopped.
        view.postDelayed(settled, REPORT_EVERY_MS + 20)
    }

    private var lastRange = -1
    private var fromEnd = 0
    private var placing = false

    private fun range(): Int {
        val content = view.getChildAt(0) ?: return 0
        return if (horizontal) {
            max(0, content.width - (view.width - view.paddingLeft - view.paddingRight))
        } else {
            max(0, content.height - (view.height - view.paddingTop - view.paddingBottom))
        }
    }

    private fun position() = if (horizontal) view.scrollX else view.scrollY

    private fun place(position: Int) {
        placing = true
        if (horizontal) view.scrollTo(position, 0) else view.scrollTo(0, position)
        placing = false
    }

    /** Goes to [offset] now if there is a layout to go to it in, else at the next one. */
    fun jumpTo(offset: Int) {
        pending = offset
        if (view.isLaidOut && !view.isLayoutRequested) laidOut() else view.requestLayout()
    }

    fun laidOut() {
        val range = range()
        val wanted = pending
        if (wanted != null) {
            pending = null
            val offset = wanted.coerceIn(0, range)
            place(if (reverse) range - offset else offset)
            fromEnd = if (reverse) offset else range - position()
            // The app asked for this, but not for where it was held to: "the
            // end" is wherever the content turned out to stop.
            moved()
        } else if (reverse && range != lastRange) {
            place((range - fromEnd).coerceIn(0, range))
        }
        lastRange = range
    }

    fun scrolled() {
        if (placing) return
        val range = range()
        fromEnd = range - position()
        onOffset?.invoke(if (reverse) fromEnd else position())
        moved()
    }

    private companion object {
        const val REPORT_EVERY_MS = 100L
    }
}

/** The vertical scroller behind a `Scroll`. Nested, so it works under pull-to-refresh. */
internal class VerticalScroller(context: Context) : NestedScrollView(context) {
    val memory = ScrollMemory(this, horizontal = false)

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        memory.laidOut()
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        memory.scrolled()
    }
}

/** The horizontal scroller behind a `Scroll`. */
internal class HorizontalScroller(context: Context) : HorizontalScrollView(context) {
    val memory = ScrollMemory(this, horizontal = true)

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        memory.laidOut()
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        memory.scrolled()
    }
}

/**
 * Pull-to-refresh around a [VerticalScroller].
 *
 * The spinner belongs to the tree: [shown] is what the last render said, and a
 * pull that the app does not answer with `refreshing: true` puts the spinner
 * straight back rather than leaving it turning forever.
 */
@SuppressLint("ViewConstructor")
internal class RefreshFrame(context: Context, val scroller: VerticalScroller) :
    SwipeRefreshLayout(context) {

    var eventId: String? = null

    var shown = false
        set(value) {
            field = value
            settle()
        }

    /** Puts the spinner where the tree last said it should be. */
    fun settle() {
        if (isRefreshing != shown) isRefreshing = shown
    }

    init {
        addView(
            scroller,
            LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
    }
}

/** The scroller inside the view a `Scroll` node rendered to, whichever shape that took. */
internal fun scrollerOf(view: View): ViewGroup? = when (view) {
    is RefreshFrame -> view.scroller
    is VerticalScroller, is HorizontalScroller -> view as ViewGroup
    else -> null
}

internal fun scrollMemoryOf(view: View): ScrollMemory? = when (val scroller = scrollerOf(view)) {
    is VerticalScroller -> scroller.memory
    is HorizontalScroller -> scroller.memory
    else -> null
}

// -----------------------------------------------------------------------------
// The root container, and the holes Flutter shows through
// -----------------------------------------------------------------------------

/**
 * The view a `FlutterSlot` becomes: nothing, of a stated size.
 *
 * It draws nothing and takes no touch. The [SlotHostLayout] above everything
 * cuts its rectangle out of the native drawing and lets a touch that starts in
 * it fall through, so what is seen and touched there is the FlutterView
 * underneath.
 */
@SuppressLint("ViewConstructor")
internal class FlutterSlotView(context: Context, var slotId: String) : View(context) {
    /** Pixels; a null width fills what is offered. */
    var slotWidth: Int? = null
    var slotHeight = 0

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val offered = MeasureSpec.getSize(widthMeasureSpec)
        val bounded = MeasureSpec.getMode(widthMeasureSpec) != MeasureSpec.UNSPECIFIED
        val width = slotWidth?.let { if (bounded) min(it, offered) else it }
            ?: if (bounded) offered else 0
        // The height is the tree's: Flutter lays its widget out against the
        // rectangle reported from here, so it cannot depend on a parent's mood.
        setMeasuredDimension(width, slotHeight)
    }
}

/**
 * The full-screen layer of a dialog or a sheet - a type, so it can be found.
 *
 * Its first child is the scrim, and the scrim reaches the bottom of the window
 * where the layer itself does not: the container keeps its content above the
 * navigation bar by padding itself, so a scrim the size of the layer left a
 * strip of the screen along the bottom at full brightness under every dialog.
 */
internal class ModalLayerFrame(context: Context) : FrameLayout(context) {
    init {
        // The surface's shadow falls outside the frame that bounds it, and a
        // layer that clipped its children cut it off square at that frame's
        // edge - a dark band past each rounded corner.
        clipChildren = false
    }

    /** The renderer's container, whose padding is the room under the layer. */
    private fun host(): SlotHostLayout? {
        var above = parent
        while (above != null && above !is SlotHostLayout) above = above.parent
        return above as? SlotHostLayout
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // The scrim is drawn outside the layer, and outside the padding of
        // everything between it and the container.
        var above = parent
        while (above is ViewGroup) {
            above.clipChildren = false
            above.clipToPadding = false
            if (above is SlotHostLayout) break
            above = above.parent
        }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        val scrim = getChildAt(0) ?: return
        val under = host()?.paddingBottom ?: return
        scrim.layout(0, 0, r - l, b - t + under)
    }
}

/**
 * The container the renderer lays over the FlutterView.
 *
 * Ordinarily it is a plain frame. With a `FlutterSlot` on screen it has
 * [holes]: rectangles, in its own coordinates, that it neither draws in nor
 * takes a touch in.
 *
 *  - Drawing: the clip is applied here, around *everything*, because a hole
 *    has to go through every ancestor of the slot - the scaffold's background,
 *    a card's - and this is the one view that is above all of them.
 *  - Touch: a gesture is routed by where it goes down. Answering false for a
 *    down inside a hole makes the activity's content frame offer it to the next
 *    view under the finger, which is the FlutterView; the rest of that gesture
 *    then never comes here.
 */
internal class SlotHostLayout(context: Context) : FrameLayout(context) {
    private var holes: List<Rect> = emptyList()

    fun setHoles(next: List<Rect>) {
        if (next == holes) return
        holes = next
        // On a hardware canvas the clip is recorded into this view's display
        // list, which is only re-recorded when this view is invalidated - a
        // child scrolling the slot along does not do that by itself.
        invalidate()
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (holes.isEmpty()) {
            super.dispatchDraw(canvas)
            return
        }
        val save = canvas.save()
        for (hole in holes) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                canvas.clipOutRect(hole)
            } else {
                @Suppress("DEPRECATION")
                canvas.clipRect(hole, Region.Op.DIFFERENCE)
            }
        }
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN &&
            holes.any { it.contains(ev.x.toInt(), ev.y.toInt()) }
        ) {
            return false
        }
        return super.dispatchTouchEvent(ev)
    }
}

/**
 * A column that is as wide as its widest child wants it, when nothing fixes
 * its width.
 *
 * A LinearLayout that wraps leaves its MATCH_PARENT children out of its own
 * width - they fill whatever the others made it - and a `Row`, a `Wrap` or a
 * box that expands is such a child. So a hugging column of one narrow widget
 * and a wider row came out as wide as the widget, with the row squeezed into
 * it and its children clipped; a wrap was broken into lines at that width but
 * kept the height of the one line it had first been measured as; and a board
 * that takes the width on offer got the width of the button under it. In
 * Flutter those children have a say: a row needs the room its children take,
 * and a box that expands takes all there is.
 */
internal class ColumnLayout(context: Context) : LinearLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val mode = MeasureSpec.getMode(widthMeasureSpec)
        if (mode == MeasureSpec.EXACTLY || orientation != VERTICAL) return
        val offered = MeasureSpec.getSize(widthMeasureSpec)
        val insets = paddingLeft + paddingRight
        var widest = measuredWidth
        var found = false
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val params = child.layoutParams as? LayoutParams ?: continue
            if (child.visibility == GONE || params.width != LayoutParams.MATCH_PARENT) continue
            if (child is BoxLayout && child.style.expandWidth) {
                // All of it - which only means something when there is a limit.
                if (mode != MeasureSpec.AT_MOST) continue
                widest = offered
            } else if (child.javaClass != View::class.java) {
                // Anything but a bare spacer, which has no width to want: a
                // row, a wrap, a slider says how wide it would be.
                val margins = params.leftMargin + params.rightMargin
                child.measure(
                    getChildMeasureSpec(
                        widthMeasureSpec, insets + margins, LayoutParams.WRAP_CONTENT),
                    MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
                )
                widest = max(widest, child.measuredWidth + insets + margins)
            } else {
                continue
            }
            found = true
        }
        if (!found) return
        if (mode == MeasureSpec.AT_MOST) widest = min(widest, offered)
        // Again at the width found, whether or not it grew: the rows were just
        // measured on their own and have to be put back at the column's.
        super.onMeasure(
            MeasureSpec.makeMeasureSpec(widest, MeasureSpec.EXACTLY),
            heightMeasureSpec,
        )
    }
}

// -----------------------------------------------------------------------------
// Parts the renderer finds again
// -----------------------------------------------------------------------------

/**
 * A scaffold: the bar, the body's area, the bar along the bottom.
 *
 * The renderer patches a scaffold's children in place, and to do that it has to
 * get from each child node back to the view that node became. They are kept by
 * name here rather than dug out by index, because which indices exist depends
 * on which of the four children the app gave.
 */
internal class ScaffoldLayout(context: Context) : LinearLayout(context) {
    var barView: View? = null
    var bodyView: View? = null
    var fabView: View? = null
    var bottomView: View? = null

    /** Holds the body (scrolling or not) with the floating button over it. */
    val bodyArea = FrameLayout(context)

    init {
        orientation = VERTICAL
    }
}

/**
 * The layer a snackbar sits in, which keeps it clear of what the scaffold
 * under it has at the bottom: Material shows a snackbar above the bottom
 * navigation bar and above the floating button, never over them.
 *
 * The snackbar is drawn beside the scaffold, not inside it, so it cannot be
 * laid out against those views; it is lifted by however far it would reach
 * into them instead. That is checked as each frame is drawn rather than at
 * layout: the bar under it can change - another tab, a button that appeared -
 * without this layer being laid out again.
 */
internal class SnackbarHost(context: Context) :
    FrameLayout(context), ViewTreeObserver.OnPreDrawListener {

    /** The room kept between the snackbar and what it is lifted above. */
    var gap = 0

    private val at = IntArray(2)

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnPreDrawListener(this)
    }

    override fun onDetachedFromWindow() {
        viewTreeObserver.removeOnPreDrawListener(this)
        super.onDetachedFromWindow()
    }

    override fun onPreDraw(): Boolean {
        val bar = getChildAt(0) ?: return true
        val scaffold = (parent as? ViewGroup)?.let { scaffoldIn(it, 0) }
        var ceiling = Int.MAX_VALUE
        for (below in listOf(scaffold?.bottomView, scaffold?.fabView)) {
            if (below == null || !below.isShown || below.height == 0) continue
            below.getLocationInWindow(at)
            ceiling = min(ceiling, at[1])
        }
        getLocationInWindow(at)
        val lift =
            if (ceiling == Int.MAX_VALUE) 0 else max(0, at[1] + bar.bottom + gap - ceiling)
        if (bar.translationY != -lift.toFloat()) bar.translationY = -lift.toFloat()
        return true
    }

    /** The scaffold on screen under [group]: the first one, a few levels down. */
    private fun scaffoldIn(group: ViewGroup, depth: Int): ScaffoldLayout? {
        for (index in 0 until group.childCount) {
            val child = group.getChildAt(index)
            if (child === this || child.visibility != VISIBLE) continue
            if (child is ScaffoldLayout) return child
            if (child is ViewGroup && depth < 6) scaffoldIn(child, depth + 1)?.let { return it }
        }
        return null
    }
}

/** A navigation rail in the scroller that lets it be taller than the window. */
@SuppressLint("ViewConstructor")
internal class RailScroller(context: Context, val rail: NavigationRailView) :
    ScrollView(context) {
    init {
        isFillViewport = true
        isVerticalScrollBarEnabled = false
        addView(
            rail,
            LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )
    }
}

/** The row of actions at the end of an app bar; its children are the action nodes' views. */
internal class AppBarActions(context: Context) : LinearLayout(context)

/** The holder of an app bar's title subtree. */
internal class AppBarTitle(context: Context) : FrameLayout(context)

/**
 * A weighted gap a row or column puts between its children to distribute them.
 * A type of its own so the views that *are* children can be told from it.
 */
internal class DistributeGap(context: Context) : View(context)
