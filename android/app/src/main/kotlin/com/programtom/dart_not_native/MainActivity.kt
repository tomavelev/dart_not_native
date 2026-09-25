package com.programtom.dart_not_native

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * Hosts the Flutter engine.
 *
 * The native UI renderer and the system back gesture are registered by
 * `DartNotNativePlugin`, which the generated plugin registrant creates - this
 * activity only has to be the androidx host, because the plain FlutterActivity
 * owns no `OnBackPressedDispatcher` for the gesture to hang off.
 */
class MainActivity : FlutterFragmentActivity()
