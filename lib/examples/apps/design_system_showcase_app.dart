/// Design System Showcase - written as a plain Flutter app.
///
/// Five pages of design-system tokens and components. The tokens come from
/// `design_system/tokens.dart`; the components (Card, Badge, Alert, Divider,
/// Switch, progress bars) are the framework's own, wrapped as Flutter-shaped
/// widgets by `widgets.dart` - so only the import sets this apart from a Flutter
/// app, and on web every component is still drawn by the active style kit.
library;

import 'package:dart_not_native/design_system/tokens.dart';
import 'package:dart_not_native/widgets.dart';

const designSystemPages = [
  'Typography',
  'Colors',
  'Spacing',
  'Buttons & Cards',
  'Feedback & Inputs',
];

class DesignSystemShowcaseApp extends StatefulWidget {
  const DesignSystemShowcaseApp({super.key, this.initialPage = 0});

  /// The page shown first, 0-based (deep-links a page for demos and captures).
  final int initialPage;

  @override
  State<DesignSystemShowcaseApp> createState() =>
      _DesignSystemShowcaseAppState();
}

class _DesignSystemShowcaseAppState extends State<DesignSystemShowcaseApp> {
  late int currentPage = widget.initialPage % designSystemPages.length;

  // Interactive component state (page 5) and last pressed button (page 4).
  String lastAction = 'none';
  bool newsletter = false;
  String plan = 'free';
  bool darkMode = false;

  void _next() => setState(
      () => currentPage = (currentPage + 1) % designSystemPages.length);
  void _prev() => setState(() => currentPage =
      (currentPage - 1 + designSystemPages.length) % designSystemPages.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Design System (Page ${currentPage + 1}/${designSystemPages.length})',
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _navigation(),
          Padding(padding: const EdgeInsets.all(16), child: _page()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Next page',
        onPressed: _next,
        child: const Icon(Icons.arrow_forward),
      ),
    );
  }

  Widget _navigation() => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('nav_prev'),
              onPressed: _prev,
              child: const Text('Previous'),
            ),
            Text(
              'Page ${currentPage + 1} of ${designSystemPages.length} · ${designSystemPages[currentPage]}',
              key: const ValueKey('page_indicator'),
              style: const TextStyle(
                  fontSize: FONT_SIZE_H5, fontWeight: FontWeight.w500),
            ),
            TextButton(
              key: const ValueKey('nav_next'),
              onPressed: _next,
              child: const Text('Next'),
            ),
          ],
        ),
      );

  Widget _page() => switch (currentPage) {
        0 => _typography(),
        1 => _colors(),
        2 => _spacing(),
        3 => _buttonsAndCards(),
        _ => _feedbackAndInputs(),
      };

  // --- Page 1: Typography ---

  Widget _typography() => _columns([
        _section('Font sizes', const [
          Text('Heading 1 (32px)',
              style: TextStyle(fontSize: FONT_SIZE_H1, fontWeight: FontWeight.w700)),
          Text('Heading 2 (28px)',
              style: TextStyle(fontSize: FONT_SIZE_H2, fontWeight: FontWeight.w600)),
          Text('Heading 3 (24px)',
              style: TextStyle(fontSize: FONT_SIZE_H3, fontWeight: FontWeight.w600)),
          Text('Body Large (18px)', style: TextStyle(fontSize: FONT_SIZE_BODY_LG)),
          Text('Body Medium (16px)', style: TextStyle(fontSize: FONT_SIZE_BODY_MD)),
          Text('Body Small (14px)', style: TextStyle(fontSize: FONT_SIZE_BODY_SM)),
          Text('Caption (12px)',
              style: TextStyle(
                  fontSize: FONT_SIZE_CAPTION, color: Color(0xFF757575))),
        ]),
        _section('Font weights', [
          const Text('Light 300',
              style: TextStyle(fontSize: FONT_SIZE_BODY_LG, fontWeight: FontWeight.w300)),
          const Text('Regular 400',
              style: TextStyle(fontSize: FONT_SIZE_BODY_LG, fontWeight: FontWeight.w400)),
          const Text('Medium 500',
              style: TextStyle(fontSize: FONT_SIZE_BODY_LG, fontWeight: FontWeight.w500)),
          const Text('Semibold 600',
              style: TextStyle(fontSize: FONT_SIZE_BODY_LG, fontWeight: FontWeight.w600)),
          const Text('Bold 700',
              style: TextStyle(fontSize: FONT_SIZE_BODY_LG, fontWeight: FontWeight.w700)),
          const SizedBox(height: SPACING_MD),
          _label('Line heights'),
          const Text('Tight (1.2) for headings'),
          const Text('Normal (1.5) for body'),
          const Text('Relaxed (1.8) for long-form'),
        ]),
      ]);

  // --- Page 2: Colors ---

  Widget _colors() => _columns([
        _section('Semantic colors', [
          for (final (name, color) in const [
            ('Primary', COLOR_PRIMARY),
            ('Secondary', COLOR_SECONDARY),
            ('Success', COLOR_SUCCESS),
            ('Error', COLOR_ERROR),
            ('Warning', COLOR_WARNING),
            ('Info', COLOR_INFO),
          ])
            Badge(label: '$name $color', color: color),
        ]),
        _section('Gray scale', [
          for (final (name, color) in const [
            ('50', COLOR_GRAY_50),
            ('100', COLOR_GRAY_100),
            ('200', COLOR_GRAY_200),
            ('400', COLOR_GRAY_400),
            ('600', COLOR_GRAY_600),
            ('800', COLOR_GRAY_800),
            ('900', COLOR_GRAY_900),
          ])
            _swatch('Gray $name $color', color),
        ]),
        _section('Text colors', [
          Text('Primary text $COLOR_TEXT_PRIMARY',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_PRIMARY))),
          Text('Secondary text $COLOR_TEXT_SECONDARY',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
          Text('Disabled text $COLOR_TEXT_DISABLED',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_DISABLED))),
          Text('Hint text $COLOR_TEXT_HINT',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_HINT))),
        ]),
      ]);

  Widget _swatch(String label, String color) => Row(
        spacing: SPACING_SM,
        children: [Badge.dot(color: color), Text(label)],
      );

  // --- Page 3: Spacing ---

  Widget _spacing() => _columns([
        _section('Scale (8px base, bars drawn x4)', [
          for (final (name, value) in const [
            ('xs', SPACING_XS),
            ('sm', SPACING_SM),
            ('md', SPACING_MD),
            ('lg', SPACING_LG),
            ('xl', SPACING_XL),
            ('xxl', SPACING_XXL),
            ('xxxl', SPACING_XXXL),
          ])
            Row(
              spacing: SPACING_SM,
              children: [
                Text('$name: ${value.toInt()}px'),
                Skeleton(width: value * 4, height: 12),
              ],
            ),
        ]),
        _section('Use cases', const [
          Text('xs (4px): tight inline spacing'),
          Text('sm (8px): button padding'),
          Text('md (16px): standard padding'),
          Text('lg (24px): card padding'),
          Text('xl (32px): page sections'),
          Text('xxl (48px): page margins'),
        ]),
      ]);

  // --- Page 4: Buttons & Cards ---

  Widget _buttonsAndCards() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Button variants'),
          Row(
            children: [
              ElevatedButton(
                  onPressed: () => setState(() => lastAction = 'primary'),
                  child: const Text('Primary')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromHex(COLOR_SECONDARY)),
                  onPressed: () => setState(() => lastAction = 'secondary'),
                  child: const Text('Secondary')),
              TextButton(
                  onPressed: () => setState(() => lastAction = 'tertiary'),
                  child: const Text('Tertiary')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromHex(COLOR_SUCCESS)),
                  onPressed: () => setState(() => lastAction = 'success'),
                  child: const Text('Success')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromHex(COLOR_ERROR)),
                  onPressed: () => setState(() => lastAction = 'error'),
                  child: const Text('Error')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromHex(COLOR_WARNING)),
                  onPressed: () => setState(() => lastAction = 'warning'),
                  child: const Text('Warning')),
            ],
          ),
          Text('Last pressed: $lastAction', key: const ValueKey('last_action')),
          const SizedBox(height: SPACING_SM),
          _label('Sizes and states'),
          Row(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Small')),
              ElevatedButton(onPressed: () {}, child: const Text('Medium')),
              ElevatedButton(onPressed: () {}, child: const Text('Large')),
              const ElevatedButton(onPressed: null, child: Text('Disabled')),
            ],
          ),
          const SizedBox(height: SPACING_SM),
          _label('Cards'),
          Row(
            spacing: SPACING_MD,
            children: const [
              Expanded(
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Elevated', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Card with a shadow'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Card.outlined(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Outlined', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Border only'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Card.filled(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Filled', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Colored background'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _label('Badges'),
          Row(
            children: [
              const Badge(label: 'Solid'),
              const Badge(label: 'Outlined', outlined: true),
              const Badge(label: 'Success', color: COLOR_SUCCESS),
              const Badge(label: 'Error', color: COLOR_ERROR),
              const Badge(label: 'Warning', color: COLOR_WARNING),
              const Badge(label: 'Info', color: COLOR_INFO),
              const Badge.dot(),
            ],
          ),
        ],
      );

  // --- Page 5: Feedback & Inputs ---

  Widget _feedbackAndInputs() => _columns([
        _section('Alerts', [
          const Alert.success(title: 'Saved', message: 'Your changes were saved.'),
          const Alert.error(title: 'Error', message: 'Something went wrong.'),
          const Alert.warning(
              message: 'Your session expires soon.', dismissible: false),
          const Alert.info(
              message: 'A new version is available.', dismissible: false),
          _label('Loading'),
          const LinearProgressIndicator(value: 0.6),
          const SizedBox(height: SPACING_SM),
          const Row(
            spacing: SPACING_MD,
            children: [
              CircularProgressIndicator(value: 0.75),
              CircularProgressIndicator(),
            ],
          ),
        ]),
        _section('Inputs', [
          Checkbox(
            value: newsletter,
            onChanged: (v) => setState(() => newsletter = v),
            label: 'Subscribe to newsletter',
          ),
          Text('Newsletter: ${newsletter ? 'on' : 'off'}',
              key: const ValueKey('newsletter_state')),
          const Divider(height: SPACING_SM),
          for (final option in const ['free', 'pro', 'team'])
            Radio<String>(
              value: option,
              groupValue: plan,
              onChanged: (v) => setState(() => plan = v),
              label: 'Plan: ${option[0].toUpperCase()}${option.substring(1)}',
            ),
          Text('Selected plan: $plan', key: const ValueKey('plan_state')),
          const Divider(height: SPACING_SM),
          Switch(
            value: darkMode,
            onChanged: (v) => setState(() => darkMode = v),
            label: 'Dark mode',
          ),
          Text('Dark mode: ${darkMode ? 'on' : 'off'}',
              key: const ValueKey('dark_mode_state')),
        ]),
      ]);

  // --- Helpers ---

  Widget _columns(List<Widget> sections) => Row(spacing: SPACING_LG, children: sections);

  Widget _section(String title, List<Widget> children) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_label(title), ...children],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text(text,
            style: const TextStyle(
                fontSize: FONT_SIZE_H5, fontWeight: FontWeight.w700)),
      );
}
