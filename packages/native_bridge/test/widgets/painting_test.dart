/// The painting value types: Flutter's shapes, in pure Dart.
///
/// These are compared against Flutter's own documented values, since the
/// point of the types is that a screen written for Flutter means the same
/// thing here.
library;

import 'dart:math' as math;

import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Color', () {
    test('reads its channels as ints and as 0..1 doubles', () {
      const color = Color(0x80FF8000);
      expect(color.alpha, 0x80);
      expect(color.red, 0xFF);
      expect(color.green, 0x80);
      expect(color.blue, 0x00);
      expect(color.a, closeTo(0.502, 0.001));
      expect(color.r, 1.0);
      expect(color.b, 0.0);
      expect(color.value, 0x80FF8000);
      expect(color.toARGB32(), 0x80FF8000);
    });

    test('fromARGB and fromRGBO build the same colour as the literal', () {
      expect(const Color.fromARGB(255, 33, 150, 243), const Color(0xFF2196F3));
      expect(const Color.fromRGBO(33, 150, 243, 1), const Color(0xFF2196F3));
      expect(const Color.fromRGBO(0, 0, 0, 0.5).alpha, 127);
      expect(
        Color.from(alpha: 1, red: 1, green: 0, blue: 0),
        const Color(0xFFFF0000),
      );
    });

    test(
      'withOpacity, withAlpha and withValues change only what they name',
      () {
        const red = Color(0xFFFF0000);
        expect(red.withOpacity(0.5), const Color(0x80FF0000));
        expect(red.withAlpha(0x10), const Color(0x10FF0000));
        expect(red.withValues(alpha: 0.5), const Color(0x80FF0000));
        expect(red.withValues(blue: 1), const Color(0xFFFF00FF));
        expect(red.withGreen(0x80), const Color(0xFFFF8000));
      },
    );

    test('lerp moves every channel, and fades a missing end', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(Color.lerp(black, white, 0), black);
      expect(Color.lerp(black, white, 1), white);
      expect(Color.lerp(black, white, 0.5), const Color(0xFF808080));
      expect(Color.lerp(null, null, 0.5), isNull);
      expect(Color.lerp(null, white, 0.5), const Color(0x80FFFFFF));
    });

    test('luminance is 0 for black and 1 for white', () {
      expect(Colors.black.computeLuminance(), 0);
      expect(Colors.white.computeLuminance(), closeTo(1, 1e-9));
    });

    test('alphaBlend over an opaque ground is opaque', () {
      final blended = Color.alphaBlend(
        const Color(0x80FFFFFF),
        const Color(0xFF000000),
      );
      expect(blended.alpha, 0xFF);
      expect(blended.red, closeTo(128, 1));
    });

    test('fromHex reads both lengths', () {
      expect(Color.fromHex('#2196f3'), const Color(0xFF2196F3));
      expect(Color.fromHex('#802196F3'), const Color(0x802196F3));
    });
  });

  group('HSLColor', () {
    test('round-trips a colour', () {
      for (final color in [Colors.teal, Colors.amber, Colors.deepPurple]) {
        expect(HSLColor.fromColor(color).toColor(), Color(color.value));
      }
    });

    test('names the hue of the primaries', () {
      expect(HSLColor.fromColor(const Color(0xFFFF0000)).hue, 0);
      expect(HSLColor.fromColor(const Color(0xFF00FF00)).hue, 120);
      expect(HSLColor.fromColor(const Color(0xFF0000FF)).hue, 240);
      expect(
        const HSLColor.fromAHSL(1, 120, 1, 0.5).toColor(),
        const Color(0xFF00FF00),
      );
    });
  });

  group('Colors', () {
    test('carries the Material values', () {
      expect(Colors.red.value, 0xFFF44336);
      expect(Colors.teal.value, 0xFF009688);
      expect(Colors.teal.shade50, const Color(0xFFE0F2F1));
      expect(Colors.teal[900], const Color(0xFF004D40));
      expect(Colors.blue.shade700, const Color(0xFF1976D2));
      expect(Colors.grey[350], const Color(0xFFD6D6D6));
      expect(Colors.grey.shade500, Colors.grey);
      expect(Colors.deepOrangeAccent.value, 0xFFFF6E40);
      expect(Colors.tealAccent.shade700, const Color(0xFF00BFA5));
      expect(Colors.blueGrey.shade900, const Color(0xFF263238));
    });

    test('carries the translucent blacks and whites', () {
      expect(Colors.transparent.alpha, 0);
      expect(Colors.black87.value, 0xDD000000);
      expect(Colors.black54.value, 0x8A000000);
      expect(Colors.black12.value, 0x1F000000);
      expect(Colors.white70.value, 0xB3FFFFFF);
      expect(Colors.white10.value, 0x1AFFFFFF);
    });

    test('a swatch is its own shade 500', () {
      for (final swatch in Colors.primaries) {
        expect(swatch.shade500.value, swatch.value);
      }
      for (final accent in Colors.accents) {
        expect(accent.shade200.value, accent.value);
      }
    });
  });

  group('EdgeInsets', () {
    test('the constructors agree', () {
      expect(const EdgeInsets.all(8), const EdgeInsets.fromLTRB(8, 8, 8, 8));
      expect(
        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        const EdgeInsets.fromLTRB(4, 2, 4, 2),
      );
      expect(
        const EdgeInsets.only(left: 1, bottom: 3),
        const EdgeInsets.fromLTRB(1, 0, 0, 3),
      );
      expect(EdgeInsets.zero, const EdgeInsets.all(0));
    });

    test('adds up', () {
      const insets = EdgeInsets.fromLTRB(1, 2, 3, 4);
      expect(insets.horizontal, 4);
      expect(insets.vertical, 6);
      expect(insets.collapsedSize, const Size(4, 6));
      expect(insets + insets, const EdgeInsets.fromLTRB(2, 4, 6, 8));
      expect(insets * 2, const EdgeInsets.fromLTRB(2, 4, 6, 8));
      expect(insets.copyWith(top: 9), const EdgeInsets.fromLTRB(1, 9, 3, 4));
      expect(insets.isUniform, isFalse);
      expect(const EdgeInsets.all(5).isUniform, isTrue);
    });

    test('a directional inset reads left-to-right', () {
      const insets = EdgeInsetsDirectional.only(start: 8, end: 2);
      expect(insets.resolve(null), const EdgeInsets.only(left: 8, right: 2));
      expect(
        insets.resolve(TextDirection.rtl),
        const EdgeInsets.only(left: 2, right: 8),
      );
      expect(insets.horizontal, 10);
      expect(
        const EdgeInsetsDirectional.fromSTEB(1, 2, 3, 4).resolve(null),
        const EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
    });
  });

  group('geometry', () {
    test('Offset arithmetic', () {
      const a = Offset(3, 4);
      expect(a.distance, 5);
      expect(a + const Offset(1, 1), const Offset(4, 5));
      expect(a - const Offset(1, 1), const Offset(2, 3));
      expect(a * 2, const Offset(6, 8));
      expect(a / 2, const Offset(1.5, 2));
      expect(-a, const Offset(-3, -4));
      expect(Offset.zero.dx, 0);
      expect(a & const Size(10, 20), const Rect.fromLTWH(3, 4, 10, 20));
    });

    test('Size', () {
      expect(const Size.square(4), const Size(4, 4));
      expect(const Size.fromHeight(56).width, double.infinity);
      expect(const Size(3, 9).shortestSide, 3);
      expect(const Size(3, 9).longestSide, 9);
      expect(const Size(4, 2).aspectRatio, 2);
      expect(Size.zero.isEmpty, isTrue);
      expect(const Size(10, 20).center(Offset.zero), const Offset(5, 10));
      expect(const Size(10, 20) - const Size(4, 5), const Offset(6, 15));
      expect(const Size(10, 20).toString(), 'Size(10.0, 20.0)');
    });

    test('Rect', () {
      const rect = Rect.fromLTWH(10, 20, 30, 40);
      expect(rect.right, 40);
      expect(rect.bottom, 60);
      expect(rect.center, const Offset(25, 40));
      expect(rect.size, const Size(30, 40));
      expect(rect.contains(const Offset(10, 20)), isTrue);
      expect(rect.contains(const Offset(40, 60)), isFalse);
      expect(rect.inflate(5), const Rect.fromLTRB(5, 15, 45, 65));
      expect(rect.deflate(5), const Rect.fromLTRB(15, 25, 35, 55));
      expect(
        rect.shift(const Offset(1, 2)),
        const Rect.fromLTWH(11, 22, 30, 40),
      );
      expect(
        Rect.fromCircle(center: const Offset(5, 5), radius: 5),
        const Rect.fromLTRB(0, 0, 10, 10),
      );
      expect(
        Rect.fromCenter(center: const Offset(5, 5), width: 4, height: 2),
        const Rect.fromLTRB(3, 4, 7, 6),
      );
    });

    test('RRect', () {
      final rounded = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 10, 20),
        const Radius.circular(4),
      );
      expect(rounded.outerRect, const Rect.fromLTWH(0, 0, 10, 20));
      expect(rounded.tlRadius, const Radius.circular(4));
      expect(RRect.fromLTRBR(0, 0, 10, 20, const Radius.circular(4)), rounded);
      expect(
        RRect.fromRectXY(const Rect.fromLTWH(0, 0, 10, 20), 4, 4),
        rounded,
      );
    });

    test('BoxConstraints', () {
      const loose = BoxConstraints(maxWidth: 100, maxHeight: 50);
      expect(loose.biggest, const Size(100, 50));
      expect(loose.smallest, Size.zero);
      expect(loose.hasBoundedWidth, isTrue);
      expect(const BoxConstraints().hasBoundedHeight, isFalse);
      expect(loose.constrain(const Size(500, 10)), const Size(100, 10));
      expect(loose.constrainWidth(30), 30);
      expect(const BoxConstraints.tightFor(width: 40).isTight, isFalse);
      expect(BoxConstraints.tight(const Size(4, 5)).isTight, isTrue);
      expect(const BoxConstraints.expand().minWidth, double.infinity);
      expect(loose.tighten(width: 500).minWidth, 100);
    });
  });

  group('borders', () {
    test('BorderRadius constructors', () {
      expect(
        BorderRadius.circular(8),
        const BorderRadius.all(Radius.circular(8)),
      );
      const top = BorderRadius.vertical(top: Radius.circular(12));
      expect(top.topLeft, const Radius.circular(12));
      expect(top.topRight, const Radius.circular(12));
      expect(top.bottomLeft, Radius.zero);
      const left = BorderRadius.horizontal(left: Radius.circular(3));
      expect(left.bottomLeft, const Radius.circular(3));
      expect(left.topRight, Radius.zero);
      expect(BorderRadius.zero.topLeft, Radius.zero);
    });

    test('Border knows whether it is the same all round', () {
      expect(Border.all(color: Colors.red, width: 2).isUniform, isTrue);
      expect(
        const Border(bottom: BorderSide(color: Colors.red)).isUniform,
        isFalse,
      );
      const symmetric = Border.symmetric(
        vertical: BorderSide(width: 3),
        horizontal: BorderSide(width: 5),
      );
      expect(symmetric.left.width, 3);
      expect(symmetric.right.width, 3);
      expect(symmetric.top.width, 5);
      expect(BorderSide.none.width, 0);
      expect(const BorderSide().color, Colors.black);
      expect(const BorderSide().width, 1);
    });

    test('shape borders carry a side and a radius', () {
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Colors.blue),
      );
      expect(shape.side.color, Colors.blue);
      expect(const CircleBorder().side, BorderSide.none);
      expect(
        const StadiumBorder()
            .copyWith(side: const BorderSide(width: 2))
            .side
            .width,
        2,
      );
    });
  });

  group('Alignment', () {
    test('the corners and the centre', () {
      expect(Alignment.topLeft, const Alignment(-1, -1));
      expect(Alignment.center, const Alignment(0, 0));
      expect(Alignment.bottomRight, const Alignment(1, 1));
      expect(
        Alignment.center.alongSize(const Size(10, 20)),
        const Offset(5, 10),
      );
      expect(
        AlignmentDirectional.centerStart.resolve(null),
        Alignment.centerLeft,
      );
      expect(
        AlignmentDirectional.centerStart.resolve(TextDirection.rtl),
        Alignment.centerRight,
      );
    });
  });

  group('Matrix4', () {
    test('identity does nothing, and says so', () {
      expect(Matrix4.identity().isIdentity(), isTrue);
      expect(Matrix4.rotationZ(math.pi).isIdentity(), isFalse);
      expect(Matrix4.identity(), Matrix4.translationValues(0, 0, 0));
    });

    test('mutators compose', () {
      final matrix = Matrix4.identity()
        ..translate(10.0, 5.0)
        ..translate(1.0)
        ..scale(2.0)
        ..rotateZ(0.5);
      final same = Matrix4.translationValues(11, 5, 0)
        ..scale(2.0)
        ..rotateZ(0.5);
      expect(matrix, same);
    });
  });
}
