/// Material Design Lite (getmdl.io, 1.3.0) style kit.
///
/// Uses MDL's CSS-only components: buttons, FAB, cards, chips, lists and
/// shadows. MDL's text fields, checkboxes and switches need its JavaScript
/// upgrade step, so those fall back to the framework (dnn.css) controls.
library;

import 'package:web/web.dart' as web;

import '../../src/contrast.dart';
import '../style_kit.dart';

class MdlKit extends WebStyleKit {
  const MdlKit();

  @override
  String get name => 'mdl';

  @override
  List<String> get stylesheets => const [
    ...WebStyleKit.baseStylesheets,
    'vendor/mdl/material.indigo-pink.min.css',
    'dnn.css',
    'kits/mdl.css',
  ];

  @override
  web.Element appBar(String title, {String? backgroundColor}) {
    final bar = super.appBar(title, backgroundColor: backgroundColor);
    bar.classList.add('mdl-shadow--4dp');
    return bar;
  }

  @override
  web.Element button(
    String label, {
    required String variant,
    required String size,
    String? color,
  }) {
    // MDL has a raised button and a flat one. Tertiary is its flat button in
    // the primary colour; outlined and tonal are the flat button too, with
    // the border or the wash added by kits/mdl.css.
    final classes = switch (variant) {
      'tertiary' => 'mdl-button mdl-button--primary',
      'outlined' || 'tonal' => 'mdl-button',
      _ => 'mdl-button mdl-button--raised',
    };
    final button = el(
      'button',
      '$classes dnn-mdl-button dnn-mdl-button--$variant dnn-mdl-button--$size',
      text: label,
    );
    if (color != null) {
      style(button, 'background', cssColor(color));
      style(button, 'color', textOn(color));
    }
    return button;
  }

  @override
  web.Element floatingActionButton(String icon) {
    final button = el(
      'button',
      'mdl-button mdl-button--fab mdl-button--colored dnn-fab',
    );
    button.appendChild(materialIcon(icon));
    return button;
  }

  @override
  web.Element iconButton(String icon) {
    final button = el('button', 'mdl-button mdl-button--icon dnn-icon-button');
    button.appendChild(materialIcon(icon));
    return button;
  }

  @override
  HostParts card({
    required String variant,
    required double elevation,
    required double padding,
    String? title,
    String? backgroundColor,
  }) {
    final depth = elevation >= 8 ? 8 : (elevation >= 4 ? 4 : 2);
    final card = el(
      'div',
      'mdl-card dnn-mdl-card dnn-mdl-card--$variant${variant == 'elevated' ? ' mdl-shadow--${depth}dp' : ''}',
    );
    if (backgroundColor != null) {
      style(card, 'background', cssColor(backgroundColor));
      // Inherited by the title and the content, which is what makes a card the
      // app coloured readable - see `src/contrast.dart`.
      style(card, 'color', textOn(backgroundColor));
    }
    if (title != null) {
      final titleBar = el('div', 'mdl-card__title');
      titleBar.appendChild(el('h2', 'mdl-card__title-text', text: title));
      card.appendChild(titleBar);
    }
    final content = el(
      'div',
      'mdl-card__supporting-text dnn-mdl-card__content',
    );
    style(content, 'padding', '${padding}px');
    card.appendChild(content);
    return HostParts(root: card, childHost: content);
  }

  @override
  web.Element badge(
    String? label, {
    required String variant,
    required String color,
  }) {
    if (variant == 'dot')
      return super.badge(label, variant: variant, color: color);
    final chip = el('span', 'mdl-chip dnn-mdl-chip dnn-mdl-chip--$variant');
    chip.appendChild(el('span', 'mdl-chip__text', text: label));
    if (variant == 'outlined') {
      style(chip, 'color', cssColor(color));
    } else {
      style(chip, 'background', cssColor(color));
      style(chip, 'color', textOn(color));
    }
    return chip;
  }

  @override
  web.Element list() => el('div', 'mdl-list dnn-mdl-list');

  @override
  web.Element listItem(String text, String? subtitle) {
    final item = el(
      'div',
      'mdl-list__item${subtitle != null ? ' mdl-list__item--two-line' : ''}',
    );
    final content = el('span', 'mdl-list__item-primary-content');
    content.appendChild(el('span', 'dnn-mdl-list__text', text: text));
    if (subtitle != null) {
      content.appendChild(
        el('span', 'mdl-list__item-sub-title', text: subtitle),
      );
    }
    item.appendChild(content);
    return item;
  }
}
