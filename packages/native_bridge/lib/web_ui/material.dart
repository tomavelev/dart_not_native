/// Material Design widgets for web using Material CSS.
///
/// This is the web bridge component of dart_not_native framework.
/// Currently delegates to Flutter Material - architecture is ready
/// for full HTML/CSS Material CSS implementation.
///
/// Do not import directly. Use the platform-agnostic export:
/// ```dart
/// import 'package:dart_not_native/material.dart';
/// ```

library dart_not_native_web_ui;

// Re-export all Flutter Material - web bridge ready for expansion
export 'package:flutter/material.dart';

// Export web renderer for native UI rendering
export 'web_renderer.dart';
