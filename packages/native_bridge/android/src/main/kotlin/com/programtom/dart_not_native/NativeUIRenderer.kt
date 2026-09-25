package com.programtom.dart_not_native

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.view.Choreographer
import android.view.inputmethod.EditorInfo
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.Interpolator
import android.view.animation.LinearInterpolator
import android.webkit.WebView
import android.widget.CheckBox
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatTextView
import androidx.appcompat.widget.SwitchCompat
import android.util.TypedValue
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.slider.Slider
import com.google.android.material.tabs.TabLayout
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Android Native UI Renderer.
 *
 * Turns the widget tree the Dart side sends into Android Views, and sends the
 * events those views produce back. The node vocabulary is the one every
 * renderer implements, so a screen written for the web DOM renderer renders
 * here unchanged.
 *
 * Constructed by [DartNotNativePlugin] once the engine is attached to an
 * activity, so an app gets it from the dependency rather than by copying this
 * file.
 */
class NativeUIRenderer(
    private val activity: Activity,
    private val messenger: BinaryMessenger
) {
    companion object {
        private const val CHANNEL = "com.programtom.dart_not_native/renderer"

        /**
         * Text over a light colour the app stated, and over a dark one. The
         * same two the Dart renderers use - see `lib/src/contrast.dart`.
         */
        /** The version an `autofocus` counts as, which is asked once. */
        private const val AUTOFOCUS_VERSION = -1

        private const val ON_LIGHT = "#212121"
        private const val ON_DARK = "#ffffff"

        /** Dart's method for an event coming back from a native view. */
        private const val EVENT_METHOD = "event"

        /**
         * The Material Icons codepoint for `close`, which the renderer draws
         * itself rather than receiving on a node - see `materialIconCodepoint`
         * in lib/src/material_icons.dart, the table it is taken from.
         */
        private const val CLOSE_CODEPOINT = 0xe16a

        /**
         * Material icon names mapped onto the drawables every device has.
         * A name with no match falls back to a visible dot rather than an
         * invisible button.
         */
        private val ICONS = mapOf(
            "add" to android.R.drawable.ic_input_add,
            "delete" to android.R.drawable.ic_menu_delete,
            "edit" to android.R.drawable.ic_menu_edit,
            "close" to android.R.drawable.ic_menu_close_clear_cancel,
            "search" to android.R.drawable.ic_menu_search,
            "share" to android.R.drawable.ic_menu_share,
            "save" to android.R.drawable.ic_menu_save,
            "refresh" to android.R.drawable.ic_popup_sync,
            "info" to android.R.drawable.ic_dialog_info,
            "warning" to android.R.drawable.ic_dialog_alert,
            "more_vert" to android.R.drawable.ic_menu_more,
            "arrow_back" to android.R.drawable.ic_media_previous,
            "arrow_forward" to android.R.drawable.ic_media_next,
            "check" to android.R.drawable.checkbox_on_background,
            "settings" to android.R.drawable.ic_menu_preferences,
        )
    }

    private var rootContainer: FrameLayout? = null
    private var channel: MethodChannel? = null

    /** One appearance's colours, sent by Dart with `initialize`. */
    private data class Palette(
        val primary: String = "#1976d2",
        val onPrimary: String = "#ffffff",
        val secondary: String = "#f57c00",
        val surface: String = "#ffffff",
        val surfaceVariant: String = "#f5f5f5",
        val text: String = "#212121",
        val textSecondary: String = "#757575",
        val divider: String = "#e0e0e0",
        val error: String = "#d32f2f",
        val success: String = "#388e3c",
        val warning: String = "#fbc02d",
        val info: String = "#0288d1",
    ) {
        companion object {
            val DARK = Palette(
                primary = "#90caf9",
                onPrimary = "#00325b",
                secondary = "#ffb74d",
                surface = "#121212",
                surfaceVariant = "#1e1e1e",
                text = "#ececec",
                textSecondary = "#a8a8a8",
                divider = "#323232",
                error = "#ef5350",
                success = "#66bb6a",
                warning = "#ffca28",
                info = "#4fc3f7",
            )

            fun from(json: Map<*, *>?, or: Palette): Palette = Palette(
                primary = json?.get("primary") as? String ?: or.primary,
                onPrimary = json?.get("onPrimary") as? String ?: or.onPrimary,
                secondary = json?.get("secondary") as? String ?: or.secondary,
                surface = json?.get("surface") as? String ?: or.surface,
                surfaceVariant =
                    json?.get("surfaceVariant") as? String ?: or.surfaceVariant,
                text = json?.get("text") as? String ?: or.text,
                textSecondary =
                    json?.get("textSecondary") as? String ?: or.textSecondary,
                divider = json?.get("divider") as? String ?: or.divider,
                error = json?.get("error") as? String ?: or.error,
                success = json?.get("success") as? String ?: or.success,
                warning = json?.get("warning") as? String ?: or.warning,
                info = json?.get("info") as? String ?: or.info,
            )
        }
    }

    private var lightPalette = Palette()
    private var darkPalette = Palette.DARK

    /** "light", "dark" or "system" - which appearance to paint. */
    private var themeMode: String = "light"

    /** The appearance last painted, so a render can notice the device changing
     *  its mind and rebuild instead of patching stale colours in place. */
    private var paintedDark: Boolean? = null

    /** Whether the dark palette is in force. */
    private val isDarkAppearance: Boolean
        get() = when (themeMode) {
            "dark" -> true
            "system" ->
                (activity.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            else -> false
        }

    /** The palette in force, and the other one - which the snackbar is drawn
     *  on, so it reads as a message over the app rather than vanishing into it. */
    private val palette: Palette get() = if (isDarkAppearance) darkPalette else lightPalette
    private val inversePalette: Palette
        get() = if (isDarkAppearance) lightPalette else darkPalette

    private val themePrimary: String get() = palette.primary
    private val themeOnPrimary: String get() = palette.onPrimary
    private val themeSecondary: String get() = palette.secondary
    private val themeSurface: String get() = palette.surface
    private val themeSurfaceVariant: String get() = palette.surfaceVariant
    private val themeText: String get() = palette.text
    private val themeTextSecondary: String get() = palette.textSecondary
    private val themeDivider: String get() = palette.divider
    private val themeError: String get() = palette.error
    private val themeSuccess: String get() = palette.success
    private val themeWarning: String get() = palette.warning
    private val themeInfo: String get() = palette.info

    /** The semantic colour for a node's `variant`, themed where it maps to a
     *  palette entry. */
    private fun variantColor(variant: Any?): String = when (variant) {
        "secondary" -> themeSecondary
        "success" -> themeSuccess
        "error" -> themeError
        "warning" -> themeWarning
        "info" -> themeInfo
        else -> themePrimary
    }

    // Material components (MaterialButton, MaterialToolbar, the FAB, cards) throw
    // unless their Context carries a Theme.MaterialComponents. The host app's
    // own theme need not be one - the framework promises zero app-side setup -
    // so Material views are built against this wrapper instead of the activity.
    // The wrapper follows the appearance too: a MaterialButton or a SwitchCompat
    // takes its own ripple, track and disabled colours from the theme, and a
    // light Material theme under a dark palette shows through wherever the
    // renderer does not paint a colour itself.
    private val lightMaterialContext: Context = ContextThemeWrapper(
        activity,
        com.google.android.material.R.style.Theme_MaterialComponents_Light_NoActionBar
    )
    private val darkMaterialContext: Context = ContextThemeWrapper(
        activity,
        com.google.android.material.R.style.Theme_MaterialComponents_NoActionBar
    )
    private val materialContext: Context
        get() = if (isDarkAppearance) darkMaterialContext else lightMaterialContext

    /**
     * The Material Icons font, which `uses-material-design: true` already bundles
     * into every build, so an icon is drawn as the real glyph rather than an
     * approximate system drawable. Null if the font is not where it is expected.
     */
    private val iconFont: Typeface? by lazy {
        try {
            Typeface.createFromAsset(
                activity.assets, "flutter_assets/fonts/MaterialIcons-Regular.otf")
        } catch (e: Exception) {
            null
        }
    }

    // The view tree is rebuilt on every render, so state that must outlive one
    // render - a snackbar's timeout, a lazy list's scroll position and the
    // range it last reported - lives here, keyed by the node's identity.
    private val handler = Handler(Looper.getMainLooper())
    private val snackbarTimers = mutableMapOf<String, Runnable>()
    private val lazyScroll = mutableMapOf<String, Int>()
    private val lazyRanges = mutableMapOf<String, Pair<Int, Int>>()

    /** The pixels each list of rows of their own heights last reported. */
    private val lazyOffsets = mutableMapOf<String, Pair<Float, Float>>()

    // The identities the render in progress has drawn; state for any other is
    // dropped once it finishes.
    private val renderedSnackbars = mutableSetOf<String>()
    private val renderedLists = mutableSetOf<String>()

    /** Node types the render in progress could not draw; reported back to Dart. */
    private val unknownTypes = mutableSetOf<String>()

    /**
     * True while a render is tearing the focused field down and standing it back
     * up. The focus and blur that churn causes are the renderer's doing, not the
     * user's, so they are suppressed - otherwise restoring focus fires a focus
     * event that re-renders, which refocuses, which re-renders, forever.
     */
    private var restoringFocus = false

    /**
     * The focus ask each field has already carried out, by event id, so the
     * same one is not obeyed twice. "Focus this" is a moment, and a tree only
     * carries states - the version is how the moment travels.
     */
    private val focusVersions = mutableMapOf<String, Int>()

    /**
     * True while a patch sets a checkbox or switch's state, so the checked
     * change that causes is not mistaken for the user toggling it - which would
     * send an event and re-render, setting it again, forever.
     */
    private var settingChecked = false

    /**
     * The normalised tree the views currently show, and the view that shows it.
     * The next render diffs against them; a null tree forces a full rebuild.
     */
    private var currentTree: Map<*, *>? = null
    private var currentRoot: View? = null

    /** The system bar insets last dispatched, so a rebuilt view starts from them. */
    private var systemBars = Insets.NONE

    fun setupChannels() {
        val channel = MethodChannel(messenger, CHANNEL)
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    (call.arguments as? Map<*, *>)?.let { t ->
                        // The light palette is the message's own fields; the
                        // dark one is nested, and absent means the built-in.
                        lightPalette = Palette.from(t, Palette())
                        darkPalette =
                            Palette.from(t["dark"] as? Map<*, *>, Palette.DARK)
                        themeMode = t["mode"] as? String ?: "light"
                    }
                    initialize()
                    result.success(null)
                }
                "render" -> {
                    val tree = call.arguments as? Map<*, *>
                    result.success(renderTree(tree))
                }
                "startFrameProbe" -> {
                    startFrameProbe()
                    result.success(null)
                }
                "stopFrameProbe" -> result.success(stopFrameProbe())
                else -> result.notImplemented()
            }
        }
    }

    private fun initialize() {
        if (rootContainer != null) return

        // The container is added over the Flutter view, so rendered native
        // views are actually on screen - Flutter then only hosts the engine.
        val container = FrameLayout(activity)
        activity.addContentView(
            container,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        rootContainer = container
        avoidKeyboard(container)
    }

    // -------------------------------------------------------------------------
    // Frame probe
    // -------------------------------------------------------------------------

    private var frameProbeRunning = false
    private var frameProbeLast = 0L
    private val frameProbeIntervals = mutableListOf<Double>()

    private val frameProbeCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!frameProbeRunning) return
            if (frameProbeLast > 0L) {
                frameProbeIntervals.add((frameTimeNanos - frameProbeLast) / 1_000_000.0)
            }
            frameProbeLast = frameTimeNanos
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    /**
     * Records the gap between frames while the probe runs.
     *
     * The Choreographer dispatches on the main thread, which is where the
     * renderer's own work happens - laying out a lazy list's window, rebuilding
     * a subtree - so anything that overruns a frame delays the next callback by
     * exactly as much as a viewer would see. An idle screen reads as a clean run
     * of nominal intervals.
     *
     * Nothing is posted, and nothing recorded, until this is called.
     */
    private fun startFrameProbe() {
        frameProbeRunning = false
        frameProbeIntervals.clear()
        frameProbeLast = 0L
        frameProbeRunning = true
        Choreographer.getInstance().postFrameCallback(frameProbeCallback)
    }

    private fun stopFrameProbe(): Map<String, Any>? {
        if (!frameProbeRunning) return null
        frameProbeRunning = false
        Choreographer.getInstance().removeFrameCallback(frameProbeCallback)
        return mapOf(
            "intervalsMs" to frameProbeIntervals.toList(),
            "refreshHz" to displayRefreshHz(),
        )
    }

    /** The display's refresh rate, which sets the budget a frame is measured against. */
    private fun displayRefreshHz(): Double {
        val rate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.refreshRate
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay?.refreshRate
        }
        return rate?.toDouble()?.takeIf { it > 0 } ?: 60.0
    }

    /**
     * Keeps a focused field out from under the soft keyboard.
     *
     * The container is padded at the bottom by however much of it the keyboard
     * covers, which shortens everything inside - a scaffold's body ScrollView, a
     * lazy list, a bottom sheet along the container's bottom edge - and then the
     * focused view is asked onto the screen, which the enclosing ScrollView
     * honours.
     *
     * The overlap is measured, rather than taken as the IME inset, because the
     * two windowing modes need different answers: with `adjustResize` on a
     * window that is not edge-to-edge the window has already shrunk and padding
     * it again would leave a gap, while edge-to-edge (the default from Android
     * 15) does not resize and the whole keyboard height has to come off here.
     * The visible display frame, which excludes the keyboard, tells the two
     * apart with the same arithmetic. Padding does not change the container's
     * own height, so the measurement cannot chase itself.
     *
     * That frame excludes the *navigation* bar too, which is why the bottom
     * edge clears it with no keyboard open at all: the container stops above
     * the bar rather than drawing under it, by 63px under gestures and 126px
     * under three buttons on the phone this was measured on - both arrived at
     * by themselves, because the number is measured rather than named. So this
     * function owns the bottom inset as much as it owns the keyboard, and a
     * later change that padded only while the keyboard was open would quietly
     * put the content back under the navigation bar. `renderer_coverage_test`
     * pins the measurement for that reason.
     */
    private fun avoidKeyboard(container: View) {
        val apply = {
            val visible = Rect()
            container.getWindowVisibleDisplayFrame(visible)
            val location = IntArray(2)
            container.getLocationOnScreen(location)
            val overlap = (location[1] + container.height - visible.bottom).coerceAtLeast(0)
            if (container.paddingBottom != overlap) {
                // Posted rather than applied here: one of the two callers below
                // runs inside a layout pass, and changing padding there is a
                // requestLayout during layout. The guard above runs again on the
                // next pass if the post is beaten to it, so nothing is lost.
                container.post {
                    container.updatePadding(bottom = overlap)
                    // Once the shorter layout lands, put the focused field on
                    // screen; the enclosing ScrollView answers by scrolling.
                    container.post {
                        val focused = container.findFocus() ?: return@post
                        // A little margin below, so the field does not land
                        // flush against the keyboard - the same 12 the iOS
                        // side insets by.
                        focused.requestRectangleOnScreen(
                            Rect(0, 0, focused.width, focused.height + dp(12)), false
                        )
                    }
                }
            }
        }
        ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
            apply()
            insets
        }
        // The insets listener fires on the window's terms; the layout listener
        // catches the resize itself, which is what arrives under adjustResize.
        container.viewTreeObserver.addOnGlobalLayoutListener { apply() }
    }

    /** Removes the container this renderer added to the activity. */
    fun dispose() {
        stopFrameProbe()
        val container = rootContainer ?: return
        (container.parent as? ViewGroup)?.removeView(container)
        rootContainer = null
        currentTree = null
        currentRoot = null
        snackbarTimers.values.forEach(handler::removeCallbacks)
        snackbarTimers.clear()
        lazyScroll.clear()
        lazyRanges.clear()
        lazyOffsets.clear()
        focusVersions.clear()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    /**
     * Renders a tree, diffing it against the one already on screen.
     *
     * Two paths, in order:
     *
     *  1. [tryPatch] walks the old and new trees together. A node whose type
     *     and props match keeps its view and recurses into its children; a
     *     changed leaf is re-derived in place ([patchText], [patchButton],
     *     [patchAppBar], [patchTextField] and the rest); a stacking container
     *     reconciles its children by `id` ([reconcileChildren]) so a list that
     *     gains, loses or reorders a row moves the views it already has, and
     *     [reconcileLazyList] does the same by `<id>/<index>` for the windowed
     *     rows. A focused EditText is left entirely alone.
     *  2. Anything [tryPatch] cannot express - a different type, a different
     *     child count, a prop only a rebuild can apply - returns false and
     *     falls through to the full rebuild below, which is always correct. So
     *     the diff can only ever make a render faster, never wrong.
     *
     * The shape is the web renderer's `_syncChildren`
     * (packages/native_bridge/lib/web_ui/web_renderer.dart), ported to Android
     * Views, where the saving is larger because inflating a View costs far more
     * than creating a DOM element.
     *
     * Neither path is covered by the test suite - `renderer_coverage_test` only
     * pins that every node type appears in the dispatch - so changes here need
     * a device or emulator to develop against.
     */
    private fun renderTree(tree: Map<*, *>?): Map<String, Any>? {
        if (tree == null) return mapOf("error" to "Error: tree is null")
        val root = rootContainer
            ?: return mapOf("error" to "Error: container not initialized")
        val next = normalized(tree)

        return try {
            unknownTypes.clear()

            // A colour is not a prop, so nothing in the tree changes when the
            // device switches appearance: the patch below would happily keep
            // every view it has, still painted in the old palette. Notice the
            // switch here and force the rebuild instead. (Dart sends the
            // render: the Flutter host watches `didChangePlatformBrightness`,
            // which fires for the same event that moved the night ui-mode this
            // reads.)
            val dark = isDarkAppearance
            if (paintedDark != dark) {
                paintedDark = dark
                currentTree = null
            }

            // Fast path: the tree kept its shape, so patch the changed leaves in
            // place and leave every other view - with the focus, caret, IME and
            // scroll it holds - untouched. This is what lets a field be typed
            // into and a list keep its position across a re-render. Any mismatch
            // returns false and falls through to the full rebuild, which is
            // always correct.
            val old = currentTree
            val oldRoot = currentRoot
            if (old != null && oldRoot != null && tryPatch(oldRoot, old, next)) {
                currentTree = next
                // A patch builds new views too - a lazy list's newly visible
                // rows - so it can meet an unknown type as readily as a rebuild.
                return if (unknownTypes.isEmpty()) null
                else mapOf("unknownTypes" to unknownTypes.sorted())
            }

            // Full rebuild. It destroys the focused field, so remember which one
            // (by its event id) and where its caret was, and restore both to the
            // rebuilt field - otherwise the render a keystroke triggers would
            // drop focus. Restoring focus fires the platform's own focus event,
            // which would re-render and refocus forever, so restoringFocus
            // suppresses the focus/blur the renderer itself causes.
            val focused = root.findFocus() as? EditText
            val focusKey = focused?.tag as? String
            val caretAtEnd =
                focused != null && focused.selectionEnd == (focused.text?.length ?: 0)
            restoringFocus = focusKey != null

            root.removeAllViews()
            renderedSnackbars.clear()
            renderedLists.clear()
            val view = renderWidget(next)
            if (view != null) {
                root.addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                )
            }
            currentRoot = view
            currentTree = next
            forgetUnrendered()

            if (focusKey != null) {
                val field = findEditTextByTag(root, focusKey)
                if (field != null) {
                    // requestFocus fails on a view that is not laid out yet, so
                    // defer it to after this rebuild's layout pass.
                    field.post {
                        field.requestFocus()
                        // Caret to the end, so appended characters keep order.
                        if (caretAtEnd) field.setSelection(field.text?.length ?: 0)
                        restoringFocus = false
                    }
                } else {
                    restoringFocus = false
                }
            }

            // An unknown node type draws a placeholder rather than throwing, so
            // report it here instead of leaving it as a silent surprise.
            // Structured, so Dart can list the types rather than parse the
            // sentence.
            if (unknownTypes.isEmpty()) null
            else mapOf("unknownTypes" to unknownTypes.sorted())
        } catch (e: Exception) {
            // A half-applied patch or build leaves the views in an unknown state;
            // forget the tree so the next render rebuilds from scratch.
            currentTree = null
            currentRoot = null
            mapOf("error" to "Render error: ${e.message}")
        }
    }

    // -------------------------------------------------------------------------
    // Reconciliation (the shape-preserving fast path)
    // -------------------------------------------------------------------------

    /**
     * Patches [view] from [oldNode] to [newNode] in place, returning true only
     * if the whole subtree kept its shape and every change was one this knows
     * how to apply. A false return means "rebuild"; nothing is left half-done
     * that a rebuild would not replace.
     */
    private fun tryPatch(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean =
        renderOver(statedBackground(newNode)) { patchNode(view, oldNode, newNode) }

    /** The background this node stated, if it stated one - see [renderOver]. */
    private fun statedBackground(node: Map<*, *>): Any? = when (node["type"]) {
        "Card" -> node["backgroundColor"]
        "AnimatedContainer" -> node["color"]
        else -> null
    }

    private fun patchNode(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        if (oldNode["type"] != newNode["type"]) return false
        // A lazy list frames its windowed rows by index rather than stacking
        // them, so it has its own keyed reconcile.
        if (newNode["type"] == "LazyList") return reconcileLazyList(view, oldNode, newNode)
        if (!patchSelf(view, oldNode, newNode)) return false

        val oldKids = childNodes(oldNode)
        val newKids = childNodes(newNode)
        if (oldKids.isEmpty() && newKids.isEmpty()) return true

        // A stacking container reconciles its children by id, so a row inserted,
        // removed or reordered moves the views already there instead of every row
        // after it being rebuilt.
        val list = keyedListContainer(view, newNode)
        if (list != null) {
            reconcileChildren(list, oldKids, newKids, newNode)
            return true
        }

        // Everything else (a Scaffold, a single-child wrapper) lines its children
        // up by position, and the count cannot change without a rebuild.
        if (oldKids.size != newKids.size) return false
        val childViews = childViews(view, newNode) ?: return false
        if (childViews.size != newKids.size) return false
        for (i in newKids.indices) {
            if (!tryPatch(childViews[i], oldKids[i], newKids[i])) return false
        }
        return true
    }

    /**
     * Reconciles a lazy list's windowed rows by their `<id>/<index>` keys, so a
     * scroll (which shifts the window) or an edit reuses the rows the two
     * windows share rather than rebuilding all of them. The rows are held in
     * window order, so the old row at position i is the one that produced
     * `rows.getChildAt(i)`; each is re-framed by its new index. Bails to a
     * rebuild if the view is not the expected scroll-view-over-frame shape.
     */
    private fun reconcileLazyList(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val scroll = view as? ReportingScrollView ?: return false
        val rows = scroll.getChildAt(0) as? FrameLayout ?: return false
        val oldRowNodes = childNodes(oldNode)
        val newRowNodes = childNodes(newNode)
        if (rows.childCount != oldRowNodes.size) return false

        val extent = ((newNode["itemExtent"] as? Number)?.toFloat() ?: 48f) *
            activity.resources.displayMetrics.density
        val startIndex = (newNode["startIndex"] as? Number)?.toInt() ?: 0
        val itemCount = (newNode["itemCount"] as? Number)?.toInt() ?: 0

        val oldByKey = HashMap<String, Int>()
        for ((i, node) in oldRowNodes.withIndex()) {
            (node["id"] as? String)?.let { oldByKey[it] = i }
        }

        // The row view for each new row, in window order - reused from the old
        // window where the keys match, built fresh otherwise.
        val newRows = ArrayList<View>(newRowNodes.size)
        for (newRow in newRowNodes) {
            val key = newRow["id"] as? String
            val oldIndex = if (key != null) oldByKey[key] else null
            val reused = oldIndex?.let { rows.getChildAt(it) }
            if (reused != null && tryPatch(reused, oldRowNodes[oldIndex!!], newRow)) {
                newRows.add(reused)
            } else {
                newRows.add(renderWidget(newRow) ?: View(activity))
            }
        }

        // Rows of their own heights arrive with the window's own heights and
        // where the window starts; uniform rows are arithmetic from the index.
        val density = activity.resources.displayMetrics.density
        val rowExtents = (newNode["extents"] as? List<*>)
            ?.map { ((it as? Number)?.toFloat() ?: 0f) * density }
        var running = ((newNode["startOffset"] as? Number)?.toFloat() ?: 0f) * density

        // Re-lay the window: detaching every row and re-adding the kept ones is a
        // re-parent, not a rebuild - no row view is created that a match covered.
        rows.removeAllViews()
        for ((offset, row) in newRows.withIndex()) {
            val index = startIndex + offset
            val top: Int
            val height: Int
            if (rowExtents == null) {
                top = (index * extent).roundToInt()
                height = ((index + 1) * extent).roundToInt() - top
            } else {
                top = running.roundToInt()
                running += rowExtents.getOrElse(offset) { 0f }
                height = running.roundToInt() - top
            }
            rows.addView(row, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, height).apply { topMargin = top })
        }
        rows.minimumHeight = if (rowExtents == null) {
            (itemCount * extent).roundToInt()
        } else {
            (((newNode["totalExtent"] as? Number)?.toFloat() ?: 0f) * density).roundToInt()
        }
        (newNode["id"] as? String)?.let { renderedLists += it }
        return true
    }

    /**
     * The [LinearLayout] whose direct children are [node]'s children one to one,
     * or null if this node is not a plain stacking list (its children then line
     * up by position instead).
     */
    private fun keyedListContainer(view: View, node: Map<*, *>): LinearLayout? =
        when (node["type"]) {
            "Column", "Row", "VStack", "HStack", "List", "ListView" ->
                // A spaced row carries extra spacer views between the children.
                if (node["mainAxisAlignment"] == "spaceBetween") null
                else view as? LinearLayout
            else -> null
        }

    /**
     * Reconciles [container]'s child views from [oldKids] to [newKids], matching
     * children that carry an `id` by it so a row keeps (and moves) the view it
     * already has. Children without an id fall back to matching by position.
     *
     * Mirrors the web renderer's `_syncChildren`: `standing` tracks, for each
     * view still in the container, the old node that produced it, and is
     * reordered alongside the views as rows move.
     */
    private fun reconcileChildren(
        container: LinearLayout,
        oldKids: List<Map<*, *>>,
        newKids: List<Map<*, *>>,
        parentNode: Map<*, *>,
    ) {
        val horizontal = parentNode["type"] == "Row" || parentNode["type"] == "HStack"
        val stretch = parentNode["type"] == "List" || parentNode["type"] == "ListView" ||
            (parentNode["type"] == "Column" && parentNode["crossAxisAlignment"] == "stretch")
        val standing = oldKids.toMutableList()

        for (i in newKids.indices) {
            val node = newKids[i]
            var existing = if (i < container.childCount) container.getChildAt(i) else null
            var before = standing.getOrNull(i)

            val id = node["id"] as? String
            if (id != null && before?.get("id") != id) {
                val found = indexOfId(standing, id, i)
                if (found != null) {
                    // The row is further down: move its view up to here.
                    val moved = container.getChildAt(found)
                    container.removeViewAt(found)
                    container.addView(moved, i)
                    standing.add(i, standing.removeAt(found))
                    existing = moved
                    before = standing[i]
                } else if (before?.get("id") != null) {
                    // A new keyed row among keyed ones: insert it, rather than
                    // overwrite a row still wanted further down.
                    container.addView(buildChild(node, horizontal, stretch), i)
                    standing.add(i, node)
                    continue
                }
            }

            if (existing != null && before != null &&
                before["type"] == node["type"] && tryPatch(existing, before, node)
            ) {
                standing[i] = node
                continue
            }

            val created = buildChild(node, horizontal, stretch)
            if (existing != null) {
                container.removeViewAt(i)
                container.addView(created, i)
                standing[i] = node
            } else {
                container.addView(created)
                standing.add(node)
            }
        }

        while (container.childCount > newKids.size) {
            container.removeViewAt(container.childCount - 1)
        }

        // Spacing is a per-index margin, so re-apply it now the rows have moved.
        val spacing = dp((parentNode["spacing"] as? Number)?.toInt() ?: 0)
        for (i in 0 until container.childCount) {
            val params = container.getChildAt(i).layoutParams as? LinearLayout.LayoutParams
                ?: continue
            if (horizontal) params.marginStart = if (i > 0) spacing else 0
            else params.topMargin = if (i > 0) spacing else 0
            container.getChildAt(i).layoutParams = params
        }
    }

    /** First index at or after [from] whose node carries [id]. */
    private fun indexOfId(nodes: List<Map<*, *>>, id: String, from: Int): Int? {
        for (i in from until nodes.size) if (nodes[i]["id"] == id) return i
        return null
    }

    /** Builds a child view for a stacking list, with the list's layout params. */
    private fun buildChild(node: Map<*, *>, horizontal: Boolean, stretch: Boolean): View {
        val view = renderWidget(node) ?: View(activity)
        view.layoutParams = stackChildParams(view, node, horizontal, stretch)
        return view
    }

    /**
     * The layout params for [view] as a child of a stacking list of the given
     * orientation. An `Expanded` fills the main axis through the weight it
     * already carries, but must be sized to the container's cross axis - height
     * in a row, width in a column - which is where it collapses if left at the
     * zero its own renderer set for an orientation it could not know.
     */
    private fun stackChildParams(
        view: View,
        node: Map<*, *>,
        horizontal: Boolean,
        stretch: Boolean,
    ): LinearLayout.LayoutParams {
        val params = view.layoutParams as? LinearLayout.LayoutParams
            ?: LinearLayout.LayoutParams(
                if (horizontal) ViewGroup.LayoutParams.WRAP_CONTENT
                else if (stretch) ViewGroup.LayoutParams.MATCH_PARENT
                else ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        if (node["type"] == "Expanded") {
            if (horizontal) {
                params.width = 0
                params.height = ViewGroup.LayoutParams.WRAP_CONTENT
            } else {
                params.width = ViewGroup.LayoutParams.MATCH_PARENT
                params.height = 0
            }
        } else if (node["type"] == "Wrap" && !horizontal) {
            // A Wrap needs the full width of the column to have a line to wrap
            // within, even when the column only left-aligns its children.
            params.width = ViewGroup.LayoutParams.MATCH_PARENT
        }
        return params
    }

    /**
     * The views that hold [node]'s children, one per child in order, or null if
     * this node's views cannot be walked 1:1 (a spaced row, a card, an overlay -
     * the caller rebuilds instead).
     */
    private fun childViews(view: View, node: Map<*, *>): List<View>? {
        val kids = childNodes(node)
        // child-views:begin
        return when (node["type"]) {
            "Scaffold", "NavigationStack" -> scaffoldChildViews(view, node)
            "Card" -> {
                // The card's children live in its content column, after an
                // optional title view.
                val content = (view as? MaterialCardView)?.getChildAt(0) as? LinearLayout
                    ?: return null
                val titleOffset = if (node["title"] != null) 1 else 0
                if (content.childCount - titleOffset != kids.size) return null
                (titleOffset until content.childCount).map { content.getChildAt(it) }
            }
            "SwipeActions" -> {
                // The row sits inside the foreground layer; the action bar is
                // the view behind it. Without this case the row's view could
                // never be patched, so a lazy list rebuilt every row it had
                // matched by key - the whole point of the keyed reconcile.
                val foreground = (view as? SwipeActionsLayout)?.getChildAt(1)
                    as? FrameLayout ?: return null
                if (foreground.childCount != kids.size) return null
                (0 until foreground.childCount).map { foreground.getChildAt(it) }
            }
            "Column", "Row", "VStack", "HStack", "List", "ListView",
            "Center", "Padding", "Expanded", "Overlay", "AnimatedOpacity",
            "AnimatedContainer" -> {
                // A spaced row carries extra spacer views, so its children no
                // longer line up one to one.
                if (node["mainAxisAlignment"] == "spaceBetween") return null
                val group = view as? ViewGroup ?: return null
                if (group.childCount != kids.size) return null
                (0 until group.childCount).map { group.getChildAt(it) }
            }
            else -> if (kids.isEmpty()) emptyList() else null
        }
        // child-views:end
    }

    /**
     * A Scaffold puts its children in different places - the app bar and body in
     * a column, the body wrapped in a scroll view, the floating action button in
     * an overlay - so map each child node back to the view that holds it.
     */
    private fun scaffoldChildViews(view: View, node: Map<*, *>): List<View>? {
        val column = (if (view is FrameLayout) view.getChildAt(0) else view) as? LinearLayout
            ?: return null
        val fab = if (view is FrameLayout) view.getChildAt(1) else null
        val result = mutableListOf<View>()
        var columnIndex = 0
        for (child in childNodes(node)) {
            when (child["type"]) {
                "FloatingActionButton" -> result.add(fab ?: return null)
                "AppBar", "NavigationBar" ->
                    result.add(column.getChildAt(columnIndex++) ?: return null)
                else -> {
                    val holder = column.getChildAt(columnIndex++) ?: return null
                    // Every body but a lazy list is wrapped in a scroll view.
                    val body = when {
                        child["type"] == "LazyList" -> holder
                        holder is ScrollView -> holder.getChildAt(0)
                        else -> holder
                    }
                    result.add(body ?: return null)
                }
            }
        }
        return result
    }

    /**
     * Applies [newNode]'s own props to [view] in place. Returns true when the
     * props are unchanged, or changed only in ways this knows how to re-derive;
     * false means the change needs a rebuild.
     */
    private fun patchSelf(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        if (propsEqual(oldNode, newNode)) return true
        return when (newNode["type"]) {
            "Text" -> patchText(view, newNode)
            "Button", "MaterialButton" -> patchButton(view, newNode)
            "AppBar", "NavigationBar" -> patchAppBar(view, newNode)
            "TextField" -> patchTextField(view, oldNode, newNode)
            "Checkbox" -> patchControl(view, newNode, "checked")
            "Toggle" -> patchControl(view, newNode, "enabled")
            "Radio" -> patchControl(view, newNode, "selected")
            "Slider" -> patchSlider(view, newNode)
            "Tabs" -> patchTabs(view, newNode)
            "AnimatedOpacity" -> patchAnimatedOpacity(view, oldNode, newNode)
            "AnimatedContainer" -> patchAnimatedContainer(view, newNode)
            "Card" -> patchCard(view, oldNode, newNode)
            // Container or leaf whose own props changed in a way not handled
            // here: rebuild. (Children changing does not reach this - equal props
            // return true above, then the children are walked.)
            else -> false
        }
    }

    private fun patchText(view: View, node: Map<*, *>): Boolean {
        val label = view as? AppCompatTextView ?: return false
        label.text = node["content"] as? String ?: ""
        label.textSize = (node["fontSize"] as? Number)?.toFloat() ?: 14f
        label.setTextColor(
            if (node["color"] == null) textInForce ?: color(null, themeText)
            else color(node["color"], themeText)
        )
        val bold = ((node["fontWeight"] as? Number)?.toInt() ?: 400) >= 600
        label.setTypeface(null, if (bold) Typeface.BOLD else Typeface.NORMAL)
        var flags = label.paintFlags and
            (Paint.STRIKE_THRU_TEXT_FLAG or Paint.UNDERLINE_TEXT_FLAG).inv()
        when (node["decoration"]) {
            "lineThrough" -> flags = flags or Paint.STRIKE_THRU_TEXT_FLAG
            "underline" -> flags = flags or Paint.UNDERLINE_TEXT_FLAG
        }
        label.paintFlags = flags
        clampLines(label, node)
        return true
    }

    private fun patchButton(view: View, node: Map<*, *>): Boolean {
        val button = view as? MaterialButton ?: return false
        button.text = node["label"] as? String ?: "Button"
        button.isEnabled = node["disabled"] != true
        val variant = node["variant"] as? String ?: "primary"
        val tint = color(node["color"] ?: variantColor(variant), themePrimary)
        when (variant) {
            "secondary", "tertiary" -> {
                button.setBackgroundColor(Color.TRANSPARENT)
                button.setTextColor(tint)
            }
            else -> {
                button.setBackgroundColor(tint)
                button.setTextColor(color(null, themeOnPrimary))
            }
        }
        // Keep the tap handler pointed at the latest node (event id, data).
        bindTap(button, node)
        return true
    }

    private fun patchAppBar(view: View, node: Map<*, *>): Boolean {
        val bar = view as? MaterialToolbar ?: return false
        bar.title = node["title"] as? String ?: ""
        bar.setBackgroundColor(color(node["backgroundColor"], themePrimary))
        return true
    }

    /** Re-derives a checkbox/switch/radio's label, enabled and checked state. */
    private fun patchControl(view: View, node: Map<*, *>, checkedKey: String): Boolean {
        val button = view as? CompoundButton ?: return false
        button.text = node["label"] as? String ?: ""
        button.isEnabled = node["disabled"] != true
        val checked = node[checkedKey] == true
        if (button.isChecked != checked) {
            // Set the state without the listener treating it as a user toggle.
            settingChecked = true
            button.isChecked = checked
            settingChecked = false
        }
        return true
    }

    /**
     * Re-derives a card's own look; the title is patched too but a change in
     * whether it is present reshapes the content, so that is left to a rebuild
     * (which then keeps the title/child mapping [childViews] relies on right).
     */
    private fun patchCard(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val card = view as? MaterialCardView ?: return false
        if ((oldNode["title"] != null) != (newNode["title"] != null)) return false
        val content = card.getChildAt(0) as? LinearLayout ?: return false

        card.setCardBackgroundColor(
            color(newNode["backgroundColor"], themeSurfaceVariant)
        )
        when (newNode["variant"]) {
            "outlined" -> {
                card.cardElevation = 0f
                card.strokeWidth = dp(1)
                card.strokeColor = color(null, themeDivider)
            }
            "filled" -> {
                card.cardElevation = 0f
                card.strokeWidth = 0
            }
            else -> {
                card.strokeWidth = 0
                card.cardElevation =
                    dp((newNode["elevation"] as? Number)?.toInt() ?: 2).toFloat()
            }
        }
        val padding = dp((newNode["padding"] as? Number)?.toInt() ?: 16)
        content.setPadding(padding, padding, padding, padding)
        (newNode["title"] as? String)?.let { title ->
            (content.getChildAt(0) as? AppCompatTextView)?.apply {
                text = title
                setTextColor(textInForce ?: color(null, themeText))
            }
        }
        return true
    }

    private fun patchTextField(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val layout = view as? TextInputLayout
        val floating = newNode["label"] != null && newNode["floatingLabel"] != false
        // A field that changed shape - gained a floating label, or lost one -
        // is rebuilt; the two are different view trees.
        if ((layout != null) != floating) return false
        if (layout != null) {
            // The layout draws the label and the error itself, so both change in
            // place: a validation message appearing while the user types no
            // longer costs a rebuild, and the field keeps its caret.
            val label = newNode["label"] as? String
            if (layout.hint != label) layout.hint = label
            val error = newNode["error"] as? String
            if (layout.error != error) layout.error = error
            val hintText = newNode["hint"] as? String ?: newNode["placeholder"] as? String
            layout.placeholderText = hintText?.ifEmpty { null }
        } else {
            // The label and error are drawn as siblings here, so a change in
            // whether they are present changes this field's own view tree -
            // leave that to a rebuild. Everything else is patched on the live
            // EditText, which keeps its focus, caret and keyboard.
            if ((oldNode["label"] != null) != (newNode["label"] != null)) return false
            if (oldNode["label"] != newNode["label"]) return false
            if ((oldNode["error"] != null) != (newNode["error"] != null)) return false
            if (oldNode["error"] != newNode["error"]) return false
        }
        if (oldNode["obscureText"] != newNode["obscureText"]) return false
        if (oldNode["maxLines"] != newNode["maxLines"]) return false

        val field = findEditText(view) ?: return false
        field.isEnabled = newNode["enabled"] != false
        // Sync the text when the user is not the one editing it, or when the app
        // itself changed the value - a controller.clear() after submitting bumps
        // the field's version, which the user's own typing never does. A
        // re-render that merely echoes the value the field already holds is left
        // alone, so typing is never interrupted and the caret never jumps.
        val value = newNode["initialValue"] as? String ?: ""
        // Only a *deliberate* change by the app - a bumped controller version -
        // overwrites what someone is typing. The value in the tree follows the
        // user's own keystrokes a beat behind (the controller records them
        // without bumping the version), so treating a different value as an app
        // change wrote that stale echo back into the field and ate whatever had
        // been typed in the meantime.
        val appChanged = (oldNode["valueVersion"] as? Number)?.toInt() !=
            (newNode["valueVersion"] as? Number)?.toInt()
        if (field.text?.toString() != value && (!field.isFocused || appChanged)) {
            field.setText(value)
            field.setSelection(value.length)
        }
        // A focus ask usually arrives on a live field - a failed submit sending
        // the caret back to the first thing to fix - so it has to be answered
        // here as well as at build time, or the second failed submit (nothing
        // else about the field changed) would be ignored.
        val eventId = newNode["eventId"] as? String
        if (eventId != null) applyFocusRequest(field, eventId, newNode)
        return true
    }

    private fun findEditText(view: View): EditText? {
        if (view is EditText) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findEditText(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    /** Deep equality over two nodes' own props (ignoring `id`, and children). */
    private fun propsEqual(a: Map<*, *>, b: Map<*, *>): Boolean =
        mapEqual(a["props"] as? Map<*, *> ?: emptyMap<Any?, Any?>(),
            b["props"] as? Map<*, *> ?: emptyMap<Any?, Any?>())

    private fun mapEqual(a: Map<*, *>, b: Map<*, *>): Boolean {
        val keysA = a.keys.filter { it != "id" }
        val keysB = b.keys.filter { it != "id" }
        if (keysA.size != keysB.size) return false
        for (key in keysA) {
            if (!b.containsKey(key)) return false
            if (!valueEqual(a[key], b[key])) return false
        }
        return true
    }

    private fun valueEqual(a: Any?, b: Any?): Boolean {
        if (a == b) return true
        if (a is Map<*, *> && b is Map<*, *>) return mapEqual(a, b)
        if (a is List<*> && b is List<*>) {
            if (a.size != b.size) return false
            for (i in a.indices) if (!valueEqual(a[i], b[i])) return false
            return true
        }
        return false
    }

    /** Depth-first search for the EditText tagged with [key]. */
    private fun findEditTextByTag(view: View, key: String): EditText? {
        if (view is EditText && view.tag == key) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findEditTextByTag(view.getChildAt(i), key)?.let { return it }
            }
        }
        return null
    }

    // -------------------------------------------------------------------------
    // Dispatch
    // -------------------------------------------------------------------------

    // node-types:begin
    private fun renderWidget(node: Map<*, *>): View? = when (node["type"] as? String) {
        // Structure
        "Scaffold", "NavigationStack" -> renderScaffold(node)
        "AppBar", "NavigationBar" -> renderAppBar(node)

        // Layout
        "Column" -> renderColumn(node)
        "VStack" -> renderStack(node, LinearLayout.VERTICAL)
        "Row" -> renderRow(node)
        "HStack" -> renderStack(node, LinearLayout.HORIZONTAL)
        "Wrap" -> renderWrap(node)
        "Expanded" -> renderExpanded(node)
        "Center" -> renderCenter(node)
        "SwipeActions" -> SwipeActionsLayout(node)
        "Padding" -> renderPadding(node)
        "SizedBox" -> renderSizedBox(node)
        "Spacer" -> renderSpacer(node)
        "Divider" -> renderDivider(node)

        // Content
        "Text" -> renderText(node)
        "Image" -> renderImage(node)
        "Loading" -> renderLoading(node)
        "Badge" -> renderBadge(node)
        "Alert" -> renderAlert(node)
        "Card" -> renderCard(node)

        // Controls
        "Button", "MaterialButton" -> renderButton(node)
        "IconButton" -> renderIconButton(node)
        "FloatingActionButton" -> renderFab(node)
        "TextField" -> renderTextField(node)
        "Checkbox" -> renderCheckbox(node)
        "Radio" -> renderRadio(node)
        "Toggle" -> renderToggle(node)
        "Slider" -> renderSlider(node)
        "Tabs" -> renderTabs(node)
        "AnimatedOpacity" -> renderAnimatedOpacity(node)
        "AnimatedContainer" -> renderAnimatedContainer(node)

        "WebView" -> renderWebView(node)
        "MapView" -> renderMapPlaceholder(node)
        "CameraPreview" -> renderPlaceholder(
            node,
            "A camera preview needs the CameraX dependency on Android.",
        )

        // Lists
        "List", "ListView" -> renderList(node)
        "ListItem", "ListRow" -> renderListItem(node)
        "LazyList" -> renderLazyList(node)
        "GridView" -> renderGrid(node)

        // Overlays
        "Overlay" -> renderOverlay(node)
        "Dialog" -> renderDialog(node)
        "BottomSheet" -> renderBottomSheet(node)
        "Snackbar" -> renderSnackbar(node)

        else -> AppCompatTextView(activity).apply {
            unknownTypes.add(node["type"]?.toString() ?: "?")
            text = "Unknown widget: ${node["type"]}"
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }
    }
    // node-types:end

    // -------------------------------------------------------------------------
    // Structure
    // -------------------------------------------------------------------------

    /**
     * A Scaffold's children are, in order, an optional app bar, the body and an
     * optional floating action button - the shape `UIBuilder.scaffold` builds.
     */
    private fun renderScaffold(node: Map<*, *>): View {
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = matchParent()
            setBackgroundColor(color(null, themeSurface))
        }

        var fab: View? = null
        for (child in childNodes(node)) {
            when (child["type"] as? String) {
                "FloatingActionButton" -> fab = renderWidget(child)
                "AppBar", "NavigationBar" -> renderWidget(child)?.let {
                    column.addView(it, linear(height = ViewGroup.LayoutParams.WRAP_CONTENT))
                }
                // A lazy list scrolls itself and needs a bounded height to know
                // which rows are visible, so it takes the space directly.
                "LazyList" -> renderWidget(child)?.let { body ->
                    column.addView(body, linear(height = 0, weight = 1f))
                }
                else -> renderWidget(child)?.let { body ->
                    // The body scrolls, so a screen taller than the window is
                    // reachable rather than clipped. A body that asked to fill
                    // - a column distributing its children - gets the viewport
                    // to fill; anything else keeps wrapping, as before.
                    val fills =
                        body.layoutParams?.height == ViewGroup.LayoutParams.MATCH_PARENT
                    val scroll = ScrollView(activity).apply {
                        isFillViewport = fills
                        addView(
                            body,
                            ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                if (fills) ViewGroup.LayoutParams.MATCH_PARENT
                                else ViewGroup.LayoutParams.WRAP_CONTENT,
                            ),
                        )
                    }
                    column.addView(scroll, linear(height = 0, weight = 1f))
                }
            }
        }

        if (fab == null) return column

        return FrameLayout(activity).apply {
            layoutParams = matchParent()
            addView(column, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
            addView(fab, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                setMargins(0, 0, dp(16), dp(16))
            })
        }
    }

    private fun renderAppBar(node: Map<*, *>): View = MaterialToolbar(materialContext).apply {
        title = node["title"] as? String ?: ""
        layoutParams = linear(height = ViewGroup.LayoutParams.WRAP_CONTENT)
        val background = color(node["backgroundColor"], themePrimary)
        setBackgroundColor(background)
        // A title over a colour the app stated reads against that colour; over
        // the theme's own primary it stays the palette's onPrimary.
        setTitleTextColor(
            if (node["backgroundColor"] == null) color(null, themeOnPrimary)
            else textOn(background)
        )
        // The window is edge-to-edge from Android 15 on, so a bar at the top of
        // it draws *behind* the clock and the status icons unless it pads
        // itself past them - which is what the dialog, sheet and snackbar
        // surfaces already do. Padding rather than margin, so the bar's colour
        // still fills the space behind the icons.
        //
        // The minimum height has to grow by the same inset, or the bar wraps to
        // the padding plus the title and the title is the whole content area -
        // which puts it flat against the bottom edge. A recent phone's inset is
        // 50dp, so there is a lot of nothing above it and none below. Giving
        // the bar a full title row *under* the inset is what a toolbar centres
        // its title in.
        val titleRow = actionBarHeight()
        onSystemBars(this) { bars ->
            updatePadding(top = bars.top)
            minimumHeight = titleRow + bars.top
        }
    }

    // -------------------------------------------------------------------------
    // Layout
    // -------------------------------------------------------------------------

    private fun renderColumn(node: Map<*, *>): View {
        // Distributing the children needs height to distribute, so a column
        // that was asked to do it grows into its parent instead of wrapping.
        val main = node["mainAxisAlignment"] as? String
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = if (main == null) matchWidth() else ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            val cross = when (node["crossAxisAlignment"]) {
                "start" -> Gravity.START
                "end" -> Gravity.END
                "stretch" -> Gravity.FILL_HORIZONTAL
                else -> Gravity.CENTER_HORIZONTAL
            }
            gravity = cross or when (main) {
                "center" -> Gravity.CENTER_VERTICAL
                "end" -> Gravity.BOTTOM
                else -> Gravity.TOP
            }
        }
        val stretch = node["crossAxisAlignment"] == "stretch"
        addChildren(column, node, horizontal = false, stretch = stretch)
        // spaceBetween has no gravity: weighted spacers between the children
        // carry it, exactly as in a row.
        if (main == "spaceBetween") spaceBetween(column)
        return column
    }

    private fun renderRow(node: Map<*, *>): View {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = matchWidth()
            gravity = when (node["mainAxisAlignment"]) {
                "center" -> Gravity.CENTER_HORIZONTAL
                "end" -> Gravity.END
                else -> Gravity.START
            } or Gravity.CENTER_VERTICAL
        }
        addChildren(row, node, horizontal = true, stretch = false)
        // spaceBetween has no gravity: spacers between the children carry it.
        if (node["mainAxisAlignment"] == "spaceBetween") spaceBetween(row)
        return row
    }

    /** A run of children that wraps onto the next line when it runs out of width. */
    private fun renderWrap(node: Map<*, *>): View {
        val flow = FlowLayout(
            activity,
            dp((node["spacing"] as? Number)?.toInt() ?: 0),
            dp((node["runSpacing"] as? Number)?.toInt() ?: 0),
        )
        for (child in childNodes(node)) {
            renderWidget(child)?.let { flow.addView(it, wrapContent()) }
        }
        return flow
    }

    /** VStack and HStack: the iOS flavour of Column and Row. */
    private fun renderStack(node: Map<*, *>, orientation: Int): View {
        val stack = LinearLayout(activity).apply {
            this.orientation = orientation
            layoutParams = matchWidth()
            gravity = if (orientation == LinearLayout.VERTICAL) {
                when (node["alignment"]) {
                    "center" -> Gravity.CENTER_HORIZONTAL
                    "trailing" -> Gravity.END
                    else -> Gravity.START
                }
            } else {
                when (node["alignment"]) {
                    "top" -> Gravity.TOP
                    "bottom" -> Gravity.BOTTOM
                    else -> Gravity.CENTER_VERTICAL
                }
            }
        }
        addChildren(stack, node, horizontal = orientation == LinearLayout.HORIZONTAL,
            stretch = false)
        return stack
    }

    /** Takes the remaining space of the row or column it sits in. */
    private fun renderExpanded(node: Map<*, *>): View {
        val flex = (node["flex"] as? Number)?.toFloat() ?: 1f
        val container = FrameLayout(activity)
        firstChild(node)?.let { child ->
            renderWidget(child)?.let { container.addView(it, matchWidth()) }
        }
        // The parent reads the weight; the zero size lets it decide.
        container.layoutParams = LinearLayout.LayoutParams(0, 0, flex)
        return container
    }

    private fun renderCenter(node: Map<*, *>): View = FrameLayout(activity).apply {
        layoutParams = matchParent()
        firstChild(node)?.let { child ->
            renderWidget(child)?.let {
                addView(it, FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { gravity = Gravity.CENTER })
            }
        }
    }

    private fun renderPadding(node: Map<*, *>): View {
        // One number for every edge, or four - see UIBuilder.padding.
        val uniform = (node["padding"] as? Number)?.toInt()
        fun edge(name: String) =
            dp(uniform ?: (node[name] as? Number)?.toInt() ?: 0)
        return FrameLayout(activity).apply {
            layoutParams = matchWidth()
            setPadding(
                edge("paddingLeft"),
                edge("paddingTop"),
                edge("paddingRight"),
                edge("paddingBottom"),
            )
            firstChild(node)?.let { child ->
                renderWidget(child)?.let { addView(it, matchWidth()) }
            }
        }
    }

    private fun renderSizedBox(node: Map<*, *>): View = View(activity).apply {
        val height = (node["height"] as? Number)?.toInt()
        val width = (node["width"] as? Number)?.toInt()
        // LinearLayout's own params, because a column or row keeps the params a
        // child arrives with only when they are of that type - a plain
        // ViewGroup.LayoutParams was dropped, and with it this box's height.
        layoutParams = LinearLayout.LayoutParams(
            if (width != null) dp(width) else ViewGroup.LayoutParams.MATCH_PARENT,
            if (height != null) dp(height) else 0
        )
    }

    private fun renderSpacer(node: Map<*, *>): View = View(activity).apply {
        val minLength = dp((node["minLength"] as? Number)?.toInt() ?: 0)
        // Weight makes it take what is left; the minimum is the floor.
        layoutParams = LinearLayout.LayoutParams(minLength, minLength, 1f)
    }

    private fun renderDivider(node: Map<*, *>): View {
        val thickness = dp((node["thickness"] as? Number)?.toInt() ?: 1)
        val vertical = node["orientation"] == "vertical"
        return View(activity).apply {
            setBackgroundColor(color(node["color"], themeDivider))
            layoutParams = if (vertical) {
                LinearLayout.LayoutParams(
                    thickness,
                    dp((node["height"] as? Number)?.toInt() ?: 24)
                ).apply { gravity = Gravity.CENTER_VERTICAL }
            } else {
                val margin = dp((node["margin"] as? Number)?.toInt() ?: 16)
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    thickness
                ).apply { setMargins(0, margin, 0, margin) }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Content
    // -------------------------------------------------------------------------

    /**
     * The colour text takes when the tree states none, while the children of a
     * container that stated its own background are being built.
     *
     * A render is depth-first and synchronous, so saving and restoring around
     * those children is enough; [renderOver] does both. The patch walk keeps
     * the same field in force, so a text that changes inside a coloured card
     * is repainted the same way it was drawn.
     */
    private var textInForce: Int? = null

    /** Runs [body] with text over [background] made legible against it. */
    private fun <T> renderOver(background: Any?, body: () -> T): T {
        val stated = background as? String ?: return body()
        val saved = textInForce
        textInForce = textOn(color(stated, stated))
        try {
            return body()
        } finally {
            textInForce = saved
        }
    }

    private fun renderText(node: Map<*, *>): View = AppCompatTextView(activity).apply {
        text = node["content"] as? String ?: ""
        textSize = (node["fontSize"] as? Number)?.toFloat() ?: 14f
        setTextColor(
            if (node["color"] == null) textInForce ?: color(null, themeText)
            else color(node["color"], themeText)
        )
        layoutParams = wrapContent()

        val weight = (node["fontWeight"] as? Number)?.toInt() ?: 400
        if (weight >= 600) setTypeface(typeface, Typeface.BOLD)

        when (node["decoration"]) {
            "lineThrough" -> paintFlags = paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
            "underline" -> paintFlags = paintFlags or Paint.UNDERLINE_TEXT_FLAG
        }
        clampLines(this, node)
    }

    /**
     * Caps a text at `maxLines`, ending it with an ellipsis when asked.
     *
     * Without a cap a TextView wraps as far as it likes, which is what makes
     * an unknown-length line push a fixed-height row out of shape.
     */
    private fun clampLines(label: AppCompatTextView, node: Map<*, *>) {
        val maxLines = (node["maxLines"] as? Number)?.toInt() ?: 0
        if (maxLines <= 0) {
            label.maxLines = Integer.MAX_VALUE
            label.ellipsize = null
            return
        }
        label.maxLines = maxLines
        label.ellipsize = if (node["overflow"] == "clip") null
        else TextUtils.TruncateAt.END
    }

    /**
     * An image.
     *
     * A URL is fetched off the main thread and applied when it arrives; any
     * other source is looked up in the app's drawables. A source that cannot
     * be loaded leaves the alt text in place, which is also the view's content
     * description - so a broken image is still announced and still visible.
     */
    private fun renderImage(node: Map<*, *>): View {
        val alt = node["alt"] as? String ?: ""
        val container = FrameLayout(activity)
        container.layoutParams = LinearLayout.LayoutParams(
            (node["width"] as? Number)?.let { dp(it.toInt()) }
                ?: ViewGroup.LayoutParams.MATCH_PARENT,
            (node["height"] as? Number)?.let { dp(it.toInt()) }
                ?: ViewGroup.LayoutParams.WRAP_CONTENT
        )

        val fallback = AppCompatTextView(activity).apply {
            text = alt
            setTextColor(color(null, themeTextSecondary))
            gravity = Gravity.CENTER
        }
        container.addView(fallback, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        val image = ImageView(activity).apply {
            contentDescription = alt
            scaleType = when (node["fit"]) {
                "contain" -> ImageView.ScaleType.FIT_CENTER
                "fill" -> ImageView.ScaleType.FIT_XY
                "none" -> ImageView.ScaleType.CENTER
                "scaleDown" -> ImageView.ScaleType.CENTER_INSIDE
                else -> ImageView.ScaleType.CENTER_CROP
            }
        }
        container.addView(image, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        loadImage(node["src"] as? String, into = image, hiding = fallback)
        return container
    }

    /** Fills [into] from [src], hiding [hiding] once it arrives. */
    private fun loadImage(src: String?, into: ImageView, hiding: View) {
        if (src.isNullOrEmpty()) return

        if (!src.startsWith("http://") && !src.startsWith("https://")) {
            // A drawable that ships with the app.
            val id = activity.resources.getIdentifier(
                src.substringAfterLast('/').substringBeforeLast('.'),
                "drawable",
                activity.packageName,
            )
            if (id != 0) {
                into.setImageResource(id)
                hiding.visibility = View.GONE
            }
            return
        }

        // Network images are fetched off the main thread; the view is filled
        // back on it, and a failure simply leaves the alt text showing.
        Thread {
            val bitmap = try {
                (java.net.URL(src).openConnection() as java.net.HttpURLConnection)
                    .let { connection ->
                        connection.connectTimeout = 10_000
                        connection.readTimeout = 10_000
                        connection.inputStream.use {
                            android.graphics.BitmapFactory.decodeStream(it)
                        }
                    }
            } catch (e: Exception) {
                null
            }
            if (bitmap != null) {
                activity.runOnUiThread {
                    into.setImageBitmap(bitmap)
                    hiding.visibility = View.GONE
                }
            }
        }.start()
    }

    private fun renderLoading(node: Map<*, *>): View {
        val tint = color(node["color"], themePrimary)
        val indeterminate = node["indeterminate"] == true
        val value = ((node["value"] as? Number)?.toFloat() ?: 0f) * 100

        return when (prop(node, "type")) {
            "progress-linear" -> ProgressBar(
                activity, null, android.R.attr.progressBarStyleHorizontal
            ).apply {
                isIndeterminate = indeterminate
                progress = value.toInt()
                layoutParams = matchWidth()
            }
            "skeleton" -> View(activity).apply {
                background = GradientDrawable().apply {
                    setColor(color(null, themeDivider))
                    cornerRadius = dp(4).toFloat()
                }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp((node["height"] as? Number)?.toInt() ?: 16)
                )
            }
            "pulse" -> FrameLayout(activity).apply {
                layoutParams = matchWidth()
                firstChild(node)?.let { child ->
                    renderWidget(child)?.let { addView(it, matchWidth()) }
                }
            }
            else -> ProgressBar(activity).apply {
                isIndeterminate = indeterminate || value <= 0f
                progress = value.toInt()
                indeterminateTintList = android.content.res.ColorStateList.valueOf(tint)
                val size = dp((node["size"] as? Number)?.toInt() ?: 24)
                layoutParams = LinearLayout.LayoutParams(size, size)
            }
        }
    }

    private fun renderBadge(node: Map<*, *>): View {
        val tint = color(node["color"], themePrimary)
        val outlined = node["variant"] == "outlined"
        val label = node["label"] as? String

        if (node["variant"] == "dot" || label == null) {
            return View(activity).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(tint)
                }
                layoutParams = LinearLayout.LayoutParams(dp(8), dp(8))
            }
        }

        return AppCompatTextView(activity).apply {
            text = label
            textSize = 12f
            setTextColor(if (outlined) tint else textOn(tint))
            setPadding(dp(8), dp(2), dp(8), dp(2))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                if (outlined) {
                    setStroke(dp(1), tint)
                } else {
                    setColor(tint)
                }
            }
            layoutParams = wrapContent()
        }
    }

    /**
     * A web page, in the platform's own browser view.
     *
     * Sized by its `height` prop rather than by its content: a WebView has no
     * height of its own, and a scaffold's body scrolls, so one left to itself
     * would be zero pixels tall.
     */
    /**
     * Android has no map here: the Maps SDK needs a dependency *and* an API
     * key, which is the app's decision rather than the framework's (TODO §2.2).
     * A labelled placeholder, the same shape the Flutter host draws, so the
     * screen says what is missing instead of leaving a hole.
     */
    private fun renderMapPlaceholder(node: Map<*, *>): View {
        val latitude = (node["latitude"] as? Number)?.toDouble() ?: 0.0
        val longitude = (node["longitude"] as? Number)?.toDouble() ?: 0.0
        return renderPlaceholder(
            node,
            "A map needs the Maps SDK and an API key on Android.\n" +
                "$latitude, $longitude",
        )
    }

    /** A labelled box where this target has no way to draw something. */
    private fun renderPlaceholder(node: Map<*, *>, message: String): View =
        AppCompatTextView(activity).apply {
            text = message
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(color(null, themeTextSecondary))
            setBackgroundColor(color(null, themeSurfaceVariant))
            val height = dp((node["height"] as? Number)?.toInt() ?: 300)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                height,
            )
        }

    private fun renderWebView(node: Map<*, *>): View = WebView(activity).apply {
        // Off unless the app asks, matching the other renderers: a page that is
        // only being read does not need to run code.
        @Suppress("SetJavaScriptEnabled")
        settings.javaScriptEnabled = node["javaScriptEnabled"] == true
        val height = ((node["height"] as? Number)?.toFloat() ?: 300f) *
            activity.resources.displayMetrics.density
        layoutParams = linear(height = height.toInt())
        val url = node["url"] as? String
        if (url.isNullOrEmpty()) unknownTypes.add("WebView(url)") else loadUrl(url)
    }

    private fun renderAlert(node: Map<*, *>): View {
        val tint = color(
            when (prop(node, "type")) {
                "success" -> themeSuccess
                "error" -> themeError
                "warning" -> themeWarning
                else -> themeInfo
            },
            themeInfo
        )

        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
        }

        (node["title"] as? String)?.let { title ->
            body.addView(AppCompatTextView(activity).apply {
                text = title
                setTextColor(tint)
                setTypeface(typeface, Typeface.BOLD)
            }, matchWidth())
        }
        body.addView(AppCompatTextView(activity).apply {
            text = node["message"] as? String ?: ""
            setTextColor(color(null, themeText))
        }, matchWidth())

        // A row rather than a column, so a dismissible alert puts its close
        // button at the trailing edge - where the other three renderers put
        // theirs.
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = matchWidth()
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = GradientDrawable().apply {
                setColor(withAlpha(tint, 0.1f))
                setStroke(dp(4), tint)
            }
        }
        row.addView(
            body,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )

        if (node["dismissible"] == true) {
            row.addView(ImageButton(activity).apply {
                setIcon(this, CLOSE_CODEPOINT, "close", tint)
                setBackgroundColor(Color.TRANSPARENT)
                contentDescription = "Dismiss"
                // Removed here rather than reported to Dart, which is what the
                // other renderers do: the alert is a leaf the app did not ask
                // to hear about.
                setOnClickListener { (row.parent as? ViewGroup)?.removeView(row) }
            }, wrapContent())
        }
        return row
    }

    private fun renderCard(node: Map<*, *>): View {
        val card = MaterialCardView(materialContext).apply {
            layoutParams = linear(
                height = ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(dp(8), dp(8), dp(8), dp(8)) }
            radius = dp(8).toFloat()
            // Every variant draws the colour the app stated; only what it
            // does *besides* the fill - a border, a shadow - is the variant's.
            setCardBackgroundColor(color(node["backgroundColor"], themeSurfaceVariant))
            when (node["variant"]) {
                "outlined" -> {
                    cardElevation = 0f
                    strokeWidth = dp(1)
                    strokeColor = color(null, themeDivider)
                }
                "filled" -> cardElevation = 0f
                else -> cardElevation = dp((node["elevation"] as? Number)?.toInt() ?: 2)
                    .toFloat()
            }
        }

        val padding = dp((node["padding"] as? Number)?.toInt() ?: 16)
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        renderOver(node["backgroundColor"]) {
            (node["title"] as? String)?.let { title ->
                content.addView(AppCompatTextView(activity).apply {
                    text = title
                    setTypeface(typeface, Typeface.BOLD)
                    textInForce?.let { setTextColor(it) }
                }, matchWidth())
            }
            for (child in childNodes(node)) {
                renderWidget(child)?.let { content.addView(it, matchWidth()) }
            }
        }
        card.addView(content)
        return card
    }

    // -------------------------------------------------------------------------
    // Controls
    // -------------------------------------------------------------------------

    private fun renderButton(node: Map<*, *>): View = MaterialButton(materialContext).apply {
        text = node["label"] as? String ?: "Button"
        layoutParams = wrapContent()
        isEnabled = node["disabled"] != true

        // The one button scale, shared by every renderer - see UIBuilder.button.
        val (heightDp, fontSp, padDp) = when (node["size"]) {
            "sm" -> Triple(28, 12f, 12)
            "lg" -> Triple(44, 16f, 24)
            else -> Triple(36, 14f, 16)
        }
        // MaterialButton insets itself by 6dp top and bottom, which would make
        // every button that much taller than the scale says.
        insetTop = 0
        insetBottom = 0
        // The scale, then whatever the app stated instead of it.
        val height = (node["minHeight"] as? Number)?.toInt() ?: heightDp
        val font = (node["fontSize"] as? Number)?.toFloat() ?: fontSp
        val padH = (node["paddingHorizontal"] as? Number)?.toInt() ?: padDp
        val padV = (node["paddingVertical"] as? Number)?.toInt() ?: 0
        minHeight = dp(height)
        minimumHeight = dp(height)
        (node["minWidth"] as? Number)?.toInt()?.let {
            minWidth = dp(it)
            minimumWidth = dp(it)
        }
        textSize = font
        setPadding(dp(padH), dp(padV), dp(padH), dp(padV))

        val variant = node["variant"] as? String ?: "primary"
        val tint = color(node["color"] ?: variantColor(variant), themePrimary)
        when (variant) {
            "secondary", "tertiary" -> {
                setBackgroundColor(Color.TRANSPARENT)
                setTextColor(tint)
            }
            else -> {
                setBackgroundColor(tint)
                setTextColor(
                    if (node["color"] == null) color(null, themeOnPrimary)
                    else textOn(tint)
                )
            }
        }
        bindTap(this, node)
    }

    private fun renderIconButton(node: Map<*, *>): View = ImageButton(activity).apply {
        // A dark glyph, since an icon button sits on the surface, not a fill.
        applyIcon(this, node, defaultName = "more_vert", colorInt = color(null, themeTextSecondary))
        setBackgroundColor(Color.TRANSPARENT)
        contentDescription = node["tooltip"] as? String
        layoutParams = wrapContent()
        bindTap(this, node)
    }

    private fun renderFab(node: Map<*, *>): View = FloatingActionButton(materialContext).apply {
        // The brand primary, matching the web FAB, unless the node overrides it.
        backgroundTintList = android.content.res.ColorStateList.valueOf(
            color(node["backgroundColor"], themePrimary))
        // White for contrast against the FAB's filled background.
        applyIcon(this, node, defaultName = "add", colorInt = color(null, themeOnPrimary))
        contentDescription = node["tooltip"] as? String
        layoutParams = wrapContent()
        bindTap(this, node)
    }

    /**
     * A text field that reports what the user does.
     *
     * The events match every other renderer: `<eventId>_change` on each
     * keystroke, `_focus` and `_blur`, and `_submit` on the keyboard's action
     * key.
     *
     * A labelled field is a Material `TextInputLayout`, whose hint *is* the
     * label: it sits in the outline and animates out of the way on focus, and
     * it names the field to TalkBack without a `labelFor` of its own. A field
     * with no label, or one the app asked to keep its label above the box
     * (`floatingLabel: false`), is a plain EditText in a column.
     */
    private fun renderTextField(node: Map<*, *>): View {
        val label = node["label"] as? String
        return if (label != null && node["floatingLabel"] != false) {
            floatingLabelField(node, label)
        } else {
            plainLabelField(node, label)
        }
    }

    private fun floatingLabelField(node: Map<*, *>, label: String): View {
        val layout = TextInputLayout(materialContext).apply {
            hint = label
            isHintEnabled = true
            layoutParams = linear()
        }
        // The placeholder would sit under the label while the field is empty;
        // TextInputLayout shows it only once the label has floated up.
        val hintText = node["hint"] as? String ?: node["placeholder"] as? String
        if (!hintText.isNullOrEmpty()) layout.placeholderText = hintText
        // TextInputEditText is the editor the layout expects, and it is built
        // under the Material theme the layout itself uses.
        val field = configureEditText(node, TextInputEditText(materialContext), hint = null)
        // The editor's own underline is what TextInputLayout otherwise leaves in
        // place, and the box is then never drawn. Cleared, the layout draws its
        // own - and the editor's padding goes with the drawable it came from,
        // so the room the floated label needs above the text is stated here.
        field.background = null
        field.setPadding(dp(12), dp(26), dp(12), dp(10))
        // TextInputLayout is a LinearLayout and casts the params it is handed,
        // so a bare ViewGroup.LayoutParams here throws where our own columns
        // would have converted it.
        layout.addView(field, linear())
        // The box around the field is the platform's: a built-in-code layout
        // takes neither the theme's outlined style nor a box set on it
        // afterwards (tried on a device - the box never drew), so the field
        // wears Android's own underline rather than web's outline. The label
        // is the part that had to be right, and it is.
        //
        // The app's palette rather than the Material theme's, so the label
        // matches the rest of the screen.
        layout.defaultHintTextColor = ColorStateList.valueOf(color(null, themeTextSecondary))
        layout.hintTextColor = ColorStateList.valueOf(color(null, themePrimary))
        // The layout draws the error under the box itself, so the error is not
        // a sibling view here and a validation message no longer changes this
        // field's view tree.
        (node["error"] as? String)?.let { layout.error = it }
        return layout
    }

    private fun plainLabelField(node: Map<*, *>, label: String?): View {
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = matchWidth()
        }

        // The field needs an id before the label can point at it - see
        // labelFor below.
        val fieldViewId = View.generateViewId()

        label?.let {
            column.addView(AppCompatTextView(activity).apply {
                text = it
                textSize = 13f
                setTextColor(color(null, themeTextSecondary))
                // Ties the label to the field, so TalkBack announces the two
                // together. Without it the label is a separate piece of text
                // and the field reaches the user unnamed.
                labelFor = fieldViewId
            }, matchWidth())
        }

        // A plain EditText under the host activity's own theme, as before:
        // nothing here needs Material, and an AppCompat view under a
        // non-AppCompat theme is how the Toggle once crashed.
        val field = configureEditText(
            node,
            EditText(activity),
            hint = node["hint"] as? String ?: node["placeholder"] as? String ?: "",
        )
        field.id = fieldViewId
        column.addView(field, matchWidth())

        (node["error"] as? String)?.let { error ->
            column.addView(AppCompatTextView(activity).apply {
                text = error
                textSize = 12f
                setTextColor(color(null, themeError))
            }, matchWidth())
        }
        return column
    }

    /**
     * The editor itself, wired to the app.
     *
     * [hint] is null inside a [TextInputLayout], which draws the hint as the
     * floating label and would otherwise show both.
     */
    private fun configureEditText(node: Map<*, *>, field: EditText, hint: String?): EditText {
        val eventId = node["eventId"] as? String
        field.apply {
            if (hint != null) this.hint = hint
            setText(node["initialValue"] as? String ?: "")
            isEnabled = node["enabled"] != false
            val maxLines = (node["maxLines"] as? Number)?.toInt() ?: 1
            setLines(maxLines)
            inputType = if (node["obscureText"] == true) {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            } else if (maxLines > 1) {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            } else {
                InputType.TYPE_CLASS_TEXT
            }
            // What the keyboard's return key says. A multi-line field keeps its
            // newline key: advancing out of it would make it impossible to
            // write a second line.
            if (node["textInputAction"] == "next" && maxLines <= 1) {
                imeOptions = EditorInfo.IME_ACTION_NEXT
            }
            layoutParams = matchWidth()
        }

        if (eventId != null) {
            // Names the field so its focus and caret can be restored to the view
            // the next render rebuilds in its place (see renderTree).
            field.tag = eventId
            applyFocusRequest(field, eventId, node)
            field.addTextChangedListener(object : TextWatcher {
                override fun afterTextChanged(s: Editable?) {
                    // The whole point of a bound field: what the user typed
                    // goes back to Dart. Dropping this (which the floating
                    // label work did, for two days) leaves a field that looks
                    // right, keeps its focus, and tells the app nothing.
                    sendEvent("${eventId}_change", mapOf("value" to (s?.toString() ?: "")))
                }

                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
            })
            field.setOnFocusChangeListener { _, hasFocus ->
                // A focus change the renderer itself caused is not a user action.
                if (restoringFocus) return@setOnFocusChangeListener
                val suffix = if (hasFocus) "focus" else "blur"
                sendEvent("${eventId}_$suffix", mapOf("value" to field.text.toString()))
            }
            field.setOnEditorActionListener { _, actionId, _ ->
                sendEvent("${eventId}_submit", mapOf("value" to field.text.toString()))
                // Returning false hands the action back to the platform, whose
                // default for IME_ACTION_NEXT is to focus the next field in
                // traversal order - the reading order of the tree, which is
                // what the app meant by "next". Anything else is consumed, so
                // the keyboard closes as it did.
                actionId != EditorInfo.IME_ACTION_NEXT
            }
        }
        return field
    }

    private fun renderCheckbox(node: Map<*, *>): View = CheckBox(activity).apply {
        text = node["label"] as? String ?: ""
        setTextColor(color(null, themeText))
        buttonTintList = controlTint(
            checked = color(null, themePrimary),
            unchecked = color(null, themeTextSecondary),
        )
        isChecked = node["checked"] == true
        isEnabled = node["disabled"] != true
        layoutParams = wrapContent()
        setOnCheckedChangeListener { _, checked ->
            if (!settingChecked) sendEvent(node, mapOf("checked" to checked))
        }
    }

    private fun renderRadio(node: Map<*, *>): View = RadioButton(activity).apply {
        text = node["label"] as? String ?: ""
        setTextColor(color(null, themeText))
        buttonTintList = controlTint(
            checked = color(null, themePrimary),
            unchecked = color(null, themeTextSecondary),
        )
        isChecked = node["selected"] == true
        isEnabled = node["disabled"] != true
        layoutParams = wrapContent()
        setOnClickListener {
            sendEvent(node, mapOf("value" to (node["value"] ?: "")))
        }
    }

    /**
     * A value dragged along a track.
     *
     * Material's own slider, so the thumb, the ripple and the value label are
     * the platform's. `divisions` becomes a step, which is what makes the thumb
     * snap; without one the value is continuous, and Material calls that a step
     * of zero.
     */
    /**
     * Equal cells in a fixed number of columns.
     *
     * Frame-positioned like the Wrap's flow, because every cell has to be the
     * same size - which no stock container does without a weight per row.
     */
    private fun renderGrid(node: Map<*, *>): View {
        val grid = GridLayoutView(
            activity,
            columns = (node["crossAxisCount"] as? Number)?.toInt() ?: 2,
            hSpacing = dp((node["spacing"] as? Number)?.toInt() ?: 0),
            vSpacing = dp((node["runSpacing"] as? Number)?.toInt() ?: 0),
            aspectRatio = (node["childAspectRatio"] as? Number)?.toFloat() ?: 1f,
        )
        grid.layoutParams = matchWidth()
        for (child in childNodes(node)) {
            renderWidget(child)?.let { view ->
                // The grid frames its cells, so they must not size themselves.
                view.layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                grid.addView(view)
            }
        }
        return grid
    }

    /**
     * Fades its child to the opacity the tree asks for.
     *
     * The first render sets the alpha; a later one that changes it animates
     * from where the view already is - which is why this node is patched
     * rather than rebuilt (see [patchAnimatedOpacity]).
     */
    private fun renderAnimatedOpacity(node: Map<*, *>): View =
        FrameLayout(activity).apply {
            layoutParams = matchWidth()
            alpha = ((node["opacity"] as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
            firstChild(node)?.let { child ->
                renderWidget(child)?.let { addView(it, matchWidth()) }
            }
        }

    private fun patchAnimatedOpacity(
        view: View,
        oldNode: Map<*, *>,
        newNode: Map<*, *>,
    ): Boolean {
        val target = ((newNode["opacity"] as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
        if (view.alpha == target) return true
        val duration = (newNode["durationMs"] as? Number)?.toLong() ?: 200L
        view.animate().cancel()
        view.animate()
            .alpha(target)
            .setDuration(duration)
            .setInterpolator(interpolator(newNode))
            .start()
        return true
    }

    /**
     * A box that moves to the size and colour the tree asks for.
     *
     * Like the fade, the first render sets it and a later one animates the
     * difference - so this node is patched rather than rebuilt, and is listed
     * in [childViews] for that to be possible at all. The child is centred: a
     * box that is about to grow says nothing about where a label inside it
     * should sit, and centred is what the other three renderers do.
     */
    private fun renderAnimatedContainer(node: Map<*, *>): View =
        FrameLayout(activity).apply {
            layoutParams = animatedBoxParams(node)
            (node["color"] as? String)?.let { setBackgroundColor(color(it, it)) }
            val child = renderOver(node["color"]) {
                firstChild(node)?.let { renderWidget(it) }
            }
            child?.let {
                addView(
                    it,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        Gravity.CENTER,
                    ),
                )
            }
        }

    /**
     * The box's own params: a stated width or height in dp, and the same
     * wrap-or-fill it would have had without one.
     *
     * LinearLayout's own params, for the reason [renderSizedBox] gives - a
     * column drops params of any other type, and the stated size with them.
     */
    private fun animatedBoxParams(node: Map<*, *>) = LinearLayout.LayoutParams(
        (node["width"] as? Number)?.let { dp(it.toInt()) }
            ?: ViewGroup.LayoutParams.MATCH_PARENT,
        (node["height"] as? Number)?.let { dp(it.toInt()) }
            ?: ViewGroup.LayoutParams.WRAP_CONTENT,
    )

    /**
     * Moves the box to its new size and colour over the stated duration.
     *
     * A width or height is animated by stepping the layout params, because
     * that is the only thing a parent re-measures; the colour is stepped
     * through ARGB, since interpolating a packed int would run through the
     * wrong hues.
     */
    private fun patchAnimatedContainer(view: View, newNode: Map<*, *>): Boolean {
        val params = view.layoutParams ?: return false
        val duration = (newNode["durationMs"] as? Number)?.toLong() ?: 200L
        val ease = interpolator(newNode)

        val targets = animatedBoxParams(newNode)
        for ((from, to, apply) in listOf(
            Triple(params.width, targets.width, { v: Int -> params.width = v }),
            Triple(params.height, targets.height, { v: Int -> params.height = v }),
        )) {
            if (from == to) continue
            // A wrap or match target has no pixel value to travel to, so it is
            // set at once rather than animated to a negative number.
            if (from < 0 || to < 0) {
                apply(to)
                view.requestLayout()
                continue
            }
            ValueAnimator.ofInt(from, to).apply {
                setDuration(duration)
                interpolator = ease
                addUpdateListener {
                    apply(it.animatedValue as Int)
                    view.requestLayout()
                }
            }.start()
        }

        val target = (newNode["color"] as? String)?.let { color(it, it) }
        val current = (view.background as? ColorDrawable)?.color
        if (target != null && target != current) {
            if (current == null) {
                view.setBackgroundColor(target)
            } else {
                ValueAnimator.ofObject(ArgbEvaluator(), current, target).apply {
                    setDuration(duration)
                    interpolator = ease
                    addUpdateListener {
                        view.setBackgroundColor(it.animatedValue as Int)
                    }
                }.start()
            }
        } else if (target == null && current != null) {
            view.background = null
        }
        return true
    }

    /** A protocol curve name as an Android interpolator. */
    private fun interpolator(node: Map<*, *>): Interpolator = when (node["curve"]) {
        "linear" -> LinearInterpolator()
        "easeIn" -> AccelerateInterpolator()
        "easeOut" -> DecelerateInterpolator()
        // 'ease' is CSS's name for a curve that starts fast out of the gate;
        // Android's nearest is the same ease-in-out the default uses.
        else -> AccelerateDecelerateInterpolator()
    }

    /**
     * A strip of labels, one selected - Material's own tabs.
     *
     * The selection is the app's: a tap reports the index and the next tree
     * says which tab is selected, so the bar never disagrees with the screen
     * below it.
     */
    private fun renderTabs(node: Map<*, *>): View = TabLayout(materialContext).apply {
        val labels = (node["tabs"] as? List<*>)?.map { it.toString() } ?: emptyList()
        tabMode = if (labels.size > 3) TabLayout.MODE_SCROLLABLE else TabLayout.MODE_FIXED
        tabGravity = TabLayout.GRAVITY_FILL
        setSelectedTabIndicatorColor(color(null, themePrimary))
        setTabTextColors(color(null, themeTextSecondary), color(null, themePrimary))
        layoutParams = matchWidth()
        for (label in labels) addTab(newTab().setText(label))
        selectTabAt(this, node)

        val eventId = node["eventId"] as? String
        if (eventId != null) {
            addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
                override fun onTabSelected(tab: TabLayout.Tab) {
                    // A selection the renderer itself made is not a tap.
                    if (settingChecked) return
                    val payload = mutableMapOf<String, Any?>("index" to tab.position)
                    (node["data"] as? Map<*, *>)?.forEach { (k, v) ->
                        payload[k.toString()] = v
                    }
                    sendEvent(eventId, payload)
                }

                override fun onTabUnselected(tab: TabLayout.Tab) = Unit
                override fun onTabReselected(tab: TabLayout.Tab) = Unit
            })
        }
    }

    /** Selects the tab [node] names, without the listener calling it a tap. */
    private fun selectTabAt(tabs: TabLayout, node: Map<*, *>) {
        val index = (node["selectedIndex"] as? Number)?.toInt() ?: 0
        val tab = tabs.getTabAt(index.coerceIn(0, (tabs.tabCount - 1).coerceAtLeast(0)))
            ?: return
        if (tab.isSelected) return
        settingChecked = true
        tab.select()
        settingChecked = false
    }

    private fun patchTabs(view: View, node: Map<*, *>): Boolean {
        val tabs = view as? TabLayout ?: return false
        val labels = (node["tabs"] as? List<*>)?.map { it.toString() } ?: emptyList()
        // A different set of tabs is a different bar; only the selection moves
        // in place, which is what a tap changes.
        if (labels.size != tabs.tabCount) return false
        for ((index, label) in labels.withIndex()) {
            if (tabs.getTabAt(index)?.text != label) return false
        }
        selectTabAt(tabs, node)
        return true
    }

    private fun renderSlider(node: Map<*, *>): View = Slider(materialContext).apply {
        val from = (node["min"] as? Number)?.toFloat() ?: 0f
        val to = (node["max"] as? Number)?.toFloat() ?: 1f
        valueFrom = from
        valueTo = to
        stepSize = (node["divisions"] as? Number)?.let { (to - from) / it.toFloat() } ?: 0f
        value = sliderValue(node, from, to)
        isEnabled = node["disabled"] != true
        trackActiveTintList = ColorStateList.valueOf(color(null, themePrimary))
        thumbTintList = ColorStateList.valueOf(color(null, themePrimary))
        layoutParams = matchWidth()

        val eventId = node["eventId"] as? String
        if (eventId != null) {
            addOnChangeListener { _, value, fromUser ->
                // A value the renderer itself set is not a drag.
                if (fromUser) sendEvent("${eventId}_change", payload(node, value))
            }
            addOnSliderTouchListener(object : Slider.OnSliderTouchListener {
                override fun onStartTrackingTouch(slider: Slider) = Unit
                override fun onStopTrackingTouch(slider: Slider) {
                    sendEvent("${eventId}_end", payload(node, slider.value))
                }
            })
        }
    }

    /** [node]'s value, clamped: Material throws on one outside the range. */
    private fun sliderValue(node: Map<*, *>, from: Float, to: Float): Float {
        val value = (node["value"] as? Number)?.toFloat() ?: from
        return value.coerceIn(from, to)
    }

    private fun payload(node: Map<*, *>, value: Float): Map<String, Any?> {
        val data = node["data"] as? Map<*, *>
        val payload = mutableMapOf<String, Any?>()
        data?.forEach { (key, v) -> payload[key.toString()] = v }
        payload["value"] = value.toDouble()
        return payload
    }

    private fun patchSlider(view: View, node: Map<*, *>): Boolean {
        val slider = view as? Slider ?: return false
        val from = (node["min"] as? Number)?.toFloat() ?: 0f
        val to = (node["max"] as? Number)?.toFloat() ?: 1f
        slider.valueFrom = from
        slider.valueTo = to
        slider.isEnabled = node["disabled"] != true
        val value = sliderValue(node, from, to)
        // Not while it is being dragged: the app is echoing back the value the
        // finger is already setting, and writing it would fight the gesture.
        if (slider.value != value && !slider.isPressed) slider.value = value
        return true
    }

    private fun renderToggle(node: Map<*, *>): View = SwitchCompat(materialContext).apply {
        // Build under the Material theme so the track/thumb are styled and
        // visible. Material switches show no ON/OFF thumb text; leaving it on
        // lays out textOn/textOff, which are null under the host activity's
        // non-AppCompat theme and crash onMeasure with an NPE.
        showText = false
        text = node["label"] as? String ?: ""
        setTextColor(color(null, themeText))
        // The thumb takes the brand colour when on and the surface when off;
        // the track is the same colour faded, which is how Material draws it.
        thumbTintList = controlTint(
            checked = color(null, themePrimary),
            unchecked = color(null, themeSurfaceVariant),
        )
        trackTintList = controlTint(
            checked = withAlpha(color(null, themePrimary), 0.5f),
            unchecked = color(null, themeDivider),
        )
        isChecked = node["enabled"] == true
        isEnabled = node["disabled"] != true
        layoutParams = wrapContent()
        setOnCheckedChangeListener { _, checked ->
            if (!settingChecked) sendEvent(node, mapOf("enabled" to checked))
        }
    }

    // -------------------------------------------------------------------------
    // Lists
    // -------------------------------------------------------------------------

    private fun renderList(node: Map<*, *>): View {
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = matchWidth()
        }
        addChildren(column, node, horizontal = false, stretch = true)
        return column
    }

    private fun renderListItem(node: Map<*, *>): View {
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = matchWidth()
            setPadding(dp(16), dp(12), dp(16), dp(12))
        }
        column.addView(AppCompatTextView(activity).apply {
            text = node["text"] as? String ?: ""
            textSize = 16f
        }, matchWidth())
        (node["subtitle"] as? String)?.let { subtitle ->
            column.addView(AppCompatTextView(activity).apply {
                text = subtitle
                textSize = 13f
                setTextColor(color(null, themeTextSecondary))
            }, matchWidth())
        }
        return column
    }

    /**
     * A long list of fixed-height rows, of which the node carries only a window.
     *
     * The scrollable area is as tall as every row would be, and each row the
     * node carries is placed where its index puts it, so the scrollbar and the
     * scroll position mean the same as for the whole list. The visible range is
     * reported whenever it changes; Dart answers with a render carrying the rows
     * around it. The scroll position is kept per list id across those renders.
     */
    private fun renderLazyList(node: Map<*, *>): View {
        val id = node["id"] as? String ?: ""
        val itemCount = (node["itemCount"] as? Number)?.toInt() ?: 0
        val extent = ((node["itemExtent"] as? Number)?.toFloat() ?: 48f) *
            activity.resources.displayMetrics.density
        val startIndex = (node["startIndex"] as? Number)?.toInt() ?: 0
        val rangeEventId = node["rangeEventId"] as? String
        renderedLists += id

        // Rows of their own heights arrive with the window's own heights and
        // where the window starts; uniform rows are arithmetic from the index.
        val density = activity.resources.displayMetrics.density
        val rowExtents = (node["extents"] as? List<*>)
            ?.map { ((it as? Number)?.toFloat() ?: 0f) * density }
        val startOffset = ((node["startOffset"] as? Number)?.toFloat() ?: 0f) * density
        val totalExtent = ((node["totalExtent"] as? Number)?.toFloat() ?: 0f) * density

        val rows = FrameLayout(activity).apply {
            // ScrollView measures its child unbounded, so the minimum is what
            // sizes the whole list.
            minimumHeight = if (rowExtents == null) {
                (itemCount * extent).roundToInt()
            } else {
                totalExtent.roundToInt()
            }
        }
        var running = startOffset
        for ((offset, child) in childNodes(node).withIndex()) {
            val view = renderWidget(child) ?: continue
            val index = startIndex + offset
            // Edges rounded from the running offset, so rows neither gap nor
            // overlap.
            val top: Int
            val height: Int
            if (rowExtents == null) {
                top = (index * extent).roundToInt()
                height = ((index + 1) * extent).roundToInt() - top
            } else {
                top = running.roundToInt()
                running += rowExtents.getOrElse(offset) { 0f }
                height = running.roundToInt() - top
            }
            rows.addView(view, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                height
            ).apply { topMargin = top })
        }

        // Nothing is saved until the old position is restored, so the first
        // layout's zero cannot overwrite it.
        var restored = false
        val report = { view: ScrollView ->
            if (rowExtents == null) {
                reportRange(view, id, itemCount, extent, rangeEventId)
            } else {
                reportOffset(view, id, rangeEventId, density)
            }
        }
        val list = ReportingScrollView(
            activity,
            onLaidOut = { view ->
                if (!restored) {
                    restored = true
                    view.scrollTo(0, lazyScroll[id] ?: 0)
                }
                report(view)
            },
            onScrolled = { view ->
                if (restored) {
                    lazyScroll[id] = view.scrollY
                    report(view)
                }
            },
        ).apply {
            layoutParams = matchParent()
            addView(rows, matchWidth())
        }
        return list
    }

    /**
     * Sends where a list of rows of their own heights is scrolled to.
     *
     * Only the Dart side knows how tall the rows outside the window are, so a
     * renderer drawing them reports pixels and lets it say which rows those
     * are - in logical pixels, like everything else on the wire.
     */
    private fun reportOffset(
        view: ScrollView,
        id: String,
        eventId: String?,
        density: Float,
    ) {
        if (eventId == null || view.height == 0) return
        val offset = view.scrollY / density
        val viewport = view.height / density
        val seen = offset to viewport
        if (lazyOffsets[id] == seen) return
        lazyOffsets[id] = seen
        sendEvent(eventId, mapOf("offset" to offset, "viewport" to viewport))
    }

    /**
     * Takes or gives up the keyboard when the app asks: once for `autofocus`,
     * and again whenever `focusVersion` changes.
     *
     * Deferred with `post`, because a view that is not laid out yet cannot
     * take focus - the same reason the rebuild's own focus restore defers.
     */
    private fun applyFocusRequest(field: EditText, eventId: String, node: Map<*, *>) {
        val version = (node["focusVersion"] as? Number)?.toInt()
        val wanted = node["focusRequested"] != false
        val auto = node["autofocus"] == true
        val ask = version ?: if (auto) AUTOFOCUS_VERSION else return
        if (focusVersions[eventId] == ask) return
        focusVersions[eventId] = ask
        field.post {
            val ime = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
                as? android.view.inputmethod.InputMethodManager
            if (wanted) {
                field.requestFocus()
                ime?.showSoftInput(field, 0)
            } else {
                field.clearFocus()
                ime?.hideSoftInputFromWindow(field.windowToken, 0)
            }
        }
    }

    /** Sends the rows [view] shows, unless this list last sent the same ones. */
    private fun reportRange(
        view: ScrollView,
        id: String,
        itemCount: Int,
        extent: Float,
        eventId: String?,
    ) {
        if (eventId == null || itemCount <= 0 || extent <= 0f || view.height == 0) return
        val offset = view.scrollY.toFloat()
        val first = floor(offset / extent).toInt().coerceIn(0, itemCount - 1)
        val last = min(itemCount - 1, ceil((offset + view.height) / extent).toInt() - 1)
            .coerceAtLeast(first)
        val range = first to last
        if (lazyRanges[id] == range) return
        lazyRanges[id] = range
        sendEvent(eventId, mapOf("first" to first, "last" to last))
    }

    // -------------------------------------------------------------------------
    // Overlays
    // -------------------------------------------------------------------------

    // Overlays are views in the renderer's own container rather than Dialog or
    // BottomSheetDialog windows: they are state in the tree, so each render
    // must show exactly the ones it carries. A renderer never removes one - a
    // tap on the scrim, a swipe or a timeout only sends the dismiss event, and
    // the app leaves the overlay out of its next tree.

    /**
     * The screen with overlays drawn over it, later ones on top.
     *
     * Every child fills the container, so an overlay is placed against the
     * whole screen and does not scroll with it. Under the topmost dialog or
     * sheet, everything is hidden from accessibility services, as its scrim
     * hides it from touch.
     */
    private fun renderOverlay(node: Map<*, *>): View {
        val layer = FrameLayout(activity).apply { layoutParams = matchParent() }
        val children = childNodes(node)
        val topModal = children.indexOfLast {
            it["type"] == "Dialog" || it["type"] == "BottomSheet"
        }
        for ((index, child) in children.withIndex()) {
            val view = renderWidget(child) ?: continue
            if (index < topModal) {
                view.importantForAccessibility =
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
            layer.addView(view, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
        }
        return layer
    }

    /**
     * A modal dialog: a rounded surface centred over a scrim, holding the title
     * and then the node's children - the content column and the actions row
     * `UIBuilder.dialog` builds.
     */
    private fun renderDialog(node: Map<*, *>): View {
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        (node["title"] as? String)?.let { title ->
            content.addView(AppCompatTextView(activity).apply {
                text = title
                textSize = 22f
                setTextColor(color(null, themeText))
            }, matchWidth())
        }
        for (child in childNodes(node)) {
            val view = renderWidget(child) ?: continue
            content.addView(view, linear().apply {
                if (content.childCount > 0) topMargin = dp(16)
            })
        }

        val card = MaterialCardView(materialContext).apply {
            radius = dp(28).toFloat()
            cardElevation = dp(6).toFloat()
            setCardBackgroundColor(color(null, themeSurfaceVariant))
            // Content taller than the screen scrolls inside the surface.
            addView(ScrollView(activity).apply { addView(content, matchWidth()) }, matchWidth())
            // A touch on the surface stays on it rather than reaching the scrim.
            setOnTouchListener { _, _ -> true }
        }

        val surface = BoundedFrame(activity, maxWidth = dp(560), maxHeightFraction = 1f)
        surface.addView(card, matchWidth())
        val params = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        )
        surface.layoutParams = params
        onSystemBars(surface) { bars ->
            params.setMargins(
                dp(24) + bars.left, dp(24) + bars.top,
                dp(24) + bars.right, dp(24) + bars.bottom
            )
            surface.layoutParams = params
        }
        return modalLayer(node, surface)
    }

    /**
     * A modal sheet along the bottom edge, over a scrim: a drag handle, the
     * title and the node's children. Dragged down far enough it sends the
     * dismiss event and springs back; the app removes it.
     */
    private fun renderBottomSheet(node: Map<*, *>): View {
        val dismiss = dismissEvent(node)
        val padding = dp(16)
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        (node["title"] as? String)?.let { title ->
            content.addView(AppCompatTextView(activity).apply {
                text = title
                textSize = 20f
                setTextColor(color(null, themeText))
            }, linear().apply { bottomMargin = dp(8) })
        }
        for (child in childNodes(node)) {
            renderWidget(child)?.let { content.addView(it, linear()) }
        }
        val scroll = ScrollView(activity).apply { addView(content, matchWidth()) }

        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(View(activity).apply {
                background = GradientDrawable().apply {
                    setColor(color(null, themeDivider))
                    cornerRadius = dp(2).toFloat()
                }
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(32), dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(12)
            })
            addView(scroll, linear())
        }

        val radius = dp(28).toFloat()
        val sheet = SheetFrame(
            activity,
            maxWidth = dp(640),
            maxHeightFraction = 0.9f,
            canScrollUp = { scroll.canScrollVertically(-1) },
            onSwipe = dismiss?.let { eventId ->
                { sendEvent(eventId, mapOf("reason" to "swipe")) }
            },
        ).apply {
            background = GradientDrawable().apply {
                setColor(color(null, themeSurfaceVariant))
                cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
            }
            elevation = dp(8).toFloat()
            clipToOutline = true
            addView(column, matchWidth())
        }
        val params = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        )
        sheet.layoutParams = params
        onSystemBars(sheet) { bars ->
            // The sheet reaches the bottom edge; its content stays clear of the
            // navigation bar.
            params.topMargin = bars.top
            sheet.layoutParams = params
            content.setPadding(padding, padding, padding, padding + bars.bottom)
        }
        return modalLayer(node, sheet)
    }

    /**
     * The full-screen layer a dialog or sheet sits in: a scrim under [surface]
     * that takes every touch outside it, sending the dismiss event where the
     * node allows one.
     */
    private fun modalLayer(node: Map<*, *>, surface: View): View {
        val dismiss = dismissEvent(node)
        val scrim = View(activity).apply {
            setBackgroundColor(Color.argb(102, 0, 0, 0))
            // Clickable either way, so no touch reaches the screen underneath.
            isClickable = true
            if (dismiss != null) {
                contentDescription = "Dismiss"
                setOnClickListener { sendEvent(dismiss, mapOf("reason" to "scrim")) }
            } else {
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        }
        (node["title"] as? String)?.let { title ->
            ViewCompat.setAccessibilityPaneTitle(surface, title)
            surface.contentDescription = title
        }
        return FrameLayout(activity).apply {
            layoutParams = matchParent()
            addView(scrim, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ))
            addView(surface)
        }
    }

    /**
     * A message along the bottom edge, with an optional action.
     *
     * Not modal: the layer it sits in takes no touches, so the screen stays
     * usable around it. Its timeout is kept by [scheduleSnackbarTimeout], since
     * this view does not outlive the render.
     */
    private fun renderSnackbar(node: Map<*, *>): View {
        scheduleSnackbarTimeout(node)

        val bar = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(48)
            setPadding(dp(16), dp(6), dp(8), dp(6))
            background = GradientDrawable().apply {
                setColor(color(null, inversePalette.surface))
                cornerRadius = dp(4).toFloat()
            }
            elevation = dp(6).toFloat()
            // Taps on the bar itself do not fall through to the screen below.
            isClickable = true
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        bar.addView(AppCompatTextView(activity).apply {
            text = node["message"] as? String ?: ""
            textSize = 14f
            setTextColor(color(null, inversePalette.text))
            setPadding(0, dp(8), dp(8), dp(8))
        }, linear(width = 0, weight = 1f))

        (node["actionLabel"] as? String)?.let { label ->
            bar.addView(MaterialButton(materialContext).apply {
                text = label
                setBackgroundColor(Color.TRANSPARENT)
                setTextColor(color(null, inversePalette.primary))
                (node["actionEventId"] as? String)?.let { eventId ->
                    setOnClickListener { sendEvent(eventId, emptyMap()) }
                }
            }, linear(width = ViewGroup.LayoutParams.WRAP_CONTENT))
        }

        val params = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        )
        bar.layoutParams = params
        onSystemBars(bar) { bars ->
            params.setMargins(
                dp(16) + bars.left, 0,
                dp(16) + bars.right, dp(16) + bars.bottom
            )
            bar.layoutParams = params
        }
        return FrameLayout(activity).apply {
            layoutParams = matchParent()
            addView(bar)
        }
    }

    /**
     * Starts the snackbar's timeout the first time its identity is rendered.
     *
     * The identity is the node's `id`, else its dismiss event, else its
     * message; the same snackbar rendered again keeps the timer it has, so the
     * dismiss event is sent once however often the tree is rendered meanwhile.
     */
    private fun scheduleSnackbarTimeout(node: Map<*, *>) {
        val eventId = node["dismissEventId"] as? String ?: return
        val duration = (node["durationMs"] as? Number)?.toLong() ?: 0L
        if (duration <= 0L) return

        val identity = node["id"] as? String ?: eventId
        renderedSnackbars += identity
        if (identity in snackbarTimers) return

        val timeout = Runnable { sendEvent(eventId, mapOf("reason" to "timeout")) }
        snackbarTimers[identity] = timeout
        handler.postDelayed(timeout, duration)
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /** Wires a tappable view to the node's event, carrying its payload. */
    private fun bindTap(view: View, node: Map<*, *>) {
        if (node["eventId"] !is String) return
        view.setOnClickListener { sendEvent(node, emptyMap()) }
    }

    /** Sends the node's own event, its payload merged with [extra]. */
    private fun sendEvent(node: Map<*, *>, extra: Map<String, Any?>) {
        val eventId = node["eventId"] as? String ?: return
        val data = (node["data"] as? Map<*, *>)
            ?.entries
            ?.associate { (key, value) -> key.toString() to value }
            ?: emptyMap()
        sendEvent(eventId, data + extra)
    }

    /**
     * Hands one event to Dart.
     *
     * Dart owns every handler - the native side only reports what happened -
     * so this is the whole of the return path.
     */
    private fun sendEvent(eventId: String, data: Map<String, Any?>) {
        channel?.invokeMethod(
            EVENT_METHOD,
            mapOf("eventId" to eventId, "data" to data),
        )
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * The tree as this file reads it: each node's props lifted onto the node.
     *
     * Dart sends `{type, props: {...}, children}`, and everything here reads a
     * prop straight off the node (`node["title"]`), so the whole tree is
     * flattened once per render. The node's own `type` and `children` win over
     * any prop of the same name, and the props stay under `props` too: Loading
     * and Alert have a prop called `type`, read through [prop].
     */
    private fun normalized(node: Map<*, *>): Map<String, Any?> {
        val props = node["props"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val flat = LinkedHashMap<String, Any?>()
        for ((key, value) in props) flat[key.toString()] = value
        flat["type"] = node["type"]
        flat["props"] = props
        flat["children"] = childNodes(node).map { normalized(it) }
        return flat
    }

    /** A prop as the app set it, for names the node itself also uses. */
    private fun prop(node: Map<*, *>, name: String): Any? =
        (node["props"] as? Map<*, *>)?.get(name)

    private fun childNodes(node: Map<*, *>): List<Map<*, *>> =
        (node["children"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()

    private fun firstChild(node: Map<*, *>): Map<*, *>? = childNodes(node).firstOrNull()

    /** Adds a node's children, honouring the gap its props ask for. */
    private fun addChildren(
        parent: LinearLayout,
        node: Map<*, *>,
        horizontal: Boolean,
        stretch: Boolean,
    ) {
        val spacing = dp((node["spacing"] as? Number)?.toInt() ?: 0)
        val children = childNodes(node)
        for ((index, child) in children.withIndex()) {
            val view = renderWidget(child) ?: continue
            val params = stackChildParams(view, child, horizontal, stretch)
            if (spacing > 0 && index > 0) {
                if (horizontal) params.marginStart = spacing else params.topMargin = spacing
            }
            parent.addView(view, params)
        }
    }

    /** Pushes a row's children apart, which is what spaceBetween means. */
    /** Weighted gaps between the children, on whichever axis [stack] runs. */
    private fun spaceBetween(stack: LinearLayout) {
        var index = 1
        while (index < stack.childCount) {
            stack.addView(View(activity).apply {
                layoutParams = LinearLayout.LayoutParams(0, 0, 1f)
            }, index)
            index += 2
        }
    }

    private fun icon(name: String?): Int =
        ICONS[name] ?: android.R.drawable.presence_online

    /**
     * Sets [view]'s image to a Material Icons glyph when the node carries a
     * codepoint (the full icon set, matching Flutter and the web), falling back
     * to the approximate system drawable - tinted [colorInt] either way.
     */
    private fun applyIcon(
        view: ImageView,
        node: Map<*, *>,
        defaultName: String,
        colorInt: Int,
    ) = setIcon(
        view,
        codepoint = (node["iconCodepoint"] as? Number)?.toInt(),
        name = node["icon"] as? String ?: defaultName,
        colorInt = colorInt,
    )

    /** [applyIcon]'s body, for an icon the renderer picks rather than a node. */
    private fun setIcon(view: ImageView, codepoint: Int?, name: String, colorInt: Int) {
        val glyph = codepoint?.let { iconGlyphDrawable(it, colorInt) }
        if (glyph != null) {
            view.setImageDrawable(glyph)
            view.imageTintList = null
        } else {
            view.setImageResource(icon(name))
            view.imageTintList = ColorStateList.valueOf(colorInt)
        }
    }

    /**
     * Glyphs already rasterised, by codepoint and colour.
     *
     * Without it every icon is a fresh Bitmap with the glyph drawn into it -
     * per icon, per view build - which a list paying for one icon a row does
     * 29 times per window.
     */
    private val glyphCache = HashMap<Long, Bitmap>()

    /** Draws a Material Icons [codepoint] into a 24dp drawable in [colorInt]. */
    private fun iconGlyphDrawable(codepoint: Int, colorInt: Int): Drawable? {
        val typeface = iconFont ?: return null
        val size = dp(24)
        val key = (codepoint.toLong() shl 32) or (colorInt.toLong() and 0xffffffffL)
        glyphCache[key]?.let { return BitmapDrawable(activity.resources, it) }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.typeface = typeface
            textSize = size.toFloat()
            color = colorInt
            textAlign = Paint.Align.CENTER
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val metrics = paint.fontMetrics
        val baseline = size / 2f - (metrics.ascent + metrics.descent) / 2f
        Canvas(bitmap).drawText(String(Character.toChars(codepoint)), size / 2f, baseline, paint)
        glyphCache[key] = bitmap
        return BitmapDrawable(activity.resources, bitmap)
    }

    /**
     * A list row that slides its child left to reveal trailing action buttons:
     * a partial drag snaps open so a button can be tapped, a full drag fires the
     * first action. It intercepts only mostly-horizontal drags, so a tap reaches
     * the child (e.g. the row's own buttons) and a vertical drag still scrolls.
     */
    private inner class SwipeActionsLayout(node: Map<*, *>) : FrameLayout(activity) {
        private val foreground: FrameLayout
        private val eventIds = mutableListOf<String>()
        private val leadingEventIds = mutableListOf<String>()
        private val actionWidthPx = dp(88)
        private val openOffset: Float
        private val openLeadingOffset: Float
        private val slop = ViewConfiguration.get(activity).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var baseTranslation = 0f
        private var dragging = false

        init {
            layoutParams = matchWidth()

            // One bar of buttons at [gravity], collecting the ids it bound.
            fun bar(key: String, gravity: Int, into: MutableList<String>) {
                val actions = (node[key] as? List<*>)?.filterIsInstance<Map<*, *>>()
                    ?: emptyList()
                if (actions.isEmpty()) return
                val bar = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                for (a in actions) {
                    val eventId = a["eventId"] as? String ?: continue
                    into.add(eventId)
                    bar.addView(MaterialButton(materialContext).apply {
                        text = a["label"] as? String ?: ""
                        setTextColor(Color.WHITE)
                        isAllCaps = false
                        cornerRadius = 0
                        insetTop = 0
                        insetBottom = 0
                        backgroundTintList = android.content.res.ColorStateList.valueOf(
                            color(a["color"], themeError))
                        layoutParams = LinearLayout.LayoutParams(
                            actionWidthPx, ViewGroup.LayoutParams.MATCH_PARENT)
                        setOnClickListener { sendEvent(eventId, emptyMap()); settle(0f) }
                    })
                }
                addView(bar, FrameLayout.LayoutParams(
                    actionWidthPx * max(1, into.size),
                    ViewGroup.LayoutParams.MATCH_PARENT, gravity))
            }

            bar("leadingActions", Gravity.START, leadingEventIds)
            bar("actions", Gravity.END, eventIds)
            openOffset = -(actionWidthPx.toFloat() * eventIds.size)
            openLeadingOffset = actionWidthPx.toFloat() * leadingEventIds.size

            foreground = FrameLayout(activity).apply {
                setBackgroundColor(color(null, themeSurface))
                firstChild(node)?.let { renderWidget(it) }?.let { addView(it, matchParent()) }
            }
            addView(foreground, matchParent())
        }

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = ev.x; downY = ev.y
                    baseTranslation = foreground.translationX
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.x - downX
                    val dy = ev.y - downY
                    if (!dragging && kotlin.math.abs(dx) > slop &&
                        kotlin.math.abs(dx) > kotlin.math.abs(dy)) {
                        dragging = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                        return true
                    }
                }
            }
            return false
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            when (ev.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    foreground.translationX = (baseTranslation + ev.x - downX)
                        .coerceIn(openOffset * 1.8f, openLeadingOffset * 1.8f)
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    parent?.requestDisallowInterceptTouchEvent(false)
                    val next = foreground.translationX
                    if (next <= openOffset * 1.6f && eventIds.isNotEmpty()) {
                        sendEvent(eventIds.first(), emptyMap())
                        settle(0f)
                    } else if (next >= openLeadingOffset * 1.6f &&
                        leadingEventIds.isNotEmpty()
                    ) {
                        sendEvent(leadingEventIds.first(), emptyMap())
                        settle(0f)
                    } else {
                        settle(
                            when {
                                next <= openOffset / 2f -> openOffset
                                openLeadingOffset > 0f &&
                                    next >= openLeadingOffset / 2f -> openLeadingOffset
                                else -> 0f
                            }
                        )
                    }
                    dragging = false
                    return true
                }
            }
            return dragging
        }

        private fun settle(value: Float) {
            foreground.animate().translationX(value).setDuration(200).start()
        }
    }

    /**
     * The colour text takes over a background the app stated, rather than over
     * the surface the theme's text colour was chosen against.
     *
     * The rule is WCAG's relative luminance, the same one the Dart renderers
     * apply from `src/contrast.dart` - white over a dark colour, the default
     * theme's near-black over a light one - so a card the app coloured reads
     * the same on all four renderers.
     */
    private fun textOn(background: Int): Int =
        if (relativeLuminance(background) > 0.179) Color.parseColor(ON_LIGHT)
        else Color.parseColor(ON_DARK)

    private fun relativeLuminance(argb: Int): Double =
        0.2126 * linearChannel(Color.red(argb)) +
            0.7152 * linearChannel(Color.green(argb)) +
            0.0722 * linearChannel(Color.blue(argb))

    private fun linearChannel(channel: Int): Double {
        val value = channel / 255.0
        return if (value <= 0.03928) value / 12.92
        else Math.pow((value + 0.055) / 1.055, 2.4)
    }

    private fun color(value: Any?, fallback: String): Int = try {
        Color.parseColor(value as? String ?: fallback)
    } catch (e: IllegalArgumentException) {
        Color.parseColor(fallback)
    }

    /**
     * The tint for a checkable control, as a state list.
     *
     * A bare CheckBox, RadioButton or SwitchCompat draws itself in the
     * platform's own accent, which belongs to neither the app nor its theme, so
     * every one of them is tinted from the palette instead: [checked] when the
     * control is on, [unchecked] when it is off, and the divider colour when it
     * is disabled, which is what reads as unavailable in both appearances.
     */
    private fun controlTint(checked: Int, unchecked: Int) = ColorStateList(
        arrayOf(
            intArrayOf(-android.R.attr.state_enabled),
            intArrayOf(android.R.attr.state_checked),
            intArrayOf(),
        ),
        intArrayOf(color(null, themeDivider), checked, unchecked),
    )

    private fun withAlpha(color: Int, alpha: Float): Int = Color.argb(
        (alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color)
    )

    private fun matchParent() = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
    )

    private fun matchWidth() = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun wrapContent() = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun linear(
        width: Int = ViewGroup.LayoutParams.MATCH_PARENT,
        height: Int = ViewGroup.LayoutParams.WRAP_CONTENT,
        weight: Float = 0f,
    ) = LinearLayout.LayoutParams(width, height, weight)

    private fun dp(value: Int): Int =
        (value * activity.resources.displayMetrics.density).toInt()

    /**
     * The height a toolbar gives its title row, from the theme.
     *
     * WRAP_CONTENT alone does not say it: a bar that also pads itself past the
     * status icons wraps to that padding plus the text, and the row the title
     * should sit in the middle of never exists.
     */
    private fun actionBarHeight(): Int {
        val value = TypedValue()
        val resolved =
            materialContext.theme.resolveAttribute(android.R.attr.actionBarSize, value, true)
        return if (resolved) {
            TypedValue.complexToDimensionPixelSize(value.data, activity.resources.displayMetrics)
        } else {
            dp(56)
        }
    }

    /** The dismiss event of a dialog or sheet, if it can be dismissed at all. */
    private fun dismissEvent(node: Map<*, *>): String? =
        if (node["dismissible"] == false) null else node["dismissEventId"] as? String

    /** Drops the per-identity state of snackbars and lists the last render left out. */
    private fun forgetUnrendered() {
        for (identity in snackbarTimers.keys - renderedSnackbars) {
            snackbarTimers.remove(identity)?.let(handler::removeCallbacks)
        }
        lazyScroll.keys.retainAll(renderedLists)
        lazyRanges.keys.retainAll(renderedLists)
    }

    /**
     * Calls [apply] with the system bar insets reaching [view]: at once with the
     * last ones seen, then as the window dispatches them. A rebuilt view was not
     * there for the last dispatch, so it asks for one when attached.
     */
    private fun onSystemBars(view: View, apply: (Insets) -> Unit) {
        apply(systemBars)
        ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            systemBars = bars
            apply(bars)
            insets
        }
        view.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) = ViewCompat.requestApplyInsets(v)
            override fun onViewDetachedFromWindow(v: View) = Unit
        })
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * A frame no wider than [maxWidth] and no taller than [maxHeightFraction]
     * of the height its parent offers - the bounds of a dialog or sheet surface.
     */
    private open class BoundedFrame(
        context: Context,
        private val maxWidth: Int,
        private val maxHeightFraction: Float,
    ) : FrameLayout(context) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val width = MeasureSpec.getSize(widthMeasureSpec)
            val height = MeasureSpec.getSize(heightMeasureSpec)
            super.onMeasure(
                MeasureSpec.makeMeasureSpec(min(width, maxWidth), MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(
                    (height * maxHeightFraction).toInt(),
                    MeasureSpec.AT_MOST
                ),
            )
        }
    }

    /**
     * A bottom sheet surface that follows a downward drag.
     *
     * The drag is taken from the content only while the content is scrolled to
     * its top, so scrolling up inside the sheet still scrolls. Released past a
     * quarter of its height it calls [onSwipe]; either way it springs back,
     * and it takes every touch on it so none reaches the scrim.
     */
    private class SheetFrame(
        context: Context,
        maxWidth: Int,
        maxHeightFraction: Float,
        private val canScrollUp: () -> Boolean,
        private val onSwipe: (() -> Unit)?,
    ) : BoundedFrame(context, maxWidth, maxHeightFraction) {
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var downY = 0f
        private var dragging = false

        override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
            if (onSwipe == null) return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> if (
                    !dragging && event.rawY - downY > touchSlop && !canScrollUp()
                ) {
                    dragging = true
                    downY = event.rawY
                }
            }
            return dragging
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    dragging = onSwipe != null
                }
                MotionEvent.ACTION_MOVE -> if (dragging) {
                    translationY = max(0f, event.rawY - downY)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val released = event.actionMasked == MotionEvent.ACTION_UP
                    if (dragging && released && translationY > height / 4f) onSwipe?.invoke()
                    dragging = false
                    animate().translationY(0f).setDuration(200).start()
                }
            }
            return true
        }
    }

    /** A ScrollView that reports its layouts and scrolls, for a lazy list. */
    private class ReportingScrollView(
        context: Context,
        private val onLaidOut: (ScrollView) -> Unit,
        private val onScrolled: (ScrollView) -> Unit,
    ) : ScrollView(context) {
        override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
            super.onLayout(changed, l, t, r, b)
            // Runs after every layout, a size change included.
            onLaidOut(this)
        }

        override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
            super.onScrollChanged(l, t, oldl, oldt)
            onScrolled(this)
        }
    }
}

/**
 * A ViewGroup that lays its children out left to right, wrapping onto the next
 * line when the current one runs out of width, and sizes itself to the height
 * that takes. Android has no wrapping layout in the framework, so a Wrap node is
 * drawn with one of these.
 */
/**
 * Equal cells in [columns] columns, each [aspectRatio] wide over tall.
 *
 * A grid is not a flow: the cells are all one size, and that size comes from
 * the width available rather than from what is inside them.
 */
private class GridLayoutView(
    context: Context,
    private val columns: Int,
    private val hSpacing: Int,
    private val vSpacing: Int,
    private val aspectRatio: Float,
) : ViewGroup(context) {

    private fun cellWidth(totalWidth: Int): Int =
        if (columns <= 0) totalWidth
        else (totalWidth - hSpacing * (columns - 1)) / columns

    private fun cellHeight(width: Int): Int =
        if (aspectRatio <= 0) width else (width / aspectRatio).toInt()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val cw = cellWidth(width)
        val ch = cellHeight(cw)
        val childWidthSpec = MeasureSpec.makeMeasureSpec(cw, MeasureSpec.EXACTLY)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(ch, MeasureSpec.EXACTLY)
        var visible = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            child.measure(childWidthSpec, childHeightSpec)
            visible++
        }
        val rows = if (columns <= 0) 0 else (visible + columns - 1) / columns
        val height = if (rows == 0) 0 else rows * ch + (rows - 1) * vSpacing
        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val cw = cellWidth(r - l)
        val ch = cellHeight(cw)
        var index = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            val column = index % columns
            val row = index / columns
            val x = column * (cw + hSpacing)
            val y = row * (ch + vSpacing)
            child.layout(x, y, x + cw, y + ch)
            index++
        }
    }
}

private class FlowLayout(
    context: Context,
    private val hSpacing: Int,
    private val vSpacing: Int,
) : ViewGroup(context) {

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxWidth = MeasureSpec.getSize(widthMeasureSpec)
        val childWidthSpec = MeasureSpec.makeMeasureSpec(maxWidth, MeasureSpec.AT_MOST)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        var x = 0
        var y = 0
        var rowHeight = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            child.measure(childWidthSpec, childHeightSpec)
            val w = child.measuredWidth
            if (x > 0 && x + w > maxWidth) {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            x += w + hSpacing
            rowHeight = maxOf(rowHeight, child.measuredHeight)
        }
        setMeasuredDimension(maxWidth, y + rowHeight)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val maxWidth = r - l
        var x = 0
        var y = 0
        var rowHeight = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            val w = child.measuredWidth
            val h = child.measuredHeight
            if (x > 0 && x + w > maxWidth) {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            child.layout(x, y, x + w, y + h)
            x += w + hSpacing
            rowHeight = maxOf(rowHeight, h)
        }
    }
}
