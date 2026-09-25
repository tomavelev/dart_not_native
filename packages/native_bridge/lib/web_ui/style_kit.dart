/// Style kits: pluggable CSS frameworks for the web DOM renderer.
///
/// [WebUIRenderer] owns the widget tree, reconciliation, layout primitives
/// and event wiring. A [WebStyleKit] decides what the Material components
/// look like: which elements and CSS classes a button, card, text field...
/// is made of, and which stylesheets the page loads.
///
/// The base class renders framework-neutral markup styled by `dnn.css`, so a
/// new kit only overrides the components its CSS framework styles:
///
/// ```dart
/// class MyKit extends WebStyleKit {
///   const MyKit();
///   @override
///   String get name => 'mykit';
///   @override
///   List<String> get stylesheets =>
///       [...WebStyleKit.baseStylesheets, 'vendor/mykit/mykit.css'];
///   @override
///   web.Element button(String label,
///           {required String variant, required String size, String? color}) =>
///       el('button', 'my-btn my-btn--$variant', text: label);
/// }
/// ```
///
/// Kits only build markup. The renderer adds ids, tooltips, disabled state,
/// values and event listeners to the elements they return.
library;

import 'package:web/web.dart' as web;

import '../src/contrast.dart';

/// Elements of a text field the renderer updates in place.
class TextFieldParts {
  final web.Element root;
  final web.Element label;
  final web.Element input;
  final web.Element error;

  const TextFieldParts({
    required this.root,
    required this.label,
    required this.input,
    required this.error,
  });
}

/// A checkbox, radio or switch: [root] is inserted, [input] carries state.
class InputParts {
  final web.Element root;
  final web.HTMLInputElement input;

  const InputParts({required this.root, required this.input});
}

/// A container whose node children are rendered into [childHost].
class HostParts {
  final web.Element root;
  final web.Element childHost;

  const HostParts({required this.root, required this.childHost});
}

/// An alert; the renderer hides [root] when [close] is clicked.
class AlertParts {
  final web.Element root;
  final web.Element? close;

  const AlertParts({required this.root, this.close});
}

abstract class WebStyleKit {
  const WebStyleKit();

  /// Fonts and framework layout rules every kit needs.
  static const List<String> baseStylesheets = [
    'vendor/roboto/roboto.css',
    'vendor/material-icons/material-icons.css',
  ];

  /// Short identifier, also accepted as `?kit=<name>` by `runWebApp`.
  String get name;

  /// Stylesheets (relative to the page) loaded, in order, before the first
  /// render. Include `dnn.css` for layout primitives.
  List<String> get stylesheets;

  // ---------------------------------------------------------------------------
  // Components. Defaults produce dnn-* markup styled by dnn.css.
  // ---------------------------------------------------------------------------

  web.Element appBar(String title, {String? backgroundColor}) {
    final bar = el('header', 'dnn-appbar');
    if (backgroundColor != null) {
      style(bar, 'background', backgroundColor);
      // The stylesheet's title colour was chosen against the theme's primary,
      // not against whatever the app just asked for.
      style(bar, 'color', textOn(backgroundColor));
    }
    bar.appendChild(el('span', 'dnn-appbar__title', text: title));
    return bar;
  }

  /// [variant]: primary, secondary, tertiary, success, error, warning.
  /// [size]: sm, md, lg. [color] overrides the variant's background.
  web.Element button(
    String label, {
    required String variant,
    required String size,
    String? color,
  }) {
    final button = el(
      'button',
      'dnn-button dnn-button--$variant dnn-button--$size',
      text: label,
    );
    if (color != null) {
      style(button, 'background', color);
      style(button, 'color', textOn(color));
    }
    return button;
  }

  web.Element floatingActionButton(String icon) {
    final button = el('button', 'dnn-fab dnn-fab--plain');
    button.appendChild(materialIcon(icon));
    return button;
  }

  web.Element iconButton(String icon) {
    final button = el('button', 'dnn-icon-button');
    button.appendChild(materialIcon(icon));
    return button;
  }

  TextFieldParts textField({required bool multiline}) {
    final root = el('div', 'dnn-textfield');
    final label = el('label', 'dnn-textfield__label');
    final input = web.document.createElement(multiline ? 'textarea' : 'input')
      ..className = 'dnn-textfield__input';
    final error = el('div', 'dnn-textfield__error');
    root
      ..appendChild(label)
      ..appendChild(input)
      ..appendChild(error);
    return TextFieldParts(root: root, label: label, input: input, error: error);
  }

  /// A strip of labels, one selected: real buttons, so the keyboard and
  /// assistive technology treat them as the choices they are.
  web.Element tabs(List<String> labels, int selected) {
    final bar = el('div', 'dnn-tabs');
    bar.setAttribute('role', 'tablist');
    for (var i = 0; i < labels.length; i++) {
      final tab = el('button', 'dnn-tabs__tab', text: labels[i]);
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-selected', '${i == selected}');
      if (i == selected) tab.classList.add('dnn-tabs__tab--selected');
      bar.appendChild(tab);
    }
    return bar;
  }

  /// A value dragged along a track: the browser's own range input, which
  /// brings the keyboard and pointer handling with it.
  web.HTMLInputElement slider() =>
      _input('range')..className = 'dnn-slider';

  void setTextFieldError(TextFieldParts parts, bool hasError) {
    parts.root.classList.toggle('dnn-textfield--error', hasError);
  }

  InputParts checkbox(String? label) =>
      _choice('dnn-checkbox', 'checkbox', label);

  InputParts radio(String? label) => _choice('dnn-radio', 'radio', label);

  InputParts toggle(String? label) {
    final root = el('label', 'dnn-switch');
    final input = _input('checkbox')..setAttribute('role', 'switch');
    root
      ..appendChild(input)
      ..appendChild(el('span', 'dnn-switch__track'));
    if (label != null)
      root.appendChild(el('span', 'dnn-switch__label', text: label));
    return InputParts(root: root, input: input);
  }

  /// [variant]: elevated, outlined, filled.
  HostParts card({
    required String variant,
    required double elevation,
    required double padding,
    String? title,
    String? backgroundColor,
  }) {
    final card = el('div', 'dnn-card dnn-card--$variant');
    if (variant == 'elevated') style(card, 'box-shadow', shadow(elevation));
    if (backgroundColor != null) {
      style(card, 'background', backgroundColor);
      // Inherited by the title and by every child that did not state a colour
      // of its own, which is what makes a dark card readable.
      style(card, 'color', textOn(backgroundColor));
    }
    if (title != null)
      card.appendChild(el('div', 'dnn-card__title', text: title));
    final content = el('div', 'dnn-card__content');
    style(content, 'padding', '${padding}px');
    card.appendChild(content);
    return HostParts(root: card, childHost: content);
  }

  /// [variant]: solid, outlined, dot.
  web.Element badge(
    String? label, {
    required String variant,
    required String color,
  }) {
    final badge = el(
      'span',
      'dnn-badge dnn-badge--$variant',
      text: variant == 'dot' ? null : label,
    );
    if (variant == 'outlined') {
      style(badge, 'color', color);
    } else {
      style(badge, 'background', color);
      style(badge, 'color', textOn(color));
    }
    return badge;
  }

  /// [type]: success, error, warning, info.
  AlertParts alert({
    required String type,
    required String message,
    String? title,
    required bool dismissible,
  }) {
    final alert = el('div', 'dnn-alert dnn-alert--$type');
    final body = el('div', 'dnn-alert__body');
    if (title != null)
      body.appendChild(el('span', 'dnn-alert__title', text: title));
    body.appendChild(el('span', 'dnn-alert__message', text: message));
    alert.appendChild(body);
    web.Element? close;
    if (dismissible) {
      close = el('button', 'dnn-alert__close', text: '×');
      alert.appendChild(close);
    }
    return AlertParts(root: alert, close: close);
  }

  /// [value] is 0..1.
  web.Element progressLinear(double value, String color) {
    final track = el('div', 'dnn-progress');
    style(track, 'color', color);
    final bar = el('div', 'dnn-progress__bar');
    style(bar, 'width', '${(value * 100).clamp(0, 100)}%');
    track.appendChild(bar);
    return track;
  }

  /// Container for list items (its children are rendered into it).
  web.Element list() => el('div', 'dnn-list');

  web.Element listItem(String text, String? subtitle) {
    final item = el('div', 'dnn-list-item');
    item.appendChild(el('span', 'dnn-list-item__text', text: text));
    if (subtitle != null) {
      item.appendChild(el('span', 'dnn-list-item__subtitle', text: subtitle));
    }
    return item;
  }

  // ---------------------------------------------------------------------------
  // Helpers for kit implementations
  // ---------------------------------------------------------------------------

  web.Element el(String tag, String classes, {String? text}) {
    final element = web.document.createElement(tag)..className = classes;
    if (text != null) element.textContent = text;
    return element;
  }

  /// A Material Icons ligature element.
  web.Element materialIcon(String name) =>
      el('i', 'material-icons', text: name);

  void style(web.Element element, String property, String value) {
    (element as web.HTMLElement).style.setProperty(property, value);
  }

  /// CSS box-shadow approximating a Material elevation (dp).
  String shadow(double elevation) {
    if (elevation <= 0) return 'none';
    final e = elevation.clamp(1, 24);
    return '0 ${e / 2}px ${e}px rgba(0,0,0,0.14), 0 ${e / 4}px ${e / 2}px rgba(0,0,0,0.12)';
  }

  InputParts _choice(String cls, String type, String? label) {
    final root = el('label', cls);
    final input = _input(type);
    root.appendChild(input);
    // A span right after the input is also the hook CSS-only kits
    // (e.g. Materialize) use to draw the control.
    root.appendChild(el('span', '${cls}__label', text: label ?? ''));
    return InputParts(root: root, input: input);
  }

  web.HTMLInputElement _input(String type) =>
      web.document.createElement('input') as web.HTMLInputElement..type = type;
}

/// Framework CSS only (`dnn.css`), no third-party stylesheet.
class PlainKit extends WebStyleKit {
  const PlainKit();

  @override
  String get name => 'plain';

  @override
  List<String> get stylesheets => const [
    ...WebStyleKit.baseStylesheets,
    'dnn.css',
  ];
}
