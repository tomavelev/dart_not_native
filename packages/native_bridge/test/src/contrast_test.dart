/// The rule every renderer applies over a colour the app chose.
library;

import 'package:dart_not_native/src/contrast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark text over a light colour, white over a dark one', () {
    expect(textOn('#ffffff'), onLight);
    expect(textOn('#f5f5f5'), onLight);
    expect(textOn('#000000'), onDark);
    expect(textOn('#1976d2'), onDark);
  });

  test('brightness is the eye\'s, not the average of three channels', () {
    // Pure green and pure blue have the same average channel value; one is
    // the brightest colour a screen makes and the other nearly the darkest.
    expect(textOn('#00ff00'), onLight);
    expect(textOn('#0000ff'), onDark);
  });

  test('the borderline is where white and black read equally well', () {
    // Luminance 0.179 is the crossing point of WCAG's two contrast ratios.
    expect(relativeLuminance('#757575')!, lessThan(0.179));
    expect(relativeLuminance('#767676')!, greaterThan(0.179));
    expect(textOn('#757575'), onDark);
    expect(textOn('#767676'), onLight);
  });

  test('the short and alpha-carrying forms are read too', () {
    expect(textOn('#fff'), onLight);
    expect(textOn('#000'), onDark);
    // An alpha channel says how much of it is drawn, not how bright it is.
    expect(textOn('#ff000000'), onDark);
  });

  test('a colour that cannot be read is left to the theme, not guessed', () {
    expect(relativeLuminance('rebeccapurple'), isNull);
    expect(relativeLuminance('#12345'), isNull);
    expect(textOn('not a colour'), onLight);
  });

  test('white and black are the ends of the scale', () {
    expect(relativeLuminance('#ffffff'), closeTo(1, 0.0001));
    expect(relativeLuminance('#000000'), 0);
  });
}
