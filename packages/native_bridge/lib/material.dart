/// Material Design widgets for all platforms
///
/// Import this for cross-platform Material Design:
/// ```dart
/// import 'package:dart_not_native/material.dart';
/// ```
///
/// On mobile (Android/iOS): Uses Flutter Material (native rendering)
/// On web (browser): Uses Flutter Material (from framework)
///
/// For native UI rendering with widget tree protocol:
/// ```dart
/// import 'package:dart_not_native/material.dart';
///
/// final tree = UIBuilder.scaffold(...);
/// final renderer = WebUIRenderer();
/// await renderer.render(tree);
/// ```

// Flutter names that the framework redefines are hidden so the framework's
// versions win (Flutter's remain available via package:flutter/material.dart).
export 'material_adapter.dart'
    hide Route, Router, RouterConfig, Locale, Form, FormField;
export 'src/ui_renderer.dart';
export 'src/native_ui_app.dart';
export 'src/system_back.dart';
export 'src/event_binding.dart';
export 'routing/route.dart';
export 'routing/navigation_app.dart';
export 'routing/history_sync.dart';
export 'platforms/system_back_channel.dart';
export 'platforms/flutter_renderer.dart';
export 'i18n/translations.dart';
export 'i18n/translation_bundles.dart';
export 'i18n/i18n_preferences.dart';
export 'plugins/plugin.dart';
export 'plugins/app_builder.dart';
export 'storage/storage_service.dart';
export 'forms/validators.dart';
export 'forms/form.dart';
export 'forms/forms_plugin.dart';
