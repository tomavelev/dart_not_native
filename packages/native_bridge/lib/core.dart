/// Platform-neutral core of dart_not_native (pure Dart, no Flutter).
///
/// Apps written against this library can be mounted on any renderer:
/// the web DOM renderer (`package:dart_not_native/web.dart`), the native
/// Android/iOS renderers, or a Flutter host.
///
/// ```dart
/// import 'package:dart_not_native/core.dart';
/// ```
library;

export 'src/ui_renderer.dart';
export 'src/app_theme.dart';
export 'src/native_ui_app.dart';
export 'src/system_back.dart';
export 'src/event_binding.dart';
export 'src/frame_probe.dart';
export 'src/listenable.dart';
export 'src/render_error.dart';
export 'storage/storage_migration.dart';
export 'src/frame_stats.dart';
export 'platforms/android_ui_builder.dart';
export 'platforms/ios_ui_builder.dart';
export 'design_system/tokens.dart';
export 'design_system/components.dart';
export 'routing/route.dart';
export 'routing/navigation_app.dart';
export 'routing/history_sync.dart';
export 'i18n/translations.dart';
export 'i18n/translation_bundles.dart';
export 'i18n/i18n_preferences.dart';
export 'storage/storage_service.dart';
export 'biometrics/biometrics_service.dart';
