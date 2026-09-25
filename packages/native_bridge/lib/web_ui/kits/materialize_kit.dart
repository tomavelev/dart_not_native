/// Materialize CSS (materializecss.com, 1.0.0) style kit.
///
/// Materialize draws checkboxes, radios, switches and text fields in pure
/// CSS, so every component maps to native Materialize markup; no
/// Materialize JavaScript is loaded.
library;

import 'package:web/web.dart' as web;

import '../../src/contrast.dart';
import '../style_kit.dart';

class MaterializeKit extends WebStyleKit {
  const MaterializeKit();

  @override
  String get name => 'materialize';

  @override
  List<String> get stylesheets => const [
    ...WebStyleKit.baseStylesheets,
    'vendor/materialize/materialize.min.css',
    'dnn.css',
    'kits/materialize.css',
  ];

  /// Materialize color classes per design-system variant.
  static const _colors = {
    'primary': 'blue darken-2',
    'secondary': 'orange darken-2',
    'success': 'green darken-2',
    'error': 'red darken-2',
    'warning': 'yellow darken-2 black-text',
    'info': 'light-blue darken-2',
  };

  static const _alertColors = {
    'success': 'green lighten-5 green-text text-darken-4',
    'error': 'red lighten-5 red-text text-darken-4',
    'warning': 'amber lighten-5 amber-text text-darken-4',
    'info': 'light-blue lighten-5 light-blue-text text-darken-4',
  };

  @override
  web.Element appBar(String title, {String? backgroundColor}) {
    final nav = el('nav', 'dnn-appbar dnn-mz-nav ${_colors['primary']}');
    if (backgroundColor != null) {
      style(nav, 'background', backgroundColor);
      style(nav, 'color', textOn(backgroundColor));
    }
    final wrapper = el('div', 'nav-wrapper');
    wrapper.appendChild(el('span', 'dnn-mz-nav__title', text: title));
    nav.appendChild(wrapper);
    return nav;
  }

  @override
  web.Element button(
    String label, {
    required String variant,
    required String size,
    String? color,
  }) {
    final sizeClass = switch (size) {
      'sm' => ' btn-small',
      'lg' => ' btn-large',
      _ => '',
    };
    final classes = variant == 'tertiary'
        ? 'btn-flat$sizeClass'
        : 'btn$sizeClass ${_colors[variant] ?? _colors['primary']}';
    final button = el('button', '$classes dnn-mz-button', text: label);
    if (color != null) {
      style(button, 'background', color);
      style(button, 'color', textOn(color));
    }
    return button;
  }

  @override
  web.Element floatingActionButton(String icon) {
    final button = el(
      'button',
      'btn-floating btn-large ${_colors['primary']} dnn-fab',
    );
    button.appendChild(materialIcon(icon));
    return button;
  }

  @override
  web.Element iconButton(String icon) {
    final button = el('button', 'btn-flat dnn-mz-icon-button');
    button.appendChild(materialIcon(icon));
    return button;
  }

  @override
  TextFieldParts textField({required bool multiline}) {
    final root = el('div', 'input-field dnn-mz-textfield');
    final input = web.document.createElement(multiline ? 'textarea' : 'input')
      ..className = multiline ? 'materialize-textarea' : '';
    // Materialize floats the label with JavaScript; keep it raised instead.
    final label = el('label', 'active');
    final error = el('span', 'helper-text dnn-mz-textfield__error');
    root
      ..appendChild(input)
      ..appendChild(label)
      ..appendChild(error);
    return TextFieldParts(root: root, label: label, input: input, error: error);
  }

  @override
  void setTextFieldError(TextFieldParts parts, bool hasError) {
    parts.input.classList.toggle('invalid', hasError);
  }

  @override
  InputParts checkbox(String? label) => _choice('checkbox', 'filled-in', label);

  @override
  InputParts radio(String? label) => _choice('radio', 'with-gap', label);

  @override
  InputParts toggle(String? label) {
    final root = el('div', 'switch dnn-mz-switch');
    final wrapper = el('label', '');
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'checkbox';
    wrapper
      ..appendChild(input)
      ..appendChild(el('span', 'lever'));
    if (label != null)
      wrapper.appendChild(el('span', 'dnn-mz-switch__label', text: label));
    root.appendChild(wrapper);
    return InputParts(root: root, input: input);
  }

  @override
  HostParts card({
    required String variant,
    required double elevation,
    required double padding,
    String? title,
    String? backgroundColor,
  }) {
    final depth = elevation <= 0 ? 0 : (elevation / 4).ceil().clamp(1, 5);
    final card = el(
      'div',
      'card dnn-mz-card dnn-mz-card--$variant${variant == 'elevated' ? ' z-depth-$depth' : ''}',
    );
    if (backgroundColor != null) {
      style(card, 'background', backgroundColor);
      style(card, 'color', textOn(backgroundColor));
    }
    final content = el('div', 'card-content');
    style(content, 'padding', '${padding}px');
    if (title != null)
      content.appendChild(el('span', 'card-title', text: title));
    final host = el('div', 'dnn-mz-card__body');
    content.appendChild(host);
    card.appendChild(content);
    return HostParts(root: card, childHost: host);
  }

  @override
  web.Element badge(
    String? label, {
    required String variant,
    required String color,
  }) {
    if (variant == 'dot')
      return super.badge(label, variant: variant, color: color);
    final chip = el(
      'span',
      'chip dnn-mz-chip dnn-mz-chip--$variant',
      text: label,
    );
    if (variant == 'outlined') {
      style(chip, 'color', color);
    } else {
      style(chip, 'background', color);
      style(chip, 'color', textOn(color));
    }
    return chip;
  }

  @override
  AlertParts alert({
    required String type,
    required String message,
    String? title,
    required bool dismissible,
  }) {
    final panel = el(
      'div',
      'card-panel dnn-mz-alert ${_alertColors[type] ?? _alertColors['info']}',
    );
    final body = el('div', 'dnn-mz-alert__body');
    if (title != null)
      body.appendChild(el('strong', 'dnn-mz-alert__title', text: title));
    body.appendChild(el('span', 'dnn-mz-alert__message', text: message));
    panel.appendChild(body);
    web.Element? close;
    if (dismissible) {
      close = el('button', 'btn-flat dnn-mz-alert__close');
      close.appendChild(materialIcon('close'));
      panel.appendChild(close);
    }
    return AlertParts(root: panel, close: close);
  }

  @override
  web.Element progressLinear(double value, String color) {
    final track = el('div', 'progress dnn-mz-progress');
    final bar = el('div', 'determinate');
    style(bar, 'width', '${(value * 100).clamp(0, 100)}%');
    style(bar, 'background-color', color);
    track.appendChild(bar);
    return track;
  }

  @override
  web.Element list() => el('div', 'collection dnn-mz-list');

  @override
  web.Element listItem(String text, String? subtitle) {
    final item = el('div', 'collection-item');
    item.appendChild(el('span', 'title', text: text));
    if (subtitle != null)
      item.appendChild(el('p', 'dnn-mz-list__subtitle', text: subtitle));
    return item;
  }

  InputParts _choice(String type, String modifier, String? label) {
    final root = el('label', 'dnn-mz-choice');
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = type
      ..className = modifier;
    root
      ..appendChild(input)
      // Materialize draws the control on this span.
      ..appendChild(el('span', '', text: label ?? ''));
    return InputParts(root: root, input: input);
  }
}
