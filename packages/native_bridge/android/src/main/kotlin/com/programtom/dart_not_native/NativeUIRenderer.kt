package com.programtom.dart_not_native

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.ComponentCallbacks
import android.content.Context
import android.content.DialogInterface
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.os.Bundle
import android.net.http.HttpResponseCache
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.TextWatcher
import android.text.format.DateFormat
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import android.util.Base64
import android.util.LruCache
import android.view.Choreographer
import android.view.KeyEvent
import android.view.KeyboardShortcutGroup
import android.view.Menu
import android.view.ViewTreeObserver
import android.view.Window
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
import android.widget.TextView
import android.widget.RadioButton
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatTextView
import androidx.appcompat.widget.SwitchCompat
import androidx.appcompat.widget.Toolbar
import androidx.appcompat.widget.TooltipCompat
import android.util.TypedValue
import androidx.core.graphics.Insets
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.core.widget.TextViewCompat
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.datepicker.CalendarConstraints
import com.google.android.material.datepicker.CompositeDateValidator
import com.google.android.material.datepicker.DateValidatorPointBackward
import com.google.android.material.datepicker.DateValidatorPointForward
import com.google.android.material.datepicker.MaterialDatePicker
import com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.navigation.NavigationBarView
import com.google.android.material.navigationrail.NavigationRailView
import com.google.android.material.checkbox.MaterialCheckBox
import com.google.android.material.progressindicator.LinearProgressIndicator
import com.google.android.material.radiobutton.MaterialRadioButton
import com.google.android.material.slider.Slider
import com.google.android.material.tabs.TabLayout
import com.google.android.material.textfield.MaterialAutoCompleteTextView
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import com.google.android.material.timepicker.MaterialTimePicker
import com.google.android.material.timepicker.TimeFormat
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
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

        // The events the renderer sends on its own account, with no node
        // asking - `RendererEvents` in lib/src/ui_renderer.dart.
        private const val VIEWPORT_EVENT = "dnn:viewport"
        private const val KEY_EVENT = "dnn:key"
        private const val SLOT_RECT_EVENT = "dnn:slotRect"
        private const val LIFECYCLE_EVENT = "dnn:lifecycle"

        // Material Icons codepoints the renderer draws without a node naming
        // them: an app bar's `leading`. From lib/src/material_icons.dart.
        private const val BACK_CODEPOINT = 0xe092
        private const val MENU_CODEPOINT = 0xe3dc

        /** Marks a box that carries a tooltip, so one that loses it is told. */
        private const val TOOLTIP_TAG = "dnn:tooltip"

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

    private var rootContainer: SlotHostLayout? = null
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

    /** Whether the screen on show was laid out right to left. */
    private var paintedRtl = false

    /**
     * Turns the whole screen to the direction the tree's root states -
     * `textDirection: 'rtl'`, or nothing for left to right - and answers
     * whether that changed anything.
     *
     * It is set on the root container and nowhere else: a view inherits its
     * layout direction and its text direction from its parent, so every
     * LinearLayout row, every START and END gravity, every relative padding
     * and every Material control underneath turns with it, and the custom
     * layouts ask their own `layoutDirection` when they place their children.
     * Text is told as well as layout, so a line with no strong character of
     * its own - a number, a price - still starts at the right.
     *
     * A view only resolves to right-to-left in an app that declares
     * `android:supportsRtl="true"`, and a Flutter app's manifest does not
     * unless somebody added it. A tree that asks for right to left is that
     * declaration, so the flag is raised here rather than making every app
     * edit a manifest to get what it already said it wanted.
     */
    private fun applyDirection(root: View, tree: Map<*, *>): Boolean {
        val rtl = tree["textDirection"] == "rtl"
        if (rtl) {
            val info = activity.applicationInfo
            info.flags = info.flags or android.content.pm.ApplicationInfo.FLAG_SUPPORTS_RTL
        }
        root.layoutDirection =
            if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        // Left to right is left as the platform's own first-strong rule, which
        // is what it has always been: an Arabic name in an English screen
        // still reads from its own right.
        root.textDirection =
            if (rtl) View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_FIRST_STRONG
        val changed = paintedRtl != rtl
        paintedRtl = rtl
        return changed
    }

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
    // unless their Context carries a Material theme. It is Material 3's: the
    // shapes and sizes a view is not told - a button's round ends, a 64dp app
    // bar, a navigation bar with its pill - are then the ones a Flutter app,
    // Material 3 by default, draws. Colours are the app's palette, painted on
    // each view; the theme's own show only where the renderer forgot one.
    // The host app's
    // own theme need not be one - the framework promises zero app-side setup -
    // so Material views are built against this wrapper instead of the activity.
    // The wrapper follows the appearance too: a MaterialButton or a SwitchCompat
    // takes its own ripple, track and disabled colours from the theme, and a
    // light Material theme under a dark palette shows through wherever the
    // renderer does not paint a colour itself.
    private val lightMaterialContext: Context = ContextThemeWrapper(
        activity,
        com.google.android.material.R.style.Theme_Material3_Light_NoActionBar
    )
    private val darkMaterialContext: Context = ContextThemeWrapper(
        activity,
        com.google.android.material.R.style.Theme_Material3_Dark_NoActionBar
    )
    // By the palette in force rather than by the device: an app with one
    // theme for both appearances is light on a dark device too, and a dark
    // Material theme under it wrote the menu of a dropdown in white on white.
    private val materialContext: Context
        get() = if (ColorUtils.calculateLuminance(color(null, themeSurface)) < 0.5) {
            darkMaterialContext
        } else {
            lightMaterialContext
        }

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

    /** Where each `Scroll` with an id was scrolled to, so a rebuild can put it back. */
    private val scrollOffsets = mutableMapOf<String, Int>()

    /**
     * The `scrollVersion` each scroller last obeyed, by id. Like a focus ask,
     * "scroll to here" is a moment; the version is how a tree, which only
     * carries states, says it happened again.
     */
    private val scrollVersions = mutableMapOf<String, Int>()

    /** The size each `sizeEventId` last carried, so a rebuilt box does not say it again. */
    private val sizeReports = mutableMapOf<String, Pair<Float, Float>>()
    private val renderedSizes = mutableSetOf<String>()

    /** The date and time pickers on screen, by node id, each with the way to close it. */
    private val openPickers = mutableMapOf<String, () -> Unit>()

    /** What the box, stack and canvas views need of the renderer. */
    private val viewHost = object : ViewHost {
        override val density: Float get() = activity.resources.displayMetrics.density

        override fun send(eventId: String, data: Map<String, Any?>) = sendEvent(eventId, data)

        override fun reportSize(eventId: String, width: Float, height: Float) {
            val size = width to height
            if (sizeReports[eventId] == size) return
            sizeReports[eventId] = size
            sendEvent(
                eventId,
                mapOf("width" to width.toDouble(), "height" to height.toDouble()),
            )
        }
    }

    // The identities the render in progress has drawn; state for any other is
    // dropped once it finishes.
    private val renderedSnackbars = mutableSetOf<String>()
    private val renderedLists = mutableSetOf<String>()
    private val renderedScrolls = mutableSetOf<String>()

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
        // views are actually on screen - Flutter then only hosts the engine,
        // and paints through the holes a FlutterSlot leaves (SlotHostLayout).
        val container = SlotHostLayout(activity)
        activity.addContentView(
            container,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        rootContainer = container
        avoidKeyboard(container)
        closeKeyboardWithFocus(container)
        watchSlots(container)
        watchViewport(container)
        watchLifecycle()
        watchKeys()
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
            // Posted: the app is told about the insets the window has settled
            // on, which is not yet true while they are being dispatched.
            container.post { reportViewport() }
            insets
        }
        // The insets listener fires on the window's terms; the layout listener
        // catches the resize itself, which is what arrives under adjustResize.
        container.viewTreeObserver.addOnGlobalLayoutListener {
            apply()
            reportViewport()
        }
    }

    // -------------------------------------------------------------------------
    // Renderer events: the viewport, the lifecycle, hardware keys, slot rects
    // -------------------------------------------------------------------------

    /** The viewport last sent, so only a change is. */
    private var lastViewport: Map<String, Any>? = null

    /**
     * Tells Dart how much room there is and what is in the way of it.
     *
     * Sent once the container has a size and again whenever any of it changes:
     * a rotation, the keyboard, the font scale, night mode. Everything is in
     * logical pixels. `paddingBottom` is the navigation bar and stays put while
     * the keyboard is up; `keyboardInset` is the keyboard's whole height from
     * the bottom of the window, as Flutter's `viewInsets.bottom` is.
     */
    private fun reportViewport() {
        val container = rootContainer ?: return
        if (container.width == 0 || container.height == 0) return
        val density = activity.resources.displayMetrics.density
        val insets = ViewCompat.getRootWindowInsets(container)
        val bars = insets?.getInsets(
            WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
        ) ?: systemBars
        val keyboard = insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        val configuration = activity.resources.configuration
        fun logical(pixels: Int) = (pixels / density).toDouble()

        val viewport = mapOf<String, Any>(
            "width" to logical(container.width),
            "height" to logical(container.height),
            "paddingTop" to logical(bars.top),
            "paddingBottom" to logical(bars.bottom),
            "paddingLeft" to logical(bars.left),
            "paddingRight" to logical(bars.right),
            "keyboardInset" to logical(keyboard),
            "devicePixelRatio" to density.toDouble(),
            "textScale" to configuration.fontScale.toDouble(),
            // The device's own setting, whatever appearance the app chose to
            // paint: an app in "system" mode is the one that needs to know.
            "dark" to ((configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES),
        )
        if (viewport == lastViewport) return
        lastViewport = viewport
        sendEvent(VIEWPORT_EVENT, viewport)
    }

    /** The font scale and night mode change without the container's size doing so. */
    private val configurationWatcher = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) {
            rootContainer?.post { reportViewport() }
        }

        @Suppress("OVERRIDE_DEPRECATION")
        override fun onLowMemory() = Unit
    }

    private fun watchViewport(container: View) {
        activity.registerComponentCallbacks(configurationWatcher)
        container.post { reportViewport() }
    }

    /**
     * The activity's lifecycle under the names Flutter's `AppLifecycleState`
     * uses, mapped the way the Flutter embedding maps them: visible but not in
     * front is 'inactive', no longer visible is 'paused'.
     */
    private val lifecycleWatcher = object : Application.ActivityLifecycleCallbacks {
        private fun report(which: Activity, state: String) {
            if (which === activity) sendEvent(LIFECYCLE_EVENT, mapOf("state" to state))
        }

        override fun onActivityResumed(activity: Activity) = report(activity, "resumed")
        override fun onActivityPaused(activity: Activity) = report(activity, "inactive")
        override fun onActivityStopped(activity: Activity) = report(activity, "paused")
        override fun onActivityStarted(activity: Activity) = report(activity, "inactive")
        override fun onActivityDestroyed(activity: Activity) = report(activity, "detached")
        override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    }

    private fun watchLifecycle() {
        activity.application.registerActivityLifecycleCallbacks(lifecycleWatcher)
        // The renderer starts after the activity did, so the callbacks above
        // have nothing to say until something changes; say where it stands.
        val resumed = (activity as? LifecycleOwner)?.lifecycle?.currentState
            ?.isAtLeast(Lifecycle.State.RESUMED) ?: true
        sendEvent(LIFECYCLE_EVENT, mapOf("state" to if (resumed) "resumed" else "inactive"))
    }

    /** The window's own callback while this renderer's sits in front of it. */
    private var keyCallback: Window.Callback? = null
    private var originalKeyCallback: Window.Callback? = null
    private var watchingKeys = false

    /**
     * Reports hardware key presses - a keyboard, a d-pad, a game controller.
     *
     * The window's callback is the one place every key passes before the view
     * tree decides who gets it, so this wraps it: each key is reported and then
     * handed on untouched, to do whatever it did before. System keys - back,
     * volume - are left out; back has its own channel (see the plugin).
     */
    private fun watchKeys() {
        val window = activity.window ?: return
        val original = window.callback ?: return
        watchingKeys = true
        val wrapper = object : Window.Callback by original {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (watchingKeys) reportKey(event)
                return original.dispatchKeyEvent(event)
            }

            // The two the interface gives a default body: delegation only
            // forwards the abstract ones, and these still belong to the
            // callback underneath.
            override fun onProvideKeyboardShortcuts(
                data: MutableList<KeyboardShortcutGroup>?,
                menu: Menu?,
                deviceId: Int,
            ) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    original.onProvideKeyboardShortcuts(data, menu, deviceId)
                }
            }

            override fun onPointerCaptureChanged(hasCapture: Boolean) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    original.onPointerCaptureChanged(hasCapture)
                }
            }
        }
        keyCallback = wrapper
        originalKeyCallback = original
        window.callback = wrapper
    }

    private fun reportKey(event: KeyEvent) {
        if (event.isSystem) return
        val down = when (event.action) {
            KeyEvent.ACTION_DOWN -> true
            KeyEvent.ACTION_UP -> false
            else -> return
        }
        val key = keyName(event) ?: return
        sendEvent(KEY_EVENT, mapOf("key" to key, "down" to down))
    }

    /** A key under the name a browser's `KeyboardEvent.key` gives it. */
    private fun keyName(event: KeyEvent): String? = when (event.keyCode) {
        KeyEvent.KEYCODE_DPAD_UP -> "ArrowUp"
        KeyEvent.KEYCODE_DPAD_DOWN -> "ArrowDown"
        KeyEvent.KEYCODE_DPAD_LEFT -> "ArrowLeft"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "ArrowRight"
        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER,
        KeyEvent.KEYCODE_DPAD_CENTER -> "Enter"
        KeyEvent.KEYCODE_SPACE -> " "
        KeyEvent.KEYCODE_DEL -> "Backspace"
        KeyEvent.KEYCODE_FORWARD_DEL -> "Delete"
        KeyEvent.KEYCODE_ESCAPE -> "Escape"
        KeyEvent.KEYCODE_TAB -> "Tab"
        KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> "Shift"
        KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_CTRL_RIGHT -> "Control"
        KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_ALT_RIGHT -> "Alt"
        KeyEvent.KEYCODE_META_LEFT, KeyEvent.KEYCODE_META_RIGHT -> "Meta"
        KeyEvent.KEYCODE_PAGE_UP -> "PageUp"
        KeyEvent.KEYCODE_PAGE_DOWN -> "PageDown"
        KeyEvent.KEYCODE_MOVE_HOME -> "Home"
        KeyEvent.KEYCODE_MOVE_END -> "End"
        in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F12 ->
            "F${event.keyCode - KeyEvent.KEYCODE_F1 + 1}"
        else -> event.unicodeChar.takeIf { it > 0 }?.let { String(Character.toChars(it)) }
    }

    /** The slots on screen by `slotId`, and what was last said about each. */
    private val slots = LinkedHashMap<String, FlutterSlotView>()
    private val slotReports = HashMap<String, List<Any>>()
    private val slotPreDraw = ViewTreeObserver.OnPreDrawListener {
        updateSlots()
        true
    }
    private val slotScrolled = ViewTreeObserver.OnScrollChangedListener { updateSlots() }

    private fun watchSlots(container: View) {
        // Before every frame, and on every scroll: a slot moves whenever
        // anything around it does, and the frame that moves it is the frame
        // the hole has to move in.
        container.viewTreeObserver.addOnPreDrawListener(slotPreDraw)
        container.viewTreeObserver.addOnScrollChangedListener(slotScrolled)
    }

    /**
     * Works out where every `FlutterSlot` is, tells Dart about the ones that
     * moved, and gives the container the holes to leave.
     *
     * The rectangle reported is the slot's whole frame, in logical pixels from
     * the container's top-left corner - which is the FlutterView's, the two
     * being siblings that both fill the activity's content. The hole is only
     * the part of it on screen: a slot half scrolled under the app bar must
     * not cut a hole in the bar.
     */
    private fun updateSlots() {
        val container = rootContainer ?: return
        if (slots.isEmpty()) return
        val density = activity.resources.displayMetrics.density
        val origin = IntArray(2)
        container.getLocationInWindow(origin)
        val holes = ArrayList<Rect>()
        val gone = ArrayList<String>()

        for ((slotId, view) in slots) {
            val attached = view.isAttachedToWindow
            val seen = Rect()
            val visible = attached && view.isShown && view.width > 0 && view.height > 0 &&
                view.getGlobalVisibleRect(seen)
            val at = IntArray(2)
            if (attached) view.getLocationInWindow(at)
            val x = at[0] - origin[0]
            val y = at[1] - origin[1]

            val report = listOf<Any>(x, y, view.width, view.height, visible)
            if (slotReports[slotId] != report) {
                slotReports[slotId] = report
                sendEvent(
                    SLOT_RECT_EVENT,
                    mapOf(
                        "slotId" to slotId,
                        "x" to (x / density).toDouble(),
                        "y" to (y / density).toDouble(),
                        "width" to (view.width / density).toDouble(),
                        "height" to (view.height / density).toDouble(),
                        "visible" to visible,
                    ),
                )
            }

            if (!attached) {
                gone += slotId
            } else if (visible && !underModal(view, container)) {
                seen.offset(-origin[0], -origin[1])
                holes += seen
            }
        }
        for (slotId in gone) {
            slots.remove(slotId)
            slotReports.remove(slotId)
        }
        container.setHoles(holes)
    }

    /**
     * Whether a dialog or a sheet is drawn over [view].
     *
     * A hole goes through everything, the scrim included, so a slot under a
     * modal keeps its native cover: the Flutter widget goes dark with the rest
     * of the screen instead of shining through the dialog.
     */
    private fun underModal(view: View, container: View): Boolean {
        var child = view
        while (child !== container) {
            val parent = child.parent as? ViewGroup ?: return false
            for (i in parent.indexOfChild(child) + 1 until parent.childCount) {
                if (parent.getChildAt(i) is ModalLayerFrame) return true
            }
            child = parent
        }
        return false
    }

    /** Removes the container this renderer added to the activity. */
    fun dispose() {
        stopFrameProbe()
        val container = rootContainer ?: return
        container.viewTreeObserver.removeOnPreDrawListener(slotPreDraw)
        container.viewTreeObserver.removeOnScrollChangedListener(slotScrolled)
        activity.unregisterComponentCallbacks(configurationWatcher)
        activity.application.unregisterActivityLifecycleCallbacks(lifecycleWatcher)
        // Another library may have wrapped the window's callback since; then
        // this one stays in the chain, forwarding and no longer reporting.
        watchingKeys = false
        if (keyCallback != null && activity.window?.callback === keyCallback) {
            activity.window.callback = originalKeyCallback
        }
        keyCallback = null
        originalKeyCallback = null
        openPickers.values.forEach { it() }
        openPickers.clear()
        slots.clear()
        slotReports.clear()
        lastViewport = null
        (container.parent as? ViewGroup)?.removeView(container)
        rootContainer = null
        currentTree = null
        currentRoot = null
        snackbarTimers.values.forEach(handler::removeCallbacks)
        snackbarTimers.clear()
        // What the HTTP cache has only in memory goes to disk, so the next
        // launch finds the images this one fetched.
        HttpResponseCache.getInstalled()?.flush()
        lazyScroll.clear()
        lazyRanges.clear()
        lazyOffsets.clear()
        scrollOffsets.clear()
        scrollVersions.clear()
        sizeReports.clear()
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
            // From here on an event is this tree's: a patch can raise one
            // before it returns (a box given a size listener reports at once).
            treeBuild = (tree["build"] as? Number)?.toInt()

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
            // The direction is read off every tree, because an app changes
            // language while it runs. A change is a rebuild for the same
            // reason the appearance is: the views on screen were built for the
            // other direction, and a patch would keep them.
            if (applyDirection(root, next)) currentTree = null

            // Fast path: the tree kept its shape, so patch the changed leaves in
            // place and leave every other view - with the focus, caret, IME and
            // scroll it holds - untouched. This is what lets a field be typed
            // into and a list keep its position across a re-render. Any mismatch
            // returns false and falls through to the full rebuild, which is
            // always correct.
            val old = currentTree
            val oldRoot = currentRoot
            val typing = root.findFocus() is EditText
            if (old != null && oldRoot != null && tryPatch(oldRoot, old, next)) {
                currentTree = next
                closeOrphanedKeyboard(root, typing)
                syncPickers(next)
                syncStatusIcons(next)
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
            renderedScrolls.clear()
            renderedSizes.clear()
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
            syncPickers(next)
            syncStatusIcons(next)

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
            closeOrphanedKeyboard(root, typing)

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

    /**
     * Puts the keyboard away when the focus goes from a field that types to
     * something that does not - a dropdown, which takes the focus to open its
     * menu and has nothing to type into. The platform only closes a keyboard
     * it is told to, so it stayed up over the menu.
     */
    private fun closeKeyboardWithFocus(container: View) {
        container.viewTreeObserver.addOnGlobalFocusChangeListener { old, new ->
            if (old == null || new == null || !old.onCheckIsTextEditor() ||
                new.onCheckIsTextEditor()
            ) {
                return@addOnGlobalFocusChangeListener
            }
            val keyboard = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
                as? android.view.inputmethod.InputMethodManager
            keyboard?.hideSoftInputFromWindow(new.windowToken, 0)
        }
    }

    /**
     * Puts the keyboard away when the field it was typing into is gone.
     *
     * A dialog closed with its field still focused takes the field with it,
     * and the platform leaves the keyboard up over a screen with nothing to
     * type in. [typing] is whether a field had the focus before this render;
     * a rebuild that is about to give the focus back is left alone.
     */
    private fun closeOrphanedKeyboard(root: View, typing: Boolean) {
        if (!typing || restoringFocus || root.findFocus() is EditText) return
        val keyboard = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
            as? android.view.inputmethod.InputMethodManager
        keyboard?.hideSoftInputFromWindow(root.windowToken, 0)
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
    private fun tryPatch(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        // The colour in force inside the node changed - a card went from a
        // light fill to a dark one. Everything below that states no colour of
        // its own was painted in the old one, and a node whose own props did
        // not change is not painted again: the text stayed dark on the dark
        // card until something else rebuilt the screen. So this is a rebuild.
        val foreground = foregroundOf(newNode)
        if (foreground != foregroundOf(oldNode)) return false
        return withForeground(foreground) { patchNode(view, oldNode, newNode) }
    }

    /**
     * The colour text and icons take inside this node when they state none of
     * their own, or null if the node says nothing about it - see [renderOver].
     *
     * The render functions put the same colour in force around their children,
     * so a text patched inside a coloured card is repainted as it was drawn.
     */
    private fun foregroundOf(node: Map<*, *>): Int? = when (node["type"]) {
        "Card" -> parseColorOrNull(node["backgroundColor"])?.let(::textOn)
        "AnimatedContainer" -> parseColorOrNull(node["color"])?.let(::textOn)
        "Box" -> boxForeground(node)
        "AppBar", "NavigationBar" -> appBarForeground(node)
        else -> null
    }

    /**
     * What reads against a box's fill - where the fill is solid enough to be
     * what the text is actually seen against. A tint at a tenth of its alpha
     * is still the surface underneath, and says nothing.
     */
    private fun boxForeground(node: Map<*, *>): Int? =
        parseColorOrNull(node["color"])?.takeIf { Color.alpha(it) >= 128 }?.let(::textOn)

    /** An app bar's title and icon colour: the one stated, else one that reads on the bar. */
    private fun appBarForeground(node: Map<*, *>): Int =
        parseColorOrNull(node["foregroundColor"])
            ?: if (node["backgroundColor"] == null) color(null, themeOnPrimary)
            else textOn(color(node["backgroundColor"], themePrimary))

    private fun patchNode(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        if (oldNode["type"] != newNode["type"]) return false
        // A lazy list frames its windowed rows by index rather than stacking
        // them, so it has its own keyed reconcile.
        if (newNode["type"] == "LazyList") {
            return reconcileLazyList(view, oldNode, newNode).also { if (it) identify(view, newNode) }
        }
        if (!patchSelf(view, oldNode, newNode)) return false
        identify(view, newNode)
        // A slot's child is the fallback for renderers with no engine to show
        // through; there is no view of it here to walk.
        if (newNode["type"] == "FlutterSlot") return true

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
        // A jump the app asked for since the last render: the list is live, so
        // it goes there now rather than at its next build.
        val listId = newNode["id"] as? String ?: ""
        val version = (newNode["scrollVersion"] as? Number)?.toInt() ?: 0
        if (newNode["scrollOffset"] != null && scrollVersions["lazy:$listId"] != version) {
            scrollVersions["lazy:$listId"] = version
            val target = px(newNode["scrollOffset"])
            lazyScroll[listId] = target
            scroll.post { scroll.scrollTo(0, target) }
        }
        return true
    }

    /**
     * The [LinearLayout] whose direct children are [node]'s children one to one,
     * or null if this node is not a plain stacking list (its children then line
     * up by position instead).
     */
    private fun keyedListContainer(view: View, node: Map<*, *>): ViewGroup? =
        when (node["type"]) {
            "Column", "Row", "VStack", "HStack", "List", "ListView" ->
                // A spaced row carries extra spacer views between the children.
                if (isDistributed(node)) null
                else view as? LinearLayout
            // A stack's children are its views one to one, and a board whose
            // pieces come and go is exactly what should not be rebuilt.
            "Stack" -> view as? StackLayout
            else -> null
        }

    /** Whether [node] spreads its children with gap views between them. */
    private fun isDistributed(node: Map<*, *>): Boolean =
        (node["type"] == "Column" || node["type"] == "Row") &&
            when (node["mainAxisAlignment"]) {
                "spaceBetween", "spaceAround", "spaceEvenly" -> true
                else -> false
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
        container: ViewGroup,
        oldKids: List<Map<*, *>>,
        newKids: List<Map<*, *>>,
        parentNode: Map<*, *>,
    ) {
        val horizontal = parentNode["type"] == "Row" || parentNode["type"] == "HStack"
        val stretch = parentNode["type"] == "List" || parentNode["type"] == "ListView" ||
            ((parentNode["type"] == "Column" || parentNode["type"] == "Row") &&
                parentNode["crossAxisAlignment"] == "stretch")
        // A stack places its children itself; only a row or a column has
        // layout params to give them.
        val linear = container is LinearLayout
        fun build(node: Map<*, *>): View =
            if (linear) buildChild(node, horizontal, stretch)
            else renderWidget(node) ?: View(activity)
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
                    container.addView(build(node), i)
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

            val created = build(node)
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
        if (!linear) return
        val spacing = px(parentNode["spacing"])
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
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
        // `stretch` is across the stack: the width in a column, the height in
        // a row.
        val params = view.layoutParams as? LinearLayout.LayoutParams
            ?: LinearLayout.LayoutParams(
                if (!horizontal && stretch) match else wrap,
                if (horizontal && stretch) match else wrap,
            )
        when (node["type"]) {
            "Expanded" -> {
                if (horizontal) {
                    params.width = 0
                    params.height = if (stretch) match else wrap
                } else {
                    params.width = match
                    params.height = 0
                }
                // What is inside fills the share - or, with `fit: 'loose'`,
                // may be smaller than it along the stack's own axis. Only here
                // is that axis known, which is why it is not the Expanded's
                // own renderer that says so.
                val loose = node["fit"] == "loose"
                (view as? ViewGroup)?.getChildAt(0)?.layoutParams = FrameLayout.LayoutParams(
                    if (loose && horizontal) wrap else match,
                    if (loose && !horizontal) wrap else match,
                )
            }
            // A Wrap needs the full width of the column to have a line to wrap
            // within, even when the column only left-aligns its children.
            "Wrap" -> if (!horizontal) params.width = match
            // A Padding is as wide as what it pads, and a row or a text field
            // is as wide as it is allowed to be - so around one of those it
            // takes the column's width, as it does in Flutter. Left to hug,
            // it offered its row no width to fill, and the Expanded in that
            // row - a search field beside its button - got none of it.
            "Padding" -> if (!horizontal && fillsWidth(node)) params.width = match
            // A row inside a row has no width to fill - the outer one offers
            // as much as it likes - so it is as wide as its children.
            "Row" -> if (horizontal) params.width = wrap
            // The free-form nodes carry params of their own (they have to, to
            // say "expand"), so a stretching parent is applied on top of them.
            "Box", "Canvas", "Stack", "Scroll", "Positioned", "Dropdown" -> {
                // A menu button in a row is as wide as what it shows. It
                // arrives asking for the whole width, and a row hands its
                // unweighted children theirs first: the menu took the row,
                // and the Expanded beside it - a list tile's title - was left
                // none, wrapping a letter to a line.
                if (horizontal && node["type"] == "Dropdown") params.width = wrap
                if (stretch) {
                    if (horizontal && params.height == wrap) params.height = match
                    if (!horizontal && params.width == wrap) params.width = match
                }
            }
        }
        return params
    }

    /**
     * Whether [node] takes all the width it is offered: a row that was not
     * asked to hug, a text field, a wrap, or a padding around one of them.
     */
    private fun fillsWidth(node: Map<*, *>): Boolean = when (node["type"]) {
        "Row" -> node["mainAxisSize"] != "min"
        "TextField", "Wrap" -> true
        "Padding" -> firstChild(node)?.let { fillsWidth(it) } ?: false
        else -> false
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
                // Asked for by name: it is the second child with one bar
                // behind it and the third with two.
                val foreground = (view as? SwipeActionsLayout)?.foreground
                    ?: return null
                if (foreground.childCount != kids.size) return null
                (0 until foreground.childCount).map { foreground.getChildAt(it) }
            }
            "AppBar", "NavigationBar" -> appBarChildViews(view, node)
            "Image" -> {
                // The one child is the fallback, which is the first view in
                // the image's frame, in front of the picture or hidden by it.
                val frame = view as? FrameLayout ?: return null
                if (kids.isEmpty()) return emptyList()
                if (kids.size != 1 || frame.childCount != 2) return null
                listOf(frame.getChildAt(0))
            }
            "Scroll" -> {
                // The child is inside the scroller, which may itself be inside
                // the pull-to-refresh frame.
                val content = scrollerOf(view)?.getChildAt(0) ?: return null
                if (kids.size != 1) return null
                listOf(content)
            }
            "Column", "Row", "VStack", "HStack", "List", "ListView",
            "Center", "Padding", "Expanded", "Overlay", "AnimatedOpacity",
            "AnimatedContainer", "Box", "Canvas", "Stack", "Positioned",
            "BottomBar", "Wrap", "GridView" -> {
                // A spaced row carries gap views between its children; they
                // are a type of their own so the children can be told from
                // them and still be walked.
                val group = view as? ViewGroup ?: return null
                val views = (0 until group.childCount).map { group.getChildAt(it) }
                    .filter { it !is DistributeGap }
                if (views.size != kids.size) return null
                views
            }
            else -> if (kids.isEmpty()) emptyList() else null
        }
        // child-views:end
    }

    /**
     * An app bar's children are the title subtree, when it has one, and then
     * its actions; they sit in two holders inside the toolbar, among views
     * that are the toolbar's own.
     */
    private fun appBarChildViews(view: View, node: Map<*, *>): List<View>? {
        val bar = view as? MaterialToolbar ?: return null
        val kids = childNodes(node)
        if (kids.isEmpty()) return emptyList()
        var title: AppBarTitle? = null
        var actions: AppBarActions? = null
        for (i in 0 until bar.childCount) {
            when (val child = bar.getChildAt(i)) {
                is AppBarTitle -> title = child
                is AppBarActions -> actions = child
            }
        }
        val result = ArrayList<View>(kids.size)
        val hasTitle = node["hasTitleNode"] == true
        if (hasTitle) result += title?.getChildAt(0) ?: return null
        val actionCount = kids.size - if (hasTitle) 1 else 0
        if (actionCount > 0) {
            val row = actions ?: return null
            if (row.childCount != actionCount) return null
            for (i in 0 until row.childCount) result += row.getChildAt(i)
        }
        return result
    }

    /**
     * A Scaffold puts its children in different places - the app bar and body in
     * a column, the body wrapped in a scroll view, the floating action button in
     * an overlay - so map each child node back to the view that holds it.
     */
    private fun scaffoldChildViews(view: View, node: Map<*, *>): List<View>? {
        val scaffold = view as? ScaffoldLayout ?: return null
        val result = mutableListOf<View>()
        for (child in childNodes(node)) {
            result.add(
                when (child["type"]) {
                    "FloatingActionButton" -> scaffold.fabView
                    "AppBar", "NavigationBar" -> scaffold.barView
                    "BottomBar" -> scaffold.bottomView
                    else -> scaffold.bodyView
                } ?: return null
            )
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
            "Button", "MaterialButton" -> patchButton(view, oldNode, newNode)
            "IconButton" -> patchIconButton(view, newNode)
            "AppBar", "NavigationBar" -> patchAppBar(view, oldNode, newNode)
            "Scaffold", "NavigationStack" -> patchScaffold(view, oldNode, newNode)
            "Box" -> patchBox(view, newNode)
            "Canvas" -> patchCanvas(view, oldNode, newNode)
            "Stack" -> patchStack(view, newNode)
            "Positioned" -> patchPositioned(view, newNode)
            "Scroll" -> patchScroll(view, oldNode, newNode)
            "Icon" -> patchIcon(view, newNode)
            "Wrap" -> patchWrap(view, newNode)
            "Dropdown" -> patchDropdown(view, oldNode, newNode)
            "BottomNavigation" -> patchBottomNavigation(view, oldNode, newNode)
            "FlutterSlot" -> patchFlutterSlot(view, newNode)
            // A picker is a window of its own, opened once for its id; what
            // the tree says about it afterwards changes nothing on screen.
            "DatePicker", "TimePicker" -> true
            "TextField" -> patchTextField(view, oldNode, newNode)
            "Checkbox" -> patchControl(view, newNode, "checked")
            "Toggle" -> patchControl(view, newNode, "enabled")
            "Radio" -> patchControl(view, newNode, "selected")
            "Slider" -> patchSlider(view, newNode)
            "Loading" -> patchLoading(view, oldNode, newNode)
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
        // Everything a text node says is re-derived by the function that drew
        // it, so a prop added there cannot be forgotten here.
        styleText(label, node)
        return true
    }

    private fun patchButton(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val button = view as? MaterialButton ?: return false
        // Filling the width is the layout params' business, and those belong
        // to whichever parent the button is in.
        if (oldNode["expand"] != newNode["expand"]) return false
        styleButton(button, newNode)
        // Keep the tap handler pointed at the latest node (event id, data).
        bindTap(button, newNode)
        return true
    }

    private fun patchIconButton(view: View, node: Map<*, *>): Boolean {
        val button = view as? ImageButton ?: return false
        styleIconButton(button, node)
        bindTap(button, node)
        return true
    }

    private fun patchAppBar(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val bar = view as? MaterialToolbar ?: return false
        // The title subtree and the plain title are different views in the
        // bar, and a centred subtree is held differently from a leading one.
        if (oldNode["hasTitleNode"] != newNode["hasTitleNode"]) return false
        if (newNode["hasTitleNode"] == true &&
            oldNode["centerTitle"] != newNode["centerTitle"]
        ) {
            return false
        }
        // The actions were drawn in the old foreground and only repaint when
        // their own props change, so a bar that changes colour under them is
        // rebuilt.
        if (childNodes(newNode).isNotEmpty() &&
            appBarForeground(oldNode) != appBarForeground(newNode)
        ) {
            return false
        }
        styleAppBar(bar, newNode)
        return true
    }

    private fun patchScaffold(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val scaffold = view as? ScaffoldLayout ?: return false
        // Whether the body scrolls, and whether it is inset, decide what the
        // body is wrapped in; the colour is the only prop that is just paint.
        if (oldNode["bodyScrolls"] != newNode["bodyScrolls"]) return false
        if (oldNode["safeArea"] != newNode["safeArea"]) return false
        scaffold.setBackgroundColor(color(newNode["backgroundColor"], themeSurface))
        return true
    }

    /** Re-derives a checkbox/switch/radio's label, enabled and checked state. */
    private fun patchControl(view: View, node: Map<*, *>, checkedKey: String): Boolean {
        val button = view as? CompoundButton ?: return false
        button.text = node["label"] as? String ?: ""
        applyDisabled(button, node)
        tintControl(button, node)
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
            if (layout.error != error) {
                layout.error = error
                // An error taken away leaves the line it was written on, and
                // the fields below stay pushed down by it, until this says
                // there is no error to keep room for.
                if (error == null) layout.isErrorEnabled = false
            }
            val hintText = newNode["hint"] as? String ?: newNode["placeholder"] as? String
            layout.placeholderText = hintText?.ifEmpty { null }
        } else {
            // The helper is a sibling view too, like the label and the error.
            if (oldNode["helper"] != newNode["helper"]) return false
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
        // Which keyboard the field raises, and whether it takes typing at all,
        // are set as the editor is built - changing them under a focused field
        // restarts its input connection - so a field that changes kind is
        // rebuilt. So is one whose touch handling changes.
        for (key in listOf(
            "keyboardType", "textCapitalization", "readOnly", "tappable", "suffixTappable",
        )) {
            if (oldNode[key] != newNode[key]) return false
        }

        val field = findEditText(view) ?: return false
        field.isEnabled = newNode["enabled"] != false
        // Only when one of them changed: this runs on every keystroke of a
        // bound field, and the value is the one prop that changes then.
        if (listOf("helper", "prefixIcon", "suffixIcon", "maxLength", "textAlign")
                .any { oldNode[it] != newNode[it] }
        ) {
            styleField(newNode, layout, field)
        }
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

    /** Builds the view for [node], and tells accessibility which node it is. */
    private fun renderWidget(node: Map<*, *>): View? =
        drawWidget(node)?.also { identify(it, node) }

    /**
     * Exposes the node's `id` - a widget's `Key` - as the view's resource
     * name through an accessibility delegate: what uiautomator prints as
     * `resource-id`, and what a device test's `id` selector matches.
     *
     * The name is the id as written, with no `<package>:id/` in front. That is
     * what React Native does with a `testID` and Compose with
     * `testTagsAsResourceId`, and it is what the tools expect: agent-device
     * compares an `id="..."` selector with the whole string, so a prefixed
     * name could only be addressed by spelling the package out in every flow.
     *
     * Called on every build and every patch, so an id that arrives, changes or
     * goes on a view that is kept is followed. A text field's id goes on the
     * field itself rather than the layout around it, since the field is what a
     * test fills.
     */
    private fun identify(view: View, node: Map<*, *>) {
        val id = (node["id"] as? String)?.takeIf { it.isNotEmpty() }
        // The field is what a test fills and reads, not the layout around it.
        val target = when (node["type"]) {
            "TextField", "Dropdown" -> findEditText(view) ?: view
            else -> view
        }
        val access = NodeAccessibility.of(target)
        if (access.resourceName != id) {
            access.resourceName = id
            // A view somebody named is one a test or a screen reader may ask
            // for, so it has to be in the tree even if it is only a layout.
            if (id != null &&
                target.importantForAccessibility == View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
            ) {
                target.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            }
        }
        // What the node says it is, where the view's class would not: a text
        // that is a heading, a box that is an image, a drawing with a name.
        val role = node["semanticRole"] as? String
            ?: if (node["type"] == "Canvas" && node["semanticLabel"] != null) "image" else null
        access.heading = role == "heading"
        access.className = when (role) {
            "button" -> android.widget.Button::class.java.name
            "image" -> ImageView::class.java.name
            "progress" -> ProgressBar::class.java.name
            else -> null
        }
        // A button drawn from a box and switched off has no tap left to be
        // told from text by; the node says so.
        access.disabled = node["type"] == "Box" && node["disabled"] == true
        // On or off, for a box that is a toggle - a filter chip's tick is a
        // picture, and says nothing to a reader.
        access.selected = if (node["type"] == "Box") node["selected"] as? Boolean else null
        when (node["type"]) {
            "Icon" -> access.text = node["semanticLabel"] as? String ?: ""
            // "Loading", said by name: a bare ring is announced as nothing.
            "Loading" -> {
                val name = node["semanticLabel"] as? String
                if (view.contentDescription != name) view.contentDescription = name
            }
        }
    }

    // node-types:begin
    private fun drawWidget(node: Map<*, *>): View? = when (node["type"] as? String) {
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
        // Opened as windows of their own once the render is done (syncPickers);
        // what stands in the tree is only a place for the patch walk to find.
        "DatePicker", "TimePicker" -> renderPickerAnchor()

        // Free-form composition
        "Box" -> renderBox(node)
        "Stack" -> renderLayers(node)
        "Positioned" -> renderPositioned(node)
        "Scroll" -> renderScroll(node)
        "Icon" -> renderIcon(node)
        "Canvas" -> renderCanvas(node)
        "Dropdown" -> renderDropdown(node)

        // App chrome along the bottom edge
        "BottomBar" -> renderBottomBar(node)
        "BottomNavigation" -> renderBottomNavigation(node)

        "FlutterSlot" -> renderFlutterSlot(node)

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
     * A Scaffold's children are told apart by type: the `AppBar`, the
     * `BottomBar`, the `FloatingActionButton`, and whatever is none of those is
     * the body - the shape `UIBuilder.scaffold` builds.
     *
     * The bar, the body's area and the bottom bar stack in a column; the body
     * and the floating button share the area between the two bars, so the
     * button sits above the bottom bar without either knowing the other's
     * height.
     */
    private fun renderScaffold(node: Map<*, *>): View {
        val scaffold = ScaffoldLayout(activity).apply {
            layoutParams = matchParent()
            setBackgroundColor(color(node["backgroundColor"], themeSurface))
        }
        val scrolls = node["bodyScrolls"] != false
        val area = scaffold.bodyArea
        val fill = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )

        for (child in childNodes(node)) {
            when (child["type"] as? String) {
                "FloatingActionButton" -> scaffold.fabView = renderWidget(child)
                "AppBar", "NavigationBar" -> scaffold.barView = renderWidget(child)
                "BottomBar" -> scaffold.bottomView = renderWidget(child)
                else -> renderWidget(child)?.let { body ->
                    scaffold.bodyView = body
                    if (child["type"] == "LazyList" || !scrolls) {
                        // A lazy list scrolls itself and needs a bounded height
                        // to know which rows are visible. So does a body that
                        // lays itself out against the screen - an Expanded, a
                        // Scroll of its own, a Stack - which is what
                        // `bodyScrolls: false` says: it gets exactly the height
                        // left between the bars.
                        area.addView(body, fill)
                    } else {
                        // The body scrolls, so a screen taller than the window
                        // is reachable rather than clipped. A body that asked
                        // to fill - a column distributing its children - gets
                        // the viewport to fill; anything else keeps wrapping.
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
                        area.addView(scroll, fill)
                    }
                }
            }
        }

        scaffold.barView?.let {
            // The height the bar gave itself - an app bar's is its title row
            // plus the status bar it draws behind.
            scaffold.addView(it, linear(
                height = it.layoutParams?.height ?: ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        scaffold.addView(area, linear(height = 0, weight = 1f))
        scaffold.bottomView?.let {
            scaffold.addView(it, linear(height = ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        scaffold.fabView?.let { fab ->
            area.addView(fab, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                // The end margin, not the right one: the button is in the
                // bottom-left corner of a right-to-left screen.
                bottomMargin = dp(16)
                marginEnd = dp(16)
            })
        }

        // The app bar pads itself past the status icons, and the container
        // stops above the navigation bar (see avoidKeyboard), so what is left
        // for the scaffold to keep clear is the top when there is no bar to do
        // it, and the sides - a cutout, a navigation bar in landscape.
        // `safeArea: false` lets the body run under those.
        if (node["safeArea"] != false) {
            val hasBar = scaffold.barView != null
            onSystemBars(area) { bars ->
                area.setPadding(bars.left, if (hasBar) 0 else bars.top, bars.right, 0)
            }
        }
        return scaffold
    }

    private fun renderAppBar(node: Map<*, *>): View = MaterialToolbar(materialContext).apply {
        layoutParams = linear(height = ViewGroup.LayoutParams.WRAP_CONTENT)
        // The title, the colours, the leading button and the elevation - shared
        // with the patch, so the two cannot drift apart.
        styleAppBar(this, node)

        // The children are the title subtree, when there is one, and then the
        // actions. Both are drawn in the bar's foreground unless they say
        // otherwise, which is what makes an icon button legible on a primary
        // bar without the app naming a colour for it.
        val kids = childNodes(node)
        val hasTitle = node["hasTitleNode"] == true && kids.isNotEmpty()
        withForeground(appBarForeground(node)) {
            if (hasTitle) {
                val holder = AppBarTitle(activity)
                renderWidget(kids.first())?.let { holder.addView(it, wrapContent()) }
                addView(holder, Toolbar.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    if (node["centerTitle"] == true) Gravity.CENTER
                    else Gravity.START or Gravity.CENTER_VERTICAL,
                ))
            }
            val actions = if (hasTitle) kids.drop(1) else kids
            if (actions.isNotEmpty()) {
                // One row holding every action, rather than each as a toolbar
                // child: a toolbar lays its end-aligned children out from the
                // edge inwards, which would show the actions in reverse.
                val row = AppBarActions(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                for (action in actions) {
                    val view = renderWidget(action) ?: continue
                    if (action["type"] == "IconButton") {
                        // The touch target Material gives a toolbar action.
                        view.minimumWidth = dp(48)
                        view.minimumHeight = dp(48)
                    }
                    row.addView(view, LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ))
                }
                addView(row, Toolbar.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.END or Gravity.CENTER_VERTICAL,
                ))
            }
        }

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
        //
        // The row is the minimum height and the inset is added to the bar's
        // stated height, rather than both going into the minimum: a toolbar
        // centres its navigation button in the minimum height, measured from
        // the padding, so an inset counted there pushed the back arrow half
        // the status bar's height below the title.
        val titleRow = actionBarHeight()
        onSystemBars(this) { bars ->
            updatePadding(top = bars.top)
            minimumHeight = titleRow
            layoutParams = layoutParams.apply { height = titleRow + bars.top }
        }
    }

    /** Everything about an app bar that is not its children. */
    private fun styleAppBar(bar: MaterialToolbar, node: Map<*, *>) {
        // A title subtree stands where the title text would; the text is left
        // out rather than drawn underneath it.
        bar.title = if (node["hasTitleNode"] == true) null else node["title"] as? String ?: ""
        // The title is the screen's heading: what "next heading" lands on, and
        // what tells a reader which screen this is.
        for (i in 0 until bar.childCount) {
            val child = bar.getChildAt(i)
            if (child is TextView && child.text == bar.title) {
                ViewCompat.setAccessibilityHeading(child, true)
            }
        }
        bar.setBackgroundColor(color(node["backgroundColor"], themePrimary))
        // A title over a colour the app stated reads against that colour; over
        // the theme's own primary it stays the palette's onPrimary - unless the
        // app named the foreground itself.
        val foreground = appBarForeground(node)
        bar.setTitleTextColor(foreground)
        bar.isTitleCentered = node["centerTitle"] == true
        bar.elevation = pxf(node["elevation"]) ?: 0f

        val leading = node["leading"] as? String
        val glyph = when (leading) {
            "back" -> BACK_CODEPOINT to "arrow_back"
            "close" -> CLOSE_CODEPOINT to "close"
            "menu" -> MENU_CODEPOINT to "more_vert"
            else -> null
        }
        if (glyph == null) {
            bar.navigationIcon = null
            bar.setNavigationOnClickListener(null)
            return
        }
        bar.navigationIcon = iconGlyphDrawable(glyph.first, foreground)
            ?: androidx.core.content.ContextCompat.getDrawable(activity, icon(glyph.second))
                ?.mutate()?.apply { setTint(foreground) }
        // Back is a direction: in a right-to-left screen the way back is to
        // the right, so the arrow is drawn turned round. A cross and a menu
        // mean the same either way.
        bar.navigationIcon?.isAutoMirrored = leading == "back"
        // What a screen reader calls the button: the platform's own words for
        // the three things it can be.
        bar.navigationContentDescription = when (leading) {
            "back" -> "Navigate up"
            "close" -> "Close"
            else -> "Open navigation menu"
        }
        val eventId = node["leadingEventId"] as? String
        bar.setNavigationOnClickListener {
            if (eventId != null) sendEvent(eventId, emptyMap())
        }
    }

    // -------------------------------------------------------------------------
    // Layout
    // -------------------------------------------------------------------------

    private fun renderColumn(node: Map<*, *>): View {
        // Distributing the children needs height to distribute, so a column
        // that was asked to do it grows into its parent instead of wrapping.
        // `mainAxisSize` says so outright: 'max' fills without distributing
        // anything, 'min' hugs even when an alignment was asked for.
        val main = node["mainAxisAlignment"] as? String
        val fills = when (node["mainAxisSize"]) {
            "max" -> true
            "min" -> false
            else -> main != null
        }
        val column = ColumnLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = if (!fills) matchWidth() else ViewGroup.LayoutParams(
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
        // The three "space" alignments have no gravity: weighted gaps between
        // the children carry them, exactly as in a row.
        distribute(column, main)
        return column
    }

    private fun renderRow(node: Map<*, *>): View {
        val main = node["mainAxisAlignment"] as? String
        val cross = node["crossAxisAlignment"] as? String
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            // As wide as it is allowed, unless it was asked to hug. Linear
            // params, because a column keeps a child's own params only when
            // they are its kind - and without them a row in a column was as
            // wide as its children, with nothing for an alignment or an
            // Expanded inside it to work with.
            layoutParams = LinearLayout.LayoutParams(
                if (node["mainAxisSize"] == "min") ViewGroup.LayoutParams.WRAP_CONTENT
                else ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            gravity = when (main) {
                "center" -> Gravity.CENTER_HORIZONTAL
                "end" -> Gravity.END
                else -> Gravity.START
            } or when (cross) {
                "start" -> Gravity.TOP
                "end" -> Gravity.BOTTOM
                else -> Gravity.CENTER_VERTICAL
            }
        }
        addChildren(row, node, horizontal = true, stretch = cross == "stretch")
        // The "space" alignments have no gravity: gaps between the children
        // carry them.
        distribute(row, main)
        return row
    }

    /** A run of children that wraps onto the next line when it runs out of width. */
    private fun renderWrap(node: Map<*, *>): View {
        val flow = FlowLayout(activity)
        styleWrap(flow, node)
        for (child in childNodes(node)) {
            renderWidget(child)?.let { flow.addView(it, wrapContent()) }
        }
        return flow
    }

    private fun styleWrap(flow: FlowLayout, node: Map<*, *>) {
        flow.hSpacing = px(node["spacing"])
        flow.vSpacing = px(node["runSpacing"])
        flow.alignment = node["alignment"] as? String ?: "start"
        flow.crossAlignment = node["crossAxisAlignment"] as? String ?: "start"
        flow.requestLayout()
    }

    private fun patchWrap(view: View, node: Map<*, *>): Boolean {
        val flow = view as? FlowLayout ?: return false
        styleWrap(flow, node)
        return true
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
    private fun <T> renderOver(background: Any?, body: () -> T): T =
        withForeground(parseColorOrNull(background)?.let(::textOn), body)

    /**
     * Runs [body] with [foreground] as the colour text and icons take when
     * they state none; null leaves whatever is in force alone.
     */
    private fun <T> withForeground(foreground: Int?, body: () -> T): T {
        if (foreground == null) return body()
        val saved = textInForce
        textInForce = foreground
        try {
            return body()
        } finally {
            textInForce = saved
        }
    }

    // Built against the Material context, like the icon below: an AppCompat
    // view made from an activity whose theme is not an AppCompat one logs an
    // error each time, and a screen redrawn by a timer made hundreds a second.
    // Everything the theme would have decided, styleText states.
    private fun renderText(node: Map<*, *>): View = AppCompatTextView(materialContext).apply {
        layoutParams = wrapContent()
        styleText(this, node)
    }

    /**
     * Everything a `Text` node says, applied to its view - by the build and by
     * the patch alike.
     */
    private fun styleText(label: AppCompatTextView, node: Map<*, *>) {
        label.textSize = (node["fontSize"] as? Number)?.toFloat() ?: 14f
        label.setTextColor(
            if (node["color"] == null) textInForce ?: color(null, themeText)
            else color(node["color"], themeText)
        )

        val weight = (node["fontWeight"] as? Number)?.toInt() ?: 400
        val italic = node["italic"] == true
        val family = typefaceFor(node["fontFamily"] as? String)
        if (family == null && !italic) {
            // The common case, as it always was: the default face, bold from
            // 600 up.
            label.setTypeface(null, if (weight >= 600) Typeface.BOLD else Typeface.NORMAL)
        } else {
            label.typeface = weighted(family, weight, italic)
        }

        var flags = label.paintFlags and
            (Paint.STRIKE_THRU_TEXT_FLAG or Paint.UNDERLINE_TEXT_FLAG).inv()
        when (node["decoration"]) {
            "lineThrough" -> flags = flags or Paint.STRIKE_THRU_TEXT_FLAG
            "underline" -> flags = flags or Paint.UNDERLINE_TEXT_FLAG
        }
        label.paintFlags = flags

        // The tree gives letter spacing in logical pixels; a TextView takes it
        // in ems, which is that over the text size.
        val spacing = pxf(node["letterSpacing"])
        label.letterSpacing = if (spacing != null && label.textSize > 0f) {
            spacing / label.textSize
        } else {
            0f
        }
        // A multiple of the font size, as CSS and Flutter spell it - not of the
        // font's own line height, which is what a TextView's multiplier scales.
        val lineHeight = (node["lineHeight"] as? Number)?.toFloat()
        if (lineHeight != null && lineHeight > 0f) {
            TextViewCompat.setLineHeight(label, (lineHeight * label.textSize).roundToInt())
        } else {
            label.setLineSpacing(0f, 1f)
        }

        // The alignment shows where the text has more width than it needs: in
        // a stretching column, or once it wraps.
        // 'left' and 'right' are sides and stay put; 'start', 'end' and
        // saying nothing follow the screen's direction.
        label.gravity = Gravity.TOP or when (node["textAlign"]) {
            "center" -> Gravity.CENTER_HORIZONTAL
            "left" -> Gravity.LEFT
            "right" -> Gravity.RIGHT
            "end" -> Gravity.END
            else -> Gravity.START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            label.justificationMode = if (node["textAlign"] == "justify") {
                android.text.Layout.JUSTIFICATION_MODE_INTER_WORD
            } else {
                android.text.Layout.JUSTIFICATION_MODE_NONE
            }
        }

        val selectable = node["selectable"] == true
        if (label.isTextSelectable != selectable) label.setTextIsSelectable(selectable)

        val spans = (node["spans"] as? List<*>)?.filterIsInstance<Map<*, *>>()
        label.text = if (spans.isNullOrEmpty()) node["content"] as? String ?: ""
        else spannedText(spans)
        clampLines(label, node)
    }

    /**
     * A text node's `spans` as one string with a style over each run. What a
     * run does not say, it inherits from the view - which is the node.
     */
    private fun spannedText(spans: List<Map<*, *>>): CharSequence {
        val text = SpannableStringBuilder()
        for (span in spans) {
            val start = text.length
            text.append(span["text"]?.toString() ?: "")
            val end = text.length
            if (end == start) continue
            fun mark(what: Any) = text.setSpan(what, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

            parseColorOrNull(span["color"])?.let { mark(ForegroundColorSpan(it)) }
            (span["fontSize"] as? Number)?.toFloat()?.let { size ->
                // Scaled pixels, like the node's own font size.
                mark(AbsoluteSizeSpan(
                    TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_SP, size, activity.resources.displayMetrics
                    ).roundToInt()
                ))
            }
            val bold = (span["fontWeight"] as? Number)?.toInt()?.let { it >= 600 }
            val italic = span["italic"] == true
            when {
                bold == true && italic -> mark(StyleSpan(Typeface.BOLD_ITALIC))
                bold == true -> mark(StyleSpan(Typeface.BOLD))
                italic -> mark(StyleSpan(Typeface.ITALIC))
            }
            when (span["decoration"]) {
                "lineThrough" -> mark(StrikethroughSpan())
                "underline" -> mark(UnderlineSpan())
            }
        }
        return text
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
     * other source is a Flutter asset or, failing that, one of the app's
     * drawables (see [loadImage]). Until it arrives, and for good if it never
     * does, the image's place is taken by the node's child when it has one -
     * a fallback the app drew - and otherwise by the alt text. Either way the
     * alt text is the view's content description, so a broken image is still
     * announced.
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

        // The fallback is the first view in the container whether or not it is
        // ever seen, so the patch can find the child's view where the node
        // says it has one (see childViews).
        val fallback = imageFallback(node) ?: AppCompatTextView(activity).apply {
            text = alt
            setTextColor(color(null, themeTextSecondary))
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(fallback)

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

        loadImage(node["src"] as? String, into = image, hiding = fallback, limit = imageLimit(node))
        return container
    }

    /**
     * The view of an `Image` node's fallback child, or null when it has none.
     *
     * It keeps the size it asks for and sits in the middle of the image's
     * place, which is where the alt text it replaces would have been.
     */
    private fun imageFallback(node: Map<*, *>): View? {
        val child = firstChild(node) ?: return null
        val view = renderWidget(child) ?: return null
        val own = view.layoutParams
        view.layoutParams = FrameLayout.LayoutParams(
            own?.width ?: ViewGroup.LayoutParams.WRAP_CONTENT,
            own?.height ?: ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER,
        )
        return view
    }

    /**
     * The longest side, in pixels, an image needs to be decoded at: twice the
     * larger of the sizes the node states, and never more than twice the
     * screen. A 40dp avatar cut from a 2000-pixel photo is kept as an avatar.
     */
    private fun imageLimit(node: Map<*, *>): Int {
        val metrics = activity.resources.displayMetrics
        val screen = max(metrics.widthPixels, metrics.heightPixels) * 2
        val stated = max(
            (node["width"] as? Number)?.let { dp(it.toInt()) } ?: 0,
            (node["height"] as? Number)?.let { dp(it.toInt()) } ?: 0,
        )
        return if (stated > 0) min(stated * 2, screen) else screen
    }

    /**
     * Images already decoded, by source and the size they were decoded for.
     *
     * A rebuild makes a new ImageView for a picture that was on screen a
     * moment ago; without this it would show the alt text for the frames it
     * takes to read the file again - or, for a URL, to fetch it again. A
     * remote image is kept here like any other: what a URL answers can
     * change, but an app that redraws does not want its avatars to blink, and
     * the HTTP cache underneath is what decides how fresh a new fetch is.
     */
    private val imageCache = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    /**
     * The fetches and decodes under way, by cache key, with everyone waiting
     * on each. A list of forty rows showing the same logo asks for it once.
     * Only touched on the main thread.
     */
    private val imageWaiters = HashMap<String, MutableList<(Bitmap?) -> Unit>>()

    /**
     * A few threads for fetching and decoding, shared, rather than one per
     * image - and let go again once there has been nothing to load for a
     * while, so an idle app is not holding four threads for it.
     */
    private val imageLoaders: java.util.concurrent.ExecutorService by lazy {
        java.util.concurrent.ThreadPoolExecutor(
            4, 4, 30L, java.util.concurrent.TimeUnit.SECONDS,
            java.util.concurrent.LinkedBlockingQueue(),
        ).apply { allowCoreThreadTimeOut(true) }
    }

    /**
     * Gives remote images a cache on disk, once.
     *
     * The platform's own `HttpResponseCache` sits under every
     * `HttpURLConnection` in the process and honours what the server said
     * about freshness - `Cache-Control`, `ETag`, `Expires` - so an image that
     * is still good is read from disk and one that is stale is revalidated.
     * It is process-wide and there can be one: if the app installed its own,
     * that one is used and left alone. Called on a loader thread, since
     * opening it reads the disk.
     */
    private fun installHttpCache() {
        synchronized(imageCache) {
            if (httpCacheChecked) return
            httpCacheChecked = true
            try {
                if (HttpResponseCache.getInstalled() == null) {
                    HttpResponseCache.install(
                        java.io.File(activity.cacheDir, "dart_not_native_http"),
                        20L * 1024 * 1024,
                    )
                }
            } catch (e: Exception) {
                // No disk cache is slower, not broken: the fetch still works.
            }
        }
    }

    private var httpCacheChecked = false

    /**
     * Fills [into] from [src], hiding [hiding] once it arrives.
     *
     * A URL is fetched, a `data:` URI decoded, and anything else is a path the
     * platform resolves against its own assets: first a Flutter asset - the
     * `assets/photo.jpg` an app declares in its pubspec, which the build puts
     * in the APK under `flutter_assets/` - and failing that a drawable of the
     * same base name. All of it off the main thread, decoded no larger than
     * [limit] on its longest side; the view is filled back on the main thread,
     * and a failure simply leaves [hiding] - the fallback - showing.
     *
     * An image already in memory is shown before this returns, so a rebuild
     * goes straight from picture to picture with no fallback in between.
     */
    private fun loadImage(src: String?, into: ImageView, hiding: View, limit: Int) {
        if (src.isNullOrEmpty()) return
        fun show(bitmap: Bitmap) {
            into.setImageBitmap(bitmap)
            hiding.visibility = View.GONE
        }
        val key = "$limit $src"
        imageCache.get(key)?.let {
            show(it)
            return
        }

        val remote = src.startsWith("http://") || src.startsWith("https://")
        fun arrived(bitmap: Bitmap?) {
            if (bitmap != null) {
                show(bitmap)
            } else if (!remote) {
                // Not a Flutter asset: a drawable that ships with the app.
                val id = activity.resources.getIdentifier(
                    src.substringAfterLast('/').substringBeforeLast('.'),
                    "drawable",
                    activity.packageName,
                )
                if (id != 0) {
                    into.setImageResource(id)
                    hiding.visibility = View.GONE
                }
            }
        }
        // Somebody is already fetching this one: wait for theirs.
        imageWaiters[key]?.let {
            it += ::arrived
            return
        }
        imageWaiters[key] = mutableListOf(::arrived)

        imageLoaders.execute {
            val bitmap = try {
                when {
                    remote -> {
                        installHttpCache()
                        // Read once into memory: the decode below opens its
                        // source twice, and a URL should be fetched once.
                        val connection = java.net.URL(src).openConnection()
                            as java.net.HttpURLConnection
                        val bytes = try {
                            connection.connectTimeout = 10_000
                            connection.readTimeout = 10_000
                            connection.useCaches = true
                            connection.inputStream.use { it.readBytes() }
                        } finally {
                            connection.disconnect()
                        }
                        decodeSampled(limit) { bytes.inputStream() }
                    }
                    src.startsWith("data:") -> {
                        val bytes = Base64.decode(src.substringAfter(','), Base64.DEFAULT)
                        decodeSampled(limit) { bytes.inputStream() }
                    }
                    else -> decodeSampled(limit) { activity.assets.open(flutterAssetKey(src)) }
                }
            } catch (e: Exception) {
                null
            } catch (e: OutOfMemoryError) {
                null
            }
            activity.runOnUiThread {
                if (bitmap != null) imageCache.put(key, bitmap)
                imageWaiters.remove(key)?.forEach { it(bitmap) }
            }
        }
    }

    /**
     * Where the APK keeps the Flutter asset an app calls [path].
     *
     * The loader knows the directory the build used; the literal is what it
     * answers for every build there has been, for the case it cannot be asked.
     */
    private fun flutterAssetKey(path: String): String = try {
        FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
    } catch (e: Exception) {
        "flutter_assets/$path"
    }

    /**
     * Decodes what [open] yields at no more than about [limit] on its longest
     * side (see [imageLimit]): a camera photo shown in a card does not need
     * its twelve megapixels in memory. [open] is called twice - once for the
     * size, once for the pixels - because a stream cannot be read again.
     */
    private fun decodeSampled(limit: Int, open: () -> java.io.InputStream): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        open().use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= limit) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return open().use { BitmapFactory.decodeStream(it, null, options) }
    }

    private fun renderLoading(node: Map<*, *>): View {
        val tint = color(node["color"], themePrimary)
        val indeterminate = node["indeterminate"] == true
        val value = ((node["value"] as? Number)?.toFloat() ?: 0f) * 100

        return when (prop(node, "type")) {
            // Material's bar, in the node's colour over a faint track of it.
            // The platform's own horizontal ProgressBar takes its look from
            // the activity's theme, which need not be a Material one: it drew
            // a short grey hatched strip.
            "progress-linear" -> LinearProgressIndicator(materialContext).apply {
                isIndeterminate = indeterminate
                progress = value.toInt()
                setIndicatorColor(tint)
                trackColor = withAlpha(tint, 0.24f)
                // Linear params, so a column keeps the width: the bar has no
                // content to be as wide as.
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                )
            }
            "skeleton" -> View(activity).apply {
                background = GradientDrawable().apply {
                    setColor(color(null, themeDivider))
                    cornerRadius = dp(4).toFloat()
                }
                layoutParams = LinearLayout.LayoutParams(
                    // The width the node states; one that states none - or an
                    // infinite one, which is how "all of it" is spelled -
                    // fills what it is given.
                    (node["width"] as? Number)?.toDouble()
                        ?.takeIf { it.isFinite() && it > 0 }
                        ?.let { dp(it.toInt()) }
                        ?: ViewGroup.LayoutParams.MATCH_PARENT,
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

    /**
     * Moves a determinate bar to its new value. A bar that fills as a timer
     * runs is re-rendered many times a second, and rebuilding it each time
     * would restart the indicator's own animation; anything else that changed
     * - the kind of indicator, its colour, whether it has a value at all - is
     * a rebuild.
     */
    private fun patchLoading(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val bar = view as? ProgressBar ?: return false
        fun same(name: String) = oldNode[name] == newNode[name]
        if (prop(oldNode, "type") != prop(newNode, "type")) return false
        if (!same("indeterminate") || !same("color") || !same("size")) return false
        val value = ((newNode["value"] as? Number)?.toFloat() ?: 0f) * 100
        // A spinner with no value yet spins; one that has gained or lost its
        // value is a different indicator.
        val linear = prop(newNode, "type") == "progress-linear"
        val spins = newNode["indeterminate"] == true || (!linear && value <= 0f)
        if (bar.isIndeterminate != spins) return false
        if (!bar.isIndeterminate) bar.progress = value.toInt()
        return true
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
            radius = dp(12).toFloat()
            // Every variant draws the colour the app stated; only what it
            // does *besides* the fill - a border, a shadow - is the variant's.
            setCardBackgroundColor(color(node["backgroundColor"], themeSurfaceVariant))
            // Material 3's card style is the outlined one; only the variant
            // that asks has a border here.
            strokeWidth = 0
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
        // `expand` fills the width it is offered instead of hugging the label.
        layoutParams = if (node["expand"] == true) {
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        } else {
            wrapContent()
        }
        styleButton(this, node)
        bindTap(this, node)
    }

    /** A button's label, scale, colours and icon - for the build and the patch alike. */
    private fun styleButton(button: MaterialButton, node: Map<*, *>) = button.apply {
        // The label as the app wrote it: Material's button style capitalises
        // every letter, which is not what a sentence-case label asked for.
        isAllCaps = false
        // And without the wide tracking that style adds for its capitals.
        letterSpacing = 0f
        text = node["label"] as? String ?: "Button"
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
        // What each variant does with its colour: fill with it, outline in it,
        // tint with it, or only write in it.
        val (fill, onFill) = when (variant) {
            "secondary", "tertiary", "outlined" -> Color.TRANSPARENT to tint
            "tonal" -> withAlpha(tint, 0.16f) to tint
            else -> tint to
                if (node["color"] == null) color(null, themeOnPrimary) else textOn(tint)
        }
        val foreground = parseColorOrNull(node["foregroundColor"]) ?: onFill
        setBackgroundColor(fill)
        setTextColor(foreground)
        // Material's button style raises every button, pressed or not, and a
        // shadow has nothing to hide behind when the fill is see-through: a
        // text, outlined or tonal button showed a grey box around its label.
        if (Color.alpha(fill) < 255) {
            stateListAnimator = null
            elevation = 0f
        }
        strokeWidth = if (variant == "outlined") dp(1) else 0
        strokeColor = ColorStateList.valueOf(tint)

        // A Material Icons glyph before the label, in the label's colour.
        val glyph = (node["iconCodepoint"] as? Number)?.toInt()
            ?.let { iconGlyphDrawable(it, Color.WHITE, dp(18)) }
        icon = glyph
        if (glyph != null) {
            iconTint = ColorStateList.valueOf(foreground)
            iconGravity = MaterialButton.ICON_GRAVITY_TEXT_START
            iconPadding = dp(8)
            iconSize = dp(18)
        }
    }

    private fun renderIconButton(node: Map<*, *>): View = ImageButton(activity).apply {
        // No fill, and the platform's round ripple where it has one to give.
        val ripple = TypedValue()
        if (activity.theme.resolveAttribute(
                android.R.attr.selectableItemBackgroundBorderless, ripple, true)
        ) {
            setBackgroundResource(ripple.resourceId)
        } else {
            setBackgroundColor(Color.TRANSPARENT)
        }
        // The room Material keeps around the glyph: a 24dp icon is a 48dp
        // target, as it is in Flutter and (at 40) in the web renderer. Without
        // it the button was the glyph - too small to hit, and flush against
        // whatever was beside it.
        val around = dp(12)
        setPadding(around, around, around, around)
        layoutParams = wrapContent()
        styleIconButton(this, node)
        bindTap(this, node)
    }

    private fun styleIconButton(button: ImageButton, node: Map<*, *>) {
        // The colour the node names; else the one in force around it - an app
        // bar's foreground, the text colour over a coloured card; else a dark
        // glyph, since an icon button sits on the surface, not a fill.
        val tint = parseColorOrNull(node["color"])
            ?: textInForce
            ?: color(null, themeTextSecondary)
        setIcon(
            button,
            codepoint = (node["iconCodepoint"] as? Number)?.toInt(),
            name = node["icon"] as? String ?: "more_vert",
            colorInt = tint,
            size = px(node["size"], 24f),
        )
        val tooltip = node["tooltip"] as? String
        button.contentDescription = tooltip
        TooltipCompat.setTooltipText(button, tooltip)
        val enabled = node["disabled"] != true
        button.isEnabled = enabled
        // Material's own opacity for something that cannot be pressed.
        button.alpha = if (enabled) 1f else 0.38f
    }

    private fun renderFab(node: Map<*, *>): View {
        // The brand primary, matching the web FAB, unless the node overrides it.
        val fill = ColorStateList.valueOf(color(node["backgroundColor"], themePrimary))
        // White for contrast against the FAB's filled background, unless the
        // app said what goes on it.
        val onFill = color(node["foregroundColor"], themeOnPrimary)
        val label = node["label"] as? String
            ?: return FloatingActionButton(materialContext).apply {
                backgroundTintList = fill
                applyIcon(this, node, defaultName = "add", colorInt = onFill)
                contentDescription = node["tooltip"] as? String
                layoutParams = wrapContent()
                bindTap(this, node)
            }

        // With a label it is Material's extended button: the same colours and
        // the same glyph, in a pill with the text beside it.
        return ExtendedFloatingActionButton(materialContext).apply {
            // The label as the app wrote it; see styleButton.
            isAllCaps = false
            letterSpacing = 0f
            text = label
            setTextColor(onFill)
            backgroundTintList = fill
            icon = (node["iconCodepoint"] as? Number)?.toInt()
                ?.let { iconGlyphDrawable(it, Color.WHITE) }
                ?: androidx.core.content.ContextCompat.getDrawable(
                    activity, icon(node["icon"] as? String ?: "add"))
            iconTint = ColorStateList.valueOf(onFill)
            contentDescription = node["tooltip"] as? String
            layoutParams = wrapContent()
            bindTap(this, node)
        }
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
        // The filled box, by the overlay that names it - see dnn_styles.xml.
        // Material 3's theme would otherwise make every field an outlined one.
        val themed = ContextThemeWrapper(materialContext, R.style.DnnTextFieldFilled)
        val layout = TextInputLayout(themed).apply {
            hint = label
            isHintEnabled = true
            layoutParams = linear()
            boxBackgroundColor = fieldFill()
        }
        // The placeholder would sit under the label while the field is empty;
        // TextInputLayout shows it only once the label has floated up.
        val hintText = node["hint"] as? String ?: node["placeholder"] as? String
        if (!hintText.isNullOrEmpty()) layout.placeholderText = hintText
        // TextInputEditText is the editor the layout expects, and it is built
        // under the Material theme the layout itself uses.
        val field = configureEditText(node, TextInputEditText(layout.context), hint = null)
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
        styleField(node, layout, field)
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
        // The line under a focused field, and the caret in it, for the same
        // reason: left alone they are the Material theme's purple beside a
        // label in the app's primary.
        layout.boxStrokeColor = color(null, themePrimary)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            field.textCursorDrawable?.mutate()?.setTint(color(null, themePrimary))
        }
        // Material 3's layout colours the caret itself, over whatever the
        // editor was given.
        layout.cursorColor = ColorStateList.valueOf(color(null, themePrimary))
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
        styleField(node, null, field)

        val error = node["error"] as? String
        if (error != null) {
            column.addView(AppCompatTextView(activity).apply {
                text = error
                textSize = 12f
                setTextColor(color(null, themeError))
            }, matchWidth())
        } else {
            // The helper stands where the error would, and gives way to it.
            (node["helper"] as? String)?.let { helper ->
                column.addView(AppCompatTextView(activity).apply {
                    text = helper
                    textSize = 12f
                    setTextColor(color(null, themeTextSecondary))
                }, matchWidth())
            }
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
            inputType = fieldInputType(node, maxLines)
            if (node["readOnly"] == true) {
                // Shows its value and takes focus, but not typing: no key
                // listener to turn keys into text, no keyboard raised, no
                // caret promising either. After the input type, which installs
                // a key listener of its own.
                keyListener = null
                showSoftInputOnFocus = false
                isCursorVisible = false
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
            if (node["tappable"] == true || node["suffixTappable"] == true) {
                watchFieldTaps(field, eventId, node)
            }
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

    /** Which keyboard a field raises, and what it does to what is typed. */
    private fun fieldInputType(node: Map<*, *>, maxLines: Int): Int {
        val keyboard = node["keyboardType"] as? String
        val numeric = keyboard == "number" || keyboard == "decimal"
        if (node["obscureText"] == true) {
            return if (numeric) {
                InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            } else {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            }
        }
        val capitalization = when (node["textCapitalization"]) {
            "words" -> InputType.TYPE_TEXT_FLAG_CAP_WORDS
            "sentences" -> InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            "characters" -> InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            else -> 0
        }
        return when (keyboard) {
            "number" -> InputType.TYPE_CLASS_NUMBER
            "decimal" -> InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            "phone" -> InputType.TYPE_CLASS_PHONE
            "email" ->
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
            "url" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            else -> InputType.TYPE_CLASS_TEXT or capitalization or
                if (maxLines > 1 || keyboard == "multiline") {
                    InputType.TYPE_TEXT_FLAG_MULTI_LINE
                } else {
                    0
                }
        }
    }

    /**
     * What a field wears around its text: the helper line, the glyphs at either
     * end, the length it stops at, where the text sits.
     *
     * A floating-label field hands these to its [layout], which has a place
     * for each. A plain one ([layout] null) carries the glyphs as the editor's
     * own compound drawables; its helper is a sibling view, built with it.
     */
    private fun styleField(node: Map<*, *>, layout: TextInputLayout?, field: EditText) {
        val maxLength = (node["maxLength"] as? Number)?.toInt()?.takeIf { it > 0 }
        field.filters =
            if (maxLength != null) arrayOf(InputFilter.LengthFilter(maxLength)) else emptyArray()
        field.gravity = (field.gravity and Gravity.VERTICAL_GRAVITY_MASK) or
            when (node["textAlign"]) {
                "center" -> Gravity.CENTER_HORIZONTAL
                "left" -> Gravity.LEFT
                "right" -> Gravity.RIGHT
                "end" -> Gravity.END
                else -> Gravity.START
            }

        val tint = color(null, themeTextSecondary)
        val prefix = (node["prefixIcon"] as? Number)?.toInt()?.let { iconGlyphDrawable(it, tint) }
        val suffix = (node["suffixIcon"] as? Number)?.toInt()?.let { iconGlyphDrawable(it, tint) }
        if (layout == null) {
            field.setCompoundDrawablesRelativeWithIntrinsicBounds(prefix, null, suffix, null)
            field.compoundDrawablePadding = dp(8)
            return
        }

        layout.helperText = node["helper"] as? String
        // Flutter shows the count under a field with a limit; so does this.
        layout.isCounterEnabled = maxLength != null
        layout.counterMaxLength = maxLength ?: -1
        // The glyphs are already drawn in the palette's colour; the layout's
        // own tint is the Material theme's, which is not the app's.
        layout.setStartIconTintList(ColorStateList.valueOf(tint))
        layout.setEndIconTintList(ColorStateList.valueOf(tint))
        layout.startIconDrawable = prefix
        if (suffix == null) {
            if (layout.endIconMode != TextInputLayout.END_ICON_NONE) {
                layout.endIconMode = TextInputLayout.END_ICON_NONE
            }
            return
        }
        layout.endIconMode = TextInputLayout.END_ICON_CUSTOM
        layout.endIconDrawable = suffix
        val eventId = node["eventId"] as? String
        if (eventId != null && node["suffixTappable"] == true) {
            layout.setEndIconOnClickListener { sendEvent("${eventId}_suffix", emptyMap()) }
        } else {
            // No listener leaves the glyph a decoration: not clickable, not
            // announced as a button.
            layout.setEndIconOnClickListener(null)
        }
    }

    /**
     * Sends `<eventId>_tap` for a tap on the field and, where the suffix glyph
     * is one of the editor's own compound drawables, `<eventId>_suffix` for a
     * tap on that.
     *
     * A touch listener rather than a click listener: an EditText spends its
     * first tap on taking focus and only clicks on the second, and a field
     * that opens a picker has to open it on the first. The touch is watched,
     * never consumed, so focus and the caret behave as they always do.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun watchFieldTaps(field: EditText, eventId: String, node: Map<*, *>) {
        val slop = ViewConfiguration.get(activity).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        field.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                }
                MotionEvent.ACTION_UP ->
                    if (abs(event.x - downX) <= slop && abs(event.y - downY) <= slop) {
                        val rtl = field.layoutDirection == View.LAYOUT_DIRECTION_RTL
                        val onSuffix = field.compoundDrawablesRelative[2] != null &&
                            if (rtl) event.x <= field.compoundPaddingLeft
                            else event.x >= field.width - field.compoundPaddingRight
                        if (onSuffix && node["suffixTappable"] == true) {
                            sendEvent("${eventId}_suffix", emptyMap())
                        } else if (node["tappable"] == true) {
                            sendEvent("${eventId}_tap", emptyMap())
                        }
                    }
            }
            false
        }
    }

    /**
     * Makes a checkbox, radio button or switch say whether it can be changed.
     *
     * A disabled view takes no tap and no focus, and its tint already falls
     * back to the divider colour (see [controlTint]) - but the label beside it
     * was given a colour outright and would go on looking live, so it is
     * dimmed to the secondary text colour with it. Called by the build and by
     * the patch, so a control that becomes available again is the same view,
     * enabled.
     */
    /**
     * A check box's, a radio button's or a switch's colours: the app's own
     * where the node states them (`activeColor` and the rest), the brand's
     * where it does not. On the build and on every patch, so a control that
     * stops being coloured goes back.
     */
    private fun tintControl(button: CompoundButton, node: Map<*, *>) {
        val active = parseColorOrNull(node["activeColor"])
        when (button) {
            is MaterialCheckBox -> {
                button.buttonTintList = controlTint(
                    checked = active ?: color(null, themePrimary),
                    unchecked = color(null, themeTextSecondary),
                )
                // The tick, which reads against what the box is filled with.
                button.buttonIconTintList =
                    ColorStateList.valueOf(color(node["checkColor"], themeOnPrimary))
            }
            is SwitchCompat -> {
                // A switch the app coloured is that colour when it is on - its
                // track, solid - under the thumb the app chose, or a white one.
                // One it did not colour has the brand's thumb over the same
                // colour faded, which is how Material draws it.
                val thumb = parseColorOrNull(node["thumbColor"])
                button.thumbTintList = controlTint(
                    checked = thumb
                        ?: if (active != null) Color.WHITE else color(null, themePrimary),
                    unchecked = color(node["inactiveThumbColor"], themeSurfaceVariant),
                )
                button.trackTintList = controlTint(
                    checked = active ?: withAlpha(color(null, themePrimary), 0.5f),
                    unchecked = color(node["inactiveTrackColor"], themeDivider),
                )
            }
            else -> button.buttonTintList = controlTint(
                checked = active ?: color(null, themePrimary),
                unchecked = color(null, themeTextSecondary),
            )
        }
    }

    /** A slider's colours, the app's where it stated them. */
    private fun tintSlider(slider: Slider, node: Map<*, *>) {
        val active = color(node["activeColor"], themePrimary)
        slider.trackActiveTintList = ColorStateList.valueOf(active)
        slider.thumbTintList =
            ColorStateList.valueOf(parseColorOrNull(node["thumbColor"]) ?: active)
        // The rest of the track, the ticks and the halo are the Material
        // theme's own colours unless told - its purple, beside the app's
        // colour on the active half.
        val faint = withAlpha(active, 0.24f)
        slider.trackInactiveTintList =
            ColorStateList.valueOf(parseColorOrNull(node["inactiveColor"]) ?: faint)
        slider.tickInactiveTintList = ColorStateList.valueOf(active)
        slider.tickActiveTintList = ColorStateList.valueOf(color(null, themeOnPrimary))
        slider.haloTintList = ColorStateList.valueOf(faint)
    }

    private fun applyDisabled(button: CompoundButton, node: Map<*, *>) {
        // A control with no text of its own is named by the node - a list
        // tile's title, usually - or it is announced as "checkbox" and no more.
        val name = node["semanticLabel"] as? String
        if (button.contentDescription != name) button.contentDescription = name
        val disabled = node["disabled"] == true
        button.isEnabled = !disabled
        button.setTextColor(color(null, if (disabled) themeTextSecondary else themeText))
    }

    // Material's own box and dot, built against the Material context. The
    // platform's CheckBox and RadioButton take their drawable from the
    // activity's theme, which need not be a Material one - on a plain Flutter
    // activity they were the oversized squares of the first Android releases.
    private fun renderCheckbox(node: Map<*, *>): View = MaterialCheckBox(materialContext).apply {
        text = node["label"] as? String ?: ""
        setTextColor(color(null, themeText))
        tintControl(this, node)
        isChecked = node["checked"] == true
        applyDisabled(this, node)
        layoutParams = wrapContent()
        setOnCheckedChangeListener { _, checked ->
            if (!settingChecked) sendEvent(node, mapOf("checked" to checked))
        }
    }

    private fun renderRadio(node: Map<*, *>): View = MaterialRadioButton(materialContext).apply {
        text = node["label"] as? String ?: ""
        setTextColor(color(null, themeText))
        tintControl(this, node)
        isChecked = node["selected"] == true
        applyDisabled(this, node)
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
    private fun renderTabs(node: Map<*, *>): View = TabLayout(
        // The overlay is what keeps the labels in the case they were written.
        ContextThemeWrapper(materialContext, R.style.DnnTabs)
    ).apply {
        val labels = (node["tabs"] as? List<*>)?.map { it.toString() } ?: emptyList()
        tabMode = if (labels.size > 3) TabLayout.MODE_SCROLLABLE else TabLayout.MODE_FIXED
        tabGravity = TabLayout.GRAVITY_FILL
        setSelectedTabIndicatorColor(color(null, themePrimary))
        setTabTextColors(color(null, themeTextSecondary), color(null, themePrimary))
        // Over whatever it sits on - an app bar, the screen - rather than the
        // Material theme's own surface, which is a white box on a tinted one.
        setBackgroundColor(Color.TRANSPARENT)
        // Linear params, so a column keeps the width: a bar with fixed tabs
        // shares out the width it is given, and hugging gave it none to share.
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
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
        tintSlider(this, node)
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
        tintSlider(slider, node)
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
        tintControl(this, node)
        isChecked = node["enabled"] == true
        applyDisabled(this, node)
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

        // A position the app asked for, once per version: it replaces the one
        // remembered, and the restore below carries it out.
        if (node["scrollOffset"] != null) {
            val version = (node["scrollVersion"] as? Number)?.toInt() ?: 0
            if (scrollVersions["lazy:$id"] != version) {
                scrollVersions["lazy:$id"] = version
                lazyScroll[id] = px(node["scrollOffset"])
            }
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
                ViewCompat.setAccessibilityHeading(this, true)
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
            strokeWidth = 0
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
        // A type of its own, so the container can tell a slot is under a modal
        // and leave its hole closed (see underModal).
        return ModalLayerFrame(activity).apply {
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
            // Relative, so the wider inset stays on the message's side and the
            // narrower on the action's when the screen runs right to left.
            setPaddingRelative(dp(16), dp(6), dp(8), dp(6))
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
            setPaddingRelative(0, dp(8), dp(8), dp(8))
        }, linear(width = 0, weight = 1f))

        (node["actionLabel"] as? String)?.let { label ->
            bar.addView(MaterialButton(materialContext).apply {
                // As the app wrote it, and flat: see styleButton.
                isAllCaps = false
                letterSpacing = 0f
                text = label
                setBackgroundColor(Color.TRANSPARENT)
                stateListAnimator = null
                elevation = 0f
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
        // Above the scaffold's bottom bar and floating button, not over them.
        return SnackbarHost(activity).apply {
            layoutParams = matchParent()
            gap = dp(8)
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
    // Free-form composition: Box, Stack, Scroll, Icon, Canvas
    // -------------------------------------------------------------------------

    // These name the pieces components are made of. The renderer's part is
    // reading a node into values - pixels, colour ints, event ids - and the
    // views in NativeUIViews.kt do the measuring, painting and touch.

    /**
     * A box: size, space, paint and touch around at most one child.
     *
     * Patched rather than rebuilt whenever its props change ([patchBox]),
     * because a box that animates has to still be there to move.
     */
    private fun renderBox(node: Map<*, *>): View {
        val box = BoxLayout(activity, viewHost)
        configureBox(box, node, animate = false)
        // A filled box is a surface: text and icons inside it that name no
        // colour read against the fill, as they do in a coloured card.
        withForeground(boxForeground(node)) {
            firstChild(node)?.let { renderWidget(it) }?.let { box.addView(it) }
        }
        return box
    }

    private fun patchBox(view: View, node: Map<*, *>): Boolean {
        // A canvas is a box too, and has its own patch.
        if (view is CanvasView) return false
        val box = view as? BoxLayout ?: return false
        configureBox(box, node, animate = true)
        return true
    }

    /**
     * Applies a `Box` node's props - or a `Canvas` node's, which carries the
     * same frame - to its view. With [animate], a change to size, colour,
     * opacity or transform travels over the node's `animateMs`.
     */
    private fun configureBox(box: BoxLayout, node: Map<*, *>, animate: Boolean) {
        val style = boxStyle(node)
        val before = box.style
        val existing = box.layoutParams
        if (existing == null) {
            // Linear params, so a column keeps them: `expand` is the box
            // asking for the room, which only the params can say to a parent.
            box.layoutParams = LinearLayout.LayoutParams(
                if (style.expandWidth) ViewGroup.LayoutParams.MATCH_PARENT
                else ViewGroup.LayoutParams.WRAP_CONTENT,
                if (style.expandHeight) ViewGroup.LayoutParams.MATCH_PARENT
                else ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        } else if (before.expandWidth != style.expandWidth ||
            before.expandHeight != style.expandHeight
        ) {
            // Only the axis that changed: the other may hold what a parent
            // decided - a stretch, a weight - and is not this node's to undo.
            if (before.expandWidth != style.expandWidth) {
                existing.width = if (style.expandWidth) ViewGroup.LayoutParams.MATCH_PARENT
                else ViewGroup.LayoutParams.WRAP_CONTENT
            }
            if (before.expandHeight != style.expandHeight) {
                existing.height = if (style.expandHeight) ViewGroup.LayoutParams.MATCH_PARENT
                else ViewGroup.LayoutParams.WRAP_CONTENT
            }
            box.layoutParams = existing
        }

        val duration = if (animate) (node["animateMs"] as? Number)?.toLong() ?: 0L else 0L
        box.setStyle(style, duration, if (duration > 0) interpolator(node) else null)

        val events = boxEvents(node)
        if (events != box.events) box.events = events
        events.size?.let { renderedSizes += it }

        // Material's own strength for a pressed state, over whatever the box
        // is read against.
        box.setRipple(
            if (node["ripple"] == true) {
                withAlpha(textInForce ?: color(null, themeText), 0.12f)
            } else {
                null
            }
        )
        // The name, then the state said after it ("Upload, 40%").
        val label = listOfNotNull(
            node["semanticLabel"] as? String,
            node["semanticValue"] as? String,
        ).joinToString(", ").ifEmpty { null }
        if (box.contentDescription != label) box.contentDescription = label
        val live = if (node["liveRegion"] == true) View.ACCESSIBILITY_LIVE_REGION_POLITE
        else View.ACCESSIBILITY_LIVE_REGION_NONE
        if (box.accessibilityLiveRegion != live) box.accessibilityLiveRegion = live
        val hides = node["excludeSemantics"] == true
        if (box.hidesChildren != hides) box.hidesChildren = hides
        val tooltip = node["tooltip"] as? String
        box.tooltipLabel = tooltip
        if (tooltip != null || box.tag == TOOLTIP_TAG) {
            TooltipCompat.setTooltipText(box, tooltip)
            box.tag = if (tooltip != null) TOOLTIP_TAG else null
        }
    }

    /** A `Box` node's look, in the pixels and colour ints its view works in. */
    private fun boxStyle(node: Map<*, *>): BoxStyle {
        val expand = node["expand"] as? String
        val alignment = node["alignment"] as? List<*>
        val transform = node["transform"] as? Map<*, *>
        val radius = pxf(node["borderRadius"]) ?: 0f
        return BoxStyle(
            width = pxf(node["width"]),
            height = pxf(node["height"]),
            minWidth = pxf(node["minWidth"]),
            maxWidth = pxf(node["maxWidth"]),
            minHeight = pxf(node["minHeight"]),
            maxHeight = pxf(node["maxHeight"]),
            expandWidth = expand == "width" || expand == "both",
            expandHeight = expand == "height" || expand == "both",
            aspectRatio = (node["aspectRatio"] as? Number)?.toFloat(),
            padding = edges(node["padding"]),
            margin = edges(node["margin"]),
            alignX = alignment?.let { (it.getOrNull(0) as? Number)?.toFloat() ?: 0f },
            alignY = alignment?.let { (it.getOrNull(1) as? Number)?.toFloat() ?: 0f },
            color = parseColorOrNull(node["color"]),
            gradient = boxGradient(node["gradient"] as? Map<*, *>),
            // A colour with no width is still a request for a border; a hair
            // of one is what CSS and Flutter both draw.
            borderWidth = pxf(node["borderWidth"])
                ?: if (node["borderColor"] != null) pxf(1) ?: 1f else 0f,
            borderColor = color(node["borderColor"], themeDivider),
            radii = (node["borderRadii"] as? List<*>)?.takeIf { it.size == 4 }
                ?.map { pxf(it) ?: 0f }
                ?: listOf(radius, radius, radius, radius),
            circle = node["shape"] == "circle",
            shadow = (node["shadow"] as? Map<*, *>)?.let {
                BoxShadow(
                    // A quarter-opaque black, the shadow a designer means when
                    // they name no colour.
                    color = parseColorOrNull(it["color"]) ?: 0x40000000,
                    blur = pxf(it["blur"]) ?: 0f,
                    dx = pxf(it["dx"]) ?: 0f,
                    dy = pxf(it["dy"]) ?: 0f,
                )
            },
            clip = node["clip"] == true,
            opacity = (node["opacity"] as? Number)?.toFloat() ?: 1f,
            rotation = Math.toDegrees(
                (transform?.get("rotate") as? Number)?.toDouble() ?: 0.0
            ).toFloat(),
            scale = (transform?.get("scale") as? Number)?.toFloat() ?: 1f,
            dx = pxf(transform?.get("dx")) ?: 0f,
            dy = pxf(transform?.get("dy")) ?: 0f,
        )
    }

    private fun boxGradient(spec: Map<*, *>?): BoxGradient? {
        if (spec == null) return null
        val colors = (spec["colors"] as? List<*>)?.mapNotNull { parseColorOrNull(it) }
            ?: return null
        if (colors.size < 2) return null
        val begin = spec["begin"] as? List<*>
        val end = spec["end"] as? List<*>
        val radial = spec["type"] == "radial"
        fun at(point: List<*>?, index: Int) = (point?.getOrNull(index) as? Number)?.toFloat()
        return BoxGradient(
            radial = radial,
            colors = colors,
            stops = (spec["stops"] as? List<*>)?.map { (it as? Number)?.toFloat() ?: 0f },
            // Left to right when linear, from the middle when radial - where
            // Flutter starts each when it is not told.
            beginX = at(begin, 0) ?: if (radial) 0f else -1f,
            beginY = at(begin, 1) ?: 0f,
            endX = at(end, 0),
            endY = at(end, 1),
        )
    }

    private fun boxEvents(node: Map<*, *>) = BoxEvents(
        tap = node["tapEventId"] as? String,
        doubleTap = node["doubleTapEventId"] as? String,
        longPress = node["longPressEventId"] as? String,
        pan = node["panEventId"] as? String,
        drop = node["dropEventId"] as? String,
        size = node["sizeEventId"] as? String,
        dragData = node["dragData"] as? String,
        ignorePointer = node["ignorePointer"] == true,
    )

    /**
     * A surface drawn by a list of commands, inside a box's frame.
     *
     * The view is never rebuilt for a new picture: [patchCanvas] compiles the
     * new commands and invalidates the view that is already there, which is
     * what lets a game send a frame a tick.
     */
    private fun renderCanvas(node: Map<*, *>): View {
        val canvas = CanvasView(activity, viewHost)
        configureBox(canvas, node, animate = false)
        canvas.setOps(canvasOps(node))
        firstChild(node)?.let { renderWidget(it) }?.let { canvas.addView(it) }
        return canvas
    }

    /** The node's commands compiled against its paints - once per render, not per draw. */
    private fun canvasOps(node: Map<*, *>): List<CanvasOp> = compileCanvas(
        commands = node["commands"] as? List<*> ?: emptyList<Any?>(),
        paints = node["paints"] as? List<*> ?: emptyList<Any?>(),
        defaultTextColor = textInForce ?: color(null, themeText),
        typefaceFor = ::typefaceFor,
    )

    private fun patchCanvas(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val canvas = view as? CanvasView ?: return false
        // The frame is touched only when the frame changed. Every tick of a
        // game arrives here with new commands and nothing else.
        fun frame(node: Map<*, *>) = (node["props"] as? Map<*, *>)
            ?.filterKeys { it != "commands" && it != "paints" } ?: emptyMap<Any?, Any?>()
        if (!mapEqual(frame(oldNode), frame(newNode))) {
            configureBox(canvas, newNode, animate = true)
        }
        canvas.setOps(canvasOps(newNode))
        return true
    }

    /**
     * Children drawn over one another, first at the back. (`renderStack` is
     * the VStack and HStack of the iOS vocabulary; this is Flutter's Stack.)
     */
    private fun renderLayers(node: Map<*, *>): View {
        val stack = StackLayout(activity)
        styleStack(stack, node)
        stack.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        for (child in childNodes(node)) {
            renderWidget(child)?.let { stack.addView(it) }
        }
        return stack
    }

    private fun styleStack(stack: StackLayout, node: Map<*, *>) {
        val alignment = node["alignment"] as? List<*>
        // An alignment the tree states is a place, and stays where it is said
        // to be; one it leaves out is Flutter's top-start, which follows the
        // screen's direction - so that is left for the layout to resolve.
        stack.alignX = (alignment?.getOrNull(0) as? Number)?.toFloat()
        stack.alignY = (alignment?.getOrNull(1) as? Number)?.toFloat() ?: -1f
        stack.expandFit = node["fit"] == "expand"
        stack.clips = node["clip"] != false
        stack.requestLayout()
    }

    private fun patchStack(view: View, node: Map<*, *>): Boolean {
        val stack = view as? StackLayout ?: return false
        styleStack(stack, node)
        return true
    }

    /** A child pinned to the edges of the stack it is in; a plain frame anywhere else. */
    private fun renderPositioned(node: Map<*, *>): View {
        val frame = PositionedFrame(activity)
        stylePositioned(frame, node)
        firstChild(node)?.let { renderWidget(it) }?.let {
            frame.addView(it, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        return frame
    }

    private fun stylePositioned(frame: PositionedFrame, node: Map<*, *>) {
        fun edge(name: String) = if (node[name] == null) null else px(node[name])
        frame.edgeLeft = edge("left")
        frame.edgeTop = edge("top")
        frame.edgeRight = edge("right")
        frame.edgeBottom = edge("bottom")
        frame.fixedWidth = edge("width")
        frame.fixedHeight = edge("height")
        frame.requestLayout()
    }

    private fun patchPositioned(view: View, node: Map<*, *>): Boolean {
        val frame = view as? PositionedFrame ?: return false
        stylePositioned(frame, node)
        return true
    }

    /**
     * Scrolls its child along one axis.
     *
     * It takes the room it is given on that axis; `shrinkWrap` makes it as long
     * as its child instead, where there is room for that. Its position survives
     * a re-render because the view does ([patchScroll]), and survives a rebuild
     * - for a scroll with an `id` - because the offset is kept by that id and
     * put back at the first layout.
     */
    private fun renderScroll(node: Map<*, *>): View {
        val horizontal = node["axis"] == "horizontal"
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
        val scroller: ViewGroup =
            if (horizontal) HorizontalScroller(activity) else VerticalScroller(activity)
        val memory = scrollMemoryOf(scroller)
        // Padding scrolls with the content rather than cropping it: the last
        // row clears the bottom edge, and nothing is cut off on the way there.
        scroller.clipToPadding = false
        styleScroll(scroller, node)
        firstChild(node)?.let { renderWidget(it) }?.let {
            scroller.addView(
                it,
                FrameLayout.LayoutParams(
                    if (horizontal) wrap else match,
                    if (horizontal) match else wrap,
                ),
            )
        }

        val id = node["id"] as? String
        if (id != null && memory != null) {
            renderedScrolls += id
            memory.pending = scrollOffsets[id]
            memory.onOffset = { scrollOffsets[id] = it }
        }
        if (memory != null) applyScrollRequest(memory, node, id, live = false)

        val along = if (node["shrinkWrap"] == true) wrap else match
        val params = LinearLayout.LayoutParams(
            if (horizontal) along else match,
            if (horizontal) wrap else along,
        )
        val refresh = node["refreshEventId"] as? String
        if (refresh == null || scroller !is VerticalScroller) {
            scroller.layoutParams = params
            return scroller
        }

        // Pull-to-refresh is a vertical gesture; the platform has none for a
        // sideways list.
        return RefreshFrame(activity, scroller).apply {
            layoutParams = params
            eventId = refresh
            shown = node["refreshing"] == true
            setColorSchemeColors(color(null, themePrimary))
            setProgressBackgroundColorSchemeColor(color(null, themeSurfaceVariant))
            setOnRefreshListener {
                eventId?.let { sendEvent(it, emptyMap()) }
                // The pull starts the spinner; the tree decides whether it
                // stays. The app gets a moment to answer `refreshing: true`,
                // and a pull it does not answer does not spin forever.
                postDelayed({ settle() }, 600)
            }
        }
    }

    private fun styleScroll(scroller: ViewGroup, node: Map<*, *>) {
        val padding = edges(node["padding"])
        scroller.setPadding(padding[0], padding[1], padding[2], padding[3])
        val memory = scrollMemoryOf(scroller) ?: return
        memory.reverse = node["reverse"] == true
        // Set on every patch: the id is a prop like any other, and names a
        // different callback from one build to the next.
        val scrolled = node["scrollEventId"] as? String
        val density = activity.resources.displayMetrics.density
        memory.onReport = if (scrolled == null) null else { offset, range, viewport ->
            sendEvent(scrolled, mapOf(
                "offset" to offset / density,
                "maxExtent" to range / density,
                "viewport" to viewport / density,
            ))
        }
    }

    /**
     * Carries out a `scrollOffset` once per `scrollVersion`.
     *
     * [key] is the scroller's id, under which the version it last obeyed is
     * remembered - so a rebuild, which draws the same tree again, does not
     * throw the reader back to where the app once sent them. [live] is a
     * scroller already on screen, which goes now; a new one goes at its first
     * layout.
     */
    private fun applyScrollRequest(
        memory: ScrollMemory,
        node: Map<*, *>,
        key: String?,
        live: Boolean,
    ) {
        if (node["scrollOffset"] == null) return
        val version = (node["scrollVersion"] as? Number)?.toInt() ?: 0
        if (key != null) {
            if (scrollVersions[key] == version) return
            scrollVersions[key] = version
        }
        val target = px(node["scrollOffset"])
        if (live) memory.jumpTo(target) else memory.pending = target
    }

    private fun patchScroll(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        // The axis, whether it hugs, and whether it is wrapped for the refresh
        // gesture are each a different view or different params.
        if (oldNode["axis"] != newNode["axis"]) return false
        if (oldNode["shrinkWrap"] != newNode["shrinkWrap"]) return false
        if ((oldNode["refreshEventId"] == null) != (newNode["refreshEventId"] == null)) {
            return false
        }
        val scroller = scrollerOf(view) ?: return false
        styleScroll(scroller, newNode)
        (view as? RefreshFrame)?.let {
            it.eventId = newNode["refreshEventId"] as? String
            it.shown = newNode["refreshing"] == true
        }
        val memory = scrollMemoryOf(view) ?: return true
        val id = newNode["id"] as? String
        // Without an id there is nowhere to remember the version, so the two
        // trees are compared instead.
        if (id != null || oldNode["scrollOffset"] == null ||
            oldNode["scrollVersion"] != newNode["scrollVersion"]
        ) {
            applyScrollRequest(memory, newNode, id, live = true)
        }
        return true
    }

    /**
     * One glyph of an icon font - Material Icons unless the node names
     * another the app bundles.
     *
     * A text view rather than a bitmap: the glyph is then drawn at whatever
     * size is asked, in a colour that can change in place.
     */
    private fun renderIcon(node: Map<*, *>): View = AppCompatTextView(materialContext).apply {
        includeFontPadding = false
        gravity = Gravity.START or Gravity.CENTER_VERTICAL
        styleIcon(this, node)
    }

    private fun styleIcon(label: AppCompatTextView, node: Map<*, *>) {
        val size = (node["size"] as? Number)?.toFloat() ?: 24f
        label.typeface = typefaceFor(node["fontFamily"] as? String) ?: iconFont
        // Density pixels, not scaled ones: an icon is a shape, and does not
        // grow with the reader's font size.
        label.setTextSize(TypedValue.COMPLEX_UNIT_DIP, size)
        label.text = (node["codepoint"] as? Number)?.toInt()
            ?.let { String(Character.toChars(it)) } ?: ""
        // The colour the node names, else the one in force around it - an app
        // bar's foreground, the text over a filled box - else the theme's.
        label.setTextColor(
            parseColorOrNull(node["color"]) ?: textInForce ?: color(null, themeText)
        )
        val name = node["semanticLabel"] as? String
        label.contentDescription = name
        // An icon nobody named is decoration, and a screen reader that spoke
        // its codepoint would be reading out a private-use character.
        label.importantForAccessibility =
            if (name == null) View.IMPORTANT_FOR_ACCESSIBILITY_NO
            else View.IMPORTANT_FOR_ACCESSIBILITY_YES
        // The em square, whatever the glyph's own metrics say.
        val side = px(size)
        label.width = side
        label.height = side
        val params = label.layoutParams
        if (params == null) {
            label.layoutParams = LinearLayout.LayoutParams(side, side)
        } else if (params.width >= 0 && params.height >= 0 && params.width != side) {
            // Params that still hold a size are this function's own, from the
            // build; a parent's wrap or fill is left as the parent set it.
            params.width = side
            params.height = side
            label.layoutParams = params
        }
    }

    private fun patchIcon(view: View, node: Map<*, *>): Boolean {
        val label = view as? AppCompatTextView ?: return false
        styleIcon(label, node)
        return true
    }

    // -------------------------------------------------------------------------
    // Choosing: Dropdown, DatePicker, TimePicker
    // -------------------------------------------------------------------------

    /**
     * One of a list, chosen from Material's exposed dropdown menu: a text
     * field that cannot be typed in, with the choices in a menu under it.
     *
     * The layout is built against one of the two overlays in
     * `res/values/dnn_styles.xml`, because the menu's whole look comes from the
     * style its constructor reads - see the comment there.
     */
    private fun renderDropdown(node: Map<*, *>): View {
        val themed = ContextThemeWrapper(
            materialContext,
            if (node["outlined"] != false) R.style.DnnDropdownOutlined
            else R.style.DnnDropdownFilled,
        )
        val layout = TextInputLayout(themed).apply {
            layoutParams = linear()
            if (node["outlined"] == false) boxBackgroundColor = fieldFill()
        }
        // Built against the layout's own context, which carries the overlay
        // that styles the editor as a menu anchor.
        val field = MaterialAutoCompleteTextView(layout.context).apply {
            // Not a keyboard field: a tap opens the menu and nothing else.
            inputType = InputType.TYPE_NULL
        }
        layout.addView(field, linear())
        styleDropdown(layout, field, node, items = true)
        // The node the listener answers for is whichever was last drawn here.
        layout.tag = node
        field.setOnItemClickListener { _, _, position, _ ->
            (layout.tag as? Map<*, *>)?.let { sendEvent(it, mapOf("index" to position)) }
        }
        return layout
    }

    /**
     * The fill of a filled field or dropdown: a wash of the text colour over
     * the surface. The Material theme's own is a grey tinted with a purple no
     * app chose.
     */
    private fun fieldFill(): Int = ColorUtils.compositeColors(
        // Made opaque here, over the palette's surface: the layout lays a
        // see-through fill over the Material theme's surface instead.
        withAlpha(color(null, themeText), 0.08f),
        color(null, themeSurface),
    )

    private fun styleDropdown(
        layout: TextInputLayout,
        field: MaterialAutoCompleteTextView,
        node: Map<*, *>,
        items: Boolean,
    ) {
        val label = node["label"] as? String
        val hint = node["hint"] as? String
        // With a label the hint is what shows once the label has floated up;
        // without one the hint is all there is to say what the field is.
        layout.hint = label ?: hint
        layout.placeholderText = if (label != null) hint else null
        val error = node["error"] as? String
        if (layout.error != error) {
            layout.error = error
            // See patchTextField: no error, no line kept for one.
            if (error == null) layout.isErrorEnabled = false
        }
        // The app's primary on the focused outline and label, not the
        // Material theme's purple.
        layout.boxStrokeColor = color(null, themePrimary)
        layout.hintTextColor = ColorStateList.valueOf(color(null, themePrimary))
        // And on the arrow, which the layout marks activated while the menu's
        // field has the focus.
        layout.setEndIconTintList(ColorStateList(
            arrayOf(intArrayOf(android.R.attr.state_activated), intArrayOf()),
            intArrayOf(color(null, themePrimary), color(null, themeTextSecondary)),
        ))
        // The menu itself: the palette's surface, and a wash of the primary
        // behind the choice that is selected.
        field.setDropDownBackgroundTint(color(null, themeSurfaceVariant))
        field.simpleItemSelectedColor = withAlpha(color(null, themePrimary), 0.12f)
        val enabled = node["enabled"] != false
        layout.isEnabled = enabled
        field.isEnabled = enabled

        val choices = (node["items"] as? List<*>)?.map { it.toString() } ?: emptyList()
        if (items) field.setSimpleItems(choices.toTypedArray())
        val selected = (node["selectedIndex"] as? Number)?.toInt()
        val text = selected?.let { choices.getOrNull(it) } ?: ""
        // `false`: showing the selection is not the user filtering the list.
        if (field.text?.toString() != text) field.setText(text, false)
    }

    private fun patchDropdown(view: View, oldNode: Map<*, *>, newNode: Map<*, *>): Boolean {
        val layout = view as? TextInputLayout ?: return false
        val field = layout.editText as? MaterialAutoCompleteTextView ?: return false
        // Outlined or filled is the constructor's style; see renderDropdown.
        if (oldNode["outlined"] != newNode["outlined"]) return false
        styleDropdown(
            layout, field, newNode,
            items = !valueEqual(oldNode["items"], newNode["items"]),
        )
        layout.tag = newNode
        return true
    }

    /**
     * What a picker node leaves in the view tree: nothing to see, and
     * something for the overlay to hold in its place so the children still
     * line up with the nodes.
     */
    private fun renderPickerAnchor(): View =
        View(activity).apply { visibility = View.GONE }

    /**
     * Opens the pickers the tree has gained and closes the ones it has lost.
     *
     * A picker is an overlay like a dialog - in the tree while it is open -
     * but it is the platform's own window, not a view in the container, so it
     * cannot be "rendered" on every pass: it is shown once, when a node with
     * its `id` first appears, and closed when no node carries that id any
     * more. Run after every render, whichever path the render took.
     */
    private fun syncPickers(tree: Map<*, *>) {
        val wanted = LinkedHashMap<String, Map<*, *>>()
        collectPickers(tree, wanted)
        if (wanted.isEmpty() && openPickers.isEmpty()) return
        for (id in openPickers.keys - wanted.keys) openPickers.remove(id)?.invoke()
        for ((id, node) in wanted) {
            if (id in openPickers) continue
            openPickers[id] =
                if (node["type"] == "DatePicker") showDatePicker(node, id)
                else showTimePicker(node, id)
        }
    }

    /**
     * Draws the clock and the status icons in the shade that reads over what
     * the screen puts behind them: its app bar, or its own background when it
     * has no bar.
     *
     * The window is edge-to-edge, so those icons sit on the app's own paint,
     * and the platform keeps whatever shade the activity's theme chose - dark
     * icons on a dark primary bar. Flutter's AppBar is what would have said
     * otherwise, and here it is not the one drawing. Run after every render,
     * because a patch can change the colour as readily as a rebuild.
     */
    private fun syncStatusIcons(tree: Map<*, *>) {
        val scaffold = topScaffold(tree) ?: return
        val bar = childNodes(scaffold).firstOrNull {
            it["type"] == "AppBar" || it["type"] == "NavigationBar"
        }
        val behind = if (bar != null) color(bar["backgroundColor"], themePrimary)
        else color(scaffold["backgroundColor"], themeSurface)
        val light = relativeLuminance(behind) > 0.179
        // Asked of the window each time rather than remembered: the Flutter
        // engine underneath sets the same flag when its own first frame is
        // drawn, after the first render here.
        val window = activity.window
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (controller.isAppearanceLightStatusBars != light) {
            controller.isAppearanceLightStatusBars = light
        }
    }

    /**
     * The scaffold drawn last, and so on top - a pushed page over the one
     * under it - without going into a scaffold for the ones nested in it.
     */
    private fun topScaffold(node: Map<*, *>): Map<*, *>? {
        if (node["type"] == "Scaffold") return node
        var found: Map<*, *>? = null
        for (child in childNodes(node)) topScaffold(child)?.let { found = it }
        return found
    }

    private fun collectPickers(node: Map<*, *>, into: MutableMap<String, Map<*, *>>) {
        if (node["type"] == "DatePicker" || node["type"] == "TimePicker") {
            into[node["id"] as? String ?: node["eventId"] as? String ?: return] = node
            return
        }
        for (child in childNodes(node)) collectPickers(child, into)
    }

    /**
     * The activity as a fragment host, if Material's pickers can run in it.
     *
     * They are dialog fragments, so they need a FragmentActivity; and they
     * read their look from an attribute only a Material theme defines,
     * throwing when it is missing - inside a fragment transaction, where it
     * cannot be caught. A Flutter app's activity theme is usually not a
     * Material one, so this asks first, and the platform's own dialogs stand
     * in when the answer is no.
     */
    private fun materialPickerHost(themeAttribute: Int): FragmentActivity? {
        val host = activity as? FragmentActivity ?: return null
        if (host.supportFragmentManager.isStateSaved) return null
        val defined = activity.theme.resolveAttribute(themeAttribute, TypedValue(), true)
        return if (defined) host else null
    }

    /** Closes a picker fragment, now or as soon as its transaction has run. */
    private fun closer(picker: DialogFragment): () -> Unit = {
        if (picker.isAdded) {
            picker.dismissAllowingStateLoss()
        } else {
            handler.post { if (picker.isAdded) picker.dismissAllowingStateLoss() }
        }
    }

    /** `yyyy-mm-dd` as year, month (1-12) and day, or today when it is not one. */
    private fun dateParts(value: Any?): Triple<Int, Int, Int> {
        val parts = (value as? String)?.split('-')?.mapNotNull { it.toIntOrNull() }
        if (parts != null && parts.size == 3) return Triple(parts[0], parts[1], parts[2])
        val today = Calendar.getInstance()
        return Triple(
            today.get(Calendar.YEAR),
            today.get(Calendar.MONTH) + 1,
            today.get(Calendar.DAY_OF_MONTH),
        )
    }

    /** Midnight at the start of a date, in [zone]. */
    private fun dateMillis(date: Triple<Int, Int, Int>, zone: TimeZone): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(date.first, date.second - 1, date.third)
        }.timeInMillis

    private fun isoDate(year: Int, month: Int, day: Int): String =
        String.format(Locale.US, "%04d-%02d-%02d", year, month, day)

    /** Shows the date picker for [node], answering how to close it. */
    private fun showDatePicker(node: Map<*, *>, id: String): () -> Unit {
        val eventId = node["eventId"] as? String
        val dismiss = node["dismissEventId"] as? String
        val initial = dateParts(node["initial"])
        val first = dateParts(node["first"])
        val last = dateParts(node["last"])
        fun dismissed() {
            if (dismiss != null) sendEvent(dismiss, emptyMap())
        }

        val host = materialPickerHost(com.google.android.material.R.attr.materialCalendarTheme)
        if (host != null) {
            // Material's calendar counts days in UTC.
            val utc = TimeZone.getTimeZone("UTC")
            val start = dateMillis(first, utc)
            val end = dateMillis(last, utc)
            val picker = MaterialDatePicker.Builder.datePicker()
                .setSelection(dateMillis(initial, utc).coerceIn(start, maxOf(start, end)))
                .setCalendarConstraints(
                    CalendarConstraints.Builder()
                        .setStart(start)
                        .setEnd(maxOf(start, end))
                        .setValidator(
                            CompositeDateValidator.allOf(
                                listOf(
                                    DateValidatorPointForward.from(start),
                                    // `before` includes the day it is given.
                                    DateValidatorPointBackward.before(maxOf(start, end)),
                                )
                            )
                        )
                        .build()
                )
                .apply {
                    (node["title"] as? String)?.let { setTitleText(it) }
                    (node["confirmLabel"] as? String)?.let { setPositiveButtonText(it) }
                    (node["cancelLabel"] as? String)?.let { setNegativeButtonText(it) }
                }
                .build()
            picker.addOnPositiveButtonClickListener { millis ->
                val chosen = Calendar.getInstance(utc).apply { timeInMillis = millis }
                if (eventId != null) {
                    sendEvent(
                        eventId,
                        mapOf(
                            "value" to isoDate(
                                chosen.get(Calendar.YEAR),
                                chosen.get(Calendar.MONTH) + 1,
                                chosen.get(Calendar.DAY_OF_MONTH),
                            )
                        ),
                    )
                }
            }
            // Cancel, and back or a tap outside. Closing it from here - the
            // node having left the tree - is neither, and says nothing.
            picker.addOnNegativeButtonClickListener { dismissed() }
            picker.addOnCancelListener { dismissed() }
            picker.show(host.supportFragmentManager, "dnn:$id")
            return closer(picker)
        }

        // The platform's own dialog, under the renderer's Material theme. Its
        // calendar counts days in the device's time zone.
        val local = TimeZone.getDefault()
        val dialog = DatePickerDialog(
            materialContext,
            { _, year, month, day ->
                if (eventId != null) {
                    sendEvent(eventId, mapOf("value" to isoDate(year, month + 1, day)))
                }
            },
            initial.first, initial.second - 1, initial.third,
        )
        val start = dateMillis(first, local)
        dialog.datePicker.minDate = start
        dialog.datePicker.maxDate = maxOf(start, dateMillis(last, local))
        labelDialog(dialog, node, dialog)
        // The Cancel button cancels the dialog, so this hears it as well as
        // back and a tap outside.
        dialog.setOnCancelListener { dismissed() }
        dialog.show()
        return { if (dialog.isShowing) dialog.dismiss() }
    }

    /** Shows the time picker for [node], answering how to close it. */
    private fun showTimePicker(node: Map<*, *>, id: String): () -> Unit {
        val eventId = node["eventId"] as? String
        val dismiss = node["dismissEventId"] as? String
        val hour = ((node["hour"] as? Number)?.toInt() ?: 0).coerceIn(0, 23)
        val minute = ((node["minute"] as? Number)?.toInt() ?: 0).coerceIn(0, 59)
        // Absent follows the device's own setting.
        val use24Hour = node["use24Hour"] as? Boolean ?: DateFormat.is24HourFormat(activity)
        fun picked(hour: Int, minute: Int) {
            if (eventId != null) sendEvent(eventId, mapOf("hour" to hour, "minute" to minute))
        }
        fun dismissed() {
            if (dismiss != null) sendEvent(dismiss, emptyMap())
        }

        val host = materialPickerHost(com.google.android.material.R.attr.materialTimePickerTheme)
        if (host != null) {
            val picker = MaterialTimePicker.Builder()
                .setTimeFormat(if (use24Hour) TimeFormat.CLOCK_24H else TimeFormat.CLOCK_12H)
                .setHour(hour)
                .setMinute(minute)
                .apply {
                    (node["title"] as? String)?.let { setTitleText(it) }
                    (node["confirmLabel"] as? String)?.let { setPositiveButtonText(it) }
                    (node["cancelLabel"] as? String)?.let { setNegativeButtonText(it) }
                }
                .build()
            picker.addOnPositiveButtonClickListener { picked(picker.hour, picker.minute) }
            picker.addOnNegativeButtonClickListener { dismissed() }
            picker.addOnCancelListener { dismissed() }
            picker.show(host.supportFragmentManager, "dnn:$id")
            return closer(picker)
        }

        val dialog = TimePickerDialog(
            materialContext,
            { _, pickedHour, pickedMinute -> picked(pickedHour, pickedMinute) },
            hour, minute, use24Hour,
        )
        labelDialog(dialog, node, dialog)
        dialog.setOnCancelListener { dismissed() }
        dialog.show()
        return { if (dialog.isShowing) dialog.dismiss() }
    }

    /**
     * Gives a platform picker dialog the title and button labels the node
     * names. [listener] is the dialog itself: both platform pickers handle
     * their own buttons, and a relabelled button has to keep doing so.
     */
    private fun labelDialog(
        dialog: android.app.AlertDialog,
        node: Map<*, *>,
        listener: DialogInterface.OnClickListener,
    ) {
        (node["title"] as? String)?.let { dialog.setTitle(it) }
        (node["confirmLabel"] as? String)?.let {
            dialog.setButton(DialogInterface.BUTTON_POSITIVE, it, listener)
        }
        (node["cancelLabel"] as? String)?.let {
            dialog.setButton(DialogInterface.BUTTON_NEGATIVE, it, listener)
        }
    }

    // -------------------------------------------------------------------------
    // App chrome along the bottom edge, and the Flutter slot
    // -------------------------------------------------------------------------

    /**
     * What a scaffold pins along its bottom edge. The scaffold finds it by
     * type and places it; the system's own inset under it is already cleared
     * by the container (see avoidKeyboard), so this is only the holder.
     */
    private fun renderBottomBar(node: Map<*, *>): View = FrameLayout(activity).apply {
        layoutParams = matchWidth()
        firstChild(node)?.let { child ->
            renderWidget(child)?.let { addView(it, matchWidth()) }
        }
    }

    /**
     * The destinations of an app, one selected: Material's bottom navigation,
     * or its navigation rail down the leading edge when the node asks.
     *
     * The selection is the app's, as with the tabs: a tap reports the index,
     * and the next tree says which destination is selected.
     */
    private fun renderBottomNavigation(node: Map<*, *>): View {
        val rail = node["rail"] == true
        val bar: NavigationBarView =
            if (rail) NavigationRailView(materialContext) else BottomNavigationView(materialContext)
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
        bar.layoutParams =
            if (rail) LinearLayout.LayoutParams(wrap, match) else LinearLayout.LayoutParams(match, wrap)
        bar.setBackgroundColor(color(null, themeSurfaceVariant))
        bar.labelVisibilityMode = NavigationBarView.LABEL_VISIBILITY_LABELED
        // The app's palette rather than the Material theme's: the selected
        // destination in the primary, the rest in the secondary text colour.
        val tint = ColorStateList(
            arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
            intArrayOf(color(null, themePrimary), color(null, themeTextSecondary)),
        )
        // A label as wide as it is written - no tracking, and the selected
        // one no bolder than the rest - so four destinations' worth of
        // "Active Reminders" is not cut short. Before the colours, which a
        // text appearance would otherwise replace.
        bar.itemTextAppearanceInactive = R.style.DnnNavigationLabel
        bar.itemTextAppearanceActive = R.style.DnnNavigationLabel
        bar.setItemTextAppearanceActiveBoldEnabled(false)
        bar.itemIconTintList = tint
        bar.itemTextColor = tint
        // The pill behind the selected destination, likewise: a quiet tint of
        // the primary where the theme has its own secondary container.
        bar.itemActiveIndicatorColor =
            ColorStateList.valueOf(withAlpha(color(null, themePrimary), 0.16f))
        // Both views pad themselves past the system bars when left to. The
        // container has already stopped above the navigation bar, so that
        // would leave the gap twice; this listener replaces theirs.
        ViewCompat.setOnApplyWindowInsetsListener(bar) { _, insets -> insets }

        fillNavigation(bar, node)
        bar.tag = node
        bar.setOnItemSelectedListener { item ->
            // A selection the renderer itself made is not a tap.
            if (!settingChecked) {
                (bar.tag as? Map<*, *>)?.let {
                    sendEvent(it, mapOf("index" to item.itemId - 1))
                }
            }
            true
        }
        if (bar !is NavigationRailView) return bar
        // A rail is as tall as its destinations and does not shrink them, so
        // seven of them are taller than a phone held sideways and the last
        // were cut off. It scrolls where it does not fit, and fills the
        // height - its colour with it - where it does.
        return RailScroller(activity, bar).apply {
            layoutParams = LinearLayout.LayoutParams(wrap, match)
            setBackgroundColor(color(null, themeSurfaceVariant))
        }
    }

    /** Rebuilds the bar's menu from the node's items, and selects the one it names. */
    private fun fillNavigation(bar: NavigationBarView, node: Map<*, *>) {
        val items = (node["items"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
        bar.menu.clear()
        // Material refuses more destinations than it has room for - five along
        // the bottom, seven down a rail - by throwing; the rest are left out.
        for ((index, item) in items.take(bar.maxItemCount).withIndex()) {
            // Ids from one: zero is the menu's "no id".
            bar.menu.add(Menu.NONE, index + 1, index, item["label"]?.toString() ?: "")
                .icon = navigationIcon(item)
        }
        selectNavigation(bar, node)
    }

    /**
     * A destination's glyph, and the one it shows while selected when the item
     * names a second. White, because the bar tints it.
     */
    private fun navigationIcon(item: Map<*, *>): Drawable? {
        val normal = (item["icon"] as? Number)?.toInt()
            ?.let { iconGlyphDrawable(it, Color.WHITE) } ?: return null
        val selected = (item["selectedIcon"] as? Number)?.toInt()
            ?.let { iconGlyphDrawable(it, Color.WHITE) } ?: return normal
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_checked), selected)
            addState(intArrayOf(), normal)
        }
    }

    private fun selectNavigation(bar: NavigationBarView, node: Map<*, *>) {
        if (bar.menu.size() == 0) return
        val index = ((node["selectedIndex"] as? Number)?.toInt() ?: 0)
            .coerceIn(0, bar.menu.size() - 1)
        if (bar.selectedItemId == index + 1) return
        settingChecked = true
        bar.selectedItemId = index + 1
        settingChecked = false
    }

    private fun patchBottomNavigation(
        view: View,
        oldNode: Map<*, *>,
        newNode: Map<*, *>,
    ): Boolean {
        val bar = (view as? RailScroller)?.rail ?: view as? NavigationBarView ?: return false
        // A rail and a bar are different views.
        if (oldNode["rail"] != newNode["rail"]) return false
        bar.tag = newNode
        if (valueEqual(oldNode["items"], newNode["items"])) selectNavigation(bar, newNode)
        else fillNavigation(bar, newNode)
        return true
    }

    /**
     * A region the Flutter engine paints, inside a screen the platform draws.
     *
     * The view is an empty placeholder of the node's size. What makes it a
     * slot is the container: it leaves a hole where the placeholder is - in
     * what it draws and in what it takes touches for - and reports the
     * rectangle to Dart, which paints the Flutter widget there (see
     * [updateSlots] and SlotHostLayout). The node's child is the fallback for
     * renderers with no engine underneath, and is not drawn here.
     */
    private fun renderFlutterSlot(node: Map<*, *>): View {
        val slotId = node["slotId"] as? String ?: ""
        val view = FlutterSlotView(activity, slotId)
        styleFlutterSlot(view, node)
        view.layoutParams = LinearLayout.LayoutParams(
            if (node["width"] == null) ViewGroup.LayoutParams.MATCH_PARENT
            else ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        // The newest view for an id is the slot; one it replaces is detached
        // by the time anything looks.
        slots[slotId] = view
        return view
    }

    private fun styleFlutterSlot(view: FlutterSlotView, node: Map<*, *>) {
        view.slotWidth = if (node["width"] == null) null else px(node["width"])
        view.slotHeight = px(node["height"])
        view.requestLayout()
    }

    private fun patchFlutterSlot(view: View, node: Map<*, *>): Boolean {
        val slot = view as? FlutterSlotView ?: return false
        // A different slot is a different widget underneath; let it be built
        // and registered afresh.
        if (slot.slotId != node["slotId"]) return false
        styleFlutterSlot(slot, node)
        return true
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
            // `build` names the tree the views are showing. An id allocated by
            // order means something else after a rebuild that allocated a
            // different number before it, and Dart may have built several
            // times since this tree was sent.
            mapOf("eventId" to eventId, "data" to data, "build" to treeBuild),
        )
    }

    /** The number Dart gave the tree being shown; null if it gave none. */
    private var treeBuild: Int? = null

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
        val spacing = px(node["spacing"])
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

    /**
     * Spreads [stack]'s children along its axis with weighted gaps, for the
     * alignments gravity has no word for.
     *
     *  - `spaceBetween`: a gap between each pair, none at the ends.
     *  - `spaceEvenly`: the same gap everywhere, the ends included.
     *  - `spaceAround`: half a gap at each end, which is each child having the
     *    same space on both its sides.
     */
    private fun distribute(stack: LinearLayout, alignment: String?) {
        val (edge, between) = when (alignment) {
            "spaceBetween" -> 0f to 1f
            "spaceEvenly" -> 1f to 1f
            "spaceAround" -> 1f to 2f
            else -> return
        }
        // An Expanded or a Spacer among the children takes all the room there
        // is, so there is none to spread - as in Flutter. Weighted gaps beside
        // it would each take a share of what is its: a page label between two
        // buttons was cut to a third of the row.
        for (i in 0 until stack.childCount) {
            val params = stack.getChildAt(i).layoutParams as? LinearLayout.LayoutParams
            if (params != null && params.weight > 0f) return
        }
        fun gap(weight: Float) = DistributeGap(activity).apply {
            layoutParams = LinearLayout.LayoutParams(0, 0, weight)
        }
        var index = 1
        while (index < stack.childCount) {
            stack.addView(gap(between), index)
            index += 2
        }
        if (edge > 0f && stack.childCount > 0) {
            stack.addView(gap(edge), 0)
            stack.addView(gap(edge))
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
    private fun setIcon(
        view: ImageView,
        codepoint: Int?,
        name: String,
        colorInt: Int,
        size: Int = dp(24),
    ) {
        val glyph = codepoint?.let { iconGlyphDrawable(it, colorInt, size) }
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

    /**
     * Draws a Material Icons [codepoint] into a drawable [size] pixels square -
     * 24dp unless told otherwise - in [colorInt].
     */
    private fun iconGlyphDrawable(codepoint: Int, colorInt: Int, size: Int = dp(24)): Drawable? {
        val typeface = iconFont ?: return null
        if (size <= 0) return null
        // Codepoint, size and colour packed into one key: 20 bits, 12 and 32.
        val key = (codepoint.toLong() shl 44) or
            ((size.toLong() and 0xfffL) shl 32) or
            (colorInt.toLong() and 0xffffffffL)
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
     * A list row that slides its child towards its start to reveal trailing
     * action buttons: a partial drag snaps open so a button can be tapped, a
     * full drag fires the first action. It intercepts only mostly-horizontal
     * drags, so a tap reaches the child (e.g. the row's own buttons) and a
     * vertical drag still scrolls.
     *
     * The offsets are counted towards the *end* of the row - negative uncovers
     * the trailing actions - and the bars are placed at the start and the end,
     * so in a right-to-left screen Delete is on the left and is reached by
     * dragging right, as it is on iOS. The finger and `translationX` are in
     * screen coordinates and are turned by [sign] to match.
     */
    private inner class SwipeActionsLayout(node: Map<*, *>) : FrameLayout(activity) {
        /** The layer the row itself is in, over the one or two bars of actions. */
        val foreground: FrameLayout
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

        /** 1, or -1 when the row reads right to left. */
        private val sign: Float
            get() = if (layoutDirection == View.LAYOUT_DIRECTION_RTL) -1f else 1f

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
                        // Every row has a "Delete": the row's own id tells
                        // one from the next, as `<row id>.<bar>-<n>`.
                        (node["id"] as? String)?.takeIf { it.isNotEmpty() }?.let { row ->
                            NodeAccessibility.of(this).resourceName =
                                "$row.${if (key == "actions") "action" else "leading"}-${into.size - 1}"
                        }
                    })
                }
                addView(bar, FrameLayout.LayoutParams(
                    actionWidthPx * max(1, into.size),
                    ViewGroup.LayoutParams.MATCH_PARENT, gravity))
            }

            // Start and end, so the bars change sides with the screen; the
            // drag below is turned by `sign` so that it still uncovers the bar
            // on the side it opens.
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
                    baseTranslation = foreground.translationX * sign
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
                // Taken, or nothing after it is delivered. A row whose child
                // does nothing with a touch - a plain list tile - handed the
                // finger straight to this view, which declined it: the drag
                // that followed never arrived, and the row could only be
                // swiped by starting on the action button hidden under it.
                // A scroller above still takes a vertical drag for itself.
                MotionEvent.ACTION_DOWN -> return true
                MotionEvent.ACTION_MOVE -> {
                    if (!dragging) {
                        // Not through a child, so `onInterceptTouchEvent`
                        // was not asked: the same test, made here.
                        val dx = ev.x - downX
                        val dy = ev.y - downY
                        if (kotlin.math.abs(dx) <= slop ||
                            kotlin.math.abs(dx) <= kotlin.math.abs(dy)) {
                            return true
                        }
                        dragging = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                    }
                    foreground.translationX = (baseTranslation + (ev.x - downX) * sign)
                        .coerceIn(openOffset * 1.8f, openLeadingOffset * 1.8f) * sign
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    parent?.requestDisallowInterceptTouchEvent(false)
                    // A touch that never became a drag leaves the row as it is.
                    if (!dragging) return true
                    val next = foreground.translationX * sign
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
            foreground.animate().translationX(value * sign).setDuration(200).start()
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

    /**
     * [value] as a colour - `#rrggbb` or `#aarrggbb`, the two forms the
     * protocol writes - or [fallback] when it is absent or not a colour.
     */
    private fun color(value: Any?, fallback: String): Int =
        parseColorOrNull(value) ?: Color.parseColor(fallback)

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
     * A prop in logical pixels as device pixels, rounded - for the props that
     * arrive as doubles and may well be fractions, which [dp] would truncate
     * twice over.
     */
    private fun px(value: Any?, fallback: Float = 0f): Int =
        (((value as? Number)?.toFloat() ?: fallback) *
            activity.resources.displayMetrics.density).roundToInt()

    /** As [px], unrounded, and null when the prop is absent. */
    private fun pxf(value: Any?): Float? =
        (value as? Number)?.toFloat()?.times(activity.resources.displayMetrics.density)

    /**
     * Four edges - `[left, top, right, bottom]` in logical pixels - as device
     * pixels. One number stands for all four; anything else is no edges.
     */
    private fun edges(value: Any?): List<Int> = when (value) {
        is Number -> px(value).let { listOf(it, it, it, it) }
        is List<*> -> if (value.size == 4) value.map { px(it) } else BoxStyle.NO_EDGES
        else -> BoxStyle.NO_EDGES
    }

    /** Typefaces already resolved, by family; null for one that could not be. */
    private val typefaces = HashMap<String, Typeface?>()

    /**
     * The fonts the app bundles, by family, as Flutter's build wrote them into
     * `FontManifest.json` - the first file of each family.
     */
    private val bundledFonts: Map<String, String> by lazy {
        val fonts = HashMap<String, String>()
        try {
            val manifest = activity.assets.open(flutterAssetKey("FontManifest.json"))
                .bufferedReader().use { it.readText() }
            val families = org.json.JSONArray(manifest)
            for (i in 0 until families.length()) {
                val family = families.getJSONObject(i)
                val files = family.optJSONArray("fonts") ?: continue
                if (files.length() == 0) continue
                fonts[family.getString("family")] = files.getJSONObject(0).getString("asset")
            }
        } catch (e: Exception) {
            // No manifest, or not one this understands: no bundled fonts.
        }
        fonts
    }

    /**
     * The typeface for a `fontFamily`: one of the generic names, a font the app
     * bundles, or a family the device has. Null for no family at all.
     */
    private fun typefaceFor(family: String?): Typeface? {
        if (family == null) return null
        if (typefaces.containsKey(family)) return typefaces[family]
        val typeface = when (family) {
            "monospace" -> Typeface.MONOSPACE
            "serif" -> Typeface.SERIF
            "sans-serif" -> Typeface.SANS_SERIF
            "MaterialIcons" -> iconFont
            else -> bundledFonts[family]?.let {
                try {
                    Typeface.createFromAsset(activity.assets, flutterAssetKey(it))
                } catch (e: Exception) {
                    null
                }
            } ?: Typeface.create(family, Typeface.NORMAL)
        }
        typefaces[family] = typeface
        return typeface
    }

    /**
     * The height a toolbar gives its title row, from the theme.
     *
     * WRAP_CONTENT alone does not say it: a bar that also pads itself past the
     * status icons wraps to that padding plus the text, and the row the title
     * should sit in the middle of never exists.
     */
    // 56dp: what Flutter's AppBar is, under Material 3 as under 2 (its
    // `kToolbarHeight`; the 64dp of the Material 3 spec is not what a Flutter
    // app draws), and what the widget layer's own bar for a nested scaffold
    // is - so the two bars of one app are the same height. Stated rather
    // than read from the theme, whose toolbar is the spec's 64.
    private fun actionBarHeight(): Int = dp(56)

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
        scrollOffsets.keys.retainAll(renderedScrolls)
        scrollVersions.keys.retainAll(renderedScrolls + renderedLists.map { "lazy:$it" })
        sizeReports.keys.retainAll(renderedSizes)
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
            // The cells run from the start of each row, which in a
            // right-to-left screen is its right-hand end.
            val fromStart = column * (cw + hSpacing)
            val x = if (layoutDirection == LAYOUT_DIRECTION_RTL) (r - l) - fromStart - cw
            else fromStart
            val y = row * (ch + vSpacing)
            child.layout(x, y, x + cw, y + ch)
            index++
        }
    }
}

/**
 * A ViewGroup that lays its children out from the start of the line (the left,
 * or the right in a right-to-left screen), wrapping onto the next
 * line when the current one runs out of width, and sizes itself to the height
 * that takes. Android has no wrapping layout in the framework, so a Wrap node is
 * drawn with one of these.
 *
 * [alignment] places the children along each line - 'start', 'center', 'end'
 * or 'spaceBetween' - and [crossAlignment] across it, for a line whose children
 * are not all one height.
 */
private class FlowLayout(context: Context) : ViewGroup(context) {
    var hSpacing = 0
    var vSpacing = 0
    var alignment = "start"
    var crossAlignment = "start"

    /** One line: the children on it, how wide they are with their gaps, how tall. */
    private class Line {
        val views = ArrayList<View>()
        var width = 0
        var height = 0
    }

    /** Breaks the measured children into lines no wider than [maxWidth]. */
    private fun lines(maxWidth: Int): List<Line> {
        val lines = ArrayList<Line>()
        var line = Line()
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            val w = child.measuredWidth
            if (line.views.isNotEmpty() && line.width + hSpacing + w > maxWidth) {
                lines += line
                line = Line()
            }
            line.width += w + if (line.views.isEmpty()) 0 else hSpacing
            line.height = maxOf(line.height, child.measuredHeight)
            line.views += child
        }
        if (line.views.isNotEmpty()) lines += line
        return lines
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // With no width to wrap within - inside a horizontal scroller, say -
        // everything is one line.
        val bounded = MeasureSpec.getMode(widthMeasureSpec) != MeasureSpec.UNSPECIFIED
        val maxWidth = if (bounded) MeasureSpec.getSize(widthMeasureSpec) else Int.MAX_VALUE / 4
        val childWidthSpec =
            if (bounded) MeasureSpec.makeMeasureSpec(maxWidth, MeasureSpec.AT_MOST)
            else MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility != GONE) child.measure(childWidthSpec, childHeightSpec)
        }
        val lines = lines(maxWidth)
        val height = lines.sumOf { it.height } + vSpacing * maxOf(0, lines.size - 1)
        setMeasuredDimension(
            if (bounded) maxWidth else lines.maxOfOrNull { it.width } ?: 0,
            height,
        )
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val maxWidth = r - l
        var y = 0
        for (line in lines(maxWidth)) {
            val free = maxOf(0, maxWidth - line.width)
            var x = when (alignment) {
                "center" -> free / 2
                "end" -> free
                else -> 0
            }
            // spaceBetween shares the line's spare width among its gaps; a
            // line of one child has no gap to give it to.
            val extra = if (alignment == "spaceBetween" && line.views.size > 1) {
                free / (line.views.size - 1)
            } else {
                0
            }
            for (child in line.views) {
                val w = child.measuredWidth
                val h = child.measuredHeight
                val top = y + when (crossAlignment) {
                    "center" -> (line.height - h) / 2
                    "end" -> line.height - h
                    else -> 0
                }
                // `x` counts from the start of the line; right to left, that
                // is a distance from the right-hand edge.
                val left = if (layoutDirection == LAYOUT_DIRECTION_RTL) maxWidth - x - w else x
                child.layout(left, top, left + w, top + h)
                x += w + hSpacing + extra
            }
            y += line.height + vSpacing
        }
    }
}
