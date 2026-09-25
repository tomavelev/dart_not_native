/// Calculator - written as a plain Flutter app.
///
/// [CalculatorLogic] is the pure arithmetic; [CalculatorApp] is an ordinary
/// Flutter `StatefulWidget`. Only the import sets it apart from a Flutter app -
/// `widgets.dart` renders it through the platform's own views (the web DOM on
/// web) instead of the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

class CalculatorLogic {
  String display = '0';
  double _firstNumber = 0;
  String _operation = '';
  bool _shouldResetDisplay = false;

  /// Apply one key: digits, '.', '+', '-', '×', '÷', '=', 'C' or '←'.
  void press(String key) {
    switch (key) {
      case 'C':
        _clear();
      case '←':
        _backspace();
      case '=':
        _calculate();
      case '+':
      case '-':
      case '×':
      case '÷':
        _setOperation(key);
      case '.':
        _appendDecimal();
      default:
        _appendNumber(key);
    }
  }

  void _appendNumber(String number) {
    if (display == '0' || _shouldResetDisplay) {
      display = number;
      _shouldResetDisplay = false;
    } else {
      display += number;
    }
  }

  void _appendDecimal() {
    if (!display.contains('.')) {
      display += '.';
      _shouldResetDisplay = false;
    }
  }

  void _setOperation(String op) {
    if (display.isEmpty) return;
    _firstNumber = double.tryParse(display) ?? 0;
    _operation = op;
    _shouldResetDisplay = true;
  }

  void _calculate() {
    if (_operation.isEmpty || display.isEmpty) return;
    final secondNumber = double.tryParse(display);
    if (secondNumber == null) {
      display = 'Error';
      return;
    }
    final double result;
    switch (_operation) {
      case '+':
        result = _firstNumber + secondNumber;
      case '-':
        result = _firstNumber - secondNumber;
      case '×':
        result = _firstNumber * secondNumber;
      case '÷':
        if (secondNumber == 0) {
          display = 'Error';
          return;
        }
        result = _firstNumber / secondNumber;
      default:
        return;
    }
    display = result.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    _operation = '';
    _shouldResetDisplay = true;
  }

  void _clear() {
    display = '0';
    _firstNumber = 0;
    _operation = '';
    _shouldResetDisplay = false;
  }

  void _backspace() {
    if (display.isNotEmpty && display != '0') {
      display = display.substring(0, display.length - 1);
      if (display.isEmpty) display = '0';
    }
  }
}

/// Keypad rows, as in the Flutter UI.
const calculatorKeys = [
  ['C', '←', '÷', '×'],
  ['7', '8', '9', '-'],
  ['4', '5', '6', '+'],
  ['1', '2', '3', '='],
  ['0', '.', '='],
];

/// Stable element id for a key, e.g. 'key_7', 'key_plus' (for tests).
String calculatorKeyId(String key, int row) => switch (key) {
  'C' => 'key_clear',
  '←' => 'key_backspace',
  '÷' => 'key_divide',
  '×' => 'key_multiply',
  '-' => 'key_minus',
  '+' => 'key_plus',
  '=' => row == 3 ? 'key_equals' : 'key_equals_2',
  '.' => 'key_dot',
  _ => 'key_$key',
};

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({super.key});

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  final logic = CalculatorLogic();

  void _press(String key) => setState(() => logic.press(key));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBar(title: Text('Calculator')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  logic.display,
                  key: const ValueKey('display'),
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var r = 0; r < calculatorKeys.length; r++)
                  Row(
                    children: [
                      for (final key in calculatorKeys[r])
                        Expanded(
                          child: ElevatedButton(
                            key: ValueKey(calculatorKeyId(key, r)),
                            onPressed: () => _press(key),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _colorFor(key),
                            ),
                            child: Text(key),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color? _colorFor(String key) {
    if (key == '=') return Colors.green;
    if (key == 'C' || key == '←') return Colors.red;
    if (const ['+', '-', '×', '÷'].contains(key)) return Colors.orange;
    return null; // digits and '.' keep the default fill
  }
}
