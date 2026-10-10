/// Snackbars wait their turn, as Flutter's do.
///
/// A renderer shows one bar at a time and says when it has gone, so the queue
/// is the widget layer's: the tree holds the bar at the front, and the next
/// one takes its place when that one closes.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

late BuildContext _context;
int _undone = 0;

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    _context = context;
    return const Scaffold(body: Text('Under the bars'));
  }
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
  String message, {
  bool undo = false,
}) => ScaffoldMessenger.of(_context).showSnackBar(
  SnackBar(
    content: Text(message),
    action: undo
        ? SnackBarAction(label: 'Undo', onPressed: () => _undone++)
        : null,
  ),
);

void main() {
  late AppTester tester;

  /// The bars in the tree. A renderer shows what is here, so more than one
  /// would be more than one on screen.
  List<WidgetNode> bars() => tester.ofType('Snackbar');
  String? showing() => bars().firstOrNull?.props['message'] as String?;

  /// What a renderer sends when the bar's time is up.
  Future<void> timeOut() =>
      tester.emit(bars().single.props['dismissEventId'] as String);

  /// Lets a `closed` future's listeners run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    _undone = 0;
    tester = AppTester.widget(const _Screen());
  });

  test('the first bar asked for shows at once', () async {
    show('One');
    await settle();

    expect(showing(), 'One');
  });

  test('a second waits behind it rather than replacing it', () async {
    show('One');
    show('Two');
    await settle();

    expect(bars(), hasLength(1));
    expect(showing(), 'One');
  });

  test('when one times out the next shows, in the order asked for', () async {
    show('One');
    show('Two');
    show('Three');
    await settle();

    await timeOut();
    expect(showing(), 'Two');
    await timeOut();
    expect(showing(), 'Three');
    await timeOut();
    expect(bars(), isEmpty);
  });

  test('each bar shown is a new bar to the renderer', () async {
    show('Same words');
    show('Same words');
    await settle();
    final first = bars().single.props['id'];

    await timeOut();

    expect(showing(), 'Same words');
    expect(bars().single.props['id'], isNot(first));
  });

  test('closed says how each one went', () async {
    final reasons = <String, SnackBarClosedReason>{};
    for (final name in ['One', 'Two']) {
      show(name, undo: true).closed.then((reason) => reasons[name] = reason);
    }
    await settle();

    await timeOut();
    await settle();
    expect(reasons, {'One': SnackBarClosedReason.timeout});

    await tester.emit(bars().single.props['actionEventId'] as String);
    await settle();
    expect(reasons['Two'], SnackBarClosedReason.action);
    expect(_undone, 1);
    expect(bars(), isEmpty);
  });

  test('hideCurrentSnackBar moves on to the next', () async {
    final first = show('One');
    show('Two');
    await settle();
    SnackBarClosedReason? reason;
    first.closed.then((value) => reason = value);

    ScaffoldMessenger.of(_context).hideCurrentSnackBar();
    await settle();

    expect(reason, SnackBarClosedReason.hide);
    expect(showing(), 'Two');
  });

  test('removeCurrentSnackBar does too, and says remove', () async {
    final first = show('One');
    show('Two');
    await settle();
    SnackBarClosedReason? reason;
    first.closed.then((value) => reason = value);

    ScaffoldMessenger.of(_context).removeCurrentSnackBar();
    await settle();

    expect(reason, SnackBarClosedReason.remove);
    expect(showing(), 'Two');
  });

  test('clearSnackBars drops the ones waiting and hides the one showing',
      () async {
    final reasons = <String, SnackBarClosedReason>{};
    for (final name in ['One', 'Two', 'Three']) {
      show(name).closed.then((reason) => reasons[name] = reason);
    }
    await settle();

    ScaffoldMessenger.of(_context).clearSnackBars();
    await settle();

    expect(bars(), isEmpty);
    expect(reasons, {
      'One': SnackBarClosedReason.hide,
      'Two': SnackBarClosedReason.remove,
      'Three': SnackBarClosedReason.remove,
    });
  });

  test("a controller's close takes its own bar out of the queue", () async {
    show('One');
    final second = show('Two');
    show('Three');
    await settle();
    SnackBarClosedReason? reason;
    second.closed.then((value) => reason = value);

    second.close();
    await settle();

    expect(reason, SnackBarClosedReason.hide);
    expect(showing(), 'One');
    await timeOut();
    expect(showing(), 'Three');
  });

  test("and takes it down when it is the one showing", () async {
    final first = show('One');
    show('Two');
    await settle();

    first.close();
    await settle();

    expect(showing(), 'Two');
  });

  test('closing twice, or with nothing showing, does nothing', () async {
    final only = show('One');
    await settle();

    only.close();
    only.close();
    ScaffoldMessenger.of(_context).hideCurrentSnackBar();
    ScaffoldMessenger.of(_context).clearSnackBars();
    await settle();

    expect(bars(), isEmpty);
  });
}
