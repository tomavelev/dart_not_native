/// Material Adapter - Platform-aware Material Design exports
///
/// This adapter automatically selects the correct Material implementation:
/// - Mobile: Flutter's native Material Design
/// - Web: Material CSS-based Material Design (currently delegates to Flutter)
///
/// Users simply import 'package:dart_not_native/material.dart' and get
/// the appropriate implementation for their platform.

// For now, both mobile and web use Flutter Material
// The web_ui bridge is architecture-ready for HTML/CSS rendering
// but currently delegates to Flutter for compatibility
export 'package:flutter/material.dart';
