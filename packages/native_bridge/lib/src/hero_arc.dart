/// The arc a Material hero flies along: Flutter's `MaterialRectArcTween`,
/// in plain numbers so the widget layer and a renderer can both use it.
///
/// Two opposite corners of the rectangle each travel along an arc of a
/// circle - the pair whose diagonal points most nearly the way the hero is
/// going - and the rectangle at any moment is the one between them. A move
/// that is nearly straight along an axis is a straight line.
library;

import 'dart:math' as math;

/// A rectangle as `(left, top, right, bottom)`.
typedef ArcRect = (double, double, double, double);

/// A point travelling from one place to another along an arc of a circle:
/// Flutter's `MaterialPointArcTween`.
class ArcPoint {
  ArcPoint(this.beginX, this.beginY, this.endX, this.endY) {
    final dx = endX - beginX;
    final dy = endY - beginY;
    final acrossX = dx.abs();
    final acrossY = dy.abs();
    // Nearly along an axis: a straight line.
    if (acrossX <= _onAxis || acrossY <= _onAxis) return;
    final distance = math.sqrt(dx * dx + dy * dy);
    double sweep(double radius) => 2 * math.asin(distance / (2 * radius));
    if (acrossX < acrossY) {
      final radius = distance * distance / acrossX / 2;
      _radius = radius;
      _centreX = endX + radius * (beginX - endX).sign;
      _centreY = endY;
      if (beginX < endX) {
        _beginAngle = sweep(radius) * (beginY - endY).sign;
        _endAngle = 0;
      } else {
        _beginAngle = math.pi + sweep(radius) * (endY - beginY).sign;
        _endAngle = math.pi;
      }
    } else {
      final radius = distance * distance / acrossY / 2;
      _radius = radius;
      _centreX = beginX;
      _centreY = beginY + (endY - beginY).sign * radius;
      if (beginY < endY) {
        _beginAngle = -math.pi / 2;
        _endAngle = _beginAngle! + sweep(radius) * (endX - beginX).sign;
      } else {
        _beginAngle = math.pi / 2;
        _endAngle = _beginAngle! + sweep(radius) * (beginX - endX).sign;
      }
    }
  }

  /// How far off an axis a move has to be to curve, as Flutter has it.
  static const double _onAxis = 2;

  final double beginX;
  final double beginY;
  final double endX;
  final double endY;
  double _radius = 0;
  double _centreX = 0;
  double _centreY = 0;
  double? _beginAngle;
  double _endAngle = 0;

  /// Where the point is [t] of the way along.
  (double, double) at(double t) {
    if (t <= 0) return (beginX, beginY);
    if (t >= 1) return (endX, endY);
    final begin = _beginAngle;
    if (begin == null) {
      return (beginX + (endX - beginX) * t, beginY + (endY - beginY) * t);
    }
    final angle = begin + (_endAngle - begin) * t;
    return (
      _centreX + math.cos(angle) * _radius,
      _centreY + math.sin(angle) * _radius,
    );
  }
}

/// A rectangle travelling from [begin] to [end] along a Material arc.
class ArcRectPath {
  factory ArcRectPath(ArcRect begin, ArcRect end) {
    final (bl, bt, br, bb) = begin;
    final (el, et, er, eb) = end;
    final towardsX = (el + er) / 2 - (bl + br) / 2;
    final towardsY = (et + eb) / 2 - (bt + bb) / 2;
    // The diagonal of the starting rectangle that points most nearly the
    // way it is going; the first of equals, as Flutter picks.
    var best = _diagonals.first;
    var support = double.negativeInfinity;
    for (final diagonal in _diagonals) {
      final (fromX, fromY) = _corner(begin, diagonal.$1);
      final (toX, toY) = _corner(begin, diagonal.$2);
      final length = math.sqrt(
        math.pow(toX - fromX, 2) + math.pow(toY - fromY, 2),
      );
      final along = length == 0
          ? 0.0
          : (towardsX * (toX - fromX) + towardsY * (toY - fromY)) / length;
      if (along > support) {
        support = along;
        best = diagonal;
      }
    }
    final (abx, aby) = _corner(begin, best.$1);
    final (aex, aey) = _corner(end, best.$1);
    final (bbx, bby) = _corner(begin, best.$2);
    final (bex, bey) = _corner(end, best.$2);
    return ArcRectPath._(
      begin,
      end,
      ArcPoint(abx, aby, aex, aey),
      ArcPoint(bbx, bby, bex, bey),
    );
  }

  ArcRectPath._(this.begin, this.end, this._first, this._second);

  final ArcRect begin;
  final ArcRect end;
  final ArcPoint _first;
  final ArcPoint _second;

  /// The rectangle [t] of the way along.
  ArcRect at(double t) {
    if (t <= 0) return begin;
    if (t >= 1) return end;
    final (ax, ay) = _first.at(t);
    final (bx, by) = _second.at(t);
    return (
      math.min(ax, bx),
      math.min(ay, by),
      math.max(ax, bx),
      math.max(ay, by),
    );
  }

  // Corners: 0 top left, 1 top right, 2 bottom left, 3 bottom right.
  static const List<(int, int)> _diagonals = [(0, 3), (3, 0), (1, 2), (2, 1)];

  static (double, double) _corner(ArcRect rect, int corner) {
    final (left, top, right, bottom) = rect;
    return switch (corner) {
      0 => (left, top),
      1 => (right, top),
      2 => (left, bottom),
      _ => (right, bottom),
    };
  }
}
