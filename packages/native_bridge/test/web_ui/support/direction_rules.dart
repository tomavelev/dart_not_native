/// The stylesheet rules a right-to-left screen turns on, as the browser tests
/// need them.
///
/// The browser tests run without `web_shell/dnn.css` - the test server does
/// not serve it - so a test that measures where something landed has to bring
/// the few rules that put it there. They are written once, here: the browser
/// test injects them, and `text_direction_css_test.dart` checks the shipped
/// stylesheet still says every one of them, so the two cannot drift apart.
library;

/// Each a selector and one declaration the stylesheet makes for it.
const List<(String, String)> directionRules = [
  ('.dnn-appbar', 'display: flex'),
  ('.dnn-appbar__actions', 'display: flex'),
  ('.dnn-appbar__actions', 'margin-inline-start: auto'),
  ('[dir="rtl"] .dnn-appbar__leading--back', 'transform: scaleX(-1)'),
  ('.dnn-row', 'display: flex'),
  ('.dnn-row--size-max', 'width: 100%'),
  ('.dnn-expanded', 'display: flex'),
  ('.dnn-box', 'display: grid'),
  ('.dnn-fab', 'position: fixed'),
  ('.dnn-fab', 'inset-inline-end: 24px'),
];

/// [directionRules] as a stylesheet.
String directionStylesheet() => [
  for (final (selector, declaration) in directionRules)
    '$selector { $declaration; }',
].join('\n');
