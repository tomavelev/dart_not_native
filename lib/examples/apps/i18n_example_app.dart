/// Internationalization example - written as a plain Flutter app.
///
/// All state lives in the framework's [I18n] instance: pressing a language
/// button calls setLocale, and every [Tr] on screen redraws itself - the screen
/// keeps no listener of its own, which is why this app has no [State] at all.
/// Only the import (`widgets.dart`) renders it through the platform's own views
/// instead of the Flutter engine.
library;

import 'package:dart_not_native/design_system/tokens.dart';
import 'package:dart_not_native/i18n/translation_bundles.dart';
import 'package:dart_not_native/i18n/translations.dart';
import 'package:dart_not_native/widgets.dart';

/// Languages offered by the example, in display order.
const i18nLanguages = [
  ('en', 'English'),
  ('es', 'Español'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('ja', '日本語'),
  ('zh', '中文'),
];

/// Initialize the global I18n with every bundle the example shows.
I18n setUpDemoI18n() {
  initializeI18n(
    defaultLocale: const Locale('en'),
    fallbackLocale: const Locale('en'),
  );
  final i18n = getI18n();
  i18n.loadTranslations(const Locale('en'), enUS);
  i18n.loadTranslations(const Locale('es'), esES);
  i18n.loadTranslations(const Locale('fr'), frFR);
  i18n.loadTranslations(const Locale('de'), deDE);
  i18n.loadTranslations(const Locale('ja'), jaJP);
  i18n.loadTranslations(const Locale('zh'), zhCN);
  return i18n;
}

class I18nExampleApp extends StatelessWidget {
  const I18nExampleApp(this.i18n, {super.key});

  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Tr('navigation.settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Language: ${i18n.currentLocale}',
                key: const ValueKey('current_locale'),
                style: const TextStyle(
                    fontSize: FONT_SIZE_H4, fontWeight: FontWeight.w500)),
            const SizedBox(height: SPACING_MD),
            const Text('Select language:'),
            const SizedBox(height: SPACING_SM),
            Row(
              children: [
                for (final (code, label) in i18nLanguages)
                  _languageButton(code, label),
              ],
            ),
            const SizedBox(height: SPACING_LG),
            const Text('Examples:',
                style: TextStyle(
                    fontSize: FONT_SIZE_H5, fontWeight: FontWeight.w700)),
            const SizedBox(height: SPACING_SM),
            ..._examples(),
          ],
        ),
      ),
    );
  }

  /// The active language is a filled (primary) button, the rest are flat
  /// (tertiary) ones.
  Widget _languageButton(String code, String label) {
    final active = i18n.currentLocale.language == code;
    void select() => i18n.setLocale(Locale(code));
    return active
        ? ElevatedButton(
            key: ValueKey('lang_$code'),
            onPressed: select,
            child: Text(label),
          )
        : TextButton(
            key: ValueKey('lang_$code'),
            onPressed: select,
            child: Text(label),
          );
  }

  /// Every row is a key rather than a string: the lookup happens where the
  /// text is drawn, and a language change redraws it without this app hearing
  /// about the change at all.
  List<Widget> _examples() => [
        _example('ok', 'Simple translation', 'common.ok'),
        _example('cancel', 'Nested key (common.cancel)', 'common.cancel'),
        _example('welcome', 'Message', 'messages.welcome'),
        _example('email', 'Form label (forms.email)', 'forms.email'),
        _example('required', 'Validation error', 'errors.required'),
        _example('items_3', 'Plural, 3 items', 'plurals.items', count: 3),
        _example('items_1', 'Plural, 1 item', 'plurals.items', count: 1),
        _example('items_0', 'Plural, 0 items', 'plurals.items', count: 0),
        _example('users_25', 'Plural, 25 users', 'plurals.users', count: 25),
        _example('just_now', 'Relative time', 'time.just_now'),
        _example(
          'fallback',
          'Missing key with default',
          'nonexistent.key',
          defaultValue: 'Custom default',
        ),
      ];

  Widget _example(
    String id,
    String title,
    String translationKey, {
    int? count,
    String? defaultValue,
  }) =>
      Row(
        spacing: SPACING_SM,
        children: [
          Text('$title:',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
          Tr(
            translationKey,
            key: ValueKey('value_$id'),
            count: count,
            defaultValue: defaultValue,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      );
}
