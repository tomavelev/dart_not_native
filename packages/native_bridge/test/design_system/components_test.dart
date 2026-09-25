/// Unit tests for the design-system component builders.
///
/// Components are renderer-agnostic: they only produce nodes, so the tests
/// assert the node type and props each renderer relies on.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DSButton', () {
    test('each constructor sets its variant', () {
      final variants = {
        'primary': DSButton.primary(label: 'L', eventId: 'e'),
        'secondary': DSButton.secondary(label: 'L', eventId: 'e'),
        'tertiary': DSButton.tertiary(label: 'L', eventId: 'e'),
        'success': DSButton.success(label: 'L', eventId: 'e'),
        'error': DSButton.error(label: 'L', eventId: 'e'),
        'warning': DSButton.warning(label: 'L', eventId: 'e'),
      };

      variants.forEach((variant, node) {
        expect(node.type, 'Button');
        expect(node.props['variant'], variant);
        expect(node.props['label'], 'L');
        expect(node.props['eventId'], 'e');
        expect(node.props['size'], 'md', reason: 'default size');
      });
    });

    test('a loading primary button is disabled', () {
      final node = DSButton.primary(
        label: 'Save',
        eventId: 'save',
        loading: true,
      );

      expect(node.props['loading'], isTrue);
      expect(node.props['disabled'], isTrue);
    });

    test('size is forwarded', () {
      expect(
        DSButton.secondary(label: 'L', eventId: 'e', size: 'lg').props['size'],
        'lg',
      );
    });
  });

  group('DSCard', () {
    test('elevated carries elevation and wraps its content', () {
      final node = DSCard.elevated(
        content: UIBuilder.text('body'),
        title: 'Title',
      );

      expect(node.type, 'Card');
      expect(node.props['variant'], 'elevated');
      expect(node.props['elevation'], isNotNull);
      expect(node.props['title'], 'Title');
      expect(node.children!.single.props['content'], 'body');
    });

    test('outlined has no elevation and no title unless given', () {
      final node = DSCard.outlined(content: UIBuilder.text('body'));

      expect(node.props['variant'], 'outlined');
      expect(node.props.containsKey('elevation'), isFalse);
      expect(node.props.containsKey('title'), isFalse);
    });

    test('filled carries a background colour', () {
      final node = DSCard.filled(
        content: UIBuilder.text('body'),
        backgroundColor: '#ff0000',
      );

      expect(node.props['variant'], 'filled');
      expect(node.props['backgroundColor'], '#ff0000');
    });
  });

  group('DSBadge', () {
    test('solid, outlined and dot differ by variant', () {
      expect(DSBadge.solid(label: 'New').props['variant'], 'solid');
      expect(DSBadge.outlined(label: 'New').props['variant'], 'outlined');

      final dot = DSBadge.dot();
      expect(dot.props['variant'], 'dot');
      expect(dot.props.containsKey('label'), isFalse);
    });

    test('a badge with no colour omits it, to follow the theme primary', () {
      expect(DSBadge.solid(label: 'New').props.containsKey('color'), isFalse);
      expect(DSBadge.outlined(label: 'New').props.containsKey('color'), isFalse);
      expect(DSBadge.dot().props.containsKey('color'), isFalse);
    });

    test('semantic badges pick the matching palette colour', () {
      expect(DSBadge.success(label: 'OK').props['color'], COLOR_SUCCESS);
      expect(DSBadge.error(label: 'No').props['color'], COLOR_ERROR);
      expect(DSBadge.warning(label: 'Hm').props['color'], COLOR_WARNING);
      expect(DSBadge.info(label: 'FYI').props['color'], COLOR_INFO);
    });
  });

  group('form controls', () {
    test('checkbox, radio and toggle carry their own state prop', () {
      expect(
        DSCheckbox.input(eventId: 'c', checked: true, label: 'Agree').props,
        {'eventId': 'c', 'checked': true, 'disabled': false, 'label': 'Agree'},
      );
      expect(DSRadio.input(eventId: 'r', value: 'a', selected: true).props, {
        'eventId': 'r',
        'value': 'a',
        'selected': true,
        'disabled': false,
      });
      expect(DSToggle.input(eventId: 't', enabled: true).props, {
        'eventId': 't',
        'enabled': true,
        'disabled': false,
      });
    });
  });

  group('DSDivider', () {
    test('orientation decides which dimension is set', () {
      final horizontal = DSDivider.horizontal();
      expect(horizontal.props['orientation'], 'horizontal');
      expect(horizontal.props['margin'], SPACING_MD);

      final vertical = DSDivider.vertical(height: 40);
      expect(vertical.props['orientation'], 'vertical');
      expect(vertical.props['height'], 40.0);
    });
  });

  group('DSLoading', () {
    test('every indicator is a Loading node tagged by type', () {
      expect(DSLoading.spinner().props['type'], 'spinner');
      // No colour by default: the renderer fills it with the theme primary.
      expect(DSLoading.progressLinear(value: 0.4).props, {
        'type': 'progress-linear',
        'value': 0.4,
        'indeterminate': false,
      });
      expect(
        DSLoading.progressLinear(value: 0.4, color: COLOR_ERROR).props['color'],
        COLOR_ERROR,
      );
      expect(
        DSLoading.progressCircular(indeterminate: true).props['indeterminate'],
        isTrue,
      );
      expect(DSLoading.skeleton(height: 24).props['height'], 24.0);
    });

    test('pulse wraps the child it animates', () {
      final node = DSLoading.pulse(child: UIBuilder.text('loading'));

      expect(node.props['type'], 'pulse');
      expect(node.children!.single.props['content'], 'loading');
    });
  });

  group('DSAlert', () {
    test('each severity keeps its type, message and dismissibility', () {
      final alerts = {
        'success': DSAlert.success(message: 'Saved'),
        'error': DSAlert.error(message: 'Failed', title: 'Oops'),
        'warning': DSAlert.warning(message: 'Careful'),
        'info': DSAlert.info(message: 'FYI', dismissible: false),
      };

      alerts.forEach((type, node) {
        expect(node.type, 'Alert');
        expect(node.props['type'], type);
        expect(node.props['message'], isNotEmpty);
      });
      expect(alerts['error']!.props['title'], 'Oops');
      expect(alerts['success']!.props['dismissible'], isTrue);
      expect(alerts['info']!.props['dismissible'], isFalse);
    });
  });

  group('DSSpacing', () {
    test('follows the 8px scale', () {
      expect(DSSpacing.xs().props['height'], SPACING_XS);
      expect(DSSpacing.sm().props['height'], SPACING_SM);
      expect(DSSpacing.md().props['height'], SPACING_MD);
      expect(DSSpacing.lg().props['height'], SPACING_LG);
      expect(DSSpacing.xl().props['height'], SPACING_XL);
      expect(DSSpacing.xxl().props['height'], SPACING_XXL);
    });
  });

  group('design tokens', () {
    test('the spacing scale is ordered and exposed by name', () {
      expect(
        SpacingScale.all,
        orderedEquals([4.0, 8.0, 16.0, 24.0, 32.0, 48.0, 64.0]),
      );
      expect(SpacingScale.named['md'], SPACING_MD);
    });

    test('the palette exposes the semantic colours as hex', () {
      for (final color in [
        ColorPalette.primary,
        ColorPalette.secondary,
        ColorPalette.success,
        ColorPalette.error,
        ColorPalette.warning,
        ColorPalette.info,
      ]) {
        expect(color, matches(RegExp(r'^#[0-9a-f]{6}$')));
      }
    });

    test('headings get larger and no lighter as they get more important', () {
      expect([
        FontSizeScale.h6,
        FontSizeScale.h5,
        FontSizeScale.h4,
        FontSizeScale.h3,
        FontSizeScale.h2,
        FontSizeScale.h1,
      ], orderedEquals([14.0, 16.0, 20.0, 24.0, 28.0, 32.0]));
      expect(FontWeightScale.bold, greaterThan(FontWeightScale.regular));
    });
  });

  group('DSText', () {
    test(
      'heading helpers apply their typography tokens',
      () {
        expect(DSText.h1('Title').props['fontSize'], FONT_SIZE_H1);
        expect(DSText.h1('Title').props['fontWeight'], FONT_WEIGHT_BOLD);
        expect(DSText.caption('note').props['fontSize'], FONT_SIZE_CAPTION);
      },
    );

    test('at least carry their content', () {
      expect(DSText.h1('Title').type, 'Text');
      expect(DSText.h1('Title').props['content'], 'Title');
    });
  });
}
