package com.programtom.dart_not_native

import androidx.activity.OnBackPressedCallback
import androidx.activity.OnBackPressedDispatcherOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Registers everything dart_not_native needs on Android.
 *
 * Flutter's generated plugin registrant creates this, so an app gets both of
 * the following by depending on the package - no MainActivity edits, no files
 * to copy:
 *
 *  - the native UI renderer, which paints widget trees as Android Views;
 *  - the system back gesture, forwarded to Dart as a `systemBack` call.
 *
 * The back gesture needs an activity that owns an `OnBackPressedDispatcher`,
 * which means [io.flutter.embedding.android.FlutterFragmentActivity] (the
 * plain FlutterActivity has none). With any other host the plugin still
 * renders; back simply keeps its default behaviour.
 */
class DartNotNativePlugin : FlutterPlugin, ActivityAware {
    companion object {
        private const val SYSTEM_BACK_CHANNEL = "com.programtom.dart_not_native/system_back"
        private const val SYSTEM_BACK_METHOD = "systemBack"
    }

    private var messenger: BinaryMessenger? = null
    private var systemBackChannel: MethodChannel? = null
    private var renderer: NativeUIRenderer? = null
    private var backCallback: OnBackPressedCallback? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        messenger = binding.binaryMessenger
        systemBackChannel = MethodChannel(binding.binaryMessenger, SYSTEM_BACK_CHANNEL)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        systemBackChannel = null
        messenger = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        attach(binding)

    override fun onDetachedFromActivity() = detach()

    override fun onDetachedFromActivityForConfigChanges() = detach()

    private fun attach(binding: ActivityPluginBinding) {
        detach()
        val messenger = this.messenger ?: return
        val activity = binding.activity

        renderer = NativeUIRenderer(activity, messenger).apply { setupChannels() }

        val owner = activity as? OnBackPressedDispatcherOwner ?: return
        val callback = object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = askDart(owner, this)
        }
        owner.onBackPressedDispatcher.addCallback(callback)
        backCallback = callback
    }

    private fun detach() {
        backCallback?.remove()
        backCallback = null
        renderer?.dispose()
        renderer = null
    }

    /**
     * Asks Dart whether it consumed the gesture; anything but an explicit
     * "handled" means the app is at its first screen and the activity should
     * do what it always did.
     */
    private fun askDart(
        owner: OnBackPressedDispatcherOwner,
        callback: OnBackPressedCallback,
    ) {
        val channel = systemBackChannel
        if (channel == null) {
            fallBackToDefault(owner, callback)
            return
        }
        channel.invokeMethod(
            SYSTEM_BACK_METHOD,
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result != true) fallBackToDefault(owner, callback)
                }

                override fun error(code: String, message: String?, details: Any?) =
                    fallBackToDefault(owner, callback)

                override fun notImplemented() = fallBackToDefault(owner, callback)
            },
        )
    }

    /** Runs the back behaviour this callback replaced. */
    private fun fallBackToDefault(
        owner: OnBackPressedDispatcherOwner,
        callback: OnBackPressedCallback,
    ) {
        callback.isEnabled = false
        owner.onBackPressedDispatcher.onBackPressed()
        callback.isEnabled = true
    }
}
